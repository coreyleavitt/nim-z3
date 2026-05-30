# nim-z3 v0.2 plan

A type-safe, memory-safe, idiomatic Nim wrapper for the Z3 SMT solver.

**Status**: planning. v0.1 shipped on 2026-05-29 — see [`V0.1_PLAN.md`](V0.1_PLAN.md) for the archived plan that drove it (architectural rationale, lifetime model, phantom-sort design, deferral ledger). This document is the live plan for v0.2, starting from a working v0.1 base.

**Audience**: future-me, future contributors, and anyone deciding whether v0.2's surface fits their use case.

What changes between v0.1 and v0.2:

- v0.1 covered the **core**: sorts (Int, Real, Bool, BitVec), Boolean and arithmetic ops, solver, model, pretty/SMT2 round-trip, version probes.
- v0.2 covers the **theories that turn SMT from "arithmetic checker" into "general decision procedure for software verification"**: arrays, datatypes, quantifiers. Plus the operational machinery (optimisation, tactics) that real users reach for once they hit "this constraint timed out — how do I help Z3?"

The architectural foundation (phantom-sort discipline, refcount lifecycle, current-context threadvar, error-on-FFI-call template) carries forward unchanged. v0.2 is a horizontal extension across new sorts and new solver-like objects, not a redesign.

---

## 1. Goals and non-goals

### Goals

1. **Array theory**, with phantom-typed `Z3Array[K, V]` so an `Int → Bool` array is a distinct type from an `Int → Int` array. `store`, `select`, `mkConstArray`, equality, extensionality (`Z3_mk_array_ext`).
2. **Inductive datatypes** via `Z3_mk_datatypes` — recursive sums + products. The classical SMT example is `(declare-datatype List (nil (cons (head Int) (tail List))))`; the Nim API should let users declare such a type with a single high-level call that returns the constructor / recogniser / accessor handles ready to use.
3. **Quantifiers**: `forall` / `exists` over typed-variable lists with pattern triggers. The PhD-grade part is the pattern story — Z3's instantiation behaviour collapses to garbage on quantified inputs without good patterns, and we should make the right thing easy.
4. **Optimisation** — `Z3Optimize` mirroring `Z3Solver` plus `add_soft` (with weight + id for soft-constraint grouping), `maximize` / `minimize` over arithmetic terms, `get_upper` / `get_lower` for bounds. Pareto / lex multi-objective via `set_objective_mode`.
5. **Tactics and goals** — composable `Z3Tactic` (`mkTactic`, `then`, `orElse`, `repeat`, `tryFor`, `with` for parameter overrides), `Z3Goal` (`add`, `simplify`, `to_string`), and `applyTactic(t, g)` returning a `Z3ApplyResult` so users can ablate solver strategies on a goal before handing to the main solver.
6. **`Z3_simplify` + wrapper** — surfaced in v0.1's §18 as deferred. Now the canonical "fold constants and known identities" primitive that property tests, datatype recognisers, and tactic composition all want.
7. **Big-width BitVec literals + extraction** — `mkBigBitVec(numeral, W)` for `W > 64`, `toBigUintStr` / `toBigIntStr` on `Z3BitVec[W]`. Also deferred from v0.1.
8. **Reabsorbed carryovers from step 1 and step 7**, now unblocked by step 8's `Z3Params` landing:
   - `Z3_simplify_ex(ast, params)` — params-customised simplifier.
   - `Z3_optimize_set_params(o, params)` for `priority = "box"` / `"pareto"` multi-objective on `Z3Optimize`.
   Both deferrals were logged in §8 at the time; this step lands them.
9. **Multi-version + multi-platform CI** — add macOS-x64 / macOS-aarch64 rows to the existing 4-version Z3 matrix; consider adding a valgrind job behind ASAN.

**Dropped from the plan**: a "public `z3/strategies` module" exposing the recipe ADTs from `tests/recipes.nim` was originally on the list. Dropped because (a) proptest is going to depend on `nim-z3` (for symbolic-shrinking / constraint-backed strategies), so inverting that dep direction is a design smell even guarded by `-d:z3WithProptest`; (b) no real consumer wants random *Z3 expression trees* as a library feature — it was test infrastructure dressed up as a goal. Recipes stay test-only in `tests/recipes.nim`.

### Non-goals

- **String theory, sequence theory, fixedpoint, FloatingPoint, custom theories.** These are v0.3+ feature waves per the v0.1 plan's §11; nothing in v0.2 unlocks them.
- **High-level macro DSL** (`solve: forall x in Int, x + 1 > x`). Tempting, but the wrapper IS the API call: a DSL adds rope without removing it. v0.3+ if a user makes a strong case.
- **Re-architecting v0.1.** The phantom-sort discipline, current-context threadvar, and refcount lifecycle are working as designed. v0.2 extends them; it doesn't replace them.

---

## 2. The shape of the v0.2 expansion

v0.1 settled on two type families:

- `Z3Ast[S: static SortTag]` for sorts where width / parameters don't matter at the type level (Int, Real, Bool).
- `Z3BitVec[W: static int]` for the width-tracked family.

v0.2 introduces three more type families — each with its own static parameterisation justified by what the SMT theory demands. The PhD principle from §4 of v0.1's plan applies: **each phantom family carries the minimum type-level information that catches a real bug at compile time, and nothing more.**

### Arrays — `Z3Array[K, V]` where `K, V: static SortTag`

```nim
type
  Z3Array*[K, V: static SortTag] = object
    raw: RawZ3Ast
    ctx: Z3Context

proc store*[K, V: static SortTag](
    a: Z3Array[K, V], i: Z3Ast[K], v: Z3Ast[V]): Z3Array[K, V]

proc select*[K, V: static SortTag](
    a: Z3Array[K, V], i: Z3Ast[K]): Z3Ast[V]
```

`store` and `select` enforce that the key type matches `K` and the value type matches `V` at compile time. Wrong-keyed access is a type error, not a Z3 sort error at check-sat time.

**Open call**: nested arrays (`Z3Array[K, Z3Array[K2, V]]`) and arrays whose value sort is a `Z3BitVec[W]`. Both need cooperation across the two phantom families; revisit during implementation.

### Datatypes — `Z3Datatype[NameTag: static string]` + per-constructor types

The naïve encoding `Z3Datatype[NameTag, ConstructorList]` rapidly becomes unworkable for recursive types. The pragmatic encoding:

```nim
type
  Z3DatatypeDecl* = ref object
    name*: string
    constructors*: seq[Z3ConstructorDecl]
    raw: RawZ3Sort

  Z3ConstructorDecl* = ref object
    name*: string
    fields*: seq[(string, Z3Sort | RawZ3Sort)]    # sort or self-recursion marker
    recognizer*: RawZ3FuncDecl
    accessors*: seq[RawZ3FuncDecl]
    constructor*: RawZ3FuncDecl
```

The user-facing API is:

```nim
let listDt = ctx.declareDatatype("List", @[
  constructor("nil", []),
  constructor("cons", @[
    ("head", IntSortRef),    # IntSortRef = a marker for an existing sort
    ("tail", selfRef)        # selfRef = "this datatype, recursively"
  ])
])

let nilT = listDt.constructor("nil")
let consT = listDt.constructor("cons")
let myList = consT(mkInt(1), consT(mkInt(2), nilT()))
```

Datatype values are `Z3Ast[stDatatype]` with a runtime `decl: Z3DatatypeDecl` field for accessor dispatch. The phantom story is weaker than for Int/Bool/BV because constructor / accessor compatibility is name-based, not type-based — but Z3 itself works that way, and the runtime check on accessor-against-decl is cheap.

**Mutually recursive datatypes** (List and Tree referring to each other) need `Z3_mk_datatypes` called once with both decls. The API: a single `declareDatatypes(@[...])` call that returns a tuple of `Z3DatatypeDecl`s.

### Quantifiers — bound-variable typing + pattern triggers

```nim
proc forall*[S: static SortTag](
    vars: openArray[Z3Ast[S]],
    body: Z3Bool,
    patterns: openArray[Z3Pattern] = []): Z3Bool

proc exists*[S: static SortTag](
    vars: openArray[Z3Ast[S]],
    body: Z3Bool,
    patterns: openArray[Z3Pattern] = []): Z3Bool

proc mkPattern*(terms: varargs[Z3Ast]): Z3Pattern
```

The vars must be free `Z3_mk_const` constants of the matching sort — the wrapper re-quantifies them via `Z3_mk_forall_const`. Sort-heterogeneous quantifiers (`forall (x: Int, p: Bool)`) need either a varargs-over-typed-erased-AST signature or a per-arity-overload set; settle during implementation.

**Pattern story**: `Z3_mk_pattern` takes terms that the *trigger* matches. The doc-string for `forall` should explicitly walk through "why your `forall` quantified problem ran forever" — it's almost always missing or wrong patterns. Examples in `examples/quantified.nim`.

### Optimisation — `Z3Optimize`

A solver-like object with the same lifecycle discipline:

```nim
type Z3Optimize* = ref Z3OptimizeOwn

proc newOptimize*(ctx: Z3Context): Z3Optimize
proc add*(o: Z3Optimize, c: Z3Bool)
proc addSoft*(o: Z3Optimize, c: Z3Bool, weight = 1.0, id = ""): Z3OptHandle
proc maximize*[S: static SortTag](o: Z3Optimize, t: Z3Ast[S]): Z3OptHandle
proc minimize*[S: static SortTag](o: Z3Optimize, t: Z3Ast[S]): Z3OptHandle
proc check*(o: Z3Optimize): Z3Status
proc model*(o: Z3Optimize): Z3Model
proc upper*(o: Z3Optimize, h: Z3OptHandle): Z3Ast[S]   # S inferred from h
proc lower*(o: Z3Optimize, h: Z3OptHandle): Z3Ast[S]
```

`Z3OptHandle` is a small phantom-typed handle returned from `maximize`/`minimize`/`addSoft`. It tracks the sort of the bound term so `upper`/`lower` return the right `Z3Ast[S]`.

### Tactics + goals

```nim
type
  Z3Goal* = ref Z3GoalOwn
  Z3Tactic* = ref Z3TacticOwn
  Z3ApplyResult* = ref Z3ApplyResultOwn

proc newGoal*(ctx: Z3Context, models = true, unsatCores = false,
              proofs = false): Z3Goal

proc mkTactic*(ctx: Z3Context, name: string): Z3Tactic
proc `then`*(t1, t2: Z3Tactic): Z3Tactic
proc `or`*(t1, t2: Z3Tactic): Z3Tactic
proc repeat*(t: Z3Tactic, maxSteps = high(int)): Z3Tactic
proc tryFor*(t: Z3Tactic, msTimeout: int): Z3Tactic
proc applyTactic*(t: Z3Tactic, g: Z3Goal): Z3ApplyResult
```

The combinator names match Z3's SMT-LIB tactic names (`then`, `or-else`, `repeat`, `try-for`). Nim's keyword overlap with `then`/`or` is handled by emitting them as backtick-quoted operators on `Z3Tactic`; `mkTactic("solve-eqs").then(mkTactic("simplify")).repeat(5)` reads naturally.

---

## 3. Module structure

```
src/z3/
├── ffi.nim                       # extended: array, datatype, quantifier,
│                                 # optimize, tactic, simplify FFI symbols
├── context.nim                   # unchanged (v0.1 surface stable)
├── sort.nim                      # extended: stArray, stDatatype, stPattern
│                                 # tags; mkArraySort, mkDatatypeSort
├── ast.nim                       # unchanged
├── builder.nim                   # unchanged
├── boolean.nim                   # unchanged
├── arith.nim                     # unchanged
├── solver.nim                    # unchanged
├── model.nim                     # extended: eval over Z3Array, Z3Datatype
├── bitvec.nim                    # extended: mkBigBitVec, toBigUintStr,
│                                 # toBigIntStr; simplify integration
├── pretty.nim                    # extended: pretty for new types
│
├── array.nim          # NEW       Z3Array[K, V], store, select, mkConstArray
├── datatypes.nim      # NEW       Z3DatatypeDecl, declareDatatype(s),
│                                  constructor / accessor / recognizer dispatch
├── quantifier.nim     # NEW       forall, exists, mkPattern
├── optimize.nim       # NEW       Z3Optimize, addSoft, maximize, minimize
├── tactic.nim         # NEW       Z3Tactic combinators, Z3Goal, applyTactic
├── simplify.nim       # NEW       simplify(ast, params = ...), small wrapper
└── strategies.nim     # NEW       (proptest-gated) public recipe ADTs +
                                   interpreters + smtEquiv-friendly properties
tests/
├── (every v0.1 test, unchanged)
├── tarray.nim
├── tdatatypes.nim
├── tquantifier.nim
├── toptimize.nim
├── ttactic.nim
├── tsimplify.nim
├── tbigbitvec.nim
└── tproperty.nim                  # extended with array / datatype properties
examples/
├── (every v0.1 example, unchanged)
├── array_solve.nim                # array-of-int with store/select
├── inductive_datatypes.nim        # List or Tree, plus a property
├── quantified.nim                 # forall with patterns demo
├── optimisation.nim               # soft constraints + maximize
└── tactic_pipeline.nim            # mkTactic("simplify").then("solve-eqs")
```

Naming follows the v0.1 convention: lowercase module file, idiomatic `Z3X` types, `mkX` constructors with both implicit and explicit-ctx forms.

---

## 4. Phasing — what ships when

### v0.2.0 — theory expansion

1. `Z3_simplify` + wrapper (foundation for the rest).
2. Big-width BitVec literals + extraction.
3. Arrays.
4. Datatypes (single + mutually recursive).
5. Quantifiers + patterns.
6. Optimisation.
7. Tactics + goals.
8. Reabsorbed carryovers (`Z3_simplify_ex`, `Z3_optimize_set_params` box / Pareto).
9. macOS / aarch64 CI rows.
10. Generated API reference via `nim doc --project`.
11. v0.2 tag.

### v0.3+ — theory completion

- String theory, sequence theory.
- Fixedpoint engine.
- FloatingPoint theory.
- User propagators / custom theories.
- High-level macro DSL (still under "non-goal" review).

---

## 5. Implementation sequence

The order is chosen so each step's tests can exercise the new surface end-to-end against an already-working stack.

1. **`Z3_simplify` + `z3/simplify`** (small, foundational). Tests verify constant folding on Int / Bool / BV expressions. Unlocks more aggressive property-test shape checks (no need to spin a solver for trivial reductions).

2. **`mkBigBitVec` + big-width extraction** (small, deferral from v0.1 §18). Tests verify `mkBigBitVec("12345678901234567890", 128).toBigUintStr` round-trips.

3. **Arrays** (`Z3Array[K, V]`, store, select, mkConstArray, equality, extensionality). Tests verify the classic `(store a i v)(j) == ite(i == j, v, a[j])` axiom holds via `smtEquiv`.

4. **Datatypes — single** (`declareDatatype`, constructor / accessor / recognizer dispatch). Tests on `Option[Int]`-like and `Tree[Int]`-like inductive types. **First end-to-end example with a user-defined inductive type runnable.**

5. **Datatypes — mutually recursive** (`declareDatatypes`). Tests on List + Tree referring to each other.

6. **Quantifiers** (`forall`, `exists`, `mkPattern`). Tests verify universal-property statements decide correctly; explicit pattern test catches the "no pattern, runaway instantiation" failure mode.

7. **Optimisation** (`Z3Optimize`, addSoft, maximize, minimize, upper / lower). Tests on knapsack-style and Pareto multi-objective problems.

8. **Tactics + goals** (`Z3Tactic`, `Z3Goal`, `applyTactic`, combinator surface). Tests verify standard pipelines (`simplify` → `solve-eqs` → `smt`) produce equivalent results to the default solver.

9. **Reabsorbed carryovers** unblocked by step 8's `Z3Params`:
   - `Z3_simplify_ex(ast, params)` (carryover from step 1).
   - `Z3_optimize_set_params(o, params)` exposing box / Pareto multi-objective modes on `Z3Optimize` (carryover from step 7).

10. **macOS / aarch64 CI rows** + `nim doc --project` artifact publishing.

11. **v0.2 tag.**

**Dropped from this sequence**: the public `z3/strategies` module that originally sat at step 9. See §1's "Dropped from the plan" note for why; recipes stay in `tests/recipes.nim`.

---

## 6. Risks specific to v0.2

### Datatype refcount discipline

Datatypes return a `RawZ3Sort` plus constructor / accessor / recognizer `RawZ3FuncDecl`s. Z3's refcount story for `FuncDecl` is the same as for `Ast` (inc_ref / dec_ref on the same context), but we've never wrapped that type before. Risk: same kind of "empty `bycopy` struct compares equal" bug v0.1 hit on `RawZ3Ast`; mitigate by adding `RawZ3FuncDecl` to the polymorphic `==` / `!=` / `isNil` overload sets and exercising via a stress test before the wider datatype surface lands.

### Quantifier pattern UX

Z3 will silently run forever on a quantified problem with a bad / missing pattern. The wrapper can't fix Z3's behaviour, but it can make patterns *visible* in the API surface: `forall(vars, body)` without a `patterns: =` argument might emit a compile-time warning, or at minimum the docstring should be hard-to-miss about it.

### Optimisation + tactics ABI churn across Z3 versions

Optimisation and tactics gained features across 4.10 → 4.13. Some symbols we'll want (e.g. lex / Pareto mode controls) appeared after 4.10. The matrix CI from v0.1 §12 will surface this immediately — at which point the `.optional` softlink declaration becomes mandatory (v0.1 §18 deferral that finally fires).

---

## 7. Open questions (genuinely open — answer during implementation)

1. **Datatype phantom typing strength.** Should `Z3DatatypeValue["List"]` be its own type (string literal as phantom param) or should we settle for runtime decl-pointer comparison? String-literal phantom gives compile-time mismatch checking; runtime-decl is simpler. Lean: runtime — Z3's API works that way, the user pays runtime cost anyway when picking accessors.
2. **Heterogeneous-sort `forall` signature.** `forall((x: Z3Int, p: Z3Bool), body)` is what users want; varargs over `Z3Ast[anySort]` loses static sort info; per-arity overloads explode. Likely answer: a `Z3BoundVar` typeclass / typedesc with a `mkBoundVar[S]()` helper that boxes any sort, plus a per-quantifier-arity `forall1` / `forall2` / `forall3` matching Nim's stdlib's `iterator` story.
3. **Optimisation handle scoping.** Should `Z3OptHandle` outlive the `Z3Optimize` it came from? Z3 says no (the handle indexes into the optimise's internal state). Nim ref discipline says either we enforce that with a parent-ref or we document it and trust users. Lean: parent-ref — costs one allocation per handle, makes UAF impossible.
4. **Tactic parameter passing.** Z3's `with` for tactic parameter overrides takes a `Z3_params` object. Nim ergonomic: a varargs `(string, string)` like `newContext`? A KDL-ish nested config? Lean: same `varargs[(string, string)]` for symmetry with `newContext`.

---

## 8. Deferred from v0.2 (running list, updated as we go)

Same discipline as the v0.1 §18 ledger — append-only. Format: **what**, **why**, **where it goes** (v0.3 / dropped). This is the v0.2-specific list; v0.1's deferrals that remain unaddressed live in [`V0.1_PLAN.md` §18](V0.1_PLAN.md#18-deferred-from-v01-running-list-updated-as-we-go).

### From step 1 (simplify)

- **`Z3_simplify_ex` with custom `Z3_params`**. The default-params `simplify` shipped in step 1; `Z3_simplify_ex` takes a `Z3_params` object for per-call tuning (`flat`, `som`, `arith_lhs`, …). `Z3_params` is a refcounted entity in its own right and deserves a typed wrapper alongside the tactics module (step 7), not a one-off lifecycle hack in `simplify.nim`. **Where**: v0.2 step 7. Surfaces with `Z3Params` get added alongside.

### From step 2 (big-width BitVec)

- Nothing genuinely deferred from this step — it absorbed two v0.1 §18 items (big BV construction + extraction) and additionally fixed v0.1's strict-no-simplify behavior on `toUint`/`toInt`. The remaining gap (property tests over BV recipes with W > 8) was already logged in v0.1 §18 step 9; revisit if `tests/recipes.nim` ever grows BV-width generalisation. (Originally this entry pointed at a public `z3/strategies` module — that module was dropped from the plan; see §1.)

### From step 3 (arrays)

- **Nested arrays** (`Z3Array[Z3Int, Z3Array[Z3Int, Z3Int]]`). **Why**: Nim 2.2's typedesc-generic-param reflection doesn't compose cleanly across nesting. We can extract `T.W` from a `T: Z3BitVec`, but reflectively getting `T.Key` and `T.Val` from a `T: Z3Array` to recursively build the sort needs macro-level machinery I don't want to write up front for an edge case. **Where**: v0.2 if a user needs it before datatypes land (step 4), otherwise v0.3.
- **`mkArrayExt(a, b): Key`** (extensionality witness via `Z3_mk_array_ext`). **Why**: useful in proof-heavy code (witness the index where two arrays disagree), niche in everyday encoding. **Where**: v0.2 step 7 (tactics) or v0.3.

### Cross-cutting v0.2 design call (logged here as the precedent)

Step 3 settled the **phantom design** for sorts with sub-parameters: typedescs of the actual AST families (`Z3Int`, `Z3BitVec[W]`, …), not `static SortTag` values. `sortOfType[T](ctx)` is the dispatch helper; `T.W` extracts BV widths via Nim's static-generic-param access. Datatypes (step 4) and quantifiers (step 5) will follow the same pattern wherever they need sort-level parameterisation. The v0.1 §4 sketch — `Z3Array[K, V: static SortTag]` — is superseded; that representation collapsed BV widths to a single tag and could not express memory models.

### From step 4 (single inductive datatypes)

- **Mutually recursive datatypes** (List ↔ Tree referencing each other) — this is the step-5 deliverable. Currently `selfField` works only for the datatype being declared.
- **Heterogeneous-arity constructor application past 5 args**. The `apply` template family covers arities 0–5; bigger constructors require either adding more templates or a macro form. **Where**: defer until a user needs it.
- **Pretty-printing test for `$`** of a datatype value. Implemented but not test-asserted; trivial delegation to `Z3_ast_to_string`. **Where**: defer.
- **`Z3DatatypeValue` model evaluation** (`m[v]`, `m.eval(v)`). The existing `Z3Model.eval` is generic over `Z3Ast[S]` and doesn't dispatch to datatypes yet. A corresponding `proc eval[T](m: Z3Model, v: Z3DatatypeValue[T]): Z3DatatypeValue[T]` overload is needed. **Where**: still v0.2 — likely picked up alongside step 5 (mutually recursive) since both touch the model surface.

### From step 5 (mutually recursive datatypes)

- **`declareDatatypes` arity ≥ 4.** Per-arity overloads cover N=2 and N=3; bigger families need additional overloads (each is ~30 mechanical lines). **Where**: bump as a user surfaces the need; the precedent is set.
- **A `declareDatatypes:` block-DSL macro.** Considered during planning — would let the user write `declareDatatypes: forDatatype[Tree]: ...; forDatatype[Forest]: ...` and emit the right return tuple. Costs 200+ lines for an arity ceiling Nim itself enforces. Per-arity overloads are simpler. **Where**: revisit only if the arity overloads become a maintenance burden, otherwise drop.
- **Carry-forward from step 4: `Z3Model.eval` overload for `Z3DatatypeValue[T]`.** Still not landed; touches the model surface in the same way for both single and mutual datatypes. **Where**: alongside the next module that needs model-side datatype reads (likely v0.2 step 6 quantifiers via patterns that match on constructors, or a follow-up).

### From step 6 (quantifiers + patterns)

- **`forall`/`exists` arity ≥ 6.** Per-arity templates 1–5 in place; bump for higher arity is one ~5-line template per arity added.
- **Compile-time "missing patterns" warning.** Quantifiers without patterns are the most common cause of "my SMT problem ran forever." A compile-time `{.warning.}` whenever `forall`/`exists` is called with `patterns=[]` and a body that references anything beyond pure arithmetic (arrays / datatypes / uninterpreted functions) would guide users toward the right idiom. Selective compile-time warnings in Nim are awkward — the simple "warn always when patterns is empty" form is too noisy. **Where**: v0.2 step 7 or v0.3 — likely couples with tactics where the same diagnostic story applies to user-supplied tactic chains that hang.
- **Multi-pattern macro (`varargs[typed]`)** for `mkPattern`. Same trade-off as constructor apply in step 4 — per-arity templates keep error messages clean.
- **Quantifier weight parameter.** `Z3_mk_forall_const` accepts a `weight` argument that de-prioritises this quantifier vs. others; we hardcode 0. Useful for tuning solver heuristics on hard problems but not user-facing for v0.2. **Where**: v0.3 if a real user hits it.

### From step 7 (optimization)

- **`Z3Params` typed wrapper.** Step 1's deferral that finally bites — box and Pareto multi-objective modes are set via `Z3_optimize_set_params(o, params)` where `params: Z3_params`. Until `Z3Params` is a proper typed wrapper (refcount lifecycle, key/value setters, the canonical place tactics will use), multi-objective modes beyond the lex default aren't accessible. **Where**: alongside the tactics module if step 7's optimization caller demand surfaces, otherwise v0.3.
- **`Z3_optimize_get_objectives`**, `Z3_optimize_get_assertions`, `Z3_optimize_from_file/from_string`. Inspection helpers that aren't on a hot path. **Where**: v0.3 if a user needs them.
- **Optimize-side push/pop arity ≥ 2.** Z3's optimize.pop only takes a count of 1 (unlike the solver's `pop(n)` form). We currently expose `pop(o)` only — matches Z3. If multi-level pop ever lands in Z3 we'll expose it; not a deferral so much as a non-feature.
- **Surprise documented**: Z3's `optimize_get_upper`/`lower` returns the bound for a BV objective as an *Int* AST (the unsigned-magnitude bound). The wrapper hides this by re-converting via `Z3_mk_int2bv` so `upper(h: Z3OptHandle[Z3BitVec[8]])` returns `Z3BitVec[8]` per the typed promise. Tested round-trip. The cost is one extra FFI symbol (`Z3_mk_int2bv`) and one Z3 AST construction per call — negligible.

### From step 8 (tactics + goals + params)

- **`Z3Params` getters**. The wrapper only exposes typed `set` and `$`. Z3's C API doesn't actually expose getter functions for params — `Z3_params_to_string` is the only readback path. Not a deferral so much as a non-feature; documenting here so a future reader doesn't try to add them.
- **`Z3_mk_solver_from_tactic`**. Wraps a tactic into a `Z3Solver`-shaped object — useful for composing tactic pipelines with the existing solver-add/check workflow. Small addition; deferred because no user has surfaced the need.
- **`Z3_apply_result_convert_model`** (and proof conversion). The metadata on an apply-result lets you take a model satisfying a subgoal and convert it back to one satisfying the original goal. Needed for any real use of `apply` beyond inspection. **Where**: v0.2 follow-up if a property-test or example demands it.
- **`Z3_solver_set_params` for the existing `Z3Solver`** — now that `Z3Params` exists, the solver can take params too. Logged here for symmetry; the solver currently uses Z3's defaults.
- **Reabsorbed carryovers from earlier steps that this step *enables*:**
  - ~~**`Z3_simplify_ex` + a `simplify(ast, params)` overload** (step 1 deferral) is now unblocked; not yet implemented.~~ **Landed in step 9.**
  - ~~**`Z3_optimize_set_params` for box/Pareto multi-objective** (step 7 deferral) is now unblocked; not yet implemented.~~ **Landed in step 9.**

### From step 9 (reabsorbed carryovers)

- **Nothing newly deferred from this step** — it absorbed the two carryovers from steps 1 and 7 that step 8's `Z3Params` had unblocked. Surface added: `simplify[S](a, params)` / `simplify[W](a, params)` overloads on `z3/simplify`, `setParams(o, p)` on `Z3Optimize`. Tests: 4 new in `tsimplify.nim` (tracer + 3 shape-property tests over random int/bool/BV trees), 2 new in `toptimize.nim` (box mode gives independent objective bounds; pareto mode enumerates frontier points then returns unsat).
- Pareto-mode model conversion for `Z3Optimize` — each `check()` returns sat with a different model on the frontier; we exercise the enumeration but don't separately test extracting each model. Same gap as the §8 `Z3_apply_result_convert_model` deferral. **Where**: follow-up alongside the next step's user-facing demo of Pareto.

### Spec divergence (step 8, captured for the precedent)

v0.2 plan §2 sketched the combinators as ``proc `then`*(t1, t2)`` and ``proc `or`*(t1, t2)``. We diverged to **`andThen` / `orElse`** for two reasons:

1. `or` on `Z3Tactic` would shadow the boolean `or` (`Z3Bool` × `Z3Bool` → `Z3Bool`) we use everywhere else. Type discrimination makes it work at compile time but reading mixed-tactic-and-bool code becomes ambiguous.
2. `andThen` / `orElse` are the canonical names in Z3's SMT-LIB tactic vocabulary (`and-then`, `or-else`), so the Nim names line up with Z3's `(get-tactics)` output.

### Spec divergence (step 6, captured for the precedent)

v0.2 plan §7 Q2 leaned toward a `Z3BoundVar` typeclass with `mkBoundVar[S]()` explicit boxing. We diverged to **per-arity templates over any typed AST family** — `forall(x, p, body)` where `x: Z3Int` and `p: Z3Bool` works directly because each generic position binds independently. Same precedent as step 4's constructor `apply` template family. The Q2 alternative would have forced the user to wrap every variable: `forall([mkBoundVar(x), mkBoundVar(p)], body)`. Strictly worse ergonomics for the same expressive power.

### Spec divergence (step 4, captured here for the precedent)

v0.2 plan §7 Q1 sketched **runtime decl-pointer comparison** as the leaning, against a `static string`-phantom alternative. We diverged in two steps:

1. First tried `Z3DatatypeValue[Name: static string]` for compile-time name-based distinction. Hit a Nim 2.2 instantiation bug: `=destroy` could not be resolved for `static string`-parameterised types when constructed through a generic `applyImpl` intermediate. Reproducible in 10 lines; reported upstream (TBD).
2. Switched to **Nim marker types** as the phantom — `type Maybe = object`, then `Z3DatatypeValue[Maybe]`. Each marker is a distinct Nim type, so compile-time distinction works the same as static-string would. The Z3 sort name comes from `$T` (the marker's Nim type name), so the marker doubles as the human-readable identifier.

Cost to the user: one `type X = object` declaration per datatype. Benefit: full type-system distinction between `Z3DatatypeValue[Maybe]` and `Z3DatatypeValue[IntList]`, just as v0.1 § type-safe sorts intended. PhD-defensible: when the type system Nim gives us doesn't work for a phantom-string approach, sentinel marker types are the next-best path and they preserve the same guarantee.

---

## 9. Closing note

v0.1's plan called itself "a commitment — we ship to it." v0.1 did. v0.2's plan is the same kind of commitment, calibrated for the next slice of surface. Anything that surfaces during implementation as a spec assumption we got wrong goes in §8 above; anything that surfaces as a working design we got *right* in a way the plan didn't capture goes in the live module docstrings (which are the documentation that doesn't rot).

If reading this, future-me, after v0.2 has shipped: archive this file to `docs/V0.2_PLAN.md`, write `docs/IMPLEMENTATION_PLAN.md` for v0.3, and update the README's "Design" section to point at both archives. The pattern is: every shipped version's plan becomes the historical record; the live plan is always for the next one.

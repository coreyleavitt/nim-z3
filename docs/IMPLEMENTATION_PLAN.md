# nim-z3 v0.3 plan

A type-safe, memory-safe, idiomatic Nim wrapper for the Z3 SMT solver.

**Status**: planning. v0.2 shipped on 2026-05-29 — see [`V0.2_PLAN.md`](V0.2_PLAN.md) for the archived plan that drove it (arrays, datatypes, quantifiers, optimization, tactics + goals + params, the "phantom design via typedescs of AST families" precedent that everything else inherits). This document is the live plan for v0.3, starting from a working v0.2 base.

**Audience**: future-me, future contributors, anyone deciding whether v0.3's surface fits their use case.

What changes between v0.2 and v0.3:

- v0.1 covered the **core**: sorts (Int, Real, Bool, BitVec), Boolean and arithmetic ops, solver, model, pretty/SMT2 round-trip, version probes.
- v0.2 covered the **theories that turn SMT from "arithmetic checker" into "general decision procedure for software verification"**: arrays, datatypes, quantifiers, optimisation, tactics + goals + params.
- v0.3 covers, in priority order:
  1. **Architectural unification** — a post-v0.2 audit ([conversation log + audit findings, summarised in §2 below](#2-the-shape-of-the-v03-expansion)) surfaced that v0.2's five typed-value families (`Z3Ast[S]`, `Z3BitVec[W]`, `Z3Array[K,V]`, `Z3DatatypeValue[T]`, `Z3Pattern`) reimplement the same `=destroy`/`=copy`/`=dup` refcount hooks verbatim — 22 nearly-identical instances across 9 modules. The same pattern shows up in `wrap*` helpers (`wrap[S]`, `wrapBv[W]`, `wrapArray[K,V]`, `wrapValue[T]`) and in per-arity templates (`apply` × 6, `mkPattern` × 5, `forall` × 5, `exists` × 5). All three are symptoms of one missing abstraction: a `Z3Term` concept that binds the typed families and generates their lifecycle + wrap surface from a single declaration. Fixing it before adding the four new typed families v0.3 wants (`Z3String`, `Z3Seq[E]`, `Z3Fp[E,S]`, `Z3FuncDecl[…]`) saves ~90 lines of boilerplate and makes the new families an obvious instantiation, not another five copies.
  2. **Carried-forward gaps from v0.2 + small cleanups** that the post-v0.2 audit catalogued. Folded into v0.3 because there are no consumers and a v0.2.1 point release would be bureaucratic overhead.
  3. **The remaining theory families** — strings + regexes, sequences, FloatingPoint, uninterpreted functions.
  4. **Solver–tactic bridges** (`Z3_mk_solver_from_tactic`, `Z3_solver_set_params`).
  5. **Upstream-blocker resolution work** (multi-platform CI, nim-doc Pages) currently filed as [#1](https://github.com/coreyleavitt/nim-z3/issues/1) — still blocked on private deps; will land here if the blocker clears mid-v0.3, otherwise rolls forward.

v0.2's typedesc-phantom design + refcount lifecycle discipline + current-context threadvar all carry forward as the *contract*. v0.3 step 1 changes how the contract is *implemented* — without changing observable behaviour for users.

---

## 1. Goals and non-goals

### Goals

1. **Architectural unification** — `Z3Term` concept + unified lifecycle/wrap generation. Detail in §2; the headline:
   - A `Z3Term` concept binds the five typed value families (`Z3Ast[S]`, `Z3BitVec[W]`, `Z3Array[K,V]`, `Z3DatatypeValue[T]`, `Z3Pattern`) by their shared shape — every member carries a `raw: RawZ3Ast` (or refcountable equivalent) and a `ctx: Z3Context`.
   - A single `wrap[T: Z3Term](ctx, raw): T` template replaces `wrap[S]` / `wrapBv[W]` / `wrapArray[K,V]` / `wrapValue[T]` / inline `when T is X` dispatch blocks scattered across `array.nim`, `optimize.nim`, `datatypes.nim`, the forthcoming `model.eval[Z3Array]` / `model.eval[Z3DatatypeValue]` overloads, and more.
   - A `mixin lifecycle T` (template-generated or macro-generated) replaces the 22 verbatim copies of `=destroy` / `=copy` / `=dup` across the five families. New families opt-in by satisfying the concept.
   - **`Z3Refcountable` super-concept** covering the ref-typed handles (`Z3Solver`, `Z3Model`, `Z3Optimize`, `Z3Goal`, `Z3Tactic`, `Z3ApplyResult`, `Z3Params`, `Z3Context`) — same lifecycle generator, different inc_ref/dec_ref symbols.
   - Per-arity template families (`apply` × 6, `mkPattern` × 5, `forall` × 5, `exists` × 5) collapse to `varargs[Z3Term]` once the concept exists.
   - **Behaviour-preserving**: external API stays the same. Users can't tell whether their type's `=destroy` came from a hand-written hook or a generated one.

2. **Carried-forward gaps from v0.2 + small cleanups** (the post-v0.2 audit's full Category B + the architectural audit's polish items, folded together — no v0.2.1 point release):
   - **`z3/semantics`** module relocating `smtValid` (currently in `solver.nim`) and `smtEquiv` (currently split between `solver.nim` and `bitvec.nim`), with the missing overloads for `Z3Array[K,V]` and `Z3DatatypeValue[T]`. Discoverability + audit close in one move.
   - **`Z3Model.eval` / `[]` overloads for `Z3Array[K, V]` and `Z3DatatypeValue[T]`** — the most user-visible v0.2-promised-but-missed gap. Naturally falls out of the unified `wrap[T: Z3Term]` from goal 1.
   - **`Z3_apply_result_convert_model`** — tactic-pipeline witness round-trip.
   - **`evalReal` / `toRealApprox(precision)` composer** with a precision policy doc-noted (default 15 decimal digits; matches float64).
   - **Retire dead `SortTag` enum members** (`stArray`, `stDatatype`) or document them clearly as "scaffolding only — the typed families don't use them." Currently they exist but produce no `Z3Sort[stArray]` / `Z3Sort[stDatatype]` values anywhere.
   - **Normalise `mkBitVec` signature** — current `mkBitVec(v, 8)` takes width as a trailing positional `static int`, every other family uses generic brackets (`mkBitVecVar[8]`, `mkConstArray[K,V]`, `mkBigBitVec[128]`, `declareDatatype[T]`). Breaking change: `mkBitVec[8](5'u32)`. No consumers; pre-1.0 is the right time.

   *Scope-pruned mid-v0.3 (after step 3 review):* DOT / GraphViz AST export and wider-width BV recipes were originally queued here. Both are out of scope for the wrapper — see §8 "scope discipline" for the rationale and the redirect.

3. **String theory + regex** — `Z3String` phantom-typed values, `mkString` literals, `mkStringVar`, operators (`concat`, `length`, `at`, `substr`, `contains`, `prefixOf`, `suffixOf`), regex (`Z3_mk_re_*`).

4. **Sequence theory** — `Z3Seq[E]` phantom-typed over element type. `mkSeqEmpty`, `mkSeqUnit`, `concat`, `length`, `nth`, `extract`, `replace`, …

5. **FloatingPoint theory** — IEEE 754 / SMT-LIB FP arithmetic. `Z3Fp[E, S]` parameterised over exponent width / significand width (`Z3Fp[8, 24]` = float32, `Z3Fp[11, 53]` = float64). Rounding modes via `Z3RoundingMode`.

6. **Uninterpreted functions** — `Z3FuncDecl[ArgsTup, Ret]` typed wrapper, `mkFuncDecl[ArgsTup, Ret](name)`, per-arity `apply` template that produces the right `Ret`-typed AST. Lets users encode their own theories axiomatically: `forall x. f(g(x)) == x`.

7. **Solver–tactic bridges** — `Z3_mk_solver_from_tactic` (wrap a tactic chain into a `Z3Solver`) + `Z3_solver_set_params` (params API for existing `Z3Solver` now that `Z3Params` exists).

8. **Fixedpoint engine** — `Z3Fixedpoint` for Horn-clause solving. Lower priority; may roll to v0.4 if it has scope drift.

9. **Carried-forward CI work** if [#1](https://github.com/coreyleavitt/nim-z3/issues/1) unblocks during v0.3: macOS / aarch64 rows, nim-doc Pages, valgrind, differential testing against `z3` CLI. Logged as conditional — doesn't gate the tag.

10. **`{.optional.}` softlink declarations** once a v0.3 module uses a 4.13+ symbol.

11. **Pre-tag audit for v0.3** — the same discipline v0.2 introduced: a §8 sub-block enumerating every v0.3-promised item that didn't land before the tag.

### Non-goals

- **Custom theories via user propagators** (`Z3_solver_propagate_*`). Powerful but a substantial surface; v0.4+ unless a clear use case appears.
- **High-level macro DSL** (`solve: forall x in Int, x + 1 > x`). Same review status as v0.2 §1 non-goals — the wrapper IS the API call.
- **Differential testing against Python z3**. Bigger lift than the CLI variant under goal 9; v0.4 follow-up.

---

## 2. The shape of the v0.3 expansion

### 2.0 Architectural unification (the v0.3 step-1 work)

The post-v0.2 audit (full notes in the conversation log; the headline findings are in §1 goal 1) flagged that the five typed value families share an unstated contract that's currently encoded by repetition rather than abstraction:

| Family | Lifecycle hooks | Wrap helper | Inline `when T is X` callers |
|---|---|---|---|
| `Z3Ast[S]` | `=destroy[S]`, `=copy[S]`, `=dup[S]` in `ast.nim` | `wrap[S]` | — |
| `Z3BitVec[W]` | same shape, in `bitvec.nim` | `wrapBv[W]` | dispatched by `array.select` / `optimize.upper` / `optimize.lower` / `datatypes.read` / `model.eval` |
| `Z3Array[K, V]` | same, in `array.nim` | `wrapArray[K, V]` | dispatched by `array.select` (return type) |
| `Z3DatatypeValue[T]` | same, in `datatypes.nim` | `wrapValue[T]` (**private**) | dispatched by `datatypes.read` |
| `Z3Pattern` | same shape, in `quantifier.nim` | inline | — |

Total: 22 verbatim copies of the three lifecycle hooks across 9 modules, 5 separately-named `wrap*` helpers, 6+ inline `when T is X` dispatch blocks, plus 24 per-arity templates over `typed` (`apply` × 6, `mkPattern` × 5, `forall` × 5, `exists` × 5) that exist because there's no concept binding the families.

These are three symptoms of one missing abstraction. v0.3 step 1 introduces it before adding the next four typed families (which would otherwise copy the boilerplate four more times):

```nim
# Sketch — actual interface decided in the cycle.

type Z3Term* = concept x
  x.raw is RawZ3Ast
  x.ctx is Z3Context
  type x.RawSym is RawZ3Ast   # marker for "uses Z3_inc_ref / Z3_dec_ref"

type Z3Refcountable* = concept x
  x.raw is (RawZ3Solver | RawZ3Model | RawZ3Optimize | RawZ3Goal |
            RawZ3Tactic | RawZ3ApplyResult | RawZ3Params | RawZ3Context)
  x.ctx is Z3Context
  # different inc_ref / dec_ref symbol per raw type, looked up via the concept

template emitLifecycle*(T: typedesc, RawType: typedesc) =
  ## Generate =destroy / =copy / =dup hooks for a Z3Term-shaped type T
  ## whose underlying raw handle is RawType. Called once per typed
  ## family declaration; replaces the 22 hand-written copies.

template wrap*[T: Z3Term](theCtx: Z3Context, theRaw: RawZ3Ast): T =
  block:
    let r = theRaw
    if not r.isNil: Z3_inc_ref(theCtx.raw, r)
    T(raw: r, ctx: theCtx)
```

Critically, **this is behaviour-preserving**. The external API stays identical; users can't tell their type's `=destroy` came from a generated template rather than a hand-written copy. The new typed families v0.3 adds (`Z3String`, `Z3Seq[E]`, `Z3Fp[E,S]`, `Z3FuncDecl[…]`) then become one-line concept satisfactions, not 22-line repetitions.

The §7 open questions list one genuinely uncertain point: whether the concept cleanly handles `Z3ConstructorDeclOwn[T]` (whose lifecycle dec_refs a *list* of `RawZ3FuncDecl`, not a single AST handle). The cycle-1 TDD work answers it.

### 2.1 The typed value families (post-unification)

v0.2 settled five phantom-type families; v0.3 adds four more. All satisfy `Z3Term` after step 1:

- `Z3Ast[S: static SortTag]` for sorts where width / parameters don't matter at the type level (Int, Real, Bool).
- `Z3BitVec[W: static int]` for width-tracked BVs.
- `Z3Array[Key, Val]` typedesc-phantom over key/value AST types.
- `Z3DatatypeValue[T]` marker-type phantom (`type Maybe = object` → `Z3DatatypeValue[Maybe]`).
- `Z3Pattern` (no phantom; quantifier trigger).
- **NEW** `Z3String` (type alias under `Z3Ast[stString]`).
- **NEW** `Z3Regex` (type alias under `Z3Ast[stRegex]`).
- **NEW** `Z3Seq[E]` typedesc-phantom over element type.
- **NEW** `Z3Fp[Ebits, Sbits: static int]` width-parameterised over IEEE 754 sizes.
- **NEW** `Z3FuncDecl[ArgsTup, Ret]` typedesc-phantom over (arg tuple, return type).

Each follows the same precedent: the minimum type-level information that catches a real bug at compile time, and nothing more.

### Strings — `Z3String`

Strings in Z3 are characters from a Unicode subset. Sort is fixed (no width parameter), so `Z3String` is a plain type alias under `Z3Ast[stString]`:

```nim
type Z3String* = Z3Ast[stString]   # parallels Z3Int / Z3Real / Z3Bool
```

Surface:

```nim
proc mkString*(ctx: Z3Context, s: string): Z3String
proc mkStringVar*(name: string): Z3String

proc concat*(a, b: Z3String): Z3String      # operator and varargs
proc length*(s: Z3String): Z3Int
proc at*(s: Z3String, i: Z3Int): Z3String   # single-char substring
proc substr*(s: Z3String, off, len: Z3Int): Z3String
proc contains*(haystack, needle: Z3String): Z3Bool
proc indexOf*(s, sub: Z3String, off: Z3Int): Z3Int
proc replace*(s, src, dst: Z3String): Z3String
proc prefixOf*(p, s: Z3String): Z3Bool
proc suffixOf*(p, s: Z3String): Z3Bool
proc toRe*(s: Z3String): Z3Regex
proc inRe*(s: Z3String, r: Z3Regex): Z3Bool

proc toBigStringStr*(s: Z3String): string   # model extraction
```

### Regexes — `Z3Regex`

```nim
type Z3Regex* = Z3Ast[stRegex]

proc reUnion*(r1, r2: Z3Regex): Z3Regex
proc reInter*(r1, r2: Z3Regex): Z3Regex
proc reConcat*(r1, r2: Z3Regex): Z3Regex
proc reStar*(r: Z3Regex): Z3Regex
proc rePlus*(r: Z3Regex): Z3Regex
proc reOpt*(r: Z3Regex): Z3Regex
proc reEmpty*(): Z3Regex
proc reFull*(): Z3Regex
```

### Sequences — `Z3Seq[E]`

Generalisation of strings; `E` is the element type as a typedesc (Z3Int, Z3BitVec[W], Z3DatatypeValue[T]). Same `sortOfType` dispatch as arrays.

```nim
type Z3Seq*[E] = object
  raw*: RawZ3Ast
  ctx*: Z3Context

proc mkSeqEmpty*[E](): Z3Seq[E]
proc mkSeqUnit*[E](x: E): Z3Seq[E]
proc mkSeqVar*[E](name: string): Z3Seq[E]
proc concat*[E](a, b: Z3Seq[E]): Z3Seq[E]
proc length*[E](s: Z3Seq[E]): Z3Int
proc nth*[E](s: Z3Seq[E], i: Z3Int): E
proc extract*[E](s: Z3Seq[E], off, len: Z3Int): Z3Seq[E]
# etc.
```

### FloatingPoint — `Z3Fp[Ebits, Sbits]`

Static int parameters for exponent and significand widths. SMT-LIB FP convention: `Z3Fp[8, 24]` = float32, `Z3Fp[11, 53]` = float64, `Z3Fp[5, 11]` = float16.

```nim
type Z3Fp*[Ebits, Sbits: static int] = object
  raw*: RawZ3Ast
  ctx*: Z3Context

type Z3RoundingMode* = enum
  rmNearestEven, rmNearestAway, rmTowardPositive, rmTowardNegative, rmTowardZero

proc mkFp*[Ebits, Sbits: static int](v: float, rm: Z3RoundingMode = rmNearestEven): Z3Fp[Ebits, Sbits]
proc mkFpVar*[Ebits, Sbits: static int](name: string): Z3Fp[Ebits, Sbits]
proc `+`*[Ebits, Sbits](a, b: Z3Fp[Ebits, Sbits], rm: Z3RoundingMode = rmNearestEven): Z3Fp[Ebits, Sbits]
# etc. for -, *, /, sqrt, abs, neg, comparison, isNaN, isZero, ...
```

### Uninterpreted functions — `Z3FuncDecl[(Args), Ret]`

Phantom-typed over the arg-type tuple and return type, parallel to step 4's `Z3AccessorDecl`. Per-arity `apply` templates.

```nim
type Z3FuncDecl*[ArgsTup; Ret] = object
  raw*: RawZ3FuncDecl
  ctx*: Z3Context

proc mkFuncDecl*[ArgsTup; Ret](name: string): Z3FuncDecl[ArgsTup, Ret]

template apply*[Ret](f: Z3FuncDecl[(), Ret]): Ret
template apply*[A, Ret](f: Z3FuncDecl[(A,), Ret], a: A): Ret
template apply*[A, B, Ret](f: Z3FuncDecl[(A, B), Ret], a: A, b: B): Ret
# ... arity 1-5
```

---

## 3. Module structure

```
src/z3/
├── (every v0.2 module, unchanged)
├── string.nim          # NEW   Z3String, mkString*, concat, length, at, ...
├── regex.nim           # NEW   Z3Regex, reUnion, reStar, ...
├── seq.nim             # NEW   Z3Seq[E], mkSeqEmpty, nth, ...
├── fp.nim              # NEW   Z3Fp[Ebits, Sbits], Z3RoundingMode, FP arith
├── funcdecl.nim        # NEW   Z3FuncDecl[ArgsTup, Ret], mkFuncDecl, apply
└── dot.nim             # NEW   AST → GraphViz DOT export

src/z3/model.nim                # extended: eval / [] for Z3Array, Z3DatatypeValue
src/z3/bitvec.nim               # extended: smtEquiv overloads if not already
src/z3/array.nim                # extended: smtEquiv overload
src/z3/datatypes.nim            # extended: smtEquiv overload
src/z3/tactic.nim               # extended: Z3_apply_result_convert_model wrapper
src/z3/solver.nim               # extended: solver_from_tactic, set_params
src/z3/optimize.nim             # extended: Pareto-mode model extraction
src/z3/model.nim                # extended: evalReal / toRealApprox

tests/
├── (every v0.2 test, unchanged)
├── tstring.nim
├── tregex.nim
├── tseq.nim
├── tfp.nim
├── tfuncdecl.nim
└── tdot.nim
examples/
├── (every v0.2 example, unchanged)
├── strings_solve.nim
├── regex_match.nim
├── floats_solve.nim
└── func_axioms.nim
```

---

## 4. Phasing — what ships when

### v0.3.0 — architectural unification + theory completion

1. **Architectural unification.** `Z3Term` + `Z3Refcountable` concepts, unified lifecycle/wrap surface, behaviour-preserving migration of every existing typed family. ✅ shipped (commit `ea46a86`).
2. **`z3/semantics` module + carryover gaps.** `smtValid` / `smtEquiv` relocated with the missing `Z3Array` / `Z3DatatypeValue` overloads. `Z3Model.eval` / `[]` for those types. `convertModel` (was `Z3_apply_result_convert_model` pre-spec-correction; see §8). `evalReal` / `toRealApprox`. ✅ shipped (commit `78852f4`).
3. **Small cleanups.** Dead `SortTag` retirement + `mkBitVec` signature normalisation. ✅ shipped (commit `7b2d59f`).
4. **Strings + regexes** (`z3/char`, `z3/string`, `z3/regex`). ✅ shipped.
5. **Sequences** (`z3/seq`). ✅ shipped.
6. **FloatingPoint** (`z3/fp`). ✅ shipped.
7. **Uninterpreted functions** (`Z3FuncDecl`). ✅ shipped.
8. **Solver–tactic bridges**: `Z3_mk_solver_from_tactic` + `Z3_solver_set_params` for `Z3Solver`. ✅ shipped.
9. Pre-tag audit. ✅ shipped (this commit).
10. v0.3 tag.

*Pruned from this list mid-v0.3:* DOT / GraphViz AST export (out-of-scope; redirected to a future `nim-z3-tools` sibling per §8 scope discipline) and "wider-width BV recipes" as a numbered step (recipes are continuous — extended whenever a theory family lands).

### v0.4+ — frontier features

- Fixedpoint engine (`Z3Fixedpoint`).
- User propagators / custom theories.
- High-level macro DSL (still under review).
- Differential testing against Python z3.

---

## 5. Implementation sequence

Architectural work first (so subsequent steps inherit the unified surface and don't reintroduce boilerplate); carryover gaps and small cleanups next (so the audit closes before new theories pile on); then the new theory families; then bridges and tag.

1. **Architectural unification.** ✅ shipped (`ea46a86`). `Z3Term` + `Z3Refcountable` concepts. Lifecycle-hook generator template. Unified `wrap[T: Z3Term]` template. All 652 v0.2 tests still passed.

2. **`z3/semantics` module + missing overloads + carried-forward gaps.** ✅ shipped (`78852f4`). Relocated `smtValid` / `smtEquiv` with generic `smtEquiv[T]`. Generalised `Z3Model.eval` / `[]`. Landed `convertModel` (via `Z3_goal_convert_model` — `Z3_apply_result_convert_model` retired in Z3 4.8.0; spec correction in §8). Landed `evalReal` / `toRealApprox` (no precision knob — `Z3_get_numeral_double` picks closest float64; spec correction in §8).

3. **Small cleanups.** ✅ shipped (`7b2d59f`). Retired `stArray` / `stDatatype` from `SortTag`. Normalised `mkBitVec` to `mkBitVec[W: static int](v: SomeInteger): Z3BitVec[W]` (T moved into the value-param typeclass — Nim can't infer a second generic when the first is bracket-supplied; spec correction in §8).

4. **Strings + regexes.** ✅ shipped. Three modules: `z3/char` (Z3Char Unicode-codepoint family — first use of the step-1 unified concept for a new family), `z3/string` (Z3String with full SMT-LIB seq op coverage + Nim-string-literal lifts), `z3/regex` (Z3Regex[Basis] phantom over the basis sequence sort — Z3String only in step 4; step 5's Z3Seq[E] generalises). Spec corrections in §8.

5. **Sequences** (`z3/seq`). ✅ shipped. Generalisation of strings; same dispatch story.

6. **FloatingPoint** (`z3/fp`). ✅ shipped. Rounding-mode parameterised arithmetic; type-level width safety per IEEE 754.

7. **Uninterpreted functions** (`z3/funcdecl`). Phantom-typed over `(ArgsTup, Ret)`; per-arity `apply` templates (under step 1, these may be unifiable with `varargs[Z3Term]`).

8. **Bridges**: `Z3_mk_solver_from_tactic` + `Z3_solver_set_params` for `Z3Solver`.

9. **Pre-tag audit + rollforward annotations** per the v0.2 precedent.

10. **v0.3 tag.**

---

## 6. Risks specific to v0.3

### The architectural unification touches every existing module

Step 1 migrates 22 hand-written lifecycle hooks + 5 wrap helpers + multiple inline `when T is X` dispatch blocks to a single generator. Migration is behaviour-preserving by design — the contract callers see doesn't change — but the blast radius covers every typed module in v0.2.

Mitigation: TDD discipline at the granularity of one *type family* per cycle. The full 652-test v0.2 suite must stay green after each migration. Anomalies (e.g. `Z3ConstructorDeclOwn[T]`'s list-of-func-decls dec_ref pattern not fitting the concept; flagged in §7 Q1) get resolved by either widening the concept or keeping the offender as a hand-written hook with a clear documented exception. If the concept doesn't cleanly cover all five families, the unification falls back to *partial* unification — still a win, but a smaller one. The cycle reports honestly.

### Strings + regexes are not always decidable

Z3's string solver is incomplete in general. Some queries will return `zsUnknown` (or hang). The wrapper can't fix this, but the tests should explicitly include `zsUnknown` as a possible outcome, and the docstring should walk through the "why does my regex query never return" failure mode the same way step 6's quantifier docstring walks through "why does my forall run forever."

### FloatingPoint NaN semantics

NaN is unique among floating-point values: `nan == nan` is false, `nan != nan` is true. The wrapper's `==` overload on `Z3Fp[E, S]` returns a `Z3Bool` — that's correct, but users coming from native float comparison may be surprised. Document loudly; ensure the property tests don't accidentally exercise NaN cases assuming reflexivity.

### Uninterpreted function arity ceiling

Per-arity templates 1–5 for `apply`. Larger arities are mechanical — bump on demand or write a varargs macro (same decision as v0.2 step 4's `apply`). Lean: per-arity templates.

### v0.2 §8 "Pre-tag audit" rollover backlog

A non-trivial number of v0.2-promised items rolled to v0.3 (per V0.2_PLAN.md "Pre-tag audit" block). This step's §1 makes them all v0.3 goals; the risk is scope creep if all of them need full TDD attention. Mitigation: §5 sequence puts them first so they ship early in v0.3.

---

## 7. Open questions (genuinely open — answer during implementation)

1. **`Z3ConstructorDeclOwn[T]` fit in the `Z3Refcountable` concept.** Its `=destroy` dec_refs a *list* of `RawZ3FuncDecl` (the constructor's accessors), not a single AST handle. Does the v0.3 step-1 unified lifecycle generator handle "N inc_refs / N dec_refs per instance," or does this stay as a hand-written exception? Lean: widen the concept to take a `releaseAll(self)` proc the type provides — the generator calls that instead of issuing dec_ref directly. Decide during cycle 1.

2. **`Z3Fp[Ebits, Sbits]` vs `Z3Fp32` / `Z3Fp64` aliases.** Should we expose typed aliases for the common widths? Lean yes — `Z3Fp[8, 24]` reads poorly compared to `Z3Float32`.

3. **`toRealApprox(precision)` policy.** What's "precision" — number of decimal digits, an explicit epsilon, a tolerance? Z3 itself uses string-form rationals exactly; the approximation is purely our extraction. Lean: precision = number of decimal digits, default 15 (matches float64 precision).

4. **String element type.** SMT-LIB strings are sequences of Unicode characters; Z3 represents them as `Z3_string` (UTF-8). The Nim representation should be `string` (UTF-8 idiomatic in Nim 2). Lean: yes, with a tested round-trip.

5. **`Z3FuncDecl` arg type encoding.** `Z3FuncDecl[(A, B, C), Ret]` uses a tuple typedesc. Alternative: separate generic per arg. Tuple is cleaner for type inference; arities are visible in the type. Lean: tuple form.

---

## 8. Deferred from v0.3 (running list, updated as we go)

### Scope discipline — what nim-z3 IS and ISN'T

Pressure-tested mid-v0.3 (after step 3). The wrapper's contract is:

> Type-safe, memory-safe, Nim-idiomatic access to **every capability the Z3 C API exposes** — and nothing else.

If Z3 doesn't ship the capability, it isn't ours to build. The moment we add features Z3 doesn't have, we're a different package wearing the wrapper's clothes. Concrete consequences for the v0.3 backlog:

- **DOT / GraphViz AST export — removed from v0.3.** Z3 ships `Z3_ast_to_string` (SMT-LIB) and `Z3_benchmark_to_smtlib_string`; it does NOT ship DOT or any graph-output API. A DOT exporter would be a custom AST visitor we author — a *visualization tool over* Z3's AST graph, not a wrapping of a Z3 capability. **Redirect:** if/when DOT export is wanted, the right home is a sibling package `nim-z3-tools` (or `nim-z3-viz`) that depends on `nim-z3` and consumes its public AST surface. Same logic applies to a future interactive REPL, SMT-COMP driver, AST query DSL, etc.
- **Wider-width BV recipes — demoted from a numbered step to continuous practice.** `tests/recipes.nim` is example/idiom content, not API surface; it gets extended whenever a theory family lands that has recipe-able material. Not a release-blocker on its own.

The same lens applies to anything we add later: before promoting it to a v0.3+ step, ask "what Z3 C function does this wrap?" If the answer is "none, it builds on top," it belongs in a tools sibling, not here.

### From step 2 (semantics module + carryover gaps)

- **Spec correction**: the v0.2 audit's "`Z3_apply_result_convert_model`" promise was based on a function that was retired in Z3 4.8.0 (2018). The same capability exists today as `Z3_goal_convert_model` — lives on the sub-`Z3Goal` rather than on the `Z3ApplyResult`, but provides the identical functionality. v0.3 step 2 routed the user-facing `convertModel(applyResult, idx, subModel)` ergonomic through `Z3_goal_convert_model` on the indexed sub-goal. **No work deferred** — the capability landed, just under the modern Z3 name.
- **Spec correction**: the v0.1 §18 / v0.3 plan §7 Q3 "precision = 15 decimal digits" lean for `toRealApprox` was a misread. `Z3_get_numeral_double` doesn't take a precision parameter — Z3 picks the closest representable double and we report it. The Nim API is `toRealApprox*(a: Z3Real): float`; no `precision` arg. Same precision policy as the FFI: whatever float64 IEEE 754 lets you encode.
- **Epsilon-bound Real extraction** (e.g. optimisation bounds like `1/2 + ε`). The current `toRealApprox` raises `Z3Error` for these because `Z3_get_numeral_double` only handles numerals; the epsilon term blocks. **Where**: v0.4 if a real user wants to extract a specific finite value from an epsilon-bounded objective. Workaround: simplify + inspect the AST kind manually before extracting.

### From step 9 (pre-tag audit + sortdispatch consolidation)

- **Architectural payoff**: the three `sortOfType` / `sortOfTypeSeq` / `sortOfTypeFD` cascades collapsed to a single `mixin sortOf` dispatch in `z3/sortdispatch`. Each typed family now owns its own `sortOf` overload at the declaration site; `sortOfType[T]` is a one-line template with `mixin sortOf` that defers resolution to the instantiation site. Adding a new typed family in v0.4+ is now one `sortOf` overload in that family's module — zero edits to any central dispatcher.
- **Bonus capability**: this closes the v0.2 §8 "nested arrays deferred — typedesc-reflection limit" item. `Z3Array[Z3Int, Z3Array[Z3Int, Z3Int]]` round-trips through store/select. The same mechanism unlocks `Z3FuncDecl[(Z3Array[Z3Int, Z3Int],), Z3Bool]` and `Z3Seq[Z3Array[K, V]]` for free.
- **Z3DatatypeValue as a sortdispatch element type — explicitly deferred to v0.4.** A datatype's sort handle is created at runtime (by `declareDatatype`) and stored on its decl. `sortOf(_: typedesc[Z3DatatypeValue[T]], ctx)` would need a runtime decl-table lookup keyed by `T`'s marker type. Real Z3 capability, real ergonomic win (`Z3Array[Z3Int, Z3DatatypeValue[Foo]]`), but the decl-table indirection deserves its own design pass.
- **Dead `./sort` imports cleared** from `builder.nim`, `model.nim`, `quantifier.nim`, `optimize.nim` — four `Warning: imported and not used` lints had been printing on every compile since step 1's lifecycle relocation moved `Z3Sort` discovery off the direct-import path. Pre-tag clean compile.

### From step 8 (solver-tactic bridges)

- **Spec correction**: I originally planned an observable-effect test for `setParams` via `model=false` + `s.model()` raising on a sat solver. Z3 4.13.3 **does not honour `model=false`** on a solver in that way — `s.model()` still returns a model. The wrapper's contract is "pass the typed bag through and don't break the solver"; whether a given Z3 param has its documented runtime effect is Z3's problem, not the wrapper's. Test replaced with a typed-params-breadth check (bool / uint / float / string overloads of `Z3Params.set` all land in `setParams` without error). **No work deferred** — the bridge is solid.
- **`Z3_solver_get_param_descrs` introspection deferred.** Z3 ships a per-solver param-descrs surface that would let users discover valid keys and types at runtime. Could be useful for tooling on top of the wrapper, but the surface (a separate `Z3_param_descrs` ref-typed handle with `Z3_param_descrs_get_kind` / `_get_documentation` / `_size`) deserves its own design pass. **Where**: v0.4 if a real consumer needs schema-driven param configuration. Not blocking.
- **`Z3_solver_get_unsat_core` / `Z3_solver_get_proof` deferred.** Surfaced as natural follow-ups to setting `unsat_core=true` / `proof=true` on a solver, but these are richer features (AST vector handling for cores; the proof AST grammar for proofs) with their own ergonomics questions. **Where**: v0.4. Not blocking.

### From step 7 (uninterpreted functions)

- **`Z3_func_interp` tabular interpretation extraction deferred.** Z3 ships `Z3_model_get_func_interp(model, fd)` returning a `Z3_func_interp` handle: a sequence of explicit (args → value) entries plus an "else" default. The headline use case ("what value does f take at point x?") is covered by `evalAt(m, f, args)`. The full tabular surface (ref-typed handle, entry iteration, else-value extraction) is a richer feature and deserves its own focused design pass. **Where**: v0.4 if a real user needs to enumerate the model's full interpretation table. Not blocking the v0.3 tag.
- **`sortOfType` / `sortOfTypeSeq` / `sortOfTypeFD` duplication consolidation.** Step 7's `sortOfTypeFD` is the third cascade dispatcher (after `array.sortOfType` covering Int/Real/Bool/BV and `seq.sortOfTypeSeq` adding Char and recursive Seq). It now covers the full v0.3 family set including `Z3Fp[E, S]`. The three cascades are 80% identical; the right consolidation is a single `z3/sortdispatch` module that all three import from. **Where**: v0.3 step 9 (pre-tag audit / cleanup commit). Moved up from "future cleanup" to "blocking before tag" because every new typed family now requires updating three cascades.
- **`{.experimental: "callOperator".}` is module-local in `z3/funcdecl`.** Needed to make `f(x, y)` work as a call on the `Z3FuncDecl` value. Scoped via the `experimental` pragma at module head, not globally enabled. No knock-on effect on other modules. Documented in the module header.

### From step 6 (FloatingPoint)

- **Spec correction**: `Z3_fpa_get_numeral_double` does **not** exist in z3.h (despite the obvious symmetry with `Z3_get_numeral_double` for Reals). Z3 ships only piece-wise FP-numeral introspection (sign / significand / exponent as separate calls). Resolution: extract via `Z3_mk_fpa_to_ieee_bv` → `Z3_simplify` → `Z3_get_numeral_uint64`, then reinterpret-cast in Nim. Lossless across all IEEE-754 binary32 / binary64 bit patterns (NaN payloads preserved). **No work deferred** — the model extractor (`toFloat32` / `toFloat64` / `evalFloat32` / `evalFloat64`) shipped through the IEEE-BV route.
- **Spec correction**: `==` / `!=` on `Z3Fp[E, S]` use **IEEE equality (`Z3_mk_fpa_eq`)**, not structural equality (`Z3_mk_eq`). Deliberate divergence from every other typed family. The case for divergence: in IEEE land, `nan == nan` is false and `+0 == -0` is true, which is what users writing FP code overwhelmingly expect. The case against: it breaks the assumption that `Z3Term`'s `==` is uniformly structural. Document loudly (module head + `==` docstring); if anyone needs structural eq they can drop to `astEqual` (pointer identity) or call `Z3_mk_eq` directly via the FFI. **No work deferred.**
- **Quadruple-precision (Z3Float128) NaN-payload extraction.** `toFloat32` / `toFloat64` round-trip every IEEE binary32 / binary64 pattern. `Z3Float128` and `Z3Float16` have no Nim-native floating-point type to extract into; users wanting the bit pattern call `toIeeeBv` and inspect the BV directly. **Where**: tooling concern; if someone needs structured 128-bit extraction we surface `fpa_get_numeral_*` piecewise extractors. Not blocking.

### From step 5 (sequences)

- **Refactor: `Z3String = Z3Seq[Z3Char]` alias.** Z3 itself defines `String = (Seq Char)`. Step 4 shipped `Z3String` as its own value family with a duplicated `seq.*` surface; step 5 collapses it to a Nim type alias over `Z3Seq[Z3Char]`. Every generic seq op (`len`, `concat`, `&`, `nth`, `at`, `substr`, `contains`, `startsWith`/`endsWith`, `indexOf`, `replace`, `==`, `!=`) now lives once on `Z3Seq[E]` and applies to `Z3String` automatically. `z3/string` now ships only the string-specific surface (`mkString` via `lstring`, `mkStringVar`, `toStr`/`evalStr`, `strToInt`/`intToStr`, the Nim-`string`-literal lifts). All 14 step-4 string tests still pass; no behavior change. **No work deferred** — pure structural cleanup.
- **`Z3Regex[Basis]` widened from `Basis is Z3String` to `Basis is Z3Seq[E]`.** `Z3String` flows through via the alias; `Z3Regex[Z3Seq[Z3Int]]` etc. are now constructible. New regression test in `tregex.nim` proves the generalisation. **No work deferred.**
- **`sortOfTypeSeq[E]` cascade lives in `z3/seq`.** Step 4's `z3/array` had a `sortOfType[T]` that supported only `Z3Int / Z3Real / Z3Bool / Z3BitVec[W]`. Step 5 adds the parallel `sortOfTypeSeq` covering `Z3Char` and recursive `Z3Seq[E']` for nested sequences. Centralising both into a single `z3/sortdispatch` module is the right consolidation but isn't blocking — logged for a future cleanup commit, not deferred to v0.4.

### From step 4 (strings + regexes)

- **Spec correction**: my initial diagnosis that `Z3_mk_re_range` requires `Char`-sorted operands in 4.13.x was wrong. Z3's polymorphic sort checker explicitly rejects `Char` operands with `"Expected domain: (Seq k!0) (Seq k!0)"` — `re.range` is `(String String) RegEx String` per SMT-LIB-2.6, and Z3 enforces that. The original "UNEXPECTED CODE WAS REACHED" assertion at `ast.cpp:388` was triggered by building the operand strings via raw `Z3_mk_string` (null-terminated cstring path); switching to `Z3_mk_lstring` (length-prefixed — what our `mkString` uses) avoids the assertion. The wrapper's `range` lives on the `Z3String`-typed overload, with a `range(lo, hi: string)` Nim-string-lift ergonomic for the common ASCII case. **Resolved in source; no work deferred.**
- **`Z3Char` BV interop deferred.** `Z3_mk_char_to_bv` / `Z3_mk_char_from_bv` are real Z3 entry points but their typed BV width depends on Z3's runtime `:char-width` parameter (default 18 bits). Surfacing them well needs deciding whether to lock to `Z3BitVec[18]` or thread a width param through, plus a small reorg so `z3/char` and `z3/bitvec` can see each other. **Where**: v0.4 or a focused mid-v0.3 follow-up.
- **String replace-all.** `Z3_mk_seq_replace` is first-occurrence only. SMT-LIB / Z3 doesn't ship a direct `replace-all`; the idiom is regex-based composition. **Where**: doc note in `z3/string`; user-facing replace-all helper is a v0.4 ergonomic if a real user needs it.

### From step 3 (small cleanups)

- **Spec correction**: the §5 step-3 lean signature `mkBitVec[W: static int, T: SomeInteger](v: T): Z3BitVec[W]` didn't compile — Nim won't infer a second generic from a value parameter when the first is bracket-supplied (call site `mkBitVec[8](5'u32)` failed to bind `T`). Resolution: collapse `T` into the value-param typeclass slot: `mkBitVec[W: static int](v: SomeInteger): Z3BitVec[W]`. Functionally identical (`SomeInteger` still constrains to Nim's primitive integer types), call-site identical, but Nim can resolve it. **No work deferred** — the cleanup landed under the working signature.

### Scope-pruned items (redirected, not deferred)

- **DOT / GraphViz AST export** — out of scope per the §8 scope discipline above. If/when wanted, lives in a future `nim-z3-tools` sibling package.
- **Wider-width BV recipes as a numbered step** — recipes are continuous practice; extended in tests/recipes.nim alongside the theory family that motivates them.

Same discipline as v0.1 §18 and v0.2 §8 — append-only. Format: **what**, **why**, **where it goes** (v0.4 / dropped / sibling-package).

---

## 8b. Pre-tag audit — v0.3

The structured walk before tagging, mirroring the v0.2 precedent. Each §1 goal + §5 step is classified as **landed / rolled to v0.4 / dropped / sibling-package**, with the commit hash for landed items.

### §1 Goals

| # | Goal | Status | Commit / Notes |
|---|---|---|---|
| 1 | Architectural unification (`Z3Term` concept + unified lifecycle/wrap) | ✅ landed | `ea46a86` — v0.3 step 1 |
| 2 | Carried-forward v0.2 gaps + small cleanups | ✅ landed | `78852f4` (semantics), `7b2d59f` (small cleanups). DOT export + recipes scope-pruned mid-v0.3 (see §8 "Scope-pruned items"). |
| 3 | String theory + regex | ✅ landed | `f5c7e91` — v0.3 step 4 |
| 4 | Sequence theory | ✅ landed | `f0965ce` — v0.3 step 5. Also folded `Z3String = Z3Seq[Z3Char]` alias refactor. |
| 5 | FloatingPoint theory | ✅ landed | `438594d` — v0.3 step 6 |
| 6 | Uninterpreted functions (`Z3FuncDecl`) | ✅ landed | `78ff9dc` — v0.3 step 7 |
| 7 | Solver–tactic bridges | ✅ landed | `8be9bee` — v0.3 step 8 |
| 8 | Fixedpoint engine (`Z3Fixedpoint`) | **rolled to v0.4** | Not surfaced as a real-user need during v0.3. Plan §1 already flagged it as "may roll." |
| 9 | Carried-forward CI work (if [#1](https://github.com/coreyleavitt/nim-z3/issues/1) unblocks) | **rolled** (conditional) | The private-dep blocker that filed #1 in v0.2 stayed unresolved through v0.3. Nothing v0.3 did changes this. |
| 10 | `{.optional.}` softlink declarations | **rolled to v0.4** | None of the v0.3 modules pulled a 4.13+-only symbol. Soonest trigger: a new theory wraps a symbol added after Z3 4.10 baseline. |
| 11 | Pre-tag audit for v0.3 | ✅ this block | The audit you are reading. |

### §5 Steps

| Step | Deliverable | Status | Commit |
|---|---|---|---|
| 1 | Architectural unification | ✅ landed | `ea46a86` |
| 2 | `z3/semantics` + carryover gaps | ✅ landed | `78852f4` |
| 3 | Small cleanups (SortTag prune + `mkBitVec` bracket-W) | ✅ landed | `7b2d59f` |
| 4 | Strings + regexes (`z3/char`, `z3/string`, `z3/regex`) | ✅ landed | `f5c7e91` |
| 5 | Sequences (`z3/seq`) + Z3String alias refactor | ✅ landed | `f0965ce` |
| 6 | FloatingPoint (`z3/fp`) | ✅ landed | `438594d` |
| 7 | Uninterpreted functions (`z3/funcdecl`) | ✅ landed | `78ff9dc` |
| 8 | Solver–tactic bridges | ✅ landed | `8be9bee` |
| 9 | Pre-tag audit + sortdispatch consolidation | ✅ this commit | sortdispatch landed + audit block written |
| 10 | v0.3 tag | next commit | The actual `v0.3.0` git tag. |

### Spec corrections logged during v0.3 (cross-reference)

Every step that hit a spec assumption-needed-changing surfaced it back to the user before continuing; the corrections live in their per-step §8 entries above. Summary for the audit:

- **Step 2**: `Z3_apply_result_convert_model` retired in Z3 4.8.0 — moved to `Z3_goal_convert_model` (per-subgoal). Capability identical, modern name. `toRealApprox` precision-knob lean was a misread — `Z3_get_numeral_double` doesn't take a precision arg. Both surfaced before code touched.
- **Step 3**: Nim won't infer a second generic when the first is bracket-supplied — `mkBitVec[W, T]` collapsed to `mkBitVec[W: static int](v: SomeInteger)`. Pure resolution; no design change.
- **Step 4**: `Z3_mk_re_range` operands are **`Z3String`**, not `Z3Char` (Z3's polymorphic sort checker explicitly rejects Char). The internal-assertion failure on raw `Z3_mk_string` was orthogonal; switching to `Z3_mk_lstring` fixed it. `Z3Char` stays in scope as its own typed family with its own surface (`<=`, `<`, `isDigit`, `toInt`).
- **Step 6**: `Z3_fpa_get_numeral_double` does **not** exist in z3.h despite the obvious symmetry with `Z3_get_numeral_double`. Resolution: round-trip via `Z3_mk_fpa_to_ieee_bv` + `simplify` + `Z3_get_numeral_uint64` + Nim reinterpret-cast. Lossless across every IEEE-754 binary32/64 bit pattern. Also: `==`/`!=` on `Z3Fp[E,S]` use **IEEE equality** (`Z3_mk_fpa_eq`), not structural — deliberate divergence from every other typed family because NaN ≠ NaN is what FP users expect.
- **Step 7**: The headline `forall x. f(g(x)) == x` test hung Z3 (classic quantifier-without-trigger problem flagged in §6 risks). Replaced with concrete-witness composition (`f(g(0)) == 42` with `g(0) == 99`) that demonstrates the same uninterpreted-function-composition story while terminating.
- **Step 8**: Z3 4.13.3 **does not honour `model=false`** on a solver — `s.model()` still returns a model after sat. The observable-effect test was replaced with a typed-params-breadth check.
- **Step 9 (this)**: the `sortdispatch` consolidation also closed the v0.2 §8 "nested arrays deferred" item by using `mixin sortOf` to defer name resolution to the instantiation site — no special-case handling for arbitrary nesting depth.

### Items rolled forward to v0.4

These are logged per-step in §8 above. Consolidated here for the rollforward:

- **`Z3Fixedpoint`** — §1 goal 8. Real Z3 capability; no real-user trigger during v0.3.
- **`Z3_solver_get_unsat_core` / `Z3_solver_get_proof`** — natural follow-ups to setting `unsat_core=true` / `proof=true` (step 8). AST-vector / proof-grammar surfaces with their own design.
- **`Z3_solver_get_param_descrs`** — schema-driven param introspection (step 8). Separate ref-typed handle, deserves its own pass.
- **`Z3_func_interp` tabular extraction** — entries + else-value iteration for uninterpreted-function model interpretation (step 7). The headline "value at point" is `evalAt(m, f, args)`; the full table is a richer surface.
- **`Z3Char` BV interop** (`Z3_mk_char_to_bv` / `_from_bv`) — needs runtime `:char-width` thread + cross-module visibility (step 4).
- **`Z3Float128` / `Z3Float16` structured extraction** — no Nim-native float type for those widths; `toIeeeBv` is the escape hatch (step 6).
- **Epsilon-bound `Z3Real` extraction** — `Z3_get_numeral_double` blocks on `1/2 + ε`-shaped optimisation outputs (step 2). Workaround: inspect AST kind manually.
- **`Z3DatatypeValue[T]` as a `sortdispatch` element type** — would let `Z3Array[…, Z3DatatypeValue[Foo]]`, `Z3Seq[Z3DatatypeValue[Foo]]`, etc. construct. Needs runtime decl-table lookup (datatype sorts aren't compile-time). Not blocking pre-1.0.
- **Replace-all on `Z3String`** — Z3 doesn't ship a primitive; idiomatic path is regex composition.
- **Carry-forward CI items (#1)** — same blocker as v0.2.
- **`{.optional.}` softlink declarations** — triggers when first 4.13+-only symbol lands.
- **Differential testing against Python z3** — non-goal as of v0.3.

### Scope-pruned items (redirected to sibling packages or continuous practice)

Already in §8 "Scope-pruned items"; not deferred to v0.4:

- **DOT / GraphViz AST export** — sibling package (`nim-z3-tools`/`-viz`); not a wrapper concern.
- **Wider-width BV recipes** as a numbered step — continuous practice, extended in `tests/recipes.nim` alongside the theory family that motivates them.

### Dropped (won't ship)

(None this release. Items deferred from v0.2 stayed deferred or shipped; no new drops surfaced.)

### Cumulative test count

v0.2 closed at **652 OKs**. v0.3 closes at **890 OKs** across both `nim c` and `nim cpp`. Step-by-step delta:

| After step | Total | Delta | New tests |
|---|---|---|---|
| 1 (unification) | 652 | 0 | (refactor — no new tests) |
| 2 (semantics + carryover) | 674 | +22 | 11 × 2 |
| 3 (small cleanups) | 684 | +10 | 5 × 2 |
| 4 (strings + regexes + chars) | 752 | +68 | 34 × 2 |
| 5 (sequences + Z3String alias) | 788 | +36 | 18 × 2 |
| 6 (FloatingPoint) | 850 | +62 | 31 × 2 |
| 7 (uninterpreted functions) | 872 | +22 | 11 × 2 |
| 8 (solver-tactic bridges) | 886 | +14 | 7 × 2 |
| 9 (sortdispatch + nested arrays + Z3FuncDecl over Z3Array) | 890 | +4 | 2 × 2 |

---

## 9. Closing note

v0.2 introduced the "Pre-tag audit" discipline — a structured pass that catalogues every v0.X-promised item just before the tag and explicitly classifies it as landed / rolled / dropped. v0.3 keeps the discipline; §8 will end with the same kind of audit block before the v0.3.0 tag.

If reading this, future-me, after v0.3 has shipped: archive this file to `docs/V0.3_PLAN.md`, write `docs/IMPLEMENTATION_PLAN.md` for v0.4, and update the README's "Design" section to point at all three archives. The rotation pattern is: every shipped version's plan becomes the historical record; the live plan is always for the next one.

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
   - **DOT / GraphViz AST export** (`z3/dot`) with `Z3_get_ast_id` hash-consing awareness.
   - **Wider-width BV recipes** (W > 8) in `tests/recipes.nim`.

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

1. **Architectural unification.** `Z3Term` + `Z3Refcountable` concepts, unified lifecycle/wrap surface, behaviour-preserving migration of every existing typed family.
2. **`z3/semantics` module + carryover gaps.** `smtValid` / `smtEquiv` relocated with the missing `Z3Array` / `Z3DatatypeValue` overloads. `Z3Model.eval` / `[]` for those types. `Z3_apply_result_convert_model`. `evalReal` / `toRealApprox`.
3. **Small cleanups.** Dead `SortTag` retirement + `mkBitVec` signature normalisation.
4. DOT / GraphViz AST export.
5. Wider-width BV recipes in `tests/recipes.nim`.
6. Strings + regexes.
7. Sequences.
8. FloatingPoint.
9. Uninterpreted functions (`Z3FuncDecl`).
10. Bridges: `Z3_mk_solver_from_tactic` + `Z3_solver_set_params` for `Z3Solver`.
11. v0.3 tag.

### v0.4+ — frontier features

- Fixedpoint engine (`Z3Fixedpoint`).
- User propagators / custom theories.
- High-level macro DSL (still under review).
- Differential testing against Python z3.

---

## 5. Implementation sequence

Architectural work first (so subsequent steps inherit the unified surface and don't reintroduce boilerplate); carryover gaps and small cleanups next (so the audit closes before new theories pile on); then the new theory families; then bridges and tag.

1. **Architectural unification.** `Z3Term` + `Z3Refcountable` concepts. Lifecycle-hook generator template. Unified `wrap[T: Z3Term]` template replacing `wrap[S]` / `wrapBv[W]` / `wrapArray[K,V]` / `wrapValue[T]` and the inline `when T is X` dispatches. Migrate each of the five typed value families + the seven refcountable handles to the new generators, preserving every test. The cycle's tracer is "all 652 v0.2 tests still pass after the migration." TDD discipline: one family at a time, full suite green after each.

2. **`z3/semantics` module + missing overloads + carried-forward gaps.** Relocate `smtValid` (from `solver.nim`) and `smtEquiv` (from `solver.nim` + `bitvec.nim`) into a single `z3/semantics` module; add the missing overloads for `Z3Array[K,V]` and `Z3DatatypeValue[T]`. Land `Z3Model.eval` / `[]` for `Z3Array` and `Z3DatatypeValue` (trivial after step 1's unified `wrap`). Land `Z3_apply_result_convert_model`. Land `evalReal` / `toRealApprox(precision = 15)`.

3. **Small cleanups.** Retire (or clearly document) the unused `stArray` and `stDatatype` SortTag values. Normalise `mkBitVec` signature to `mkBitVec[W: static int](v: SomeInteger): Z3BitVec[W]` (breaking change pre-1.0; update tests + examples in the same commit).

4. **DOT / GraphViz AST export** (`z3/dot`) with `Z3_get_ast_id` hash-consing awareness.

5. **Wider-width BV recipes** (W > 8) in `tests/recipes.nim`.

6. **Strings + regexes** (`z3/string`, `z3/regex`). Tests verify common idioms (`contains` / `replace` / regex matching) decide correctly. **First new typed family using the step-1 unified concept.**

7. **Sequences** (`z3/seq`). Generalisation of strings; same dispatch story.

8. **FloatingPoint** (`z3/fp`). Rounding-mode parameterised arithmetic; type-level width safety per IEEE 754.

9. **Uninterpreted functions** (`z3/funcdecl`). Phantom-typed over `(ArgsTup, Ret)`; per-arity `apply` templates (under step 1, these may be unifiable with `varargs[Z3Term]`).

10. **Bridges**: `Z3_mk_solver_from_tactic` + `Z3_solver_set_params` for `Z3Solver`.

11. **Pre-tag audit + rollforward annotations** per the v0.2 precedent.

12. **v0.3 tag.**

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

Same discipline as v0.1 §18 and v0.2 §8 — append-only. Format: **what**, **why**, **where it goes** (v0.4 / dropped). v0.1 and v0.2 deferrals that remain unaddressed continue to live in their respective archived plans.

*(empty until the first deferral surfaces)*

---

## 9. Closing note

v0.2 introduced the "Pre-tag audit" discipline — a structured pass that catalogues every v0.X-promised item just before the tag and explicitly classifies it as landed / rolled / dropped. v0.3 keeps the discipline; §8 will end with the same kind of audit block before the v0.3.0 tag.

If reading this, future-me, after v0.3 has shipped: archive this file to `docs/V0.3_PLAN.md`, write `docs/IMPLEMENTATION_PLAN.md` for v0.4, and update the README's "Design" section to point at all three archives. The rotation pattern is: every shipped version's plan becomes the historical record; the live plan is always for the next one.

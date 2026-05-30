# nim-z3 v0.3 plan

A type-safe, memory-safe, idiomatic Nim wrapper for the Z3 SMT solver.

**Status**: planning. v0.2 shipped on 2026-05-29 — see [`V0.2_PLAN.md`](V0.2_PLAN.md) for the archived plan that drove it (arrays, datatypes, quantifiers, optimization, tactics + goals + params, the "phantom design via typedescs of AST families" precedent that everything else inherits). This document is the live plan for v0.3, starting from a working v0.2 base.

**Audience**: future-me, future contributors, anyone deciding whether v0.3's surface fits their use case.

What changes between v0.2 and v0.3:

- v0.1 covered the **core**: sorts (Int, Real, Bool, BitVec), Boolean and arithmetic ops, solver, model, pretty/SMT2 round-trip, version probes.
- v0.2 covered the **theories that turn SMT from "arithmetic checker" into "general decision procedure for software verification"**: arrays, datatypes, quantifiers, optimisation, tactics + goals + params.
- v0.3 covers the **remaining theory families** (strings, sequences, FloatingPoint), the **carried-forward gaps** from v0.2 (model conversion across tactics + arrays + datatypes, evalReal, DOT export, …), and the **upstream-blocker resolution work** (multi-platform CI, nim-doc Pages) that's currently filed as [#1](https://github.com/coreyleavitt/nim-z3/issues/1).

The architectural foundation (typedesc-phantoms, refcount lifecycle, current-context threadvar, error-on-FFI-call template, marker-type-as-phantom for datatypes) carries forward unchanged. v0.3 is feature completion across the remaining first-class SMT theories plus the polish that the v0.2 audit identified as missing.

---

## 1. Goals and non-goals

### Goals

1. **Carried-forward gaps from v0.2** (per V0.2_PLAN.md §8 "Pre-tag audit"):
   - `Z3Model.eval`/`[]` overloads for `Z3DatatypeValue[T]` and `Z3Array[K, V]`.
   - `smtEquiv` overloads for those types.
   - `Z3_apply_result_convert_model` for tactic-pipeline witnesses.
   - `evalReal` / `toRealApprox(precision)` composer with a documented precision policy.
   - DOT / GraphViz AST export (`z3/dot`) with `Z3_get_ast_id`-based hash-consing awareness.
   - Wider-width BV recipes (W > 8) in `tests/recipes.nim`.
   - Differential testing against the `z3` CLI binary as a CI job (depends on #1).
   - valgrind job alongside ASAN (depends on #1).
   - `{.optional.}` softlink declarations once a v0.3 module uses a 4.13+ symbol.

2. **String theory** — `Z3String` phantom-typed values, `mkString` literals, `mkStringVar`, operators (`concat`, `length`, `at`, `substr`, `contains`, `prefix-of`, `suffix-of`), regex (`Z3_mk_re_*`).

3. **Sequence theory** — generalisation of strings; `Z3Seq[E]` phantom-typed over element type. `seq.empty`, `unit`, `concat`, `length`, `nth`, `extract`, `replace`, `seq-in-re`, …

4. **FloatingPoint theory** — IEEE 754 / SMT-LIB FP arithmetic. `Z3Fp[E, S]` parameterised over exponent width / significand width (`Z3Fp[8, 24]` = float32, `Z3Fp[11, 53]` = float64). Rounding modes via `Z3RoundingMode`.

5. **Uninterpreted functions** — `Z3FuncDecl` typed wrapper, `mkFuncDecl[T1, …, Ret](name, …)`, `apply` template that produces the right `Ret`-typed AST. Lets users encode their own theories axiomatically: `forall x. f(g(x)) == x`.

6. **`Z3_mk_solver_from_tactic`** — wrap a tactic chain into a `Z3Solver`. Bridges the tactic surface with the standard solver API for users who want a custom solving strategy without abandoning `add` / `check`.

7. **`Z3_solver_set_params`** for the existing `Z3Solver` — now that `Z3Params` exists, the solver can take params too.

8. **Fixedpoint engine** — `Z3Fixedpoint` for Horn-clause solving. Lower priority within v0.3; might roll to v0.4 if it has scope drift.

9. **Pre-tag audit for v0.3** — the same discipline v0.2 introduced: a §8 sub-block enumerating every v0.3-promised item that didn't land before the tag.

### Non-goals

- **Custom theories via user propagators** (`Z3_solver_propagate_*`). Powerful but a substantial surface; v0.4+ unless a clear use case appears.
- **High-level macro DSL** (`solve: forall x in Int, x + 1 > x`). Same review status as v0.2 §1 non-goals — the wrapper IS the API call.
- **Pareto-mode per-point model extraction** and **`Z3_apply_result_convert_model`** are listed above as *goals* (carried forward); they're not non-goals.
- **Re-architecting v0.1 or v0.2.** v0.3 is feature completion + polish; not a redesign.

---

## 2. The shape of the v0.3 expansion

v0.2 settled five phantom-type families:

- `Z3Ast[S: static SortTag]` for sorts where width / parameters don't matter at the type level (Int, Real, Bool).
- `Z3BitVec[W: static int]` for width-tracked BVs.
- `Z3Array[Key, Val]` typedesc-phantom over key/value AST types.
- `Z3DatatypeValue[T]` marker-type phantom (`type Maybe = object` → `Z3DatatypeValue[Maybe]`).
- (Each family parallels the others in lifecycle, dispatch, and pretty-printing.)

v0.3 introduces three more sort families. Each follows the same precedent: the minimum type-level information that catches a real bug at compile time, and nothing more.

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

### v0.3.0 — theory completion

1. **Carried-forward gaps from v0.2** (Pre-tag audit, v0.2.1 bucket):
   - `Z3Model.eval`/`[]` for `Z3DatatypeValue[T]` and `Z3Array[K, V]`.
   - `smtEquiv` overloads for those types.
   - `Z3_apply_result_convert_model`.
2. `evalReal` / `toRealApprox` composer with a documented precision policy.
3. DOT / GraphViz AST export.
4. Wider-width BV recipes in `tests/recipes.nim`.
5. Strings + regexes.
6. Sequences.
7. FloatingPoint.
8. Uninterpreted functions (`Z3FuncDecl`).
9. `Z3_mk_solver_from_tactic` + `Z3_solver_set_params` for `Z3Solver`.
10. v0.3 tag.

### v0.4+ — frontier features

- Fixedpoint engine (`Z3Fixedpoint`).
- User propagators / custom theories.
- High-level macro DSL (still under review).
- Differential testing against Python z3.

---

## 5. Implementation sequence

The order is chosen so each step's tests can exercise the new surface end-to-end against an already-working stack.

1. **Carried-forward gaps from v0.2.1 bucket** (`m.eval` / `m[v]` / `smtEquiv` for `Z3Array` and `Z3DatatypeValue`). Small, mechanical, closes the most visible user-facing gaps. First because v0.2.1 was the rollover target.

2. **`Z3_apply_result_convert_model`** (also v0.2.1 bucket). Round-trips tactic-pipeline models.

3. **`evalReal` / `toRealApprox(precision)`** with a precision policy doc-noted.

4. **DOT / GraphViz AST export** — small standalone module, lifts hash-consing-aware structure into a visualisation users can `xdot` / `dot -Tpng`.

5. **Strings + regexes** (`z3/string`, `z3/regex`). Tests verify common idioms (`contains` / `replace` / regex matching) decide correctly.

6. **Sequences** (`z3/seq`). Generalisation of strings; same dispatch story.

7. **FloatingPoint** (`z3/fp`). Rounding-mode parameterised arithmetic; type-level width safety per IEEE 754.

8. **Uninterpreted functions** (`z3/funcdecl`). Phantom-typed over argument and return types; per-arity `apply` templates.

9. **`Z3_mk_solver_from_tactic`** + **`Z3_solver_set_params`** for `Z3Solver`. Bridge work.

10. **Pre-tag audit + rollforward annotations** per the v0.2 precedent.

11. **v0.3 tag.**

---

## 6. Risks specific to v0.3

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

1. **`Z3Fp[Ebits, Sbits]` vs `Z3Fp32` / `Z3Fp64` aliases.** Should we expose typed aliases for the common widths? Lean yes — `Z3Fp[8, 24]` reads poorly compared to `Z3Float32`.

2. **`toRealApprox(precision)` policy.** What's "precision" — number of decimal digits, an explicit epsilon, a tolerance? Z3 itself uses string-form rationals exactly; the approximation is purely our extraction. Lean: precision = number of decimal digits, default 15 (matches float64 precision).

3. **String element type.** SMT-LIB strings are sequences of Unicode characters; Z3 represents them as `Z3_string` (UTF-8). The Nim representation should be `string` (UTF-8 idiomatic in Nim 2). Lean: yes, with a tested round-trip.

4. **`Z3FuncDecl` arg type encoding.** `Z3FuncDecl[(A, B, C), Ret]` uses a tuple typedesc. Alternative: separate generic per arg. Tuple is cleaner for type inference; arities are visible in the type. Lean: tuple form.

---

## 8. Deferred from v0.3 (running list, updated as we go)

Same discipline as v0.1 §18 and v0.2 §8 — append-only. Format: **what**, **why**, **where it goes** (v0.4 / dropped). v0.1 and v0.2 deferrals that remain unaddressed continue to live in their respective archived plans.

*(empty until the first deferral surfaces)*

---

## 9. Closing note

v0.2 introduced the "Pre-tag audit" discipline — a structured pass that catalogues every v0.X-promised item just before the tag and explicitly classifies it as landed / rolled / dropped. v0.3 keeps the discipline; §8 will end with the same kind of audit block before the v0.3.0 tag.

If reading this, future-me, after v0.3 has shipped: archive this file to `docs/V0.3_PLAN.md`, write `docs/IMPLEMENTATION_PLAN.md` for v0.4, and update the README's "Design" section to point at all three archives. The rotation pattern is: every shipped version's plan becomes the historical record; the live plan is always for the next one.

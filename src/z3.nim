## z3 — type-safe, memory-safe Nim wrapper for the Z3 SMT solver.
##
## v0.1 — initial release; v0.2 in progress. The shipped architecture
## is captured in [docs/V0.1_PLAN.md](../docs/V0.1_PLAN.md), live work
## in [docs/IMPLEMENTATION_PLAN.md](../docs/IMPLEMENTATION_PLAN.md),
## per-release diff in [CHANGELOG.md](../CHANGELOG.md), and runnable
## starter code in [examples/](../examples/). The headline use:
##
## ```nim
## import z3
##
## let ctx = newContext()
## let x = mkIntVar("x")
## let y = mkIntVar("y")
##
## let s = newSolver()
## s.add (x + y == 10) and (x > 3)
##
## if s.check() == zsSat:
##   let m = s.model()
##   echo m.evalInt(x), " ", m.evalInt(y)
## ```
##
## Layered architecture:
##
## - `z3/ffi` — raw softlink dynlib block + opaque types. Internal;
##   surface via the modules below.
## - `z3/context` — `Z3Context` lifecycle, current-context threadvar,
##   `withContext` scoping, error handler installation, `Z3Error`,
##   `checkErr` template. **Implemented.**
## - `z3/sort` — phantom-typed `Z3Sort[S]` + sort constructors.
##   **Implemented.**
## - `z3/ast` — phantom-typed `Z3Ast[S]` + lifecycle hooks + `$` /
##   `astEqual`. **Implemented.**
## - `z3/builder` — AST literals + variables (`mkInt`, `mkBool`,
##   `mkIntVar`, `mkBoolVar`, etc.). **Implemented.**
## - `z3/boolean` — boolean operators (`and`, `or`, `not`, `xor`,
##   `implies`, `iff`, `ite`, varargs `mkAnd` / `mkOr`,
##   `mkDistinct`) with Nim-bool lift overloads. **Implemented.**
## - `z3/arith` — arithmetic + ordering operators on Z3Int + Z3Real
##   (`+`, `-`, `*`, `div`, `/`, `mod`, `rem`, `<`, `<=`, `>`, `>=`,
##   `==`, `!=`) with int-literal lift overloads. **Implemented.**
## - `z3/solver` — `Z3Solver` lifecycle, `add`/`check`/`push`/`pop`/
##   `reset`, `withFrame` template, `Z3Status` enum, `reasonUnknown`.
##   **Implemented.**
## - `z3/model` — `Z3Model` lifecycle, `eval` / `[]`, scalar
##   extractors (`toInt`, `toBool`, etc.), composers (`evalInt`,
##   `evalBool`). **Implemented.**
## - `z3/bitvec` — width-tracked `Z3BitVec[W]` phantom types with
##   sign-explicit ops (`bvudiv`/`bvsdiv`, `bvult`/`bvslt`, `lshr`/
##   `ashr`), modular arithmetic operators (`+`, `-`, `*`, `and`,
##   `or`, `xor`, `not`, `shl`), width manipulation (`extract`,
##   `concat`, `zeroExtend`, `signExtend`, `repeat`), polymorphic
##   `ite` / `mkDistinct` / `==` / `!=`, literal lifts, and signed +
##   unsigned model extraction (`toInt`, `toUint`). **Implemented.**
## - `z3/solver` also exposes `smtValid(p: Z3Bool): bool` and
##   `smtEquiv[S](a, b: Z3Ast[S]): bool` (with a `Z3BitVec[W]` overload
##   in `z3/bitvec`) — validity / equivalence oracles built on a
##   throwaway solver. Useful in property tests; also a clean primitive
##   for downstream verification tooling.
## - `z3/params` — `Z3Params` typed parameter bag for tactics,
##   solvers, optimisers. `newParams` + overloaded `set(key, value)`
##   for `bool`, `uint`, `float`, and `string` values. **v0.2 step 8.**
## - `z3/tactic` — `Z3Goal` (formula conjunction), `Z3Tactic`
##   (`mkTactic("simplify")`, `andThen`, `orElse`, `repeat`, `tryFor`,
##   `withParams`, `tacticSkip` / `tacticFail`), `Z3ApplyResult` for
##   subgoal iteration. **v0.2 step 8.**
## - `z3/optimize` — `Z3Optimize` with hard / soft constraints,
##   `maximize` / `minimize`, phantom-typed `Z3OptHandle[T]` for
##   `upper` / `lower` bound retrieval, `push` / `pop` scopes,
##   `setParams(o, p)` for `priority = "lex"` (default) / `"box"` /
##   `"pareto"` multi-objective modes. **v0.2 steps 7 + 9.**
## - `z3/quantifier` — `forall(b1, …, body, patterns=[…])` and
##   `exists(...)` with per-arity templates (1–5 bound vars). Bound
##   vars can be any typed AST family (`Z3Int`, `Z3BitVec[W]`,
##   `Z3DatatypeValue[T]`, …); each must be a free constant.
##   `Z3Pattern` is a refcount-managed trigger; `mkPattern(t1, …)`
##   builds a multi-trigger (conjunction within), and passing several
##   patterns to `forall` is alternative-trigger (disjunction across).
##   **v0.2 step 6.**
## - `z3/datatypes` — inductive sums via `declareDatatype[T]` (single)
##   or `declareDatatypes(forDatatype[T1]…, forDatatype[T2]…)` (mutually
##   recursive). Phantom is a Nim marker type (`type Foo = object`),
##   so `Z3DatatypeValue[Foo]` is distinct from `Z3DatatypeValue[Bar]`.
##   Surface: `field`, `selfField`, `crossField`, `constructor`,
##   `declareDatatype` / `forDatatype` / `declareDatatypes`, `.con` /
##   `.recognizer` / `.accessor`, `.apply` / `.test` / `.read`,
##   `mkDatatypeVar`. **v0.2 steps 4 + 5.**
## - `z3/array` — `Z3Array[Key, Val]` phantom-typed over typedescs
##   of AST families (so `Z3Array[Z3BitVec[32], Z3BitVec[8]]` is a
##   distinct type from `Z3Array[Z3BitVec[64], Z3BitVec[8]]`).
##   Surface: `mkConstArray`, `mkArrayVar`, `store`, `select`, `[]`,
##   `==`, `!=`. **v0.2 step 3.**
## - `z3/simplify` — `Z3_simplify` wrapped with phantom-type
##   preservation. `simplify[S](a: Z3Ast[S]): Z3Ast[S]` for Int/Real/
##   Bool and a parallel `simplify[W](a: Z3BitVec[W]): Z3BitVec[W]`
##   overload. Folds constants and known identities without spinning
##   a solver. Params-customised overloads via `simplify(a, p:
##   Z3Params)`. **v0.2 steps 1 + 9.**
## - `z3/pretty` — indented multi-line `pretty()` overloads (for
##   ASTs, sorts, solvers, models), `smt2Script` / `writeSmt2` for
##   self-contained SMT2 emission, `parseSmt2` for round-trip
##   parsing. The reformatter is a pure Nim Wadler-style "fit or
##   stack" pass over Z3's flat output. **Implemented.**

import z3/ffi, z3/context, z3/sort, z3/ast, z3/builder, z3/boolean, z3/arith,
       z3/solver, z3/model, z3/bitvec, z3/pretty, z3/simplify, z3/array,
       z3/datatypes, z3/quantifier, z3/optimize, z3/params, z3/tactic
export ffi, context, sort, ast, builder, boolean, arith, solver, model, bitvec,
       pretty, simplify, array, datatypes, quantifier, optimize, params, tactic
# softlink's SoftlinkError / LoadResult / lrOk live in softlink; users
# who need them `import softlink` directly.

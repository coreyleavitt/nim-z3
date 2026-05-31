## z3 — type-safe, memory-safe Nim wrapper for the Z3 SMT solver.
##
## v0.4 — **contract-completion** release. Closes the gap between the
## wrapper's "every Z3 C-API capability" scope claim and reality.
## Nine new modules: `z3/astvector`, `z3/introspect`, `z3/proof`,
## `z3/fixedpoint`, `z3/rewrite`, `z3/translate`, `z3/probe`,
## `z3/globalparams`, `z3/io`. Five new solver extensions
## (`assertConstraintAndTrack` / `getUnsatCore` / `getStatistics` /
## `getConsequences` / `getProof`). Runtime-erased `Z3AnyAst` family
## + typed lifters. Per-context `datatypeRegistry` so
## `Z3DatatypeValue[T]` participates in `sortdispatch`. Uninterpreted
## sorts (`mkUninterpretedSort` / `declareSort`). Every §1 goal of the
## v0.4 plan landed; see `docs/V0.4_PLAN.md` §8b for the audit.
##
## v0.3 was the architectural-unification + theory-completion release
## (`Z3Term` concept + unified `wrap[T]` + lifecycle generators;
## Char / String + alias `Z3String = Z3Seq[Z3Char]` / Regex /
## Sequences / FloatingPoint / uninterpreted functions; solver-tactic
## bridges). v0.2 was the theory-expansion release (arrays, datatypes,
## quantifiers, optimisation, tactics + goals + params); v0.1 was the
## core SMT primitives.
##
## Shipped architecture in [docs/V0.1_PLAN.md](../docs/V0.1_PLAN.md),
## [docs/V0.2_PLAN.md](../docs/V0.2_PLAN.md),
## [docs/V0.3_PLAN.md](../docs/V0.3_PLAN.md), and
## [docs/V0.4_PLAN.md](../docs/V0.4_PLAN.md); live work in
## [docs/IMPLEMENTATION_PLAN.md](../docs/IMPLEMENTATION_PLAN.md) (now
## the v0.5 1.0-readiness plan); per-release diff in
## [CHANGELOG.md](../CHANGELOG.md); runnable starter code in
## [examples/](../examples/). The headline use:
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
##   `reset`, `withFrame` template, `Z3Status` enum, `reasonUnknown`,
##   `setParams(s, p: Z3Params)` for timeout / random_seed / etc.
##   **Implemented. setParams in v0.3 step 8.**
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
## - `z3/introspect` — structural introspection. `Z3AstKind` enum
##   + `getAstKind[T: Z3Term]`, `getSort`, `getAppNumArgs`,
##   `getAppArg`, `getAppDecl`, `unpackApp`, `getNumeralString`.
##   `Z3SortKind` enum + `getSortKind`, `bitVecWidth`, `arrayKey` /
##   `arrayRange`, `seqElement`, `regexBasis`, `fpEbits` / `fpSbits`,
##   `datatypeName`. The erased `Z3AnyAst` family + `toAnyAst` up-cast
##   + typed lifters `asZ3Int` / `asZ3Real` / `asZ3Bool` / `asZ3Char` /
##   `asZ3BitVec[W]` / `asZ3Fp[E, S]` / `asZ3Seq[E]` / `asZ3Regex[B]`
##   with runtime sort + parameter verification. **v0.4 step 2.**
## - `z3/astvector` — `Z3AstVector` typed ref-handle for Z3's
##   heterogeneous-sort AST-vector C type. Constructor `newAstVector`,
##   `len`, `[i]` (raw access), `[]=`/`add[T: Z3Term]`/`resize`
##   mutators, `items` / `pairs` iterators, `toSeq[T]` typed
##   conversion, `$` SMT-LIB rendering. Foundational for v0.4
##   `Z3Solver.getUnsatCore` / `getConsequences` / `Z3ParserContext`.
##   **v0.4 step 1.**
## - `z3/tactic` — `Z3Goal` (formula conjunction), `Z3Tactic`
##   (`mkTactic("simplify")`, `andThen`, `orElse`, `repeat`, `tryFor`,
##   `withParams`, `tacticSkip` / `tacticFail`), `Z3ApplyResult` for
##   subgoal iteration. Plus `newSolverFromTactic(t)` / `t.toSolver()`
##   solver bridges so a tactic pipeline can drive a `Z3Solver`'s
##   decision procedure under the familiar add/check/model surface.
##   **v0.2 step 8; solver bridge v0.3 step 8.**
## - `z3/semantics` — `smtValid(p: Z3Bool): bool` and the generic
##   `smtEquiv[T](a, b: T): bool`. Single discovery location for
##   validity / equivalence oracles; covers every typed family with
##   an `==` operator (Z3Ast[S], Z3BitVec[W], Z3Array[K, V],
##   Z3DatatypeValue[T], …). **v0.3 step 2.**
## - `z3/char` — `Z3Char` Unicode-codepoint AST family. Construction
##   from int codepoint or ASCII `char` literal; ordering (`<=` / `<`),
##   `isDigit` predicate, `toInt` codepoint extractor. **v0.3 step 4.**
## - `z3/sequence` — `Z3Seq[E]` SMT-LIB sequence theory, phantom-typed
##   over the element AST family. `mkSeqEmpty[E]` / `mkSeqUnit(e)` /
##   `mkSeqVar[E](name)`, `len`, varargs `concat` + `&`, `nth(s, i)` +
##   `[i]` operator, `at(s, i)` (1-element sub-sequence), `substr`,
##   `contains`, `startsWith` / `endsWith`, `indexOf`, `replace`.
##   Supports any element type with a `sortOfTypeSeq` case (`Z3Int`,
##   `Z3Real`, `Z3Bool`, `Z3BitVec[W]`, `Z3Char`, nested
##   `Z3Seq[E']`). **v0.3 step 5.**
## - `z3/string` — **alias `Z3String = Z3Seq[Z3Char]`** plus the
##   string-specific surface only: `mkString` (via `Z3_mk_lstring`),
##   `mkStringVar`, `toStr` / `evalStr` model extraction, `strToInt`
##   / `intToStr` int interop, Nim-`string`-literal lifts on `==` /
##   `!=` / `&` / `contains` / `startsWith` / `endsWith`. All generic
##   sequence ops (len, concat, nth, at, substr, …) flow through the
##   alias from `z3/sequence`. **v0.3 steps 4 + 5.**
## - `z3/fp` — IEEE 754 / SMT-LIB FloatingPoint theory. `Z3Fp[Ebits,
##   Sbits]` phantom-typed over the encoding widths, with `Z3Float16`
##   / `Z3Float32` / `Z3Float64` / `Z3Float128` aliases. `mkFp` /
##   `mkFloat32` / `mkFloat64` / `mkNaN` / `mkInf` / `mkZero` and
##   matching `Var` forms. Operators `+` `-` `*` `/` with default
##   `rmRNE` rounding; explicit forms `fpAdd` / `fpSub` / `fpMul` /
##   `fpDiv` accept a `RoundingMode` Nim enum (`rmRNE` / `rmRNA` /
##   `rmRTP` / `rmRTN` / `rmRTZ`) or a `Z3RoundingMode` AST for
##   quantification over rounding. **`==` / `!=` use IEEE semantics
##   (NaN ≠ NaN, +0 = -0) — deliberate divergence from every other
##   typed family.** Predicates `isNaN` / `isInf` / `isZero` /
##   `isNormal` / `isSubnormal` / `isPositive` / `isNegative`. Ops
##   `abs` / unary `-` / `rem` / `min` / `max` / `sqrt` / `fma` /
##   `roundToIntegral`. Conversions `toIeeeBv` / `toFp` (from BV,
##   another FP, Real) / `toFpFromSigned` / `toFpFromUnsigned` /
##   `toReal` / `toSbv` / `toUbv`. Model extraction
##   `toFloat32` / `toFloat64` / `evalFloat32` / `evalFloat64`.
##   **v0.3 step 6.**
## - `z3/funcdecl` — `Z3FuncDecl[ArgsTup, Ret]` phantom-typed handle
##   to an uninterpreted function. The tuple captures arity + per-
##   position element type, `Ret` the return type. `mkFuncDecl[Args,
##   Ret](name)` walks the tuple's field types at compile time to
##   build the domain sort array. Per-arity `apply` overloads + `()`
##   callable hooks (0..6 args) let users write `f(x, y)` naturally.
##   `evalAt(m, f, args)` composes apply + `m.eval` for "what value
##   does f take at this specific point?" Sort dispatch covers the
##   full v0.3 family set (Int / Real / Bool / BV[W] / Char /
##   String / Seq[E] / Fp[E,S]). **v0.3 step 7.**
## - `z3/regex` — `Z3Regex[Basis]` phantom-typed over the basis
##   sequence sort (v0.3 step 4: `Z3Regex[Z3String]` only; step 5
##   widens to `Z3Regex[Z3Seq[E]]`). `mkRegex` / `mkRegexEmpty` /
##   `mkRegexFull` / `mkRegexAll`, `matches` membership predicate,
##   `star` / `plus` / `option` / `complement` unary, varargs
##   `concat` / `union` / `intersect`, `range(lo, hi: string)`
##   character ranges, `loop(r, lo, hi)` / `power(r, n)` counted
##   repetition. **v0.3 step 4.**
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
##   ASTs, sorts, solvers, models). The reformatter is a pure Nim
##   Wadler-style "fit or stack" pass over Z3's flat output.
##   **Implemented.**
## - `z3/io` — SMT-LIB2 input / output: `smt2Script` / `writeSmt2` /
##   `toSmt2Benchmark` for emission; `parseSmt2String` /
##   `parseSmt2File` for stateless parsing; `loadSmt2String` /
##   `loadSmt2File` for direct-to-solver feeds; `evalSmt2` to run
##   command scripts and read back Z3's response; `Z3ParserContext`
##   refcount-managed streaming parser with `addSort` / `addDecl` /
##   `parseFromString`. **v0.4 step 14** (relocated from `z3/pretty`
##   and extended).

import z3/ffi, z3/context, z3/error, z3/sort, z3/sortdispatch, z3/ast,
       z3/builder, z3/boolean, z3/arith, z3/solver, z3/model, z3/bitvec,
       z3/pretty, z3/simplify, z3/array, z3/datatypes, z3/quantifier,
       z3/optimize, z3/params, z3/tactic, z3/semantics, z3/char, z3/sequence,
       z3/string, z3/regex, z3/fp, z3/funcdecl, z3/astvector, z3/stats,
       z3/introspect, z3/proof, z3/fixedpoint, z3/rewrite, z3/translate,
       z3/probe, z3/globalparams, z3/io
export ffi, context, error, sort, sortdispatch, ast, builder, boolean, arith,
       solver, model, bitvec, pretty, simplify, array, datatypes, quantifier,
       optimize, params, tactic, semantics, char, sequence, string, regex, fp,
       funcdecl, astvector, stats, introspect, proof, fixedpoint, rewrite,
       translate, probe, globalparams, io
# softlink's SoftlinkError / LoadResult / lrOk live in softlink; users
# who need them `import softlink` directly.

## z3 — type-safe, memory-safe Nim wrapper for the Z3 SMT solver.
##
## **v1.0.0 — stable release.** Post-1.0 the public surface is
## SemVer-stable; see README's `## Stability` section for the
## precise definition. The live v1.x roadmap is in
## docs/IMPLEMENTATION_PLAN.md (the v0.6 = v1.0.0 plan is archived
## at docs/V0.6_PLAN.md). The five-round v1.0-readiness audit
## cycle that produced this surface is recorded in CHANGELOG
## `[1.0.0]`.
##
## What v0.5 delivered (recap — v1.0.0 inherits everything from
## v0.5 plus the audit cycle's additions): two new typed families
## (`Z3FuncInterp[Args, Ret]`, `Z3ParamDescrs`); one new module
## extracted from `z3/context` (`z3/error`); typed error hierarchy
## (12 subclasses of the abstract `Z3Error` base); cross-family
## parity (generic `pretty[T: Z3Renderable]`,
## generic `astEqual[T: Z3Term]`,
## `evalXxx` shorthand audit, `$` parity via `termToSmt2`); naming
## hygiene (`z3/seq` → `z3/sequence`, `RoundingMode` consolidation,
## `naryOp` macro family, `add`/`assertConstraint` resolution);
## memory + thread safety audit; Z3 C-API micro-gap closure
## (`Z3FuncInterp`, `Z3ParamDescrs`, `Z3Char ↔ Z3BitVec[18]`);
## 21 new property-test shape recipes; four v0.3-family examples;
## five polish docs (`GOTCHAS.md`, `INTERNAL_API.md`, `PARITY.md`,
## `THREADING.md`, `MINIMAL_BUILD.md`); feature flags + minimal-
## build story (`z3WithoutX` compile-time flags). Every §1 goal of
## the v0.5 plan landed; see `docs/V0.5_PLAN.md` §8b for the audit.
##
## v0.4 was the contract-completion release (nine new modules:
## `z3/astvector`, `z3/introspect`, `z3/proof`, `z3/fixedpoint`,
## `z3/rewrite`, `z3/translate`, `z3/probe`, `z3/globalparams`,
## `z3/io`; runtime-erased `Z3AnyAst` family; per-context
## `datatypeRegistry`; uninterpreted sorts). v0.3 was the
## architectural-unification + theory-completion release (`Z3Term`
## concept + unified `wrap[T]` + lifecycle generators; Char / String
## + alias `Z3String = Z3Seq[Z3Char]` / Regex / Sequences /
## FloatingPoint / uninterpreted functions; solver-tactic bridges).
## v0.2 was the theory-expansion release (arrays, datatypes,
## quantifiers, optimisation, tactics); v0.1 was the core SMT
## primitives.
##
## Shipped architecture in [docs/V0.1_PLAN.md](../docs/V0.1_PLAN.md),
## [docs/V0.2_PLAN.md](../docs/V0.2_PLAN.md),
## [docs/V0.3_PLAN.md](../docs/V0.3_PLAN.md),
## [docs/V0.4_PLAN.md](../docs/V0.4_PLAN.md), and
## [docs/V0.5_PLAN.md](../docs/V0.5_PLAN.md); live work in
## [docs/IMPLEMENTATION_PLAN.md](../docs/IMPLEMENTATION_PLAN.md)
## (now the v0.6 = v1.0.0 stability tag plan); per-release diff in
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
##   extractors (`toInt64`, `toBool`, etc.), composers (`evalInt`,
##   `evalBool`). **Implemented.**
## - `z3/bitvec` — width-tracked `Z3BitVec[W]` phantom types with
##   sign-explicit ops (`bvudiv`/`bvsdiv`, `bvult`/`bvslt`, `lshr`/
##   `ashr`), modular arithmetic operators (`+`, `-`, `*`, `and`,
##   `or`, `xor`, `not`, `shl`), width manipulation (`extract`,
##   `concat`, `zeroExtend`, `signExtend`, `repeat`), polymorphic
##   `ite` / `mkDistinct` / `==` / `!=`, literal lifts, and signed +
##   unsigned model extraction (`toInt`, `toUint`). **Implemented.**
## - `z3/params` — `Z3Params` typed parameter bag for tactics,
##   solvers, optimisers. `newParams` + overloaded `set(key, value)`
##   for `bool`, `uint`, `float`, and `string` values. **v0.2 step 8.**
## - `z3/introspect` — structural introspection. `Z3AstKind` enum
##   + `getAstKind[T: Z3Term]`, `getSort`, `getAppNumArgs`,
##   `getAppArg`, `getAppDecl`, `unpackApp`, `getNumeralString`.
##   `Z3SortKind` enum + `getSortKind` (with the v1.0 ergonomic
##   `getSortKind[T: Z3Term](a: T)` overload that pulls `.ctx` from
##   the AST), `bitVecWidth`, `arrayKey` / `arrayRange`, `seqElement`,
##   `regexBasis`, `fpEbits` / `fpSbits`, `datatypeName`. The erased
##   `Z3AnyAst` family + `toAnyAst` up-cast + typed lifters `asZ3Int`
##   / `asZ3Real` / `asZ3Bool` / `asZ3Char` / `asZ3BitVec[W]` /
##   `asZ3Fp[E, S]` / `asZ3Seq[E]` / `asZ3Regex[B]` with runtime sort
##   + parameter verification. `astHash[T: Z3Term](a): uint` —
##   Z3-side structural-identity hash (`Z3_get_ast_hash`); see
##   GOTCHAS #16 for the distinct-wrapper pattern for `Table`/
##   `HashSet` keys. **v0.4 step 2 + v1.0 round 2.**
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
## - `z3/chars` — `Z3Char` Unicode-codepoint AST family. Construction
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
## - `z3/strings` — **alias `Z3String = Z3Seq[Z3Char]`** plus the
##   string-specific surface only: `mkString` (via `Z3_mk_lstring`),
##   `mkStringVar`, `toStr` / `evalStr` model extraction,
##   `Z3String.toInt` / `Z3Int.toStr` int interop, Nim-`string`-literal lifts on `==` /
##   `!=` / `&` / `contains` / `startsWith` / `endsWith`. All generic
##   sequence ops (len, concat, nth, at, substr, …) flow through the
##   alias from `z3/sequence`. **v0.3 steps 4 + 5.**
## - `z3/fp` — IEEE 754 / SMT-LIB FloatingPoint theory. `Z3Fp[Ebits,
##   Sbits]` phantom-typed over the encoding widths, with `Z3Float16`
##   / `Z3Float32` / `Z3Float64` / `Z3Float128` aliases. `mkFp` /
##   `mkFloat32` / `mkFloat64` / `mkFpNaN` / `mkFpInf` / `mkFpZero` and
##   matching `Var` forms. Operators `+` `-` `*` `/` default to
##   round-nearest-ties-to-even rounding; explicit forms `fpAdd` /
##   `fpSub` / `fpMul` / `fpDiv` accept a `Z3RoundingMode` AST built
##   via the literal helpers `rmRNE()` / `rmRNA()` / `rmRTP()` /
##   `rmRTN()` / `rmRTZ()` (or `mkRoundingModeVar` for quantification
##   over rounding modes). **`==` / `!=` use IEEE semantics
##   (NaN ≠ NaN, +0 = -0) — deliberate divergence from every other
##   typed family.** Predicates `isNaN` / `isInf` / `isZero` /
##   `isNormal` / `isSubnormal` / `isPositive` / `isNegative` /
##   `isFinite` (v1.0 — `not isNaN and not isInf`). Ops
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
## - `z3/arrays` — `Z3Array[Key, Val]` phantom-typed over typedescs
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

# ============================================================================
# Feature flags (v0.5 step 10)
# ============================================================================
#
# Compile-time flags that **hide** theory families from the
# `import z3` umbrella. Useful for users who want to scope their
# surface to a subset of Z3's theories. See `docs/MINIMAL_BUILD.md`
# for the full story including the honesty disclaimer ("hides
# umbrella re-exports; doesn't necessarily reduce compile time").
#
# Cascades:
#   z3WithoutSeq    → also hides String, Regex (String = Seq[Char];
#                                              Regex needs a Seq basis)
#   z3WithoutString → also hides Regex (regex needs string operands)
#   z3WithoutTactics → also hides Probe (probe builds via Z3_tactic_cond)

const
  z3WithoutFPEff*        = defined(z3WithoutFP)
  z3WithoutSeqEff*       = defined(z3WithoutSeq)
  z3WithoutStringsEff*   = defined(z3WithoutStrings) or z3WithoutSeqEff
    # Canonical flag is `z3WithoutStrings` (plural). The singular form
    # `z3WithoutString` was an accidental alias pre-v0.5.0; dropped in
    # the v0.5.0 audit to avoid locking an undocumented alias at v1.0.
  z3WithoutRegexEff*     = defined(z3WithoutRegex) or
                           z3WithoutStringsEff or z3WithoutSeqEff
  z3WithoutFuncDeclEff*  = defined(z3WithoutFuncDecl)
  z3WithoutDatatypesEff* = defined(z3WithoutDatatypes)
  z3WithoutOptimizeEff*  = defined(z3WithoutOptimize)
  z3WithoutTacticsEff*   = defined(z3WithoutTactics)
  z3WithoutProbeEff*     = defined(z3WithoutProbe) or z3WithoutTacticsEff

# ============================================================================
# Module imports + re-exports (always-on core)
# ============================================================================

import z3/ffi, z3/context, z3/error, z3/sort, z3/sortdispatch, z3/ast,
       z3/builder, z3/boolean, z3/arith, z3/solver, z3/model, z3/bitvec,
       z3/pretty, z3/simplify, z3/arrays, z3/sets, z3/quantifier,
       z3/params, z3/semantics, z3/chars,
       z3/astvector, z3/astmap, z3/stats,
       z3/introspect, z3/proof, z3/fixedpoint, z3/rewrite, z3/translate,
       z3/globalparams, z3/io,
       z3/uninterpretedval,
       z3/rcf,
       z3/algebraic,
       z3/propagator,
       z3/onclause
export ffi, context, error, sort, sortdispatch, ast, builder, boolean, arith,
       solver, model, bitvec, pretty, simplify, arrays, sets, quantifier,
       params, semantics, chars,
       astvector, astmap, stats,
       introspect, proof, fixedpoint, rewrite,
       translate, globalparams, io,
       uninterpretedval,
       rcf,
       algebraic,
       propagator,
       onclause

# ============================================================================
# Gateable theories (re-exported only when the corresponding flag is off)
# ============================================================================

when not z3WithoutDatatypesEff:
  import z3/datatypes
  export datatypes

when not z3WithoutOptimizeEff:
  import z3/optimize
  export optimize

when not z3WithoutTacticsEff:
  import z3/tactic
  export tactic

when not z3WithoutProbeEff:
  import z3/probe
  export probe

when not defined(z3WithoutSimplifierObject):
  import z3/simplifier
  export simplifier

when not z3WithoutSeqEff:
  import z3/sequence
  export sequence

when not z3WithoutStringsEff:
  import z3/strings
  export strings

when not z3WithoutRegexEff:
  import z3/regex
  export regex

when not z3WithoutFPEff:
  import z3/fp
  export fp

when not z3WithoutFuncDeclEff:
  import z3/funcdecl
  export funcdecl

when not defined(z3WithoutSpacer):
  import z3/spacer
  export spacer

# softlink's SoftlinkError / LoadResult / lrOk live in softlink; users
# who need them `import softlink` directly.

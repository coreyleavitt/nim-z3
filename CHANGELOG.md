# Changelog

All notable changes to nim-z3. Format loosely follows [Keep a
Changelog](https://keepachangelog.com/en/1.1.0/); semver applies once
1.0 ships.

## [Unreleased]

— Work toward v0.3; see `docs/IMPLEMENTATION_PLAN.md`.

## [0.2.0] — 2026-05-29

The theory-expansion release. v0.1 covered the core SMT primitives;
v0.2 covers the theories that turn SMT from "arithmetic checker"
into "general decision procedure for software verification."

### Added

- **`Z3_simplify` + `z3/simplify`** — phantom-type-preserving simplifier
  overloads for `Z3Ast[S]` and `Z3BitVec[W]`. Default-params and
  customised (`simplify(a, p: Z3Params)`) forms.
- **Big-width `Z3BitVec[W]`** — `mkBigBitVec[W](numeral: string)`
  for arbitrary-precision construction; `toBigUintStr` / `toBigIntStr`
  for arbitrary-width extraction (signed via `Z3_mk_bv2int` round-trip).
  `mkBitVec(v, W)` now works for any `W` (v0.1 capped it at `W ≤ 64`
  defensively; the cap was wrong — `Z3_mk_unsigned_int64` accepts any
  width). `toUint`/`toInt` simplify-then-extract, so concrete
  expression trees (`mkBitVec(0xFF, 8) + mkBitVec(1, 8)`) extract
  directly without manual `simplify`.
- **`z3/array`** — `Z3Array[Key, Val]` phantom-typed over typedescs of
  AST families. Surface: `mkConstArray`, `mkArrayVar`, `store`,
  `select` / `[]`, `==`, `!=`. Supports the canonical memory model
  (`Array[BV[32], BV[8]]`); nested arrays deferred to v0.3.
- **`z3/datatypes`** — inductive sums via marker-type phantoms.
  `declareDatatype[T]` for single datatypes, `declareDatatypes(fd1,
  fd2, …)` for mutually recursive families (arity 2 and 3). Surface:
  `field` / `selfField` / `crossField`, `constructor`, `.con` /
  `.recognizer` / `.accessor`, `.apply` (arity 0–5) / `.test` /
  `.read`, `mkDatatypeVar`.
- **`z3/quantifier`** — `forall` / `exists` with per-arity templates
  (1–5 bound vars). Bound vars can be any typed AST family. `Z3Pattern`
  refcount-managed trigger; `mkPattern(t1, …)` for multi-trigger
  conjunction, multiple patterns in `forall(…, patterns=[p1, p2])` for
  alternative-trigger disjunction.
- **`z3/optimize`** — `Z3Optimize` with hard / soft constraints,
  `maximize` / `minimize`, phantom-typed `Z3OptHandle[T]` for
  `upper` / `lower`, `push` / `pop`, `setParams(o, p)` exposing
  `priority="lex"` (default) / `"box"` / `"pareto"` multi-objective
  modes. BV-objective bounds re-typed through `Z3_mk_int2bv` so the
  typed return promise holds.
- **`z3/params`** — `Z3Params` typed parameter bag for tactics,
  solvers, optimisers. `newParams` + overloaded `set(key, value)`
  for `bool` / `uint` / `int` / `float` / `string`.
- **`z3/tactic`** — `Z3Goal`, `Z3Tactic`, `Z3ApplyResult` with
  combinators: `mkTactic`, `tacticSkip` / `tacticFail`, `andThen` /
  `orElse` / `repeat` / `tryFor` / `withParams`, `apply` (with and
  without params), `numSubgoals` / `subgoal(i)`.

### Other changes

- `z3/model`'s `wrapModel(ctx, raw)` is now public so sibling
  modules (`z3/optimize`, future tactics, …) can wrap models they
  obtain from their own FFI paths.
- Test infrastructure refactor: `IntRecipe` / `BoolRecipe` /
  `BvRecipe` ADTs + strategies + interpreters extracted from
  `tests/tproperty.nim` into shared `tests/recipes.nim`. Now used by
  `tproperty.nim`, `tsimplify.nim`, and `tarray.nim`.

### Deferred to v0.2.1 / v0.3 (per `docs/V0.2_PLAN.md`)

Promised-v0.2 items that didn't land before the tag:

- v0.2.1: `Z3Model.eval`/`[]` overloads for `Z3DatatypeValue[T]` and
  `Z3Array[K, V]`; `smtEquiv` overloads for those types;
  `Z3_apply_result_convert_model` for tactic-pipeline witnesses.
- v0.3: `evalReal` / `toRealApprox`, DOT / GraphViz AST export,
  wider-width BV recipes, differential testing against `z3` CLI,
  valgrind job, `.optional` softlink declarations.
- Dropped: colourised pretty output, public `z3/strategies` module
  (proptest will depend on nim-z3, not the other way round).
- macOS / aarch64 CI rows + `nim doc --project` Pages publishing —
  filed as [#1](https://github.com/coreyleavitt/nim-z3/issues/1),
  blocked on the same private-dep upstream that's keeping v0.1's CI
  red. Rolls back into scope when `coreyleavitt/milpa` and
  `coreyleavitt/proptest` go public (or a deploy key is wired).

652 tests pass on both Nim backends (c + cpp); zero failures.

## [0.1.0] — 2026-05-29

## [0.1.0] — 2026-05-29

The initial release. A user can write the headline `x + y == 10 ∧ x > 3`
example in their first 5 minutes (per the §11 deliverable target in
`docs/IMPLEMENTATION_PLAN.md`).

### Added

- **`Z3Context` lifecycle** with `=destroy` discipline, current-context
  threadvar, `withContext(ctx): body` scoping template, auto-load of
  libz3 on first `newContext()`, typed `Z3Error` carrying a
  `Z3ErrorCode` enum, `checkErr` template wrapping every FFI call.
- **Phantom-typed sorts and ASTs**. `SortTag` enum (`stInt`, `stReal`,
  `stBool`, `stBitVec`); `Z3Sort[S]` and `Z3Ast[S]` value types with
  refcount-discipline lifecycle hooks (`=destroy` / `=copy` / `=dup`);
  type aliases `Z3Int`, `Z3Real`, `Z3Bool`.
- **Builders for literals + variables**: `mkInt` / `mkBigInt`,
  `mkReal` / `mkBigReal`, `mkBool` / `mkTrue` / `mkFalse`, and the
  `*Var` family — every builder in both implicit (current-context) and
  explicit (`ctx.mkIntVar(…)`) forms.
- **Boolean operators**: `and`, `or`, `not`, `xor`, `implies`, `iff`,
  `ite[S]`, varargs `mkAnd` / `mkOr`, `mkDistinct[S]`, with Nim-bool
  literal lifts.
- **Arithmetic operators on Int and Real**: `+`, `-`, `*`, `div`, `/`,
  `mod`, `rem`, `<`, `<=`, `>`, `>=`, `==`, `!=` — all with int-literal
  lifts on both sides.
- **Width-tracked bit-vectors** via a separate `Z3BitVec[W: static int]`
  type. Modular arithmetic operators (`+`, `-` binary + unary, `*`,
  `and`, `or`, `xor`, `not`, `shl`) overload normally; sign-dependent
  ops require explicit `bvudiv` / `bvsdiv`, `bvurem` / `bvsrem` /
  `bvsmod`, `bvult` / `bvule` / `bvugt` / `bvuge`, `bvslt` / `bvsle` /
  `bvsgt` / `bvsge`, `lshr` / `ashr`. Width manipulation —
  `extract(hi, lo)`, `concat`, `zeroExtend(N)`, `signExtend(N)`,
  `repeat(N)` — computes the result width at the type level.
  Polymorphic `ite` and `mkDistinct` overloads for BV. Model extraction
  via `toUint` (unsigned) and `toInt` (signed 2's-complement) plus
  `eval` / `[]` indexing.
- **Solver + model**: `Z3Solver` with `add`, `assertConstraint`,
  `check`, `push`, `pop`, `reset`, `withFrame: body` template,
  `Z3Status` enum (`zsSat`, `zsUnsat`, `zsUnknown`), `reasonUnknown`.
  `Z3Model` with `eval` / `[]`, scalar extractors (`toInt`, `toBool`,
  `toBigIntStr`, `toBigRealStr`), and composers (`evalInt`, `evalBool`,
  `evalBigIntStr`, `evalBigRealStr`).
- **Validity oracles** in `z3/solver`: `smtValid(p: Z3Bool)` and
  `smtEquiv[S](a, b: Z3Ast[S])` (plus a `Z3BitVec[W]` overload).
  Both use a throwaway solver per call so the caller's primary state
  stays untouched.
- **Indented pretty-printing** via a Wadler-style "fit or stack"
  reformatter in `z3/pretty`. Typed `pretty(node, indent, width)`
  overloads for AST / BV / sort / solver / model.
- **SMT2 script emission and parsing**: `smt2Script(s)` writes a
  self-contained runnable script; `writeSmt2(s, path)` is the
  to-disk variant; `parseSmt2(ctx, source)` returns a `seq[Z3Bool]`
  of parsed assertions. Round-trip preserves sat / unsat / model.
- **Version probes**: `z3Version(): (major, minor, build, revision)`,
  `z3FullVersion(): string`, `finalizeZ3Memory()`.
- **Property-based test suite** dogfooding [proptest](https://github.com/coreyleavitt/proptest)
  with random integer / boolean / BV expression trees (depth 2-3)
  asserting algebraic laws (commutativity, associativity, identity,
  de Morgan, idempotence, absorption, involutions, extract/concat
  round-trips) at the SMT level.
- **CI**: multi-version Z3 matrix (4.10.2 / 4.11.2 / 4.12.6 / 4.13.4)
  pulled from microsoft/z3 release tarballs, dual-backend (`nim c` +
  `nim cpp`) every row. Separate AddressSanitizer job on the
  lifecycle-critical test suites.
- **Examples**: `basic_solve`, `nqueens`, `bitvec_solve`,
  `pretty_and_smt2`, `properties`.

### Deferred to v0.2 (per `docs/IMPLEMENTATION_PLAN.md` §18)

- Array theory, quantifiers, optimization, custom datatypes, tactics
  (§11 v0.2 wave).
- Wide BitVec literal construction + extraction (`mkBigBitVec`,
  `toBigUintStr` for W > 64).
- `Z3_simplify` FFI + wrapper.
- DOT / GraphViz AST export, colourised pretty output, multi-byte
  UTF-8 atom tokenising.
- Public `z3/strategies` module exposing the recipe ADTs from the test
  suite.
- macOS / aarch64 CI runners, valgrind job, differential testing
  against the `z3` CLI and Python `z3-solver`.

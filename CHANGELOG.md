# Changelog

All notable changes to nim-z3. Format loosely follows [Keep a
Changelog](https://keepachangelog.com/en/1.1.0/); semver applies once
1.0 ships.

## [Unreleased]

## [0.1.0] — v0.1

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

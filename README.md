# nim-z3

Type-safe, memory-safe Nim wrapper for the [Z3 SMT solver](https://github.com/Z3Prover/z3).

```nim
import z3

let ctx = newContext()
let x = mkIntVar("x")
let y = mkIntVar("y")

let s = newSolver()
s.add (x + y == 10) and (x > 3)

case s.check()
of zsSat:
  let m = s.model()
  echo "x = ", m.evalInt(x), ", y = ", m.evalInt(y)
of zsUnsat, zsUnknown:
  echo "no solution"
```

→ `x = 4, y = 6`

That five-line example uses everything you need to be productive: a context, free variables, a constraint, a satisfiability check, and witness extraction. There is no DSL layer to learn — the wrapper IS the API.

## Why nim-z3 over a hand-rolled FFI

- **Memory-safe by construction.** Z3's `Z3_inc_ref` / `Z3_dec_ref` discipline is hidden behind Nim 2's `=destroy` / `=copy` / `=dup` hooks. No leaks, no double-frees, no use-after-free.
- **Type-safe sorts.** `Z3Ast[stInt]` and `Z3Ast[stBool]` are distinct types; adding an Int to a Bool is a compile error, not a runtime sort mismatch.
- **Width-typed bit-vectors.** `Z3BitVec[8]` and `Z3BitVec[16]` are distinct types. `extract(7, 0)`, `concat`, `zeroExtend(N)`, `signExtend(N)`, `repeat(N)` all compute the result width at the type level: `concat(BV[8], BV[8]): BV[16]` is what the compiler enforces.
- **Sign-explicit BV operators.** No silent unsigned vs signed default for `<`, `div`, `mod`, `shr` — you write `bvult` / `bvslt`, `bvudiv` / `bvsdiv`, `lshr` / `ashr`. Sign-independent ops (`+`, `-`, `*`, `and`, `or`, `xor`, `shl`) overload normally.
- **Idiomatic ergonomics.** Implicit current-context threadvar (Python z3 style) for short scripts; explicit `ctx.mkIntVar(…)` for library code. `withContext(ctx): body` for scoped use. `withFrame: body` for hypothetical solver scopes. Literal lifts (`x + 3`, `5 == y`) on every operator.
- **Round-trip SMT-LIB.** `pretty(s)` for indented human view, `smt2Script(s)` to emit a runnable script, `parseSmt2String(ctx, source)` (and `parseSmt2File` / `loadSmt2*` / `evalSmt2`) to read constraints back. The full SMT-LIB2 surface lives in `z3/io`.
- **Typed error hierarchy.** Catch `Z3SortMismatchError`, `Z3ParseError`, `Z3InvalidUsageError`, `Z3MemoryError`, etc. — 12 typed subclasses of `Z3Error`. The base class still works as a catch-all.
- **`Z3Term`-load-bearing surface.** `wrap[T]`, `eval[T]`, `smtEquiv[T]`, `astEqual[T]`, `pretty[T]`, `$[T]` are all generic over the typed value families — adding a new theory inherits the cross-cutting surface automatically.

## Install

Add to your `milpa.kdl`:

```kdl
deps {
  z3 git=(url)"https://github.com/coreyleavitt/nim-z3.git" ref="main"
}
```

`milpa fetch` resolves softlink (the dynamic-loading dep), emits the right `nim.cfg`, and you're set.

You also need:

- Nim 2.0+.
- A system `libz3.so` at runtime — `apt install libz3-dev` (Debian/Ubuntu), `brew install z3` (macOS), or unpack a [Z3 release tarball](https://github.com/Z3Prover/z3/releases) into the loader path. nim-z3 supports Z3 4.10 → 4.13.x.

`milpa` ([coreyleavitt/milpa](https://github.com/coreyleavitt/milpa)) is the project-wide Nim dep resolver — same convention used by every other library in the nimlibs family. nimble is not involved in the build path.

## Modules at a glance

`import z3` re-exports everything below. Most users never reach for a submodule directly; the table is a map of where each capability lives.

### Core

| Module | Surface |
|---|---|
| `z3/context` | `Z3Context`, `newContext`, `withContext`, current-context threadvar, `z3Version` |
| `z3/error` | `Z3Error` + 12 typed subclasses (`Z3SortMismatchError`, `Z3ParseError`, `Z3InvalidUsageError`, …), `checkErr` discipline |
| `z3/sort` | `SortTag` enum, `Z3Sort[S]`, sort constructors including `mkUninterpretedSort` / `declareSort` |
| `z3/lifecycle` | `Z3Term` concept, lifecycle generators, `wrap[T]` unification, varargs-FFI macro family |

### Typed value families

| Module | Family | Headline ops |
|---|---|---|
| `z3/ast` + `z3/builder` + `z3/boolean` + `z3/arith` | `Z3Int`, `Z3Real`, `Z3Bool` | `+`, `-`, `*`, `div`, `mod`, `<`, `<=`, `==`, `and`, `or`, `not`, `xor`, `implies`, `iff`, `ite`, `mkDistinct`, literal lifts |
| `z3/bitvec` | `Z3BitVec[W: static int]` | Modular arithmetic, `bvudiv`/`bvsdiv`/`bvult`/`bvslt`/…, width-typed `extract`/`concat`/`zeroExtend`/`signExtend`/`repeat` |
| `z3/array` | `Z3Array[Key, Val]` | `store` / `select` / `[]`, equality |
| `z3/datatypes` | `Z3DatatypeValue[T]` | `declareDatatype` / `declareDatatypes`, constructors / accessors / recognizers |
| `z3/char` + `z3/string` + `z3/sequence` + `z3/regex` | `Z3Char`, `Z3String = Z3Seq[Z3Char]`, `Z3Seq[E]`, `Z3Regex[Basis]` | SMT-LIB string / regex theory; `range`, `star`, `plus`, `option`, `concat`, `union`; `mkChar(bv: Z3BitVec[18])` ↔ `toBitVec(c: Z3Char)` |
| `z3/fp` | `Z3Fp[E, S]`, aliases `Z3Float32`/`64`/etc., `Z3RoundingMode` | IEEE 754 arithmetic with literal rounding-mode helpers (`rmRNE()` / `rmRTZ()` / …), predicates, conversions, `==` uses IEEE semantics |
| `z3/funcdecl` | `Z3FuncDecl[Args, Ret]`, `Z3FuncInterp[Args, Ret]` | Phantom-typed function decls + tabular UF model extraction |
| `z3/quantifier` | `forall` / `exists` with per-arity templates, `Z3Pattern` triggers, introspection (`isForall` / `isExists` / `isLambda`, `getQuantifierBody`, bound-var names + sorts, patterns) |
| `z3/introspect` | `Z3AstKind` / `Z3SortKind`, `Z3AnyAst` runtime-erased family + typed lifters |
| `z3/proof` | `Z3Proof`, 42-entry `ProofRule` enum, `unpackProof` |

### Decision procedures + analysis

| Module | Surface |
|---|---|
| `z3/solver` | `Z3Solver` lifecycle, `add` / `check` / `push` / `pop`, `assertConstraintAndTrack` + `getUnsatCore`, `getStatistics`, `getConsequences`, `getProof`, `setParams` + schema introspection (`getParamDescrs`) |
| `z3/model` | `Z3Model` lifecycle, `eval` / `[]`, scalar + composed extractors (`evalInt` / `evalUint` / `evalChar` / `evalSeqLen` / …) |
| `z3/tactic` | `Z3Goal`, `Z3Tactic`, combinators (`andThen`, `orElse`, `repeat`, `tryFor`, `withParams`), `toSolver()` bridge, schema introspection |
| `z3/probe` | `Z3Probe`, comparison + boolean combinators returning `Z3Probe`, `condTactic` adaptive dispatch |
| `z3/optimize` | `Z3Optimize`, `maximize` / `minimize`, `Z3OptHandle[T]`, multi-objective modes |
| `z3/fixedpoint` | `Z3Fixedpoint`, Horn-clause / CHC: `addRule` / `addFact` / `query` / `getAnswer` |

### Manipulation + I/O

| Module | Surface |
|---|---|
| `z3/rewrite` | `substitute` (by-term), `substituteVars` (de-Bruijn) |
| `z3/translate` | Cross-context AST transfer (`translate[T: Z3Term]`, `compatibleWith`) |
| `z3/simplify` | `simplify[T]` + params-customised overloads |
| `z3/astvector` | `Z3AstVector` heterogeneous-AST collection |
| `z3/pretty` | Generic `pretty[T: Z3Renderable]` over every typed family + ref handle |
| `z3/io` | `smt2Script` / `writeSmt2` / `toSmt2Benchmark`; `parseSmt2String` / `parseSmt2File`; `loadSmt2String` / `loadSmt2File`; `evalSmt2`; `Z3ParserContext` streaming parser |
| `z3/params` | `Z3Params` typed bag, `Z3ParamDescrs` schema introspection |
| `z3/globalparams` | Process-wide `setGlobalParam` / `getGlobalParam` / `resetGlobalParams` |
| `z3/stats` | `Z3Stats` runtime statistics |
| `z3/semantics` | `smtValid` / `smtEquiv[T]` validity oracles |
| `z3/sortdispatch` | `sortOf` mixin-based dispatch + `sortOfType[T]` |

## Examples

| File | What it shows |
|---|---|
| [`examples/basic_solve.nim`](examples/basic_solve.nim) | The headline `x + y == 10 ∧ x > 3`. Five minutes to first sat. |
| [`examples/nqueens.nim`](examples/nqueens.nim) | N-queens via `mkDistinct` over three sequences (cols, diag, anti-diag). Default N=8; `-d:nQueens=12` to scale. |
| [`examples/bitvec_solve.nim`](examples/bitvec_solve.nim) | Modular-arithmetic factoring on `BV[8]`, width-typed concat reconstruction, signed-vs-unsigned distinction. |
| [`examples/pretty_and_smt2.nim`](examples/pretty_and_smt2.nim) | `pretty(s)` indented view, `smt2Script(s)` emission, `parseSmt2String(ctx, …)` round-trip. The debugging loop. |
| [`examples/properties.nim`](examples/properties.nim) | Property-based testing with [proptest](https://github.com/coreyleavitt/proptest) — soundness round-trip and BV wraparound agreement with native uint8. |
| [`examples/tactic_pipeline.nim`](examples/tactic_pipeline.nim) | `simplify.andThen(smt).toSolver()` driving a small constraint set — the solver-tactic bridge. |
| [`examples/uninterpreted_axioms.nim`](examples/uninterpreted_axioms.nim) | Commutativity axiom over an uninterpreted `f: Int × Int → Int`; counter-claim is unsat. SMT solving with abstract functions. |
| [`examples/float_verification.nim`](examples/float_verification.nim) | Proves the quadratic discriminant `b² - 4ac` is NaN-safe under bounded finite inputs. IEEE 754 reasoning with the wrapper's predicates. |
| [`examples/string_constraints.nim`](examples/string_constraints.nim) | Finds a 5-char alphanumeric "username" containing at least one digit. Combines `Z3String` + `Z3Regex` + character classes. |

Run an individual example with `nim c -r examples/basic_solve.nim`, or `nimble examples` to compile + run all of them on both backends.

## Design

The wrapper ships **37 user-facing modules** (plus the internal `z3/ffi` FFI block) organised around the typed-family + ref-handle pattern. v0.4 closed the C-API contract ("every Z3 capability is reachable"); v0.5 polishes that surface for 1.0 (typed errors, parity surfaces, examples, docs).

### Reading guide

- **New here?** Start with the [example list](#examples) and the [headline example](#nim-z3) at the top of this file. Then skim [`docs/PARITY.md`](docs/PARITY.md) to see how typed families compose.
- **Hit a pitfall?** Check [`docs/GOTCHAS.md`](docs/GOTCHAS.md) — user-facing surprises with symptom / cause / wrapper-behaviour / what-to-do for each.
- **Writing multi-threaded code?** [`docs/THREADING.md`](docs/THREADING.md) is the canonical contract (per-thread contexts work; sharing handles is UB).
- **Want to scope to a subset of Z3's theories?** [`docs/MINIMAL_BUILD.md`](docs/MINIMAL_BUILD.md) covers the `z3WithoutFP` / `z3WithoutSeq` / etc. compile-time flags and the cascade rules; [`docs/config.nims.example`](docs/config.nims.example) is the copy-paste template.
- **Contributing a new typed family or module?** [`docs/PARITY.md`](docs/PARITY.md) is the checklist; [`docs/INTERNAL_API.md`](docs/INTERNAL_API.md) lists the cross-module-internal seams that exist only because Nim has no `internal` visibility.

### Archived plans (per-release rationale)

- [`docs/V0.1_PLAN.md`](docs/V0.1_PLAN.md) — the archived v0.1 plan. Phantom sort types, refcount discipline, current-context threadvar, the lifetime story, and the §18 deferral ledger from v0.1.
- [`docs/V0.2_PLAN.md`](docs/V0.2_PLAN.md) — the archived v0.2 plan. Arrays (typedesc phantoms), datatypes (marker-type phantoms, single + mutually recursive), quantifiers + patterns, optimisation, tactics + goals + params, and the §8 deferral ledger / "Pre-tag audit" from v0.2.
- [`docs/V0.3_PLAN.md`](docs/V0.3_PLAN.md) — the archived v0.3 plan. Architectural unification via the `Z3Term` concept + unified `wrap[T]` + lifecycle generators; the `z3/semantics` relocation; Char / String / Regex / Sequences / FloatingPoint / uninterpreted functions theory families; solver-tactic bridges; the `z3/sortdispatch` mixin-based consolidation; the §8 deferral ledger + §8b "Pre-tag audit" from v0.3.
- [`docs/V0.4_PLAN.md`](docs/V0.4_PLAN.md) — the archived v0.4 plan. The **contract-completion** release. Nine new modules (`z3/astvector`, `z3/introspect`, `z3/proof`, `z3/fixedpoint`, `z3/rewrite`, `z3/translate`, `z3/probe`, `z3/globalparams`, `z3/io`); five new solver extensions (`assertConstraintAndTrack` / `getUnsatCore` / `getStatistics` / `getConsequences` / `getProof`); the runtime-erased `Z3AnyAst` family + typed lifters; per-context `datatypeRegistry` so `Z3DatatypeValue[T]` participates in `sortdispatch`; quantifier introspection; uninterpreted sorts. Every §1 goal landed; the §8 deferral ledger + §8b "Pre-tag audit" archive the spec corrections logged mid-cycle.
- [`docs/V0.5_PLAN.md`](docs/V0.5_PLAN.md) — the archived v0.5 plan. The **1.0-readiness polish** release. Two new typed families (`Z3FuncInterp`, `Z3ParamDescrs`); one new module (`z3/error` extracted from `z3/context`); typed error hierarchy (12 subclasses of the abstract `Z3Error` base); cross-family parity (generic `pretty[T: Z3Renderable]`, generic `astEqual[T: Z3Term]`, `evalXxx` shorthand audit, `$` parity); naming hygiene (`z3/seq` → `z3/sequence`, `RoundingMode` consolidation, `naryOp` macro family); memory + thread safety audit (`nimble valgrind`, `tests/tconcurrency.nim`, `docs/THREADING.md`); Z3 C-API micro-gap closure (`Z3FuncInterp`, `Z3ParamDescrs`, `Z3Char ↔ Z3BitVec[18]`); 21 new property-test shape recipes; four v0.3-family examples; five polish docs (`GOTCHAS.md`, `INTERNAL_API.md`, `PARITY.md`, `THREADING.md`, `MINIMAL_BUILD.md`); feature flags (`z3WithoutX` compile-time flags). Every §1 goal landed; the §8 deferral ledger + §8b "Pre-tag audit" archive the spec corrections logged mid-cycle.
- [`docs/SPIKE_FINDINGS.md`](docs/SPIKE_FINDINGS.md) — the up-front validation log; every assumption in the v0.1 plan was checked against Z3 4.13.3 before the wrapper landed.
- [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) — the **live** plan, currently the v0.6 = v1.0.0 stability tag (a version-only delta from v0.5.0 — no new code, no new tests, no new docs beyond the CHANGELOG entry + README "Stability" section + annotated tag).

## Versioning

Pre-1.0 the public surface may shift between minor versions. We track deferrals and design changes in the live `docs/IMPLEMENTATION_PLAN.md` (and the archived `V0.1_PLAN.md` §18 / `V0.2_PLAN.md` §8 / `V0.3_PLAN.md` §8 + §8b / `V0.4_PLAN.md` §8 + §8b / `V0.5_PLAN.md` §8 + §8b for prior-version deferrals); consult `CHANGELOG.md` for the per-release diff.

v0.6 = v1.0.0 is the stability commitment with a version-only delta from v0.5.0. Post-1.0 the wrapper enforces SemVer: breaking changes only on major bumps (`2.0.0`, …).

## License

Apache-2.0.

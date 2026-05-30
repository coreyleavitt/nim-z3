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
- **Round-trip SMT-LIB.** `pretty(s)` for indented human view, `smt2Script(s)` to emit a runnable script, `parseSmt2(ctx, source)` to read constraints back.

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

## The five user-facing modules

| Module | Surface |
|---|---|
| `z3/context` | `Z3Context`, `newContext`, `withContext`, `Z3Error`, `Z3VersionInfo`, `z3Version`, `finalizeZ3Memory` |
| `z3/sort` | `SortTag` enum (`stInt`, `stReal`, `stBool`, `stBitVec`), `Z3Sort[S]`, sort constructors |
| `z3/ast` + `z3/builder` + `z3/boolean` + `z3/arith` | `Z3Ast[S]` value type with lifecycle hooks, `mkInt` / `mkReal` / `mkBool` / `mkIntVar` / …, all operators (`+`, `-`, `*`, `div`, `mod`, `<`, `<=`, `==`, `and`, `or`, `not`, `xor`, `implies`, `iff`, `ite`, `mkDistinct`) with literal lifts |
| `z3/bitvec` | `Z3BitVec[W: static int]`, `mkBitVec` / `mkBitVecVar[W]`, modular arithmetic, sign-explicit `bvudiv`/`bvsdiv`/`bvult`/`bvslt`/…, width-typed `extract`/`concat`/`zeroExtend`/`signExtend`/`repeat`, `toUint` / `toInt` |
| `z3/solver` + `z3/model` | `Z3Solver` (`add`/`check`/`push`/`pop`/`reset`/`withFrame`), `Z3Status`, `reasonUnknown`, `Z3Model` (`eval`/`[]`), scalar extractors (`toInt`/`toBool`/`toBigIntStr`/`toBigRealStr`), composers (`evalInt`/`evalBool`), validity oracles (`smtValid`/`smtEquiv`) |
| `z3/pretty` | `pretty(…, indent, width)` for AST/sort/solver/model, `smt2Script`, `writeSmt2`, `parseSmt2` |

Top-level `import z3` re-exports all of them — most users never reach for a submodule directly.

## Examples

| File | What it shows |
|---|---|
| [`examples/basic_solve.nim`](examples/basic_solve.nim) | The headline `x + y == 10 ∧ x > 3`. Five minutes to first sat. |
| [`examples/nqueens.nim`](examples/nqueens.nim) | N-queens via `mkDistinct` over three sequences (cols, diag, anti-diag). Default N=8; `-d:nQueens=12` to scale. |
| [`examples/bitvec_solve.nim`](examples/bitvec_solve.nim) | Modular-arithmetic factoring on `BV[8]`, width-typed concat reconstruction, signed-vs-unsigned distinction. |
| [`examples/pretty_and_smt2.nim`](examples/pretty_and_smt2.nim) | `pretty(s)` indented view, `smt2Script(s)` emission, `parseSmt2(ctx, …)` round-trip. The debugging loop. |
| [`examples/properties.nim`](examples/properties.nim) | Property-based testing with [proptest](https://github.com/coreyleavitt/proptest) — soundness round-trip and BV wraparound agreement with native uint8. |

Run an individual example with `nim c -r examples/basic_solve.nim`, or `nimble examples` to compile + run all of them on both backends.

## Design

- [`docs/V0.1_PLAN.md`](docs/V0.1_PLAN.md) — the archived v0.1 plan. Phantom sort types, refcount discipline, current-context threadvar, the lifetime story, and the §18 deferral ledger from v0.1.
- [`docs/V0.2_PLAN.md`](docs/V0.2_PLAN.md) — the archived v0.2 plan. Arrays (typedesc phantoms), datatypes (marker-type phantoms, single + mutually recursive), quantifiers + patterns, optimisation, tactics + goals + params, and the §8 deferral ledger / "Pre-tag audit" from v0.2.
- [`docs/SPIKE_FINDINGS.md`](docs/SPIKE_FINDINGS.md) — the up-front validation log; every assumption in the v0.1 plan was checked against Z3 4.13.3 before the wrapper landed.
- [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) — the **live** plan, currently scoped to v0.3: carried-forward gaps from v0.2 (model `eval` for arrays + datatypes, `smtEquiv` overloads, `Z3_apply_result_convert_model`, `evalReal`, DOT export), then strings + regexes, sequences, FloatingPoint, uninterpreted functions.

## Versioning

Pre-1.0 the public surface may shift between minor versions. We track deferrals and design changes in the live `docs/IMPLEMENTATION_PLAN.md` (and the archived `V0.1_PLAN.md` §18 / `V0.2_PLAN.md` §8 for prior-version deferrals); consult `CHANGELOG.md` for the per-release diff.

## License

Apache-2.0.

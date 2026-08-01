# Minimal build

> **Audience: users who want to scope nim-z3 to a subset of Z3's
> theories.** This file documents the `z3WithoutX` feature-flag
> system added in v0.5 step 10.
>
> See also: [config.nims.example](config.nims.example) (copy-paste
> template), [GOTCHAS.md](GOTCHAS.md) (user-facing pitfalls),
> [PARITY.md](PARITY.md) (cross-family contract).

## What the flags do

Each `z3WithoutX` compile-time flag **hides a theory family from the
`import z3` umbrella**. After

```nim
nim c -d:z3WithoutFP myapp.nim
```

the `Z3Fp`, `Z3Float32`, `Z3Float64`, `mkFp`, `rmRNE`, and every
other FP-family identifier is **not** in scope through `import z3`.
Trying to use one is a clean Nim "undeclared identifier" compile
error.

## The eight user-facing flags

| Flag | Hides |
|---|---|
| `z3WithoutFP` | `z3/fp` — IEEE 754 FP family + rounding modes |
| `z3WithoutSeq` | `z3/sequence` — `Z3Seq[E]` |
| `z3WithoutStrings` | `z3/strings` — `Z3String` alias + string ops |
| `z3WithoutRegex` | `z3/regex` — `Z3Regex[Basis]` family |
| `z3WithoutFuncDecl` | `z3/funcdecl` — `Z3FuncDecl` + `Z3FuncInterp` |
| `z3WithoutDatatypes` | `z3/datatypes` — `Z3DatatypeValue[T]` |
| `z3WithoutOptimize` | `z3/optimize` — `Z3Optimize` |
| `z3WithoutTactics` | `z3/tactic` — `Z3Goal`, `Z3Tactic`, `Z3ApplyResult` |

## Cascades

Some theories depend on others. Passing a high-level flag
implicitly passes the downstream flags:

| Flag | Implicitly also passes |
|---|---|
| `z3WithoutSeq` | `z3WithoutStrings`, `z3WithoutRegex` |
| `z3WithoutStrings` | `z3WithoutRegex` |
| `z3WithoutTactics` | `z3WithoutProbe` |

You don't need to remember the cascades — pass the high-level flag
and the wrapper figures out the dependents. The plan's §7 open
question 4 chose this automatic-cascade design over a
compile-time-error-if-you-forget-the-dependents design specifically
because the cascades are short and user-friendliness wins for a
common workflow.

## Always-on core

The following are **never** gated — they're the always-available
surface that the gated flags assume as a foundation:

- `z3/ffi` — softlink-loaded FFI block
- `z3/context` — `Z3Context` + threadvar
- `z3/error` — `Z3Error` abstract base + 12 typed subclasses
- `z3/sort`, `z3/sortdispatch`
- `z3/ast`, `z3/builder`, `z3/boolean`, `z3/arith`
- `z3/bitvec` — `Z3BitVec[W]`
- `z3/arrays` — `Z3Array[K, V]`
- `z3/solver`, `z3/model`
- `z3/params`, `z3/quantifier`, `z3/pretty`, `z3/simplify`
- `z3/chars` — `Z3Char` (the alphabet underneath Strings, but
  usable on its own without the Sequences theory)
- `z3/astvector`, `z3/stats`
- `z3/introspect` — AST + sort introspection, `Z3AnyAst`
- `z3/proof`, `z3/fixedpoint`
- `z3/rewrite`, `z3/translate`
- `z3/globalparams`, `z3/io`
- `z3/semantics` — `smtValid`, `smtEquiv[T]`

If you want any of these gone too, don't `import z3` — write your
own per-module imports.

## How to use

Three patterns, increasing in commitment:

**(1) One-off compile.** Pass the flag on the command line:

```bash
nim c -d:z3WithoutFP -r myapp.nim
```

**(2) Per-project `config.nims`.** Copy
[config.nims.example](config.nims.example) to your project root as
`config.nims` and uncomment the flags you want. Every compile in
that project picks them up.

**(3) Per-app pragma.** Use the `z3WithoutXEff*` compile-time
constants the umbrella exports to introspect your effective flag
set:

```nim
import z3
when z3WithoutFPEff:
  # the FP theory is hidden; don't try to compile FP code
  ...
```

## Honesty disclaimer

**Feature flags hide the umbrella re-export. They do not necessarily
reduce wrapper compile time.**

Several wrapper modules (`z3/introspect`, `z3/io`, `z3/proof`,
`z3/funcdecl` when present) **hard-import** theory modules. If you
write `import z3` with `-d:z3WithoutFP`, the FP module's
identifiers are out of scope at the umbrella level, but
`z3/fp.nim` is **still compiled** because `z3/introspect` imports
it for the `asZ3Fp` lifter on `Z3AnyAst`.

The flags' real value is at the **scope-hiding** level:

- **Discoverability** — your IDE / Nim's autocomplete shows fewer
  symbols, helping users not reach for theories they shouldn't.
- **Bug-surface reduction** — code you can't reference can't be
  the source of subtle wrong-theory bugs.
- **Documentation clarity** — `--define:z3WithoutFP` in your
  project's `config.nims` is a self-documenting statement of "this
  codebase does not use floating point."

If you need **genuine compile-time reduction**, structure your code
around per-theory imports (`import z3/solver, z3/bitvec`, etc.)
rather than the umbrella. The umbrella exists for the convenience
of single-import projects; users with stricter compile-time budgets
escape it.

## Gate-flag combination examples (v2.0+)

Common multi-flag recipes for build profiles:

| Profile | Flags |
|---|---|
| BV-only (no FP, no strings, no datatypes) | `-d:z3WithoutFP -d:z3WithoutSeq -d:z3WithoutStrings -d:z3WithoutRegex -d:z3WithoutDatatypes` |
| Solver-only (no analysis, no optimise, no CHC extras) | `-d:z3WithoutOptimize -d:z3WithoutTactics -d:z3WithoutSpacer -d:z3WithoutFixedpointCallbacks` |
| Core + BV + arrays (embedded / microcontroller verification) | `-d:z3WithoutFP -d:z3WithoutSeq -d:z3WithoutDatatypes -d:z3WithoutOptimize -d:z3WithoutFuncDecl` |
| No Spacer / CHC | `-d:z3WithoutSpacer` |
| Algebraic-number-free | `-d:z3WithoutAlgebraic -d:z3WithoutRcf` |
| Canonical full minimal (for tests/tminimal.nim) | all eight `-d:z3WithoutX` flags |

The `-d:z3WithoutSpacer`, `-d:z3WithoutAlgebraic`, and `-d:z3WithoutRcf`
flags were added in v2.0.0 for the three new heavy-weight theory families.
They follow the same scope-hiding semantics as the v0.5 flags — hides
umbrella re-export, does not necessarily reduce compile time (see
"Honesty disclaimer" above).

The `-d:z3WithoutFixedpointCallbacks` flag was added in v2.1.0. It hides
`z3/fixedpoint_callbacks` — the typed `Z3FixedpointHandlers` /
`setHandlers` / `clearHandlers` / `hasHandlers` / `handlers` /
`collectLemmas` / `Z3LemmaLog` surface (Spacer-engine export
callbacks: `newLemma`, `predecessor`, `unfold`). It follows the same
scope-hiding semantics as every other `z3WithoutX` flag. **There is
no `-d:z3WithoutFixedpoint` flag** — `z3/fixedpoint` (the CHC solver
core: relations, rules, `query`, the raw §N7.8 callback procs) is
always-on core (see "Always-on core" above) and cannot be gated out;
only the *typed callback* layer built on top of it can be. If you
want the smallest fixedpoint-adjacent footprint, combine
`-d:z3WithoutFixedpointCallbacks` (typed callbacks) with
`-d:z3WithoutSpacer` (Spacer extensions: `addCover`/`getCover`/
`getSpacerLevel`/`mkFpQuery`) — the fixedpoint core itself always
ships.

### A different category: opt-*in* feature flags

The `z3WithoutX` flags above are opt-**out** — they *hide* always-on
surface to shrink the build. nim-z3 also has a few opt-**in** flags that do
the opposite: they *expose* wrappers whose underlying Z3 C symbols are
absent from some distributions, so they ship off by default and you enable
them explicitly:

| Flag | Enables |
|---|---|
| `-d:z3WithSeqReplaceAll` | `Z3Seq.replaceAll` (`Z3_mk_seq_replace_all`) |
| `-d:z3WithSeqReplaceRe` | `z3/regex.replaceRe` (`Z3_mk_seq_replace_re`) |
| `-d:z3WithSeqReplaceReAll` | `z3/regex.replaceReAll` (`Z3_mk_seq_replace_re_all`) |

Listed here only so the full `-d:` flag surface lives in one place. See
[`MULTI_VERSION.md`](MULTI_VERSION.md) for why a symbol may be absent on a
given Z3, and GOTCHAS #24 for the regex-index soundness contract.

The regex-replace variants (`replaceRe` / `replaceReAll`) build CORRECT
`str.replace_re{,_all}` terms, but Z3's solver returns `unknown` — in both
directions — on those constraints even for fully concrete inputs; their
contract is term construction / SMT-LIB export, not solver-decidability
(GOTCHAS #19, #24; RFC-regex-index §7).

## The `nimble test-minimal` task

The nim-z3 repo ships a `nimble test-minimal` task that compiles
`tests/tminimal.nim` with the full set of `z3WithoutX` flags and
runs it on both backends (`nim c` and `nim cpp`). It verifies:

1. **Core surface still works** — Int / Bool / BV / Solver /
   Model / SMT-LIB2 round-trip pass identically under default and
   full-flag configs.
2. **Scope-hiding invariants** — `compiles()` checks pin each
   gated family. If a theory accidentally becomes reachable through
   the umbrella when its flag is set, the test catches it.

This is the canonical "the flags actually work" verification.

CI integration is gated on the same private-dep blocker (#1) that
holds the rest of the matrix; the `nimble test-minimal` task is
runnable locally as soon as `libz3` is on the system.

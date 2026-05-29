# z3

Type-safe, memory-safe Nim wrapper for the [Z3 SMT solver](https://github.com/Z3Prover/z3).

**Status**: pre-0.1 in active development. The architectural design is captured in [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md); a [spike](spike/) validated every assumption against Z3 4.13.3 before this skeleton landed.

## Goals

- **Memory safety**: Z3's `Z3_inc_ref` / `Z3_dec_ref` discipline enforced by Nim's `=destroy` / `=copy` hooks. No leaks, no double-frees, no use-after-free by construction.
- **Type safety**: phantom sort types (`Z3Ast[stInt]`, `Z3Ast[stBool]`) — Z3's dynamic sort-checking moved to compile time.
- **Idiomatic Nim**: `Option[T]` for sat/unsat/unknown, sumtypes for results, exceptions for unexpected errors, `=destroy` for resource discipline.
- **Multi-version Z3**: Z3 4.10 → 4.13.x via softlink's optional-symbols feature.

## Install

Add to your `milpa.kdl`:

```kdl
deps {
    z3 git=(url)"https://github.com/coreyleavitt/nim-z3.git" ref="main"
}
```

Then `milpa fetch` resolves and emits the appropriate `nim.cfg`. milpa is the project-wide dep resolver ([coreyleavitt/milpa](https://github.com/coreyleavitt/milpa)) — same as nkdl / intonaco / fresco / etc.

You also need:

- Nim 2.0+
- A system `libz3.so.4` at runtime (`apt install libz3-dev` / `brew install z3` / Z3 GitHub releases).
- [softlink](https://github.com/coreyleavitt/softlink) ≥ 0.3.3 — resolved transitively via this package's `milpa.kdl`.

## Status / Roadmap

See [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) §11 for the full feature matrix. Current step: v0.0.1 skeleton (this commit) — `softlink` loads, version detection works. Subsequent commits expand the surface module-by-module per the plan's §17 implementation sequence.

## License

Apache-2.0.

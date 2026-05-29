## z3 — type-safe, memory-safe Nim wrapper for the Z3 SMT solver.
##
## Status: pre-0.1. The public surface is being built per
## [docs/IMPLEMENTATION_PLAN.md](../docs/IMPLEMENTATION_PLAN.md).
##
## Layered architecture:
##
## - `z3/ffi` — raw softlink dynlib block + opaque types. Internal;
##   surface via the modules below.
## - `z3/version` — Z3 version detection + feature flags.
## - `z3/error` — `Z3Error` exception + handler installation. (TODO)
## - `z3/context` — `Z3Context` lifecycle + `=destroy`. (TODO)
## - `z3/sort` — phantom-typed `Z3Sort[S]`. (TODO)
## - `z3/ast` — phantom-typed `Z3Ast[S]` + lifecycle hooks. (TODO)
## - `z3/numeral`, `z3/boolean`, `z3/arith`, `z3/bitvec` — sort-tagged
##   builders + operators. (TODO)
## - `z3/solver`, `z3/model` — solver lifecycle + model extraction. (TODO)
##
## This file re-exports the user-facing surface once each module is
## ready. For v0.0.1 it re-exports the FFI loader so consumers can
## verify the library is available before building on top.

import z3/ffi
export ffi
# softlink's SoftlinkError is its own re-export concern; downstream
# users who need it `import softlink` directly. The same goes for
# LoadResult / lrOk / etc. — they're softlink's API, not z3's.

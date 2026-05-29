## z3 — type-safe, memory-safe Nim wrapper for the Z3 SMT solver.
##
## Status: pre-0.1. The public surface is being built per
## [docs/IMPLEMENTATION_PLAN.md](../docs/IMPLEMENTATION_PLAN.md).
##
## Layered architecture:
##
## - `z3/ffi` — raw softlink dynlib block + opaque types. Internal;
##   surface via the modules below.
## - `z3/context` — `Z3Context` lifecycle, current-context threadvar,
##   `withContext` scoping, error handler installation, `Z3Error`,
##   `checkErr` template. **Implemented.**
## - `z3/sort` — phantom-typed `Z3Sort[S]`. (TODO)
## - `z3/ast` — phantom-typed `Z3Ast[S]` + lifecycle hooks. (TODO)
## - `z3/numeral`, `z3/boolean`, `z3/arith`, `z3/bitvec` — sort-tagged
##   builders + operators. (TODO)
## - `z3/solver`, `z3/model` — solver lifecycle + model extraction. (TODO)
##
## This file re-exports the user-facing surface from each module once
## ready. For v0.0.2 it re-exports the FFI and context modules.

import z3/ffi, z3/context
export ffi, context
# softlink's SoftlinkError / LoadResult / lrOk live in softlink; users
# who need them `import softlink` directly.

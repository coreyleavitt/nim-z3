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
##   `reset`, `withFrame` template, `Z3Status` enum, `reasonUnknown`.
##   **Implemented.**
## - `z3/model` — `Z3Model` lifecycle, `eval` / `[]`, scalar
##   extractors (`toInt`, `toBool`, etc.), composers (`evalInt`,
##   `evalBool`). **Implemented.**
## - `z3/bitvec` — width-tracked BitVec phantom types + ops. (TODO)

import z3/ffi, z3/context, z3/sort, z3/ast, z3/builder, z3/boolean, z3/arith,
       z3/solver, z3/model
export ffi, context, sort, ast, builder, boolean, arith, solver, model
# softlink's SoftlinkError / LoadResult / lrOk live in softlink; users
# who need them `import softlink` directly.

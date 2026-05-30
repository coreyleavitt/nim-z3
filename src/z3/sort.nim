## `Z3Sort[S]` — phantom-typed wrapper around Z3 sorts.
##
## Sorts in SMT are the types of terms: Int, Real, Bool, BitVec[N],
## Array[K, V], etc. The Z3 C API treats sorts as opaque, type-erased
## values; we lift that into Nim's type system via a static enum
## parameter so a `Z3Ast[stInt]` and a `Z3Ast[stBool]` are distinct
## types and the compiler catches sort mismatches like `intAst + boolAst`
## at compile time.
##
## ## Phantom enum vs. distinct types
##
## We use `static SortTag` (an enum value as a type parameter) rather
## than distinct types (`IntSort = distinct void`) because:
##
## - Generic procs can pattern-match on the tag via `when S == stInt`,
##   which is convenient for shared lifecycle hooks (`=destroy[S]`,
##   `=copy[S]`).
## - BitVec width will be carried as a second static parameter on the
##   AST type (planned for step 9: `Z3Ast[stBitVec, W: static int]`).
##   That's awkward with distinct types, natural with enum tags.
## - The error messages users see ("type mismatch: expected
##   `Z3Ast[stInt]`, got `Z3Ast[stBool]`") read clearly.
##
## If a user needs a *runtime* sort handle (e.g. constructing a sort
## determined by program input), call `runtimeSort()` to get a
## `Z3Sort[stAny]` — a phantom-erased handle the FFI accepts but the
## type system treats as opaque.

import ./ffi, ./context

type
  SortTag* = enum
    ## Tags lifted into the type system via `static SortTag` on
    ## `Z3Sort[S]` and `Z3Ast[S]`. Extend this enum when adding new
    ## sort families; type-aliased builders (`Z3Int`, `Z3Bool`, etc.)
    ## live in `ast.nim` so they share visibility with the AST type.
    stInt
    stReal
    stBool
    stBitVec
      ## BitVec width lives on a separate `Z3BitVec[W: static int]` type
      ## (see `z3/bitvec`) rather than as a second generic parameter on
      ## `Z3Ast[S]` — width is a Nat parameter, fundamentally different
      ## from the small finite sort tag, and a shared two-param type
      ## would mean sentinel-value pollution (`W=0` for non-BV sorts)
      ## and invasive rework of every existing generic over `Z3Ast[S]`.
      ## This tag exists so `Z3Sort[stBitVec]` is still expressible for
      ## sort-level introspection.
    stArray
      ## Array sort. Key/value types live on a separate
      ## `Z3Array[Key, Val]` type (see `z3/array`) carrying typedesc
      ## generic parameters — same precedent as `Z3BitVec[W]` carrying
      ## its width. The flat `SortTag` enum can't express two
      ## sub-parameters (key sort + value sort, where the value can
      ## itself be a width-tracked BV), so the typed array surface
      ## lives in its own type family. This tag exists for sort-level
      ## introspection.
    stDatatype
      ## Inductive datatype sort. The datatype's identity (name +
      ## constructors) lives on `Z3DatatypeDecl[Name]` /
      ## `Z3DatatypeValue[Name]` (see `z3/datatypes`) with the name as
      ## a `static string` phantom parameter, mirroring the
      ## `Z3BitVec[W]` and `Z3Array[Key, Val]` precedents. This tag
      ## exists for sort-level introspection.

  Z3Sort*[S: static SortTag] = object
    ## Phantom-typed sort handle. Value type carrying the underlying
    ## `RawZ3Sort` plus a reference to its parent context. The phantom
    ## `S` is the user-facing type-level guarantee; the raw Z3 sort
    ## doesn't know about it.
    raw*: RawZ3Sort
    ctx*: Z3Context

# ============================================================================
# Constructors
# ============================================================================
#
# Each constructor has two forms:
#
#   mkIntSort()      — uses currentContext(); raises Z3Error if none.
#   mkIntSort(ctx)   — explicit context via UFCS: `ctx.mkIntSort()`.
#
# The explicit form is always preferred in library code that may run
# with a non-default current context. End-user code typically uses
# the implicit form after one `newContext()` call.

proc mkIntSort*(ctx: Z3Context): Z3Sort[stInt] =
  Z3Sort[stInt](raw: ctx.checkErr Z3_mk_int_sort(ctx.raw), ctx: ctx)
proc mkIntSort*(): Z3Sort[stInt] = mkIntSort(requireCurrentContext())

proc mkRealSort*(ctx: Z3Context): Z3Sort[stReal] =
  Z3Sort[stReal](raw: ctx.checkErr Z3_mk_real_sort(ctx.raw), ctx: ctx)
proc mkRealSort*(): Z3Sort[stReal] = mkRealSort(requireCurrentContext())

proc mkBoolSort*(ctx: Z3Context): Z3Sort[stBool] =
  Z3Sort[stBool](raw: ctx.checkErr Z3_mk_bool_sort(ctx.raw), ctx: ctx)
proc mkBoolSort*(): Z3Sort[stBool] = mkBoolSort(requireCurrentContext())

proc mkBitVecSort*(ctx: Z3Context, w: cuint): Z3Sort[stBitVec] =
  ## Fixed-width bit-vector sort of `w` bits. Width is a runtime cuint
  ## here at the *sort* level; the type-level width discipline lives
  ## on `Z3BitVec[W]` (see `z3/bitvec`) which calls into this with a
  ## `static int` width converted at the call site.
  Z3Sort[stBitVec](raw: ctx.checkErr Z3_mk_bv_sort(ctx.raw, w), ctx: ctx)
proc mkBitVecSort*(w: cuint): Z3Sort[stBitVec] =
  mkBitVecSort(requireCurrentContext(), w)

# ============================================================================
# Pretty-print
# ============================================================================

proc `$`*[S: static SortTag](s: Z3Sort[S]): string =
  ## SMT-LIB notation for the sort. Mostly useful for diagnostic
  ## output: `$mkIntSort() == "Int"`.
  $Z3_sort_to_string(s.ctx.raw, s.raw)

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

import ./ffi, ./context, ./error

type
  SortTag* = enum
    ## Tags lifted into the type system via `static SortTag` on
    ## `Z3Sort[S]` and `Z3Ast[S]`. Extend this enum when adding new
    ## sort families; type-aliased builders (`Z3Int`, `Z3Bool`, etc.)
    ## live in `z3/ast.nim` so they share visibility with the AST type.
    stInt
    stReal
    stBool
    stUninterpreted
      ## **v0.4 step 14.** Opaque sort identified only by its name —
      ## the SMT-LIB `(declare-sort Color)` primitive. Values of an
      ## uninterpreted sort have no built-in operations beyond `==` /
      ## `!=`; the solver picks witnesses freely subject to user
      ## axioms. Exposed via `mkUninterpretedSort(name)` /
      ## `declareSort(name)`.
    stBitVec
      ## BitVec width lives on a separate `Z3BitVec[W: static int]` type
      ## (see `z3/bitvec`) rather than as a second generic parameter on
      ## `Z3Ast[S]` — width is a Nat parameter, fundamentally different
      ## from the small finite sort tag, and a shared two-param type
      ## would mean sentinel-value pollution (`W=0` for non-BV sorts)
      ## and invasive rework of every existing generic over `Z3Ast[S]`.
      ## This tag exists so `Z3Sort[stBitVec]` is still expressible for
      ## `mkBitVecSort` and sort-level introspection.
    stFp
      ## IEEE 754 floating-point sort handle — exposes a `Z3Sort[stFp]`
      ## for the four standard-precision constructors (`mkFpSortHalf`,
      ## `mkFpSortSingle`, `mkFpSortDouble`, `mkFpSortQuadruple`) defined
      ## in `z3/fp`. The ebits/sbits live in the underlying `RawZ3Sort`;
      ## use `Z3_fpa_get_ebits` / `Z3_fpa_get_sbits` to recover them.

  # NOTE: v0.3 step 3 retired `stArray` and `stDatatype` from this enum.
  # Both were placeholder tags from v0.2 that never had a caller — the
  # array and datatype surfaces live on `Z3Array[Key, Val]` and
  # `Z3DatatypeValue[Name]` (typedesc-parameterised phantom families)
  # and never round-trip through `Z3Ast[S]`, so the tags were
  # unreachable and confused the enum's purpose. `Z3Sort[stBitVec]`
  # stays because `mkBitVecSort` actually returns it.

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
proc mkIntSort*(): Z3Sort[stInt] {.inline.} = mkIntSort(requireCurrentContext())

proc mkRealSort*(ctx: Z3Context): Z3Sort[stReal] =
  Z3Sort[stReal](raw: ctx.checkErr Z3_mk_real_sort(ctx.raw), ctx: ctx)
proc mkRealSort*(): Z3Sort[stReal] {.inline.} = mkRealSort(requireCurrentContext())

proc mkBoolSort*(ctx: Z3Context): Z3Sort[stBool] =
  Z3Sort[stBool](raw: ctx.checkErr Z3_mk_bool_sort(ctx.raw), ctx: ctx)
proc mkBoolSort*(): Z3Sort[stBool] {.inline.} = mkBoolSort(requireCurrentContext())

proc mkBitVecSort*(ctx: Z3Context, w: cuint): Z3Sort[stBitVec] =
  ## Fixed-width bit-vector sort of `w` bits. Width is a runtime cuint
  ## here at the *sort* level; the type-level width discipline lives
  ## on `Z3BitVec[W]` (see `z3/bitvec`) which calls into this with a
  ## `static int` width converted at the call site.
  Z3Sort[stBitVec](raw: ctx.checkErr Z3_mk_bv_sort(ctx.raw, w), ctx: ctx)
proc mkBitVecSort*(w: cuint): Z3Sort[stBitVec] {.inline.} =
  mkBitVecSort(requireCurrentContext(), w)

proc mkUninterpretedSort*(ctx: Z3Context, name: string): Z3Sort[stUninterpreted] =
  ## **v0.4 step 14.** Declare a fresh uninterpreted sort. Values of
  ## this sort are opaque — the solver decides only their equality
  ## relation, modulo any axioms the caller adds. The `name` becomes
  ## the sort's identifier in SMT2 emission and inside any
  ## `Z3ParserContext` it's been registered with.
  ##
  ## Two uninterpreted sorts with the same `name` in the same context
  ## are the same sort.
  let sym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)
  Z3Sort[stUninterpreted](
    raw: ctx.checkErr Z3_mk_uninterpreted_sort(ctx.raw, sym),
    ctx: ctx)

proc mkUninterpretedSort*(name: string): Z3Sort[stUninterpreted] {.inline.} =
  mkUninterpretedSort(requireCurrentContext(), name)

proc declareSort*(ctx: Z3Context, name: string): Z3Sort[stUninterpreted]
  {.inline.} = mkUninterpretedSort(ctx, name)
  ## SMT-LIB-styled alias for `mkUninterpretedSort` — matches the
  ## `(declare-sort Color)` reading site.

proc declareSort*(name: string): Z3Sort[stUninterpreted] {.inline.} =
  mkUninterpretedSort(name)

# ============================================================================
# Pretty-print
# ============================================================================

proc `$`*[S: static SortTag](s: Z3Sort[S]): string =
  ## SMT-LIB notation for the sort. Mostly useful for diagnostic
  ## output: `$mkIntSort() == "Int"`.
  $Z3_sort_to_string(s.ctx.raw, s.raw)

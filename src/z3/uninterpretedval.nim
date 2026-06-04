## `Z3UninterpretedVal[T]` — marker-phantom values of an uninterpreted sort.
##
## ## Motivation
##
## Z3's `declare-sort` primitive creates a completely opaque sort — the
## solver knows only its cardinality (potentially infinite) and an equality
## relation; there are no built-in operations.  This makes uninterpreted
## sorts the right tool for modelling abstract domains (colours, locations,
## identifiers) without committing to a representation.
##
## ## Phantom / marker design
##
## The user declares one empty Nim type per logical domain, called the
## *marker type*:
##
## ```nim
## type ColorSort = distinct void
## ```
##
## Passing that marker as `T` to `Z3UninterpretedVal[T]` gives every
## variable and constant of the "Color" sort a distinct Nim static type.
## The compiler then prevents mixing sorts statically:
##
## ```nim
## let c: Z3UninterpretedVal[ColorSort] = mkUninterpretedVar[ColorSort]("c")
## let l: Z3UninterpretedVal[LocSort]   = mkUninterpretedVar[LocSort]("l")
## discard c == l  # compile error — different T
## ```
##
## This is the same phantom pattern used by `Z3DatatypeValue[T]`.
##
## ## Registry
##
## Z3 sort handles are runtime values produced by `Z3_mk_uninterpreted_sort`.
## We store them per-context in `ctx.uninterpretedRegistry[$T]`, parallel
## to the `datatypeRegistry` used by `z3/datatypes`.  `declareUninterpretedSort`
## creates the sort and registers it; `sortOf` does the typedesc-level lookup.
##
## ## Z3Array integration
##
## `sortOf[T](_: typedesc[Z3UninterpretedVal[T]], ctx)` is the `sortOf`
## overload that `sortOfType[T](ctx)` resolves to when `T =
## Z3UninterpretedVal[MarkerType]`.  This means
## `Z3Array[Z3UninterpretedVal[ColorSort], Z3Int]` constructs through the
## standard array-builder path without any manual sort wiring.
##
## ## Lifecycle
##
## `Z3UninterpretedVal[T]` carries a `RawZ3Ast` (the const / variable AST)
## and its parent `Z3Context`. Lifecycle follows the standard
## `termDestroy` / `termCopy` / `termDup` pattern via `Z3_inc_ref` /
## `Z3_dec_ref`.

import std/tables
import ./ffi, ./context, ./error, ./sort, ./sortdispatch, ./ast, ./lifecycle

# ============================================================================
# Type definition
# ============================================================================

type
  Z3UninterpretedVal*[T] = object
    ## AST value of an uninterpreted sort, phantom-tagged with marker type `T`.
    ## Two values of distinct marker types are incompatible at the Nim
    ## type level — equality operators, solver `add`, `eval`, etc., all
    ## reject mixed-sort arguments at compile time.
    raw*: RawZ3Ast
    ctx*: Z3Context

# ============================================================================
# Lifecycle hooks
# ============================================================================

proc `=destroy`[T](v: Z3UninterpretedVal[T]) {.raises: [].} =
  termDestroy(v, Z3_dec_ref)

proc `=copy`[T](dst: var Z3UninterpretedVal[T],
                src: Z3UninterpretedVal[T]) {.raises: [].} =
  termCopy(dst, src, Z3_dec_ref, Z3_inc_ref)

proc `=dup`[T](src: Z3UninterpretedVal[T]): Z3UninterpretedVal[T] {.raises: [].} =
  termDup(result, src, Z3_inc_ref)

# ============================================================================
# sortOf overload — typedesc-level registry lookup
# ============================================================================
#
# This is the overload `sortOfType[Z3UninterpretedVal[T]](ctx)` resolves to
# when arrays, func_decls, or sequences need the RawZ3Sort for this family.
# The mixin in `sortOfType` defers name resolution to the instantiation site,
# so any module that imports `z3/uninterpretedval` (directly or via `z3`)
# automatically participates in the sortOfType dispatch.

proc sortOf*[T](_: typedesc[Z3UninterpretedVal[T]],
                ctx: Z3Context): RawZ3Sort =
  ## Per-context lookup of `T`'s registered uninterpreted sort handle.
  ## Raises `Z3InvalidUsageError` if `declareUninterpretedSort[T]` has
  ## not been called on this context yet.
  let name = $T
  if not ctx.uninterpretedRegistry.hasKey(name):
    var e = newException(Z3InvalidUsageError,
      "Z3UninterpretedVal[" & name & "] is not registered in this context " &
      "— call `declareUninterpretedSort[" & name & "](ctx, \"<SortName>\")` " &
      "before using the sort. Uninterpreted sort handles are tracked " &
      "per-context, keyed by marker-type name.")
    e.code = Z3_INVALID_USAGE
    raise e
  ctx.uninterpretedRegistry[name]

# ============================================================================
# declareUninterpretedSort
# ============================================================================

proc declareUninterpretedSort*[T](
    ctx: Z3Context, name: string): Z3Sort[stUninterpreted] =
  ## Declare a fresh uninterpreted sort named `name`, register it under
  ## marker type `T` in this context's `uninterpretedRegistry`, and
  ## return the sort handle.
  ##
  ## Two calls with the same `name` in the same context return the same
  ## Z3 sort (Z3 identifies uninterpreted sorts by name within a
  ## context); the registry is overwritten with the latest handle.
  ##
  ## ```nim
  ## type ColorSort = distinct void
  ## let colorSort = declareUninterpretedSort[ColorSort](ctx, "Color")
  ## ```
  let sym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)
  let rawSort = ctx.checkErr Z3_mk_uninterpreted_sort(ctx.raw, sym)
  # Register under $T so sortOf(Z3UninterpretedVal[T], ctx) can look it up.
  ctx.uninterpretedRegistry[$T] = rawSort
  Z3Sort[stUninterpreted](raw: rawSort, ctx: ctx)

proc declareUninterpretedSort*[T](
    name: string): Z3Sort[stUninterpreted] =
  ## Current-context form of `declareUninterpretedSort[T]`.
  declareUninterpretedSort[T](requireCurrentContext(), name)

# ============================================================================
# mkUninterpretedVar
# ============================================================================

proc mkUninterpretedVar*[T](
    name: string, ctx: Z3Context): Z3UninterpretedVal[T] =
  ## Declare a free variable of the uninterpreted sort `T` in context `ctx`.
  ## The sort must have been registered via `declareUninterpretedSort[T]`
  ## before calling this.
  let rawSort = sortOf(Z3UninterpretedVal[T], ctx)
  let sym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)
  wrap[Z3UninterpretedVal[T]](ctx,
    ctx.checkErr Z3_mk_const(ctx.raw, sym, rawSort))

proc mkUninterpretedVar*[T](name: string): Z3UninterpretedVal[T] =
  ## Current-context form of `mkUninterpretedVar[T]`.
  mkUninterpretedVar[T](name, requireCurrentContext())

# ============================================================================
# Equality operators
# ============================================================================
#
# Static constraint: both operands must have the same marker type `T`.
# Mixed-marker equality (e.g. `colorVal == locVal`) is a compile error
# because the proc is parameterised over a single `T`.

proc `==`*[T](a, b: Z3UninterpretedVal[T]): Z3Bool =
  ## SMT equality of two values of the same uninterpreted sort.
  ## Produces a `Z3Bool` formula; does not evaluate immediately.
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_eq(a.ctx.raw, a.raw, b.raw))

proc `!=`*[T](a, b: Z3UninterpretedVal[T]): Z3Bool =
  ## SMT disequality. Equivalent to `not (a == b)`.
  let eq = a == b
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_not(a.ctx.raw, eq.raw))

# ============================================================================
# Pretty-print
# ============================================================================

proc `$`*[T](v: Z3UninterpretedVal[T]): string =
  ## SMT-LIB2 rendering of the uninterpreted-sort value AST.
  termToSmt2(v)

## Arithmetic + ordering operators on `Z3Int` and `Z3Real`.
##
## ## Operators exposed
##
## Binary:
##
## ```
##              Z3Int    Z3Real    notes
## +            Y         Y        n-ary at Z3 level; binary here
## -            Y         Y
## *            Y         Y
## div          Y         -        integer division (Nim's `div` op)
## /            -         Y        real division
## mod          Y         -        Euclidean remainder
## rem          Y         -        truncated remainder (separate proc)
## <  <= > >=   Y         Y        produce Z3Bool
## ```
##
## Unary `-` for both Int and Real.
##
## ## Auto-lift overloads
##
## For every binary op there's a literal-lifted overload for each
## side, so all of these compile and produce ASTs:
##
## ```nim
## let x = mkIntVar("x")
## let y = mkIntVar("y")
## discard x + 3              # Z3Int + int → Z3Int
## discard 3 + x              # int + Z3Int → Z3Int
## discard x < 10             # Z3Int < int → Z3Bool
## discard x == 5             # Z3Int == int → Z3Bool (lift in this module)
## discard x > y              # plain typed form, also works
## ```
##
## For Real, `int` literals lift to `Z3Real` via `mkReal(ctx, n)`.
## Float-literal lift (e.g. `r + 0.5`) is intentionally NOT provided
## because floats aren't exact rationals — users wanting a specific
## ratio write `r + mkReal(1, 2)` explicitly.
##
## ## Why `==` is split between `ast.nim` and the operator modules
##
## The generic same-sort `==` lives in `ast.nim` (it's a property of
## any AST). Literal-lifting overloads (`x == 5`, `p == true`) live
## here and in `boolean.nim` because that's where users will look
## for them — alongside `<`, `and`, etc. The dispatch is unambiguous:
## `==(Z3Int, Z3Int)` resolves to ast.nim's generic; `==(Z3Int, int)`
## resolves to this module's lift.

import ./ffi, ./context, ./sort, ./ast, ./builder
export builder

# ============================================================================
# Helper: binary varargs-style ops (add, sub, mul)
# ============================================================================

template binaryVararg[S: static SortTag](
    zfn: untyped,
    a, b: Z3Ast[S]): Z3Ast[S] =
  ## Build a 2-arg call to a Z3 N-ary builder (Z3_mk_add, Z3_mk_sub,
  ## Z3_mk_mul). Returns Z3Ast[S] — same sort as the inputs.
  block:
    var args = [a.raw, b.raw]
    wrap[Z3Ast[S]](a.ctx, a.ctx.checkErr zfn(
      a.ctx.raw, 2.cuint,
      cast[ptr UncheckedArray[RawZ3Ast]](addr args[0])))

# ============================================================================
# Int arithmetic
# ============================================================================

proc `+`*(a, b: Z3Int): Z3Int = binaryVararg[stInt](Z3_mk_add, a, b)
proc `+`*(a: Z3Int, b: int): Z3Int {.inline.} = a + mkInt(a.ctx, b)
proc `+`*(a: int, b: Z3Int): Z3Int {.inline.} = mkInt(b.ctx, a) + b

proc `-`*(a, b: Z3Int): Z3Int = binaryVararg[stInt](Z3_mk_sub, a, b)
proc `-`*(a: Z3Int, b: int): Z3Int {.inline.} = a - mkInt(a.ctx, b)
proc `-`*(a: int, b: Z3Int): Z3Int {.inline.} = mkInt(b.ctx, a) - b
proc `-`*(a: Z3Int): Z3Int =
  ## Unary negation.
  wrap[Z3Int](a.ctx, a.ctx.checkErr Z3_mk_unary_minus(a.ctx.raw, a.raw))

proc `*`*(a, b: Z3Int): Z3Int = binaryVararg[stInt](Z3_mk_mul, a, b)
proc `*`*(a: Z3Int, b: int): Z3Int {.inline.} = a * mkInt(a.ctx, b)
proc `*`*(a: int, b: Z3Int): Z3Int {.inline.} = mkInt(b.ctx, a) * b

proc `div`*(a, b: Z3Int): Z3Int =
  ## Integer division. `0` divisor is a sort error caught by Z3 and
  ## surfaced as `Z3Error`.
  wrap[Z3Int](a.ctx, a.ctx.checkErr Z3_mk_div(a.ctx.raw, a.raw, b.raw))
proc `div`*(a: Z3Int, b: int): Z3Int {.inline.} = a div mkInt(a.ctx, b)
proc `div`*(a: int, b: Z3Int): Z3Int {.inline.} = mkInt(b.ctx, a) div b

proc `mod`*(a, b: Z3Int): Z3Int =
  ## Euclidean modulo (Z3's `mod`). Result has the same sign as `b`.
  ## For truncated remainder, use `rem`.
  wrap[Z3Int](a.ctx, a.ctx.checkErr Z3_mk_mod(a.ctx.raw, a.raw, b.raw))
proc `mod`*(a: Z3Int, b: int): Z3Int {.inline.} = a mod mkInt(a.ctx, b)
proc `mod`*(a: int, b: Z3Int): Z3Int {.inline.} = mkInt(b.ctx, a) mod b

proc rem*(a, b: Z3Int): Z3Int =
  ## Truncated remainder (Z3's `rem`). Differs from `mod` for negative
  ## operands.
  wrap[Z3Int](a.ctx, a.ctx.checkErr Z3_mk_rem(a.ctx.raw, a.raw, b.raw))
proc rem*(a: Z3Int, b: int): Z3Int {.inline.} = rem(a, mkInt(a.ctx, b))
proc rem*(a: int, b: Z3Int): Z3Int {.inline.} = rem(mkInt(b.ctx, a), b)

# ============================================================================
# Real arithmetic
# ============================================================================

proc `+`*(a, b: Z3Real): Z3Real = binaryVararg[stReal](Z3_mk_add, a, b)
proc `+`*(a: Z3Real, b: int): Z3Real {.inline.} = a + mkReal(a.ctx, b)
proc `+`*(a: int, b: Z3Real): Z3Real {.inline.} = mkReal(b.ctx, a) + b

proc `-`*(a, b: Z3Real): Z3Real = binaryVararg[stReal](Z3_mk_sub, a, b)
proc `-`*(a: Z3Real, b: int): Z3Real {.inline.} = a - mkReal(a.ctx, b)
proc `-`*(a: int, b: Z3Real): Z3Real {.inline.} = mkReal(b.ctx, a) - b
proc `-`*(a: Z3Real): Z3Real =
  wrap[Z3Real](a.ctx, a.ctx.checkErr Z3_mk_unary_minus(a.ctx.raw, a.raw))

proc `*`*(a, b: Z3Real): Z3Real = binaryVararg[stReal](Z3_mk_mul, a, b)
proc `*`*(a: Z3Real, b: int): Z3Real {.inline.} = a * mkReal(a.ctx, b)
proc `*`*(a: int, b: Z3Real): Z3Real {.inline.} = mkReal(b.ctx, a) * b

proc `/`*(a, b: Z3Real): Z3Real =
  ## Real division. `0` divisor is a sort error caught by Z3 and
  ## surfaced as `Z3Error`.
  wrap[Z3Real](a.ctx, a.ctx.checkErr Z3_mk_div(a.ctx.raw, a.raw, b.raw))
proc `/`*(a: Z3Real, b: int): Z3Real {.inline.} = a / mkReal(a.ctx, b)
proc `/`*(a: int, b: Z3Real): Z3Real {.inline.} = mkReal(b.ctx, a) / b

# ============================================================================
# Ordering — `<`, `<=`, `>`, `>=`
# ============================================================================
#
# Generic over numeric sorts. We use a `NumericSort` concept-style
# constraint (compile-time check that S in {stInt, stReal}) so
# attempting `Z3Bool < Z3Bool` is a compile error rather than a
# Z3-runtime SORT_ERROR.

template orderingOp[S: static SortTag](
    zfn: untyped,
    a, b: Z3Ast[S]): Z3Bool =
  block:
    when S notin {stInt, stReal}:
      {.error: "ordering operators (<, <=, >, >=) are defined only for " &
               "numeric sorts (Z3Int, Z3Real)".}
    wrap[Z3Bool](a.ctx, a.ctx.checkErr zfn(a.ctx.raw, a.raw, b.raw))

proc `<`*[S: static SortTag](a, b: Z3Ast[S]): Z3Bool =
  orderingOp[S](Z3_mk_lt, a, b)
proc `<=`*[S: static SortTag](a, b: Z3Ast[S]): Z3Bool =
  orderingOp[S](Z3_mk_le, a, b)
proc `>`*[S: static SortTag](a, b: Z3Ast[S]): Z3Bool =
  orderingOp[S](Z3_mk_gt, a, b)
proc `>=`*[S: static SortTag](a, b: Z3Ast[S]): Z3Bool =
  orderingOp[S](Z3_mk_ge, a, b)

# --- ordering literal lifts (Int) ---

proc `<`*(a: Z3Int, b: int): Z3Bool {.inline.} = a < mkInt(a.ctx, b)
proc `<`*(a: int, b: Z3Int): Z3Bool {.inline.} = mkInt(b.ctx, a) < b
proc `<=`*(a: Z3Int, b: int): Z3Bool {.inline.} = a <= mkInt(a.ctx, b)
proc `<=`*(a: int, b: Z3Int): Z3Bool {.inline.} = mkInt(b.ctx, a) <= b
proc `>`*(a: Z3Int, b: int): Z3Bool {.inline.} = a > mkInt(a.ctx, b)
proc `>`*(a: int, b: Z3Int): Z3Bool {.inline.} = mkInt(b.ctx, a) > b
proc `>=`*(a: Z3Int, b: int): Z3Bool {.inline.} = a >= mkInt(a.ctx, b)
proc `>=`*(a: int, b: Z3Int): Z3Bool {.inline.} = mkInt(b.ctx, a) >= b

# --- ordering literal lifts (Real) ---

proc `<`*(a: Z3Real, b: int): Z3Bool {.inline.} = a < mkReal(a.ctx, b)
proc `<`*(a: int, b: Z3Real): Z3Bool {.inline.} = mkReal(b.ctx, a) < b
proc `<=`*(a: Z3Real, b: int): Z3Bool {.inline.} = a <= mkReal(a.ctx, b)
proc `<=`*(a: int, b: Z3Real): Z3Bool {.inline.} = mkReal(b.ctx, a) <= b
proc `>`*(a: Z3Real, b: int): Z3Bool {.inline.} = a > mkReal(a.ctx, b)
proc `>`*(a: int, b: Z3Real): Z3Bool {.inline.} = mkReal(b.ctx, a) > b
proc `>=`*(a: Z3Real, b: int): Z3Bool {.inline.} = a >= mkReal(a.ctx, b)
proc `>=`*(a: int, b: Z3Real): Z3Bool {.inline.} = mkReal(b.ctx, a) >= b

# ============================================================================
# `==` / `!=` literal lifts (Int + Real)
# ============================================================================

proc `==`*(a: Z3Int, b: int): Z3Bool {.inline.} = a == mkInt(a.ctx, b)
proc `==`*(a: int, b: Z3Int): Z3Bool {.inline.} = mkInt(b.ctx, a) == b
proc `==`*(a: Z3Real, b: int): Z3Bool {.inline.} = a == mkReal(a.ctx, b)
proc `==`*(a: int, b: Z3Real): Z3Bool {.inline.} = mkReal(b.ctx, a) == b

proc `!=`*(a: Z3Int, b: int): Z3Bool {.inline.} = a != mkInt(a.ctx, b)
proc `!=`*(a: int, b: Z3Int): Z3Bool {.inline.} = mkInt(b.ctx, a) != b
proc `!=`*(a: Z3Real, b: int): Z3Bool {.inline.} = a != mkReal(a.ctx, b)
proc `!=`*(a: int, b: Z3Real): Z3Bool {.inline.} = mkReal(b.ctx, a) != b

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
## Float-literal lift (e.g. `r + 0.5`) is also provided: the float64
## is formatted as a decimal string and parsed by Z3's numeral parser via
## `mkReal(ctx, v: float64)`. For exact rationals without floating-point
## rounding, prefer `mkReal(num, den)` (e.g. `r + mkReal(1, 2)`).
##
## ## Why `==` is split between `z3/ast.nim` and the operator modules
##
## The generic same-sort `==` lives in `z3/ast.nim` (it's a property of
## any AST). Literal-lifting overloads (`x == 5`, `p == true`) live
## here and in `z3/boolean.nim` because that's where users will look
## for them — alongside `<`, `and`, etc. The dispatch is unambiguous:
## `==(Z3Int, Z3Int)` resolves to ast.nim's generic; `==(Z3Int, int)`
## resolves to this module's lift.

import ./ffi, ./context, ./error, ./sort, ./ast, ./builder
export builder

# ============================================================================
# Helper: binary varargs-style ops (add, sub, mul)
# ============================================================================

template binaryVararg[S: static SortTag](
    zfn: untyped,
    a, b: Z3Ast[S]): Z3Ast[S] =
  ## Build a 2-arg call to a Z3 N-ary builder (Z3_mk_add, Z3_mk_sub,
  ## Z3_mk_mul). Returns Z3Ast[S] — same sort as the inputs.
  ##
  ## Uses a heap-allocated seq for the args array: Z3 4.15 has a bug
  ## where Z3_mk_add/sub/mul with num_args≥2 crashes when the args
  ## array is stack-allocated and the context has any rec_func_decls
  ## registered (SIGSEGV inside Z3_mk_add). Heap allocation sidesteps it.
  block:
    var args = @[a.raw, b.raw]
    wrap[Z3Ast[S]](a.ctx, a.ctx.checkErr zfn(
      a.ctx.raw, 2.cuint,
      cast[ptr UncheckedArray[RawZ3Ast]](addr args[0])))

# ============================================================================
# Int arithmetic
# ============================================================================

proc `+`*(a, b: Z3Int): Z3Int {.inline.} = binaryVararg[stInt](Z3_mk_add, a, b)
proc `+`*(a: Z3Int, b: int): Z3Int {.inline.} = a + mkInt(a.ctx, b)
proc `+`*(a: int, b: Z3Int): Z3Int {.inline.} = mkInt(b.ctx, a) + b

proc `-`*(a, b: Z3Int): Z3Int {.inline.} = binaryVararg[stInt](Z3_mk_sub, a, b)
proc `-`*(a: Z3Int, b: int): Z3Int {.inline.} = a - mkInt(a.ctx, b)
proc `-`*(a: int, b: Z3Int): Z3Int {.inline.} = mkInt(b.ctx, a) - b
proc `-`*(a: Z3Int): Z3Int {.inline.} =
  ## Unary negation.
  wrap[Z3Int](a.ctx, a.ctx.checkErr Z3_mk_unary_minus(a.ctx.raw, a.raw))

proc `*`*(a, b: Z3Int): Z3Int {.inline.} = binaryVararg[stInt](Z3_mk_mul, a, b)
proc `*`*(a: Z3Int, b: int): Z3Int {.inline.} = a * mkInt(a.ctx, b)
proc `*`*(a: int, b: Z3Int): Z3Int {.inline.} = mkInt(b.ctx, a) * b

proc `div`*(a, b: Z3Int): Z3Int {.inline.} =
  ## Integer division. `0` divisor is a sort error caught by Z3 and
  ## surfaced as `Z3Error`.
  wrap[Z3Int](a.ctx, a.ctx.checkErr Z3_mk_div(a.ctx.raw, a.raw, b.raw))
proc `div`*(a: Z3Int, b: int): Z3Int {.inline.} = a div mkInt(a.ctx, b)
proc `div`*(a: int, b: Z3Int): Z3Int {.inline.} = mkInt(b.ctx, a) div b

proc `mod`*(a, b: Z3Int): Z3Int {.inline.} =
  ## Euclidean modulo (Z3's `mod`). Result has the same sign as `b`.
  ## For truncated remainder, use `rem`.
  wrap[Z3Int](a.ctx, a.ctx.checkErr Z3_mk_mod(a.ctx.raw, a.raw, b.raw))
proc `mod`*(a: Z3Int, b: int): Z3Int {.inline.} = a mod mkInt(a.ctx, b)
proc `mod`*(a: int, b: Z3Int): Z3Int {.inline.} = mkInt(b.ctx, a) mod b

proc rem*(a, b: Z3Int): Z3Int {.inline.} =
  ## Truncated remainder (Z3's `rem`). Differs from `mod` for negative
  ## operands.
  wrap[Z3Int](a.ctx, a.ctx.checkErr Z3_mk_rem(a.ctx.raw, a.raw, b.raw))
proc rem*(a: Z3Int, b: int): Z3Int {.inline.} = rem(a, mkInt(a.ctx, b))
proc rem*(a: int, b: Z3Int): Z3Int {.inline.} = rem(mkInt(b.ctx, a), b)

# ============================================================================
# Real arithmetic
# ============================================================================

proc `+`*(a, b: Z3Real): Z3Real {.inline.} = binaryVararg[stReal](Z3_mk_add, a, b)
proc `+`*(a: Z3Real, b: int): Z3Real {.inline.} = a + mkReal(a.ctx, b)
proc `+`*(a: int, b: Z3Real): Z3Real {.inline.} = mkReal(b.ctx, a) + b
proc `+`*(a: Z3Real, b: float64): Z3Real {.inline.} = a + mkReal(a.ctx, b)
proc `+`*(a: float64, b: Z3Real): Z3Real {.inline.} = mkReal(b.ctx, a) + b

proc `-`*(a, b: Z3Real): Z3Real {.inline.} = binaryVararg[stReal](Z3_mk_sub, a, b)
proc `-`*(a: Z3Real, b: int): Z3Real {.inline.} = a - mkReal(a.ctx, b)
proc `-`*(a: int, b: Z3Real): Z3Real {.inline.} = mkReal(b.ctx, a) - b
proc `-`*(a: Z3Real): Z3Real {.inline.} =
  wrap[Z3Real](a.ctx, a.ctx.checkErr Z3_mk_unary_minus(a.ctx.raw, a.raw))
proc `-`*(a: Z3Real, b: float64): Z3Real {.inline.} = a - mkReal(a.ctx, b)
proc `-`*(a: float64, b: Z3Real): Z3Real {.inline.} = mkReal(b.ctx, a) - b

proc `*`*(a, b: Z3Real): Z3Real {.inline.} = binaryVararg[stReal](Z3_mk_mul, a, b)
proc `*`*(a: Z3Real, b: int): Z3Real {.inline.} = a * mkReal(a.ctx, b)
proc `*`*(a: int, b: Z3Real): Z3Real {.inline.} = mkReal(b.ctx, a) * b
proc `*`*(a: Z3Real, b: float64): Z3Real {.inline.} = a * mkReal(a.ctx, b)
proc `*`*(a: float64, b: Z3Real): Z3Real {.inline.} = mkReal(b.ctx, a) * b

proc `/`*(a, b: Z3Real): Z3Real {.inline.} =
  ## Real division. `0` divisor is a sort error caught by Z3 and
  ## surfaced as `Z3Error`.
  wrap[Z3Real](a.ctx, a.ctx.checkErr Z3_mk_div(a.ctx.raw, a.raw, b.raw))
proc `/`*(a: Z3Real, b: int): Z3Real {.inline.} = a / mkReal(a.ctx, b)
proc `/`*(a: int, b: Z3Real): Z3Real {.inline.} = mkReal(b.ctx, a) / b
proc `/`*(a: Z3Real, b: float64): Z3Real {.inline.} = a / mkReal(a.ctx, b)
proc `/`*(a: float64, b: Z3Real): Z3Real {.inline.} = mkReal(b.ctx, a) / b

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

proc `<`*[S: static SortTag](a, b: Z3Ast[S]): Z3Bool {.inline.} =
  orderingOp[S](Z3_mk_lt, a, b)
proc `<=`*[S: static SortTag](a, b: Z3Ast[S]): Z3Bool {.inline.} =
  orderingOp[S](Z3_mk_le, a, b)
proc `>`*[S: static SortTag](a, b: Z3Ast[S]): Z3Bool {.inline.} =
  orderingOp[S](Z3_mk_gt, a, b)
proc `>=`*[S: static SortTag](a, b: Z3Ast[S]): Z3Bool {.inline.} =
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
proc `==`*(a: Z3Real, b: float64): Z3Bool {.inline.} = a == mkReal(a.ctx, b)
proc `==`*(a: float64, b: Z3Real): Z3Bool {.inline.} = mkReal(b.ctx, a) == b

proc `!=`*(a: Z3Int, b: int): Z3Bool {.inline.} = a != mkInt(a.ctx, b)
proc `!=`*(a: int, b: Z3Int): Z3Bool {.inline.} = mkInt(b.ctx, a) != b
proc `!=`*(a: Z3Real, b: int): Z3Bool {.inline.} = a != mkReal(a.ctx, b)
proc `!=`*(a: int, b: Z3Real): Z3Bool {.inline.} = mkReal(b.ctx, a) != b
proc `!=`*(a: Z3Real, b: float64): Z3Bool {.inline.} = a != mkReal(a.ctx, b)
proc `!=`*(a: float64, b: Z3Real): Z3Bool {.inline.} = mkReal(b.ctx, a) != b

# ============================================================================
# abs — absolute value
# ============================================================================

proc abs*(a: Z3Int): Z3Int {.inline.} =
  ## Absolute value of an integer term: `|a|`.
  wrap[Z3Int](a.ctx, a.ctx.checkErr Z3_mk_abs(a.ctx.raw, a.raw))

proc abs*(a: Z3Real): Z3Real {.inline.} =
  ## Absolute value of a real term: `|a|`.
  wrap[Z3Real](a.ctx, a.ctx.checkErr Z3_mk_abs(a.ctx.raw, a.raw))

# ============================================================================
# power — exponentiation
# ============================================================================

proc power*(a, b: Z3Real): Z3Real {.inline.} =
  ## Real exponentiation: `a ^ b`. Both arguments must be `Z3Real`.
  wrap[Z3Real](a.ctx, a.ctx.checkErr Z3_mk_power(a.ctx.raw, a.raw, b.raw))

proc `^`*(a, b: Z3Real): Z3Real {.inline.} =
  ## Operator alias for `power(a, b)`.
  power(a, b)

# ============================================================================
# divides — integer divisibility predicate
# ============================================================================

proc divides*(d, n: Z3Int): Z3Bool {.inline.} =
  ## Boolean predicate: true iff integer `d` divides integer `n`.
  ## Maps to Z3's `divisible` constraint: `n mod d == 0`.
  wrap[Z3Bool](d.ctx, d.ctx.checkErr Z3_mk_divides(d.ctx.raw, d.raw, n.raw))

# ============================================================================
# isInt — real-is-integer predicate
# ============================================================================

proc isInt*(r: Z3Real): Z3Bool {.inline.} =
  ## Boolean predicate: true iff real `r` has an integer value.
  wrap[Z3Bool](r.ctx, r.ctx.checkErr Z3_mk_is_int(r.ctx.raw, r.raw))

# ============================================================================
# intToReal / realToInt — coercions between Int and Real sorts
# ============================================================================

proc intToReal*(a: Z3Int): Z3Real {.inline.} =
  ## Coerce an Int-sort term to a Real-sort term.
  ## Maps to `Z3_mk_int2real`.
  wrap[Z3Real](a.ctx, a.ctx.checkErr Z3_mk_int2real(a.ctx.raw, a.raw))

proc realToInt*(a: Z3Real): Z3Int {.inline.} =
  ## Floor of a Real-sort term as an Int-sort term.
  ## Z3 semantics: `realToInt(r) = floor(r)` (rounds towards negative infinity).
  ## Maps to `Z3_mk_real2int`.
  wrap[Z3Int](a.ctx, a.ctx.checkErr Z3_mk_real2int(a.ctx.raw, a.raw))

# ============================================================================
# mkRealInt64 — exact rational from int64 numerator / denominator
# ============================================================================

proc mkRealInt64*(ctx: Z3Context, num, den: int64): Z3Real {.inline.} =
  ## Exact rational `num / den` in Z3's `Real` sort, using 64-bit precision.
  ## Prefer over `mkReal(num, den)` when values exceed `cint` (32-bit) range.
  ##
  ## `den == 0` is a sort error surfaced as `Z3Error`.
  wrap[Z3Real](ctx, ctx.checkErr Z3_mk_real_int64(ctx.raw, num, den))

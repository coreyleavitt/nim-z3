## `z3/algebraic` — operations on Z3 algebraic numerals (real-valued ASTs).
##
## ## Overview
##
## Z3 represents algebraic numbers — exact real roots of integer polynomials
## such as √2, ∛5, the golden ratio φ — as a special subset of the `Z3 Real`
## sort. These ASTs satisfy `Z3_algebraic_is_value` and are produced by:
##
##   - `algebraicRoot(a, k)` — the k-th root a^(1/k)
##   - `algebraicPower(a, k)` — the integer power a^k
##   - `algebraicAdd` / `algebraicSub` / `algebraicMul` / `algebraicDiv`
##   - `algebraicNeg`
##   - `algebraicRoots(p, vals)` — real roots of a polynomial
##
## Plain rational constants produced by `mkReal(ctx, n)` are NOT algebraic
## values in Z3's sense (Z3_algebraic_is_value returns false for them), but
## they ARE accepted as inputs to the arithmetic procs — Z3 coerces them.
##
## ## Type design
##
## The algebraic API is a family of operations on `Z3Real` (`Z3Ast[stReal]`).
## We do not introduce a new wrapper type: Z3's C API signature takes and
## returns `Z3_ast`, and the Nim Z3Real phantom type (`Z3Ast[stReal]`) is
## exactly that. Algebraic numerals are a runtime-distinguished subset of
## Z3Real, not a compile-time-distinct type.
##
## ## Lifecycle
##
## Results from arithmetic procs are fresh Z3 ASTs; they go through the
## standard `wrap[Z3Real]` path, which calls `Z3_inc_ref` on construction
## and `Z3_dec_ref` via `=destroy`. No additional bookkeeping needed.
##
## ## Polynomial subresultants (merged from N1.5)
##
## `subresultants(p, q, x)` exposes `Z3_polynomial_subresultants`, returning
## a `Z3AstVector` of the nonzero subresultant polynomial coefficients. The
## vector is ref-managed via `wrapAstVector`.

import ./ffi, ./context, ./error, ./ast, ./builder, ./astvector

# ============================================================================
# Bound-variable constructor for polynomial arguments
# ============================================================================

proc mkBoundReal*(ctx: Z3Context, index: int): Z3Real =
  ## Construct a de-Bruijn-indexed bound variable of the Real sort.
  ##
  ## Used to build polynomial expressions for `algebraicRoots` and
  ## `algebraicEval`. Z3's algebraic API requires polynomials to be
  ## expressed with *bound variables* (de-Bruijn indices), not free
  ## constants (which `mkRealVar` produces).
  ##
  ## For a univariate polynomial p(x), pass `index = 0` — Z3 treats
  ## the index-0 bound variable as the last / only variable in `p`.
  ##
  ## Example:
  ## ```nim
  ## let x = mkBoundReal(ctx, 0)
  ## let p = x * x - mkReal(ctx, 2)   # p(x) = x^2 - 2
  ## let roots = algebraicRoots(p, [])  # returns [sqrt(2), -sqrt(2)]
  ## ```
  let realSort = ctx.checkErr Z3_mk_real_sort(ctx.raw)
  wrap[Z3Real](ctx, ctx.checkErr Z3_mk_bound(ctx.raw, cuint(index), realSort))

# ============================================================================
# Predicates — return Nim bool (concrete algebraic evaluations, not Z3Bool)
# ============================================================================

proc algebraicIsValue*(a: Z3Real): bool {.inline.} =
  ## True if `a` was produced by the algebraic number package
  ## (e.g. `algebraicRoot`, `algebraicPower`, arithmetic on algebraic values).
  ## Plain rational constants from `mkReal` return false.
  Z3_algebraic_is_value(a.ctx.raw, a.raw)

proc algebraicIsPos*(a: Z3Real): bool {.inline.} =
  ## True if algebraic numeral `a` is positive.
  ## Precondition: `algebraicIsValue(a)`.
  Z3_algebraic_is_pos(a.ctx.raw, a.raw)

proc algebraicIsNeg*(a: Z3Real): bool {.inline.} =
  ## True if algebraic numeral `a` is negative.
  Z3_algebraic_is_neg(a.ctx.raw, a.raw)

proc algebraicIsZero*(a: Z3Real): bool {.inline.} =
  ## True if algebraic numeral `a` is zero.
  Z3_algebraic_is_zero(a.ctx.raw, a.raw)

proc algebraicSign*(a: Z3Real): int {.inline.} =
  ## Returns 1 (positive), 0 (zero), or -1 (negative) for algebraic numeral `a`.
  int(Z3_algebraic_sign(a.ctx.raw, a.raw))

# ============================================================================
# Arithmetic — return Z3Real (fresh algebraic numeral ASTs)
# ============================================================================

proc algebraicAdd*(a, b: Z3Real): Z3Real =
  ## Return the algebraic numeral a + b.
  wrap[Z3Real](a.ctx, a.ctx.checkErr Z3_algebraic_add(a.ctx.raw, a.raw, b.raw))

proc algebraicSub*(a, b: Z3Real): Z3Real =
  ## Return the algebraic numeral a - b.
  wrap[Z3Real](a.ctx, a.ctx.checkErr Z3_algebraic_sub(a.ctx.raw, a.raw, b.raw))

proc algebraicMul*(a, b: Z3Real): Z3Real =
  ## Return the algebraic numeral a * b.
  wrap[Z3Real](a.ctx, a.ctx.checkErr Z3_algebraic_mul(a.ctx.raw, a.raw, b.raw))

proc algebraicDiv*(a, b: Z3Real): Z3Real =
  ## Return the algebraic numeral a / b. Precondition: b ≠ 0.
  wrap[Z3Real](a.ctx, a.ctx.checkErr Z3_algebraic_div(a.ctx.raw, a.raw, b.raw))

proc algebraicNeg*(a: Z3Real): Z3Real =
  ## Return the algebraic numeral -a.
  ## Implemented as 0 - a so we don't need a dedicated FFI entry
  ## (Z3 has no Z3_algebraic_neg C proc — negation is unary minus via
  ## Z3_algebraic_sub(0, a) using the zero rational).
  let zero = mkReal(a.ctx, 0)
  wrap[Z3Real](a.ctx, a.ctx.checkErr Z3_algebraic_sub(a.ctx.raw, zero.raw, a.raw))

proc algebraicRoot*(a: Z3Real, k: int): Z3Real =
  ## Return a^(1/k), the k-th root of algebraic numeral `a`.
  ## Precondition: k is odd OR a ≥ 0.
  wrap[Z3Real](a.ctx, a.ctx.checkErr Z3_algebraic_root(a.ctx.raw, a.raw, cuint(k)))

proc algebraicPower*(a: Z3Real, k: int): Z3Real =
  ## Return a^k for non-negative integer k.
  wrap[Z3Real](a.ctx, a.ctx.checkErr Z3_algebraic_power(a.ctx.raw, a.raw, cuint(k)))

proc `^`*(a: Z3Real, k: int): Z3Real =
  ## Operator alias for `algebraicPower(a, k)` — integer power.
  ## Note: this operator is defined only when the operand is a Z3Real and k is
  ## a Nim int; it shadows no existing operator in arith.nim (which has no `^`).
  algebraicPower(a, k)

# ============================================================================
# Comparisons — return Nim bool (concrete algebraic comparisons)
# ============================================================================

proc algebraicLt*(a, b: Z3Real): bool {.inline.} =
  ## True if a < b (concrete algebraic comparison).
  Z3_algebraic_lt(a.ctx.raw, a.raw, b.raw)

proc algebraicGt*(a, b: Z3Real): bool {.inline.} =
  ## True if a > b.
  Z3_algebraic_gt(a.ctx.raw, a.raw, b.raw)

proc algebraicLe*(a, b: Z3Real): bool {.inline.} =
  ## True if a ≤ b.
  Z3_algebraic_le(a.ctx.raw, a.raw, b.raw)

proc algebraicGe*(a, b: Z3Real): bool {.inline.} =
  ## True if a ≥ b.
  Z3_algebraic_ge(a.ctx.raw, a.raw, b.raw)

proc algebraicEq*(a, b: Z3Real): bool {.inline.} =
  ## True if a = b exactly (concrete algebraic equality).
  ## Note: this is a concrete numeric comparison, NOT the symbolic Z3Bool
  ## equality that `==` produces for Z3Real in ast.nim.
  Z3_algebraic_eq(a.ctx.raw, a.raw, b.raw)

proc algebraicNeq*(a, b: Z3Real): bool {.inline.} =
  ## True if a ≠ b.
  Z3_algebraic_neq(a.ctx.raw, a.raw, b.raw)

# ============================================================================
# Root enumeration — returns seq[Z3Real]
# ============================================================================

proc algebraicRoots*(p: Z3Real, vals: openArray[Z3Real]): seq[Z3Real] =
  ## Given a multivariate polynomial `p(x_0, ..., x_{n-1}, x_n)`, return the
  ## real roots of the univariate polynomial `p(vals[0], ..., vals[n-1], x_n)`.
  ##
  ## For a univariate polynomial (e.g. `x^2 - 2`) pass `vals = []`: Z3 treats
  ## the free variable in `p` as the last variable.
  ##
  ## All elements of `vals` must satisfy `algebraicIsValue`. Plain rational
  ## constants (`mkReal`) are also accepted (Z3 coerces them).
  let ctx = p.ctx
  var rawVals = newSeq[RawZ3Ast](vals.len)
  for i, v in vals:
    rawVals[i] = v.raw
  let rawVec =
    if vals.len == 0:
      ctx.checkErr Z3_algebraic_roots(ctx.raw, p.raw, 0,
                                      cast[ptr UncheckedArray[RawZ3Ast]](nil))
    else:
      ctx.checkErr Z3_algebraic_roots(ctx.raw, p.raw, cuint(vals.len),
                                      cast[ptr UncheckedArray[RawZ3Ast]](
                                        addr rawVals[0]))
  let vec = wrapAstVector(ctx, rawVec)
  result = newSeq[Z3Real](vec.len)
  for i in 0 ..< vec.len:
    result[i] = wrap[Z3Real](ctx, ctx.checkErr vec[i])

# ============================================================================
# Sign evaluation at an algebraic point
# ============================================================================

proc algebraicEval*(p: Z3Real, vals: openArray[Z3Real]): int =
  ## Evaluate the sign of polynomial `p(vals[0], ..., vals[n-1])`.
  ## Returns 1 (positive), 0 (zero), or -1 (negative).
  ##
  ## `p` is a Z3 expression in free variables; `vals` substitutes each
  ## variable (in the order Z3 sees them). All `vals` elements must satisfy
  ## `algebraicIsValue` or be rational constants.
  let ctx = p.ctx
  var rawVals = newSeq[RawZ3Ast](vals.len)
  for i, v in vals:
    rawVals[i] = v.raw
  let sign =
    if vals.len == 0:
      ctx.checkErr Z3_algebraic_eval(ctx.raw, p.raw, 0,
                                     cast[ptr UncheckedArray[RawZ3Ast]](nil))
    else:
      ctx.checkErr Z3_algebraic_eval(ctx.raw, p.raw, cuint(vals.len),
                                     cast[ptr UncheckedArray[RawZ3Ast]](
                                       addr rawVals[0]))
  int(sign)

# ============================================================================
# Polynomial subresultants (merged from N1.5)
# ============================================================================

proc subresultants*(p, q, x: Z3Real): Z3AstVector =
  ## Return the nonzero subresultant polynomial chain of `p` and `q` with
  ## respect to variable `x`. The result is a `Z3AstVector` of ASTs
  ## representing the subresultant polynomials.
  ##
  ## This is the complete merged N1.5 surface (formerly proposed as a
  ## separate `polynomial.nim` module). Subresultants are useful for:
  ##
  ##   - Computing polynomial GCDs over algebraic extensions
  ##   - Cylindrical Algebraic Decomposition preprocessing
  ##   - Detecting common roots of two polynomials
  let ctx = p.ctx
  wrapAstVector(ctx,
    ctx.checkErr Z3_polynomial_subresultants(ctx.raw, p.raw, q.raw, x.raw))

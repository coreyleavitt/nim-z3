## `z3/algebraic` -- operations on Z3 algebraic numerals (real-valued ASTs).
##
## ## Overview
##
## Z3 represents algebraic numbers -- exact real roots of integer polynomials
## such as sqrt(2), cbrt(5), the golden ratio phi -- as a special subset of
## the `Z3 Real` sort. These ASTs satisfy `Z3_algebraic_is_value` and are
## produced by:
##
##   - `algebraicRoot(a, k)` -- the k-th root a^(1/k)
##   - `algebraicPower(a, k)` -- the integer power a^k
##   - `algebraicAdd` / `algebraicSub` / `algebraicMul` / `algebraicDiv`
##   - `algebraicNeg`
##   - `algebraicRoots(p, vals)` -- real roots of a polynomial
##
## ## Type design
##
## `Z3AlgebraicNum` is a distinct type wrapping `Z3Real`. All Z3 algebraic
## operations take and return `Z3AlgebraicNum`, NOT `Z3Real`. This eliminates
## the overload-resolution ambiguity between algebraic concrete operations
## (which return `bool` or `Z3AlgebraicNum`) and `arith.nim`'s symbolic SMT
## operators (which return `Z3Bool` or `Z3Real`). With the distinct type,
## operator overloads `+/-/*//` and `</<=/>=/>=/==/!=` are now safe to expose.
##
## Conversion procs:
##   - `toAlgebraic(r: Z3Real): Z3AlgebraicNum` -- explicit cast; precondition:
##     `r` must be an algebraic-numeral AST (i.e. satisfies `algebraicIsValue`)
##   - `toReal(a: Z3AlgebraicNum): Z3Real` -- unwrap back to Z3Real
##
## `mkBoundReal` returns `Z3Real` (bound variable for polynomial expressions).
## `algebraicRoots` and `algebraicEval` accept `Z3Real` for the polynomial
## argument and return / accept `Z3AlgebraicNum` for the algebraic values.
##
## ## Lifecycle
##
## `Z3AlgebraicNum = distinct Z3Real` -- for non-generic distinct types,
## Nim 2.2 automatically propagates the base type's `=destroy` / `=copy` /
## `=dup` hooks. Explicit redeclarations are NOT needed (and would error
## "cannot bind another =copy"). Copies of Z3AlgebraicNum correctly inc_ref
## via Z3Real's =copy; destruction correctly dec_refs via Z3Real's =destroy.
##
## ## Polynomial subresultants (merged from N1.5)
##
## `subresultants(p, q, x)` exposes `Z3_polynomial_subresultants`, returning
## a `Z3AstVector`. Arguments are `Z3Real` (symbolic vars, NOT algebraic vals).
##
## ## Build gate
##
## Gated on `-d:z3WithoutAlgebraic`. When built with that flag, this file
## imports cleanly but exports nothing. Match the existing pattern from
## `spacer.nim`, `simplifier.nim`, `order.nim`, `onclause.nim`.

when not defined(z3WithoutAlgebraic):

  import ./ffi, ./context, ./error, ./ast, ./builder, ./astvector

  # ==========================================================================
  # Z3AlgebraicNum -- distinct type for algebraic numerals
  # ==========================================================================

  type
    Z3AlgebraicNum* = distinct Z3Real
      ## A Z3 algebraic numeral: an exact real root of an integer polynomial.
      ## Distinct from `Z3Real` to prevent silent overload-resolution
      ## collisions with `arith.nim`'s symbolic operators.
      ## Lifecycle: Nim 2.2 propagates Z3Real's =destroy/=copy/=dup hooks.

  # --------------------------------------------------------------------------
  # Context/raw accessors for internal use
  # --------------------------------------------------------------------------

  template algCtx(a: Z3AlgebraicNum): Z3Context = Z3Real(a).ctx
  template algRaw(a: Z3AlgebraicNum): RawZ3Ast  = Z3Real(a).raw

  # --------------------------------------------------------------------------
  # Zero-cost conversions
  # --------------------------------------------------------------------------

  proc toAlgebraic*(r: Z3Real): Z3AlgebraicNum {.inline.} =
    ## Explicitly cast a `Z3Real` to `Z3AlgebraicNum`.
    ## Precondition: `r` must be an algebraic-numeral AST (i.e. satisfies
    ## `algebraicIsValue`). In debug/test builds a `doAssert` enforces this;
    ## in release builds the check is elided for zero cost.
    when not defined(release):
      doAssert Z3_algebraic_is_value(r.ctx.raw, r.raw),
        "toAlgebraic: precondition violated — r is not an algebraic numeral. " &
        "Use algebraicIsValue(r) to check before casting."
    Z3AlgebraicNum(r)

  proc toReal*(a: Z3AlgebraicNum): Z3Real {.inline.} =
    ## Unwrap a `Z3AlgebraicNum` back to its underlying `Z3Real`.
    Z3Real(a)

  # ==========================================================================
  # Bound-variable constructor for polynomial arguments
  # ==========================================================================

  proc mkBoundReal*(ctx: Z3Context, index: int): Z3Real =
    ## Construct a de-Bruijn-indexed bound variable of the Real sort.
    ## Returns `Z3Real` (NOT `Z3AlgebraicNum`). Used as the indeterminate in
    ## polynomial expressions passed to `algebraicRoots`.
    ## For a univariate polynomial p(x), pass `index = 0`.
    let realSort = ctx.checkErr Z3_mk_real_sort(ctx.raw)
    wrap[Z3Real](ctx, ctx.checkErr Z3_mk_bound(ctx.raw, cuint(index), realSort))

  # ==========================================================================
  # Predicates -- take Z3AlgebraicNum, return Nim bool
  # ==========================================================================

  proc algebraicIsValue*(a: Z3AlgebraicNum): bool {.inline.} =
    ## True if `a` was produced by the algebraic number package.
    Z3_algebraic_is_value(a.algCtx.raw, a.algRaw)

  proc algebraicIsPos*(a: Z3AlgebraicNum): bool {.inline.} =
    ## True if algebraic numeral `a` is positive.
    Z3_algebraic_is_pos(a.algCtx.raw, a.algRaw)

  proc algebraicIsNeg*(a: Z3AlgebraicNum): bool {.inline.} =
    ## True if algebraic numeral `a` is negative.
    Z3_algebraic_is_neg(a.algCtx.raw, a.algRaw)

  proc algebraicIsZero*(a: Z3AlgebraicNum): bool {.inline.} =
    ## True if algebraic numeral `a` is zero.
    Z3_algebraic_is_zero(a.algCtx.raw, a.algRaw)

  proc algebraicSign*(a: Z3AlgebraicNum): int {.inline.} =
    ## Returns 1 (positive), 0 (zero), or -1 (negative).
    int(Z3_algebraic_sign(a.algCtx.raw, a.algRaw))

  # ==========================================================================
  # Arithmetic -- take Z3AlgebraicNum, return Z3AlgebraicNum
  # ==========================================================================

  proc algebraicAdd*(a, b: Z3AlgebraicNum): Z3AlgebraicNum =
    ## Return the algebraic numeral a + b.
    Z3AlgebraicNum(wrap[Z3Real](a.algCtx,
      a.algCtx.checkErr Z3_algebraic_add(a.algCtx.raw, a.algRaw, b.algRaw)))

  proc algebraicSub*(a, b: Z3AlgebraicNum): Z3AlgebraicNum =
    ## Return the algebraic numeral a - b.
    Z3AlgebraicNum(wrap[Z3Real](a.algCtx,
      a.algCtx.checkErr Z3_algebraic_sub(a.algCtx.raw, a.algRaw, b.algRaw)))

  proc algebraicMul*(a, b: Z3AlgebraicNum): Z3AlgebraicNum =
    ## Return the algebraic numeral a * b.
    Z3AlgebraicNum(wrap[Z3Real](a.algCtx,
      a.algCtx.checkErr Z3_algebraic_mul(a.algCtx.raw, a.algRaw, b.algRaw)))

  proc algebraicDiv*(a, b: Z3AlgebraicNum): Z3AlgebraicNum =
    ## Return the algebraic numeral a / b. Precondition: b != 0.
    Z3AlgebraicNum(wrap[Z3Real](a.algCtx,
      a.algCtx.checkErr Z3_algebraic_div(a.algCtx.raw, a.algRaw, b.algRaw)))

  proc algebraicNeg*(a: Z3AlgebraicNum): Z3AlgebraicNum =
    ## Return the algebraic numeral -a.
    ## Z3_algebraic_neg is absent from z3_algebraic.h. Implemented as
    ## 0 - a via Z3_algebraic_sub with the zero rational.
    ##
    ## Note: Z3_mk_unary_minus is NOT used here even though it accepts
    ## Real-sorted ASTs. It produces a symbolic application node, NOT an
    ## algebraic-package numeral — i.e. the result fails Z3_algebraic_is_value.
    ## Only the Z3_algebraic_* family guarantees the algebraic-package marker
    ## on its outputs. Verified empirically with sqrt(2) as a probe input.
    let zero = mkReal(a.algCtx, 0).toAlgebraic
    Z3AlgebraicNum(wrap[Z3Real](a.algCtx,
      a.algCtx.checkErr Z3_algebraic_sub(a.algCtx.raw, zero.algRaw, a.algRaw)))

  proc algebraicRoot*(a: Z3AlgebraicNum, k: int): Z3AlgebraicNum =
    ## Return a^(1/k), the k-th root of algebraic numeral `a`.
    ## Precondition: k is odd OR a >= 0.
    Z3AlgebraicNum(wrap[Z3Real](a.algCtx,
      a.algCtx.checkErr Z3_algebraic_root(a.algCtx.raw, a.algRaw, cuint(k))))

  proc algebraicPower*(a: Z3AlgebraicNum, k: int): Z3AlgebraicNum =
    ## Return a^k for non-negative integer k.
    Z3AlgebraicNum(wrap[Z3Real](a.algCtx,
      a.algCtx.checkErr Z3_algebraic_power(a.algCtx.raw, a.algRaw, cuint(k))))

  # ==========================================================================
  # Comparisons -- named forms (take Z3AlgebraicNum, return Nim bool)
  # ==========================================================================

  proc algebraicLt*(a, b: Z3AlgebraicNum): bool {.inline.} =
    ## True if a < b (concrete algebraic comparison).
    Z3_algebraic_lt(a.algCtx.raw, a.algRaw, b.algRaw)

  proc algebraicGt*(a, b: Z3AlgebraicNum): bool {.inline.} =
    ## True if a > b.
    Z3_algebraic_gt(a.algCtx.raw, a.algRaw, b.algRaw)

  proc algebraicLe*(a, b: Z3AlgebraicNum): bool {.inline.} =
    ## True if a <= b.
    Z3_algebraic_le(a.algCtx.raw, a.algRaw, b.algRaw)

  proc algebraicGe*(a, b: Z3AlgebraicNum): bool {.inline.} =
    ## True if a >= b.
    Z3_algebraic_ge(a.algCtx.raw, a.algRaw, b.algRaw)

  proc algebraicEq*(a, b: Z3AlgebraicNum): bool {.inline.} =
    ## True if a = b exactly (concrete algebraic equality).
    ## This is a concrete numeric comparison, NOT symbolic Z3Bool equality.
    Z3_algebraic_eq(a.algCtx.raw, a.algRaw, b.algRaw)

  proc algebraicNeq*(a, b: Z3AlgebraicNum): bool {.inline.} =
    ## True if a != b.
    Z3_algebraic_neq(a.algCtx.raw, a.algRaw, b.algRaw)

  # ==========================================================================
  # Operator overloads -- safe because distinct type prevents collision
  # ==========================================================================
  # Arithmetic operators return Z3AlgebraicNum; comparison operators return
  # bool. No collision with arith.nim's Z3Real operators (distinct type).

  proc `+`*(a, b: Z3AlgebraicNum): Z3AlgebraicNum {.inline.} =
    algebraicAdd(a, b)

  proc `-`*(a, b: Z3AlgebraicNum): Z3AlgebraicNum {.inline.} =
    algebraicSub(a, b)

  proc `*`*(a, b: Z3AlgebraicNum): Z3AlgebraicNum {.inline.} =
    algebraicMul(a, b)

  proc `/`*(a, b: Z3AlgebraicNum): Z3AlgebraicNum {.inline.} =
    algebraicDiv(a, b)

  proc `-`*(a: Z3AlgebraicNum): Z3AlgebraicNum {.inline.} =
    algebraicNeg(a)

  proc `^`*(a: Z3AlgebraicNum, k: int): Z3AlgebraicNum {.inline.} =
    algebraicPower(a, k)

  proc `<`*(a, b: Z3AlgebraicNum): bool {.inline.} =
    algebraicLt(a, b)

  proc `<=`*(a, b: Z3AlgebraicNum): bool {.inline.} =
    algebraicLe(a, b)

  proc `>`*(a, b: Z3AlgebraicNum): bool {.inline.} =
    algebraicGt(a, b)

  proc `>=`*(a, b: Z3AlgebraicNum): bool {.inline.} =
    algebraicGe(a, b)

  proc `==`*(a, b: Z3AlgebraicNum): bool {.inline.} =
    algebraicEq(a, b)

  proc `!=`*(a, b: Z3AlgebraicNum): bool {.inline.} =
    algebraicNeq(a, b)

  # ==========================================================================
  # Root enumeration -- returns seq[Z3AlgebraicNum]
  # ==========================================================================

  proc algebraicRoots*(p: Z3Real, vals: openArray[Z3AlgebraicNum]): seq[Z3AlgebraicNum] =
    ## Given polynomial `p` built with `mkBoundReal`, return its real roots
    ## as `Z3AlgebraicNum`. Pass `vals = []` for a univariate polynomial.
    let ctx = p.ctx
    var rawVals = newSeq[RawZ3Ast](vals.len)
    for i, v in vals:
      rawVals[i] = v.algRaw
    let rawVec =
      if vals.len == 0:
        ctx.checkErr Z3_algebraic_roots(ctx.raw, p.raw, 0,
                                        cast[ptr UncheckedArray[RawZ3Ast]](nil))
      else:
        ctx.checkErr Z3_algebraic_roots(ctx.raw, p.raw, cuint(vals.len),
                                        cast[ptr UncheckedArray[RawZ3Ast]](
                                          addr rawVals[0]))
    let vec = wrapAstVector(ctx, rawVec)
    result = newSeq[Z3AlgebraicNum](vec.len)
    for i in 0 ..< vec.len:
      result[i] = Z3AlgebraicNum(wrap[Z3Real](ctx, ctx.checkErr vec[i]))

  # ==========================================================================
  # Sign evaluation at an algebraic point
  # ==========================================================================

  proc algebraicEval*(p: Z3Real, vals: openArray[Z3AlgebraicNum]): int =
    ## Evaluate the sign of polynomial `p(vals[0], ..., vals[n-1])`.
    ## Returns 1 (positive), 0 (zero), or -1 (negative).
    let ctx = p.ctx
    var rawVals = newSeq[RawZ3Ast](vals.len)
    for i, v in vals:
      rawVals[i] = v.algRaw
    let sign =
      if vals.len == 0:
        ctx.checkErr Z3_algebraic_eval(ctx.raw, p.raw, 0,
                                       cast[ptr UncheckedArray[RawZ3Ast]](nil))
      else:
        ctx.checkErr Z3_algebraic_eval(ctx.raw, p.raw, cuint(vals.len),
                                       cast[ptr UncheckedArray[RawZ3Ast]](
                                         addr rawVals[0]))
    int(sign)

  # ==========================================================================
  # Polynomial introspection -- defining polynomial and root index
  # ==========================================================================

  proc algebraicGetPoly*(a: Z3AlgebraicNum): Z3AstVector =
    ## Return the defining polynomial of algebraic numeral `a` as a
    ## `Z3AstVector` of coefficients ordered from lowest to highest degree.
    ## Precondition: a was obtained via algebraic ops (algebraicRoot, +, -, *, /, etc.)
    ## OR via toAlgebraic on a Z3Real that satisfies algebraicIsValue.
    ## The distinct-type wrapper makes most misuse a type error; toAlgebraic's debug
    ## assertion catches the remaining case.
    let ctx = a.algCtx
    wrapAstVector(ctx, ctx.checkErr Z3_algebraic_get_poly(ctx.raw, a.algRaw))

  proc algebraicGetI*(a: Z3AlgebraicNum): int =
    ## Return the 1-based root index among the roots of the defining polynomial.
    ## Precondition: a was obtained via algebraic ops (algebraicRoot, +, -, *, /, etc.)
    ## OR via toAlgebraic on a Z3Real that satisfies algebraicIsValue.
    ## The distinct-type wrapper makes most misuse a type error; toAlgebraic's debug
    ## assertion catches the remaining case.
    int(Z3_algebraic_get_i(a.algCtx.raw, a.algRaw))

  # ==========================================================================
  # Polynomial subresultants (merged from N1.5)
  # ==========================================================================

  proc subresultants*(p, q, x: Z3Real): Z3AstVector =
    ## Return the nonzero subresultant polynomial chain of `p` and `q` with
    ## respect to variable `x`. All three arguments are `Z3Real` (symbolic
    ## polynomial variables, NOT algebraic numerals). Use `mkRealVar` for `x`.
    let ctx = p.ctx
    wrapAstVector(ctx,
      ctx.checkErr Z3_polynomial_subresultants(ctx.raw, p.raw, q.raw, x.raw))

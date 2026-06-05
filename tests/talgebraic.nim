## `z3/algebraic` tests -- algebraic number operations and polynomial subresultants.
##
## All algebraic values are `Z3AlgebraicNum` (M5 fix). Use `.toAlgebraic` to
## wrap mkReal inputs and `.toReal` to access the underlying Z3Real when needed.

import std/unittest
import z3

suite "algebraic -- isValue":
  test "mkReal(2).toAlgebraic IS an algebraic value":
    let ctx = newContext()
    let two = mkReal(ctx, 2).toAlgebraic
    check algebraicIsValue(two)

  test "algebraicRoot(mkReal(2).toAlgebraic, 2) produces an algebraic value":
    let ctx = newContext()
    let two = mkReal(ctx, 2).toAlgebraic
    let r = algebraicRoot(two, 2)
    check algebraicIsValue(r)

suite "algebraic -- predicates":
  test "sqrt(2) is positive":
    let ctx = newContext()
    let r = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    check algebraicIsPos(r)

  test "sqrt(2) is not negative":
    let ctx = newContext()
    let r = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    check not algebraicIsNeg(r)

  test "sqrt(2) is not zero":
    let ctx = newContext()
    let r = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    check not algebraicIsZero(r)

  test "sign of sqrt(2) is 1":
    let ctx = newContext()
    let r = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    check algebraicSign(r) == 1

suite "algebraic -- arithmetic (named procs)":
  test "sqrt(2)^2 equals 2 via algebraicPower":
    let ctx = newContext()
    let r = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let r2 = algebraicPower(r, 2)
    check algebraicIsValue(r2)
    check algebraicEq(r2, mkReal(ctx, 2).toAlgebraic)

  test "sqrt(2) + sqrt(2) == 2 * sqrt(2)":
    let ctx = newContext()
    let r  = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let r2 = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let sumR = algebraicAdd(r, r2)
    let r3   = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let prod = algebraicMul(mkReal(ctx, 2).toAlgebraic, r3)
    check algebraicEq(sumR, prod)

  test "algebraicSub(sqrt(2), sqrt(2)) is zero":
    let ctx = newContext()
    let r  = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let r2 = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let d = algebraicSub(r, r2)
    check algebraicIsZero(d)

  test "algebraicDiv(sqrt(2), sqrt(2)) is one":
    let ctx = newContext()
    let r  = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let r2 = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let q = algebraicDiv(r, r2)
    check algebraicEq(q, mkReal(ctx, 1).toAlgebraic)

  test "unary neg: -sqrt(2) is negative":
    let ctx = newContext()
    let r = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let nr = algebraicNeg(r)
    check algebraicIsNeg(nr)

suite "algebraic -- arithmetic (operator aliases)":
  test "operator +: sqrt(2) + sqrt(2) == 2*sqrt(2)":
    let ctx = newContext()
    let r    = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let r2   = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let sumR = r + r2
    let r3   = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let prod = mkReal(ctx, 2).toAlgebraic * r3
    check sumR == prod

  test "operator -: sqrt(2) - sqrt(2) is zero":
    let ctx = newContext()
    let r  = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let r2 = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let d = r - r2
    check algebraicIsZero(d)

  test "operator *: sqrt(2) * sqrt(2) == 2":
    let ctx = newContext()
    let r  = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let r2 = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let p = r * r2
    check p == mkReal(ctx, 2).toAlgebraic

  test "operator /: sqrt(2) / sqrt(2) == 1":
    let ctx = newContext()
    let r  = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let r2 = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let q = r / r2
    check q == mkReal(ctx, 1).toAlgebraic

  test "operator unary -: -sqrt(2) is negative":
    let ctx = newContext()
    let r = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let nr = -r
    check algebraicIsNeg(nr)

  test "operator ^: sqrt(2)^2 == 2":
    let ctx = newContext()
    let r = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let r2 = r ^ 2
    check r2 == mkReal(ctx, 2).toAlgebraic

suite "algebraic -- comparison (named procs)":
  test "sqrt(2) < mkReal(2) is true":
    let ctx = newContext()
    let r   = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let two = mkReal(ctx, 2).toAlgebraic
    check algebraicLt(r, two)

  test "mkReal(2) > sqrt(2) is true":
    let ctx = newContext()
    let r   = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let two = mkReal(ctx, 2).toAlgebraic
    check algebraicGt(two, r)

  test "sqrt(2) <= sqrt(2) is true":
    let ctx = newContext()
    let r  = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let r2 = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    check algebraicLe(r, r2)

  test "sqrt(2) >= sqrt(2) is true":
    let ctx = newContext()
    let r  = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let r2 = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    check algebraicGe(r, r2)

  test "sqrt(2) neq mkReal(3) is true":
    let ctx = newContext()
    let r     = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let three = mkReal(ctx, 3).toAlgebraic
    check algebraicNeq(r, three)

suite "algebraic -- comparison (operator aliases)":
  test "operator <: sqrt(2) < 2":
    let ctx = newContext()
    let r   = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let two = mkReal(ctx, 2).toAlgebraic
    check r < two

  test "operator <=: sqrt(2) <= sqrt(2)":
    let ctx = newContext()
    let r  = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let r2 = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    check r <= r2

  test "operator >: 2 > sqrt(2)":
    let ctx = newContext()
    let r   = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let two = mkReal(ctx, 2).toAlgebraic
    check two > r

  test "operator >=: sqrt(2) >= sqrt(2)":
    let ctx = newContext()
    let r  = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let r2 = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    check r >= r2

  test "operator ==: sqrt(2) == sqrt(2)":
    let ctx = newContext()
    let r  = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let r2 = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    check r == r2

  test "operator !=: sqrt(2) != 3":
    let ctx = newContext()
    let r     = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let three = mkReal(ctx, 3).toAlgebraic
    check r != three

suite "algebraic -- roots":
  test "roots(x^2 - 2, []) returns 2 algebraic values":
    let ctx = newContext()
    let x = mkBoundReal(ctx, 0)
    let p = x * x - mkReal(ctx, 2)
    let rs = algebraicRoots(p, [])
    check rs.len == 2

  test "roots result elements are all algebraic values":
    let ctx = newContext()
    let x = mkBoundReal(ctx, 0)
    let p = x * x - mkReal(ctx, 2)
    let rs = algebraicRoots(p, [])
    for r in rs:
      check algebraicIsValue(r)

  test "roots result elements are Z3AlgebraicNum":
    let ctx = newContext()
    let x = mkBoundReal(ctx, 0)
    let p = x * x - mkReal(ctx, 2)
    let rs: seq[Z3AlgebraicNum] = algebraicRoots(p, [])
    check rs.len == 2

suite "algebraic -- eval":
  test "eval(x^2 - 2, [sqrt(2)]) returns 0 (sign)":
    let ctx = newContext()
    let x = mkBoundReal(ctx, 0)
    let p = x * x - mkReal(ctx, 2)
    let r = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    check algebraicEval(p, [r]) == 0

  test "eval(x^2 - 2, [2.toAlgebraic]) returns positive (2^2-2=2>0)":
    let ctx = newContext()
    let x = mkBoundReal(ctx, 0)
    let p = x * x - mkReal(ctx, 2)
    let two = mkReal(ctx, 2).toAlgebraic
    check algebraicEval(p, [two]) == 1

suite "algebraic -- subresultants (merged from N1.5)":
  test "subresultants(x^2, x+1, x) returns non-empty vector":
    let ctx = newContext()
    let x = mkRealVar(ctx, "x")
    let p = x * x
    let q = x + mkReal(ctx, 1)
    let sv = subresultants(p, q, x)
    check sv.len > 0

  test "subresultants first element is an AST (non-nil raw)":
    let ctx = newContext()
    let x = mkRealVar(ctx, "x")
    let p = x * x
    let q = x + mkReal(ctx, 1)
    let sv = subresultants(p, q, x)
    check sv.len > 0
    let first = sv[0]
    check not first.isNil

  test "subresultants(x^2 - 1, x - 1, x): GCD-like result (nonzero vector)":
    let ctx = newContext()
    let x = mkRealVar(ctx, "x")
    let p = x * x - mkReal(ctx, 1)
    let q = x - mkReal(ctx, 1)
    let sv = subresultants(p, q, x)
    check sv.len > 0

suite "algebraic -- toAlgebraic / toReal conversions":
  test "mkReal(2).toAlgebraic.toReal round-trips to Z3Real":
    let ctx = newContext()
    let r: Z3Real = mkReal(ctx, 2)
    let a: Z3AlgebraicNum = r.toAlgebraic
    let r2: Z3Real = a.toReal
    check astEqual(r, r2)

  test "algebraicRoot result .toReal produces a Z3Real":
    let ctx = newContext()
    let sqrt2 = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let asReal: Z3Real = sqrt2.toReal
    check algebraicIsValue(asReal.toAlgebraic)

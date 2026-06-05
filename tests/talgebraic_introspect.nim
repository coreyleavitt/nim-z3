## `z3/algebraic` introspection tests -- algebraicGetPoly / algebraicGetI.
##
## All algebraic values are Z3AlgebraicNum (M5 fix).

import std/unittest
import z3

suite "algebraicGetPoly":
  test "sqrt(2) polynomial has 3 coefficients (degree 2)":
    let ctx = newContext()
    let s = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let poly = algebraicGetPoly(s)
    check poly.len == 3

  test "sqrt(2) polynomial constant term (index 0) is -2":
    let ctx = newContext()
    let s = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let poly = algebraicGetPoly(s)
    let c0 = wrap[Z3Real](ctx, poly[0])
    check $c0 == "(- 2.0)"

  test "sqrt(2) polynomial leading coefficient (index 2) is 1":
    let ctx = newContext()
    let s = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    let poly = algebraicGetPoly(s)
    let c2 = wrap[Z3Real](ctx, poly[2])
    check $c2 == "1.0"

suite "algebraicGetI":
  test "sqrt(2) is the 2nd root of x^2 - 2 (positive root)":
    let ctx = newContext()
    let s = algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2)
    check algebraicGetI(s) == 2

  test "neg sqrt(2) is the 1st root of x^2 - 2 (negative root)":
    let ctx = newContext()
    let neg = algebraicNeg(algebraicRoot(mkReal(ctx, 2).toAlgebraic, 2))
    check algebraicGetI(neg) == 1

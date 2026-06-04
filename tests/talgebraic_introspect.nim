## `z3/algebraic` introspection tests — algebraicGetPoly / algebraicGetI.
##
## Covers:
##   - algebraicGetPoly: returns the defining polynomial coefficients (low→high)
##     as a Z3AstVector of length == degree + 1
##   - algebraicGetI: 1-based root index ordering the roots of the polynomial
##     by value (smallest root = 1)

import std/unittest
import z3

suite "algebraicGetPoly":
  test "sqrt(2) polynomial has 3 coefficients (degree 2)":
    let ctx = newContext()
    let s = algebraicRoot(mkReal(ctx, 2), 2)
    let poly = algebraicGetPoly(s)
    check poly.len == 3

  test "sqrt(2) polynomial constant term (index 0) is -2":
    ## x^2 - 2: coefficients low→high are [-2, 0, 1].
    ## We compare via SMT-LIB string rendering.
    let ctx = newContext()
    let s = algebraicRoot(mkReal(ctx, 2), 2)
    let poly = algebraicGetPoly(s)
    let c0 = wrap[Z3Real](ctx, poly[0])
    check $c0 == "(- 2.0)"

  test "sqrt(2) polynomial leading coefficient (index 2) is 1":
    let ctx = newContext()
    let s = algebraicRoot(mkReal(ctx, 2), 2)
    let poly = algebraicGetPoly(s)
    let c2 = wrap[Z3Real](ctx, poly[2])
    check $c2 == "1.0"

suite "algebraicGetI":
  test "sqrt(2) is the 2nd root of x^2 - 2 (positive root)":
    ## x^2 - 2 has two roots: -sqrt(2) (index 1) and sqrt(2) (index 2).
    let ctx = newContext()
    let s = algebraicRoot(mkReal(ctx, 2), 2)
    check algebraicGetI(s) == 2

  test "neg sqrt(2) is the 1st root of x^2 - 2 (negative root)":
    let ctx = newContext()
    let neg = algebraicNeg(algebraicRoot(mkReal(ctx, 2), 2))
    check algebraicGetI(neg) == 1

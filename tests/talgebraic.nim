## `z3/algebraic` tests — algebraic number operations and polynomial subresultants.
##
## Covers:
##   - Predicates: isValue, isPos, isNeg, isZero, sign
##   - Arithmetic: +, -, *, /, unary -, root, power (^)
##   - Comparisons: <, <=, >, >=, == (concrete bool comparisons)
##   - roots — multivariate polynomial root enumeration → seq[Z3Real]
##   - eval  — sign of polynomial at an algebraic point → int
##   - subresultants — polynomial subresultant chain → Z3AstVector
##
## Design note: Z3's algebraic API operates directly on Z3_ast values that
## happen to be algebraic numerals (a subset of the Z3 Real sort). The Nim
## wrapper exposes these as procs taking/returning Z3Real. The operations
## return concrete Nim values (bool/int) — they are evaluated immediately by
## Z3's algebraic decision procedure, not symbolic Z3Bool ASTs.

import std/unittest
import z3

suite "algebraic — isValue":
  test "mkReal(2) IS an algebraic value (Z3 accepts rational constants)":
    ## Z3_algebraic_is_value returns true for rational constants produced by
    ## Z3_mk_real as well as for roots produced by Z3_algebraic_root.
    ## Z3 treats any evaluatable real numeral as an algebraic value.
    let ctx = newContext()
    let two = mkReal(ctx, 2)
    check algebraicIsValue(two)

  test "algebraicRoot(mkReal(2), 2) produces an algebraic value":
    let ctx = newContext()
    let two = mkReal(ctx, 2)
    let r = algebraicRoot(two, 2)
    check algebraicIsValue(r)

suite "algebraic — predicates":
  test "sqrt(2) is positive":
    let ctx = newContext()
    let r = algebraicRoot(mkReal(ctx, 2), 2)
    check algebraicIsPos(r)

  test "sqrt(2) is not negative":
    let ctx = newContext()
    let r = algebraicRoot(mkReal(ctx, 2), 2)
    check not algebraicIsNeg(r)

  test "sqrt(2) is not zero":
    let ctx = newContext()
    let r = algebraicRoot(mkReal(ctx, 2), 2)
    check not algebraicIsZero(r)

  test "sign of sqrt(2) is 1":
    let ctx = newContext()
    let r = algebraicRoot(mkReal(ctx, 2), 2)
    check algebraicSign(r) == 1

suite "algebraic — arithmetic":
  test "sqrt(2) * sqrt(2) squared back: root(2,2)^2 is value near 2":
    ## Compute sqrt(2)^2 via algebraicPower and verify it equals 2.
    ## We check by comparing it equals mkReal(ctx, 2) via subtracting and
    ## checking algebraicIsZero on the difference.
    let ctx = newContext()
    let r = algebraicRoot(mkReal(ctx, 2), 2)
    let r2 = algebraicPower(r, 2)
    check algebraicIsValue(r2)
    # r2 should equal 2; verify via algebraicEq
    let two = mkReal(ctx, 2)
    check algebraicEq(r2, two)

  test "sqrt(2) + sqrt(2) == 2 * sqrt(2)":
    let ctx = newContext()
    let r = algebraicRoot(mkReal(ctx, 2), 2)
    let r2 = algebraicRoot(mkReal(ctx, 2), 2)
    let sumR = algebraicAdd(r, r2)
    let r3 = algebraicRoot(mkReal(ctx, 2), 2)
    let prod = algebraicMul(mkReal(ctx, 2), r3)
    check algebraicEq(sumR, prod)

  test "algebraicSub(sqrt(2), sqrt(2)) is zero":
    let ctx = newContext()
    let r  = algebraicRoot(mkReal(ctx, 2), 2)
    let r2 = algebraicRoot(mkReal(ctx, 2), 2)
    let d = algebraicSub(r, r2)
    check algebraicIsZero(d)

  test "algebraicDiv(sqrt(2), sqrt(2)) is one":
    let ctx = newContext()
    let r  = algebraicRoot(mkReal(ctx, 2), 2)
    let r2 = algebraicRoot(mkReal(ctx, 2), 2)
    let q = algebraicDiv(r, r2)
    let one = mkReal(ctx, 1)
    check algebraicEq(q, one)

  test "unary neg: -sqrt(2) is negative":
    let ctx = newContext()
    let r = algebraicRoot(mkReal(ctx, 2), 2)
    let nr = algebraicNeg(r)
    check algebraicIsNeg(nr)

suite "algebraic — comparison":
  test "sqrt(2) < mkReal(2) is true":
    let ctx = newContext()
    let r = algebraicRoot(mkReal(ctx, 2), 2)
    let two = mkReal(ctx, 2)
    check algebraicLt(r, two)

  test "mkReal(2) > sqrt(2) is true":
    let ctx = newContext()
    let r = algebraicRoot(mkReal(ctx, 2), 2)
    let two = mkReal(ctx, 2)
    check algebraicGt(two, r)

  test "sqrt(2) <= sqrt(2) is true":
    let ctx = newContext()
    let r  = algebraicRoot(mkReal(ctx, 2), 2)
    let r2 = algebraicRoot(mkReal(ctx, 2), 2)
    check algebraicLe(r, r2)

  test "sqrt(2) >= sqrt(2) is true":
    let ctx = newContext()
    let r  = algebraicRoot(mkReal(ctx, 2), 2)
    let r2 = algebraicRoot(mkReal(ctx, 2), 2)
    check algebraicGe(r, r2)

  test "sqrt(2) neq mkReal(3) is true":
    let ctx = newContext()
    let r = algebraicRoot(mkReal(ctx, 2), 2)
    let three = mkReal(ctx, 3)
    check algebraicNeq(r, three)

suite "algebraic — roots":
  test "roots(x^2 - 2, []) returns 2 algebraic values":
    ## x^2 - 2 has two real roots: ±sqrt(2).
    ## Z3_algebraic_roots requires the polynomial to be expressed with
    ## a *bound variable* (de-Bruijn index 0) as the free slot, not a
    ## named free constant (mkRealVar). We build p using mkBoundReal.
    let ctx = newContext()
    let x = mkBoundReal(ctx, 0)  # bound var at index 0 = "the last variable"
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

suite "algebraic — eval":
  test "eval(x^2 - 2, [sqrt(2)]) returns 0 (sign)":
    ## Evaluate p(x) = x^2 - 2 at x = sqrt(2). The result should be 0.
    ## Polynomial must use bound variable (de-Bruijn index 0) for `x`.
    let ctx = newContext()
    let x = mkBoundReal(ctx, 0)
    let p = x * x - mkReal(ctx, 2)
    let r = algebraicRoot(mkReal(ctx, 2), 2)
    check algebraicEval(p, [r]) == 0

  test "eval(x^2 - 2, [mkReal(2)]) returns positive (2^2-2=2>0)":
    ## Evaluate p(x) = x^2 - 2 at x = 2. Result = 4 - 2 = 2 > 0, sign = 1.
    let ctx = newContext()
    let x = mkBoundReal(ctx, 0)
    let p = x * x - mkReal(ctx, 2)
    let two = mkReal(ctx, 2)
    check algebraicEval(p, [two]) == 1

suite "algebraic — subresultants (merged from N1.5)":
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

  test "subresultants(x^2 - 1, x - 1, x): GCD-like result is x-1 (nonzero vector)":
    ## gcd(x^2-1, x-1) = x-1; subresultants captures this.
    let ctx = newContext()
    let x = mkRealVar(ctx, "x")
    let p = x * x - mkReal(ctx, 1)
    let q = x - mkReal(ctx, 1)
    let sv = subresultants(p, q, x)
    check sv.len > 0

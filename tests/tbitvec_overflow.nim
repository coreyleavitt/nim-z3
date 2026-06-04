## `z3/bitvec` — BV overflow/underflow predicate tests (N3.1).
##
## Each test asserts the predicate as a solver constraint and checks
## SAT vs UNSAT: if the predicate is provably false (overflow/underflow
## always occurs for these concrete values) adding it as a constraint
## yields UNSAT; if provably true (no overflow) it yields SAT.

import std/[unittest]
import z3

suite "Z3BitVec — overflow/underflow predicates (N3.1)":

  test "addNoOverflow: 200 + 100 overflows unsigned BV[8] (FALSE → UNSAT)":
    ## 200 + 100 = 300, which exceeds 255 (max unsigned 8-bit), so the
    ## no-overflow predicate is provably false for these concrete values.
    let ctx = newContext()
    let s = newSolver()
    s.add mkBitVec[8](200).addNoOverflow(mkBitVec[8](100), signed = false)
    check s.check() == zsUnsat

  test "addNoOverflow: 10 + 20 does not overflow unsigned BV[8] (TRUE → SAT)":
    ## 10 + 20 = 30, well within unsigned 8-bit range.
    let ctx = newContext()
    let s = newSolver()
    s.add mkBitVec[8](10).addNoOverflow(mkBitVec[8](20), signed = false)
    check s.check() == zsSat

  test "addNoUnderflow: 60 + 70 does not underflow signed BV[8] (TRUE → SAT)":
    ## Signed addition: 60 + 70 = 130 > 127, but underflow (going below
    ## -128) cannot occur for two positive values — so no-underflow is true.
    let ctx = newContext()
    let s = newSolver()
    s.add mkBitVec[8](60).addNoUnderflow(mkBitVec[8](70))
    check s.check() == zsSat

  test "addNoUnderflow: (-80) + (-80) underflows signed BV[8] (FALSE → UNSAT)":
    ## -80 + -80 = -160 < -128, signed underflow.
    let ctx = newContext()
    let s = newSolver()
    s.add mkBitVec[8](-80'i32).addNoUnderflow(mkBitVec[8](-80'i32))
    check s.check() == zsUnsat

  test "subNoOverflow: 0 - INT8_MIN overflows signed BV[8] (FALSE → UNSAT)":
    ## Signed sub overflow: 0 - (-128) = 128 > INT8_MAX (127). The
    ## no-overflow predicate is provably false for these concrete values.
    let ctx = newContext()
    let s = newSolver()
    s.add mkBitVec[8](0).subNoOverflow(mkBitVec[8](-128'i32))
    check s.check() == zsUnsat

  test "subNoUnderflow: 5 - 10 underflows unsigned BV[8] (FALSE → UNSAT)":
    ## Unsigned: 5 - 10 wraps around (borrows), so the no-underflow
    ## predicate is false.
    let ctx = newContext()
    let s = newSolver()
    s.add mkBitVec[8](5).subNoUnderflow(mkBitVec[8](10), signed = false)
    check s.check() == zsUnsat

  test "subNoUnderflow: 10 - 5 does not underflow unsigned BV[8] (TRUE → SAT)":
    ## 10 - 5 = 5, no borrow.
    let ctx = newContext()
    let s = newSolver()
    s.add mkBitVec[8](10).subNoUnderflow(mkBitVec[8](5), signed = false)
    check s.check() == zsSat

  test "mulNoOverflow: 16 * 16 overflows unsigned BV[8] (FALSE → UNSAT)":
    ## 16 * 16 = 256, which exceeds 255.
    let ctx = newContext()
    let s = newSolver()
    s.add mkBitVec[8](16).mulNoOverflow(mkBitVec[8](16), signed = false)
    check s.check() == zsUnsat

  test "mulNoOverflow: 3 * 7 does not overflow unsigned BV[8] (TRUE → SAT)":
    ## 3 * 7 = 21, well within range.
    let ctx = newContext()
    let s = newSolver()
    s.add mkBitVec[8](3).mulNoOverflow(mkBitVec[8](7), signed = false)
    check s.check() == zsSat

  test "mulNoUnderflow: (-10) * 20 underflows signed BV[8] (FALSE → UNSAT)":
    ## Signed mul underflow: -10 * 20 = -200 < -128.
    let ctx = newContext()
    let s = newSolver()
    s.add mkBitVec[8](-10'i32).mulNoUnderflow(mkBitVec[8](20))
    check s.check() == zsUnsat

  test "negNoOverflow: neg(-128) overflows signed BV[8] (FALSE → UNSAT)":
    ## INT8_MIN = -128; its 2's-complement negation is 128, which doesn't
    ## fit in a signed 8-bit value (max is 127). Overflow.
    let ctx = newContext()
    let s = newSolver()
    s.add negNoOverflow(mkBitVec[8](-128'i32))
    check s.check() == zsUnsat

  test "negNoOverflow: neg(5) does not overflow signed BV[8] (TRUE → SAT)":
    ## neg(5) = -5, well within range.
    let ctx = newContext()
    let s = newSolver()
    s.add negNoOverflow(mkBitVec[8](5))
    check s.check() == zsSat

  test "sdivNoOverflow: INT8_MIN / (-1) overflows signed BV[8] (FALSE → UNSAT)":
    ## -128 / -1 = 128, which exceeds INT8_MAX = 127. Classic signed div overflow.
    let ctx = newContext()
    let s = newSolver()
    s.add mkBitVec[8](-128'i32).sdivNoOverflow(mkBitVec[8](-1'i32))
    check s.check() == zsUnsat

  test "sdivNoOverflow: 100 / 5 does not overflow signed BV[8] (TRUE → SAT)":
    ## 100 / 5 = 20, no overflow.
    let ctx = newContext()
    let s = newSolver()
    s.add mkBitVec[8](100).sdivNoOverflow(mkBitVec[8](5))
    check s.check() == zsSat

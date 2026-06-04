## `z3/arith` conversion tests — intToReal, realToInt
##
## N4.2: int-to-real coercion (`Z3_mk_int2real`) and real-to-int floor
## (`Z3_mk_real2int`). All behaviors verified through the solver or
## model extraction, not AST string inspection.

import std/[unittest, math]
import z3

# ---------------------------------------------------------------------------
# intToReal
# ---------------------------------------------------------------------------

suite "arith conv — intToReal":
  test "intToReal(5) equals mkReal(5.0) — SAT":
    let ctx = newContext()
    let s = newSolver()
    s.add intToReal(mkInt(5)) == mkReal(5)
    check s.check() == zsSat

  test "intToReal(0) equals mkReal(0.0) — SAT":
    let ctx = newContext()
    let s = newSolver()
    s.add intToReal(mkInt(0)) == mkReal(0)
    check s.check() == zsSat

  test "intToReal of a variable produces Real-sorted term":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.add x == mkInt(7)
    check s.check() == zsSat
    let m = s.model()
    let v = m[intToReal(x)].toRealApprox
    check abs(v - 7.0) < 1e-9

# ---------------------------------------------------------------------------
# realToInt (floor semantics per Z3 spec)
# ---------------------------------------------------------------------------

suite "arith conv — realToInt":
  test "realToInt(2.7) = 2 (floor of positive)":
    let ctx = newContext()
    let s = newSolver()
    let n = mkIntVar("n")
    s.add n == realToInt(mkReal(27, 10))  # 27/10 = 2.7
    check s.check() == zsSat
    let m = s.model()
    check m[n].toInt == 2

  test "realToInt(-2.3) = -3 (floor of negative)":
    let ctx = newContext()
    let s = newSolver()
    let n = mkIntVar("n")
    s.add n == realToInt(mkReal(-23, 10))  # -23/10 = -2.3
    check s.check() == zsSat
    let m = s.model()
    check m[n].toInt == -3

  test "realToInt of an exact integer is identity":
    let ctx = newContext()
    let s = newSolver()
    let n = mkIntVar("n")
    s.add n == realToInt(mkReal(4, 1))  # exactly 4.0
    check s.check() == zsSat
    let m = s.model()
    check m[n].toInt == 4

# ---------------------------------------------------------------------------
# Round-trip: intToReal(realToInt(x)) <= x
# ---------------------------------------------------------------------------

suite "arith conv — round-trip":
  test "intToReal(realToInt(x)) <= x for symbolic x: Z3Real — SAT":
    ## For any real x, floor(x) as a real is <= x. This is the fundamental
    ## floor inequality. Verify Z3 finds it satisfiable (a model exists).
    let ctx = newContext()
    let s = newSolver()
    let x = mkRealVar("x")
    s.add intToReal(realToInt(x)) <= x
    check s.check() == zsSat

  test "intToReal(realToInt(x)) <= x is valid (UNSAT of negation)":
    ## The floor inequality holds for ALL reals, so its negation is UNSAT.
    let ctx = newContext()
    let s = newSolver()
    let x = mkRealVar("x")
    # negate: intToReal(realToInt(x)) > x should be UNSAT
    s.add intToReal(realToInt(x)) > x
    check s.check() == zsUnsat

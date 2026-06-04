## `z3/arith` extras — abs, power, divides, isInt, mkRealInt64
##
## Tests for arithmetic operations added in RFC slice N4.1.
## All behaviors are verified through the solver (SAT/UNSAT) or model
## extraction, not just AST string inspection.

import std/[unittest, math]
import z3

# ---------------------------------------------------------------------------
# abs
# ---------------------------------------------------------------------------

suite "arith extras — abs":
  test "abs(Z3Int): model value is non-negative":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.add x == mkInt(-5)
    check s.check() == zsSat
    let m = s.model()
    check m[abs(x)].toInt64 == 5

  test "abs(Z3Real): model value is non-negative":
    let ctx = newContext()
    let s = newSolver()
    let r = mkRealVar("r")
    s.add r == mkReal(-7, 2)  # -3.5
    check s.check() == zsSat
    let m = s.model()
    let v = m[abs(r)].toRealApprox
    check abs(v - 3.5) < 1e-9

  test "abs(Z3Int) of positive value is identity":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.add x == mkInt(7)
    check s.check() == zsSat
    let m = s.model()
    check m[abs(x)].toInt64 == 7

# ---------------------------------------------------------------------------
# power
# ---------------------------------------------------------------------------

suite "arith extras — power":
  test "power(Z3Real, Z3Real): 2^3 ≈ 8.0":
    let ctx = newContext()
    let s = newSolver()
    let r = mkRealVar("r")
    s.add r == power(mkReal(2, 1), mkReal(3, 1))
    check s.check() == zsSat
    let m = s.model()
    let v = m[r].toRealApprox
    check abs(v - 8.0) < 1e-6

  test "^ operator is power":
    let ctx = newContext()
    let s = newSolver()
    let r = mkRealVar("r")
    s.add r == (mkReal(3, 1) ^ mkReal(2, 1))
    check s.check() == zsSat
    let m = s.model()
    let v = m[r].toRealApprox
    check abs(v - 9.0) < 1e-6

# ---------------------------------------------------------------------------
# divides
# ---------------------------------------------------------------------------

suite "arith extras — divides":
  test "divides(3, 12) is SAT":
    let ctx = newContext()
    let s = newSolver()
    s.add divides(mkInt(3), mkInt(12))
    check s.check() == zsSat

  test "divides(3, 10) is UNSAT":
    let ctx = newContext()
    let s = newSolver()
    s.add divides(mkInt(3), mkInt(10))
    check s.check() == zsUnsat

  test "divides(1, n) is always SAT":
    let ctx = newContext()
    let s = newSolver()
    let n = mkIntVar("n")
    s.add divides(mkInt(1), n)
    check s.check() == zsSat

# ---------------------------------------------------------------------------
# isInt
# ---------------------------------------------------------------------------

suite "arith extras — isInt":
  test "isInt(5.0) is SAT":
    let ctx = newContext()
    let s = newSolver()
    s.add isInt(mkReal(5, 1))
    check s.check() == zsSat

  test "isInt(2.5) is UNSAT":
    let ctx = newContext()
    let s = newSolver()
    s.add isInt(mkReal(5, 2))  # 5/2 = 2.5
    check s.check() == zsUnsat

  test "isInt variable: SAT with integer assignment":
    let ctx = newContext()
    let s = newSolver()
    let r = mkRealVar("r")
    s.add isInt(r)
    s.add r > mkReal(0, 1)
    s.add r < mkReal(2, 1)
    check s.check() == zsSat

# ---------------------------------------------------------------------------
# mkRealInt64
# ---------------------------------------------------------------------------

suite "arith extras — mkRealInt64":
  test "mkRealInt64(1, 3) evaluates close to 1/3":
    let ctx = newContext()
    let s = newSolver()
    let r = mkRealVar("r")
    s.add r == mkRealInt64(ctx, 1'i64, 3'i64)
    check s.check() == zsSat
    let m = s.model()
    let v = m[r].toRealApprox
    check abs(v - (1.0 / 3.0)) < 1e-9

  test "mkRealInt64(22, 7) is approximately pi":
    let ctx = newContext()
    let s = newSolver()
    let r = mkRealVar("r")
    s.add r == mkRealInt64(ctx, 22'i64, 7'i64)
    check s.check() == zsSat
    let m = s.model()
    let v = m[r].toRealApprox
    check abs(v - (22.0 / 7.0)) < 1e-9

  test "mkRealInt64 negative numerator":
    let ctx = newContext()
    let s = newSolver()
    let r = mkRealVar("r")
    s.add r == mkRealInt64(ctx, -1'i64, 4'i64)
    check s.check() == zsSat
    let m = s.model()
    let v = m[r].toRealApprox
    check abs(v - (-0.25)) < 1e-9

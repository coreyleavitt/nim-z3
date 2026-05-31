## `mkLambda` — Z3 lambda terms via Z3_mk_lambda_const (HIGH #2).

import std/unittest
import z3

suite "mkLambda — typed lambda construction":
  test "λx:Int. x + 1 evaluates correctly when selected":
    let ctx = newContext()
    let x = mkIntVar("x")
    # Build λx:Int. x + 1 → Z3Array[Z3Int, Z3Int]
    let f = lambda(x, x + mkInt(1))
    # Select at 3 should be 4.
    check smtValid(f[mkInt(3)] == mkInt(4))
    check smtValid(f[mkInt(99)] == mkInt(100))

  test "λx:BV[8]. bvnot x is a Z3Array[Z3BitVec[8], Z3BitVec[8]]":
    let ctx = newContext()
    let x = mkBitVecVar[8]("x")
    let f = lambda(x, not x)
    # bvnot 0x00 = 0xFF
    check smtValid(f[mkBitVec[8](0x00'u32)] == mkBitVec[8](0xFF'u32))

  test "lambda body of differing sort yields the correct value family":
    let ctx = newContext()
    let x = mkIntVar("x")
    # λx:Int. (x > 0)  →  Z3Array[Z3Int, Z3Bool]
    let isPos = lambda(x, x > mkInt(0))
    check smtValid(isPos[mkInt(5)] == mkBool(true))
    check smtValid(isPos[mkInt(-5)] == mkBool(false))

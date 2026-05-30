## `z3/translate` tests — cross-context AST transfer + compatibility.

import std/[unittest]
import z3

suite "translate — tracer":
  test "Z3Int from ctx A round-trips to ctx B with matching SMT-LIB rendering":
    let ctxA = newContext()
    let xA = mkIntVar("x")
    let exprA = xA + mkInt(42)

    let ctxB = newContext()
    let exprB = translate(exprA, ctxB)
    check $exprA == $exprB

suite "translate — typed family preservation":
  test "Z3Bool translates and preserves type":
    let ctxA = newContext()
    let pA = mkBoolVar("p")
    let qA = mkBoolVar("q")
    let exprA = pA and qA

    let ctxB = newContext()
    let exprB: Z3Bool = translate(exprA, ctxB)
    check $exprA == $exprB

  test "Z3BitVec[W] translates with width preserved":
    let ctxA = newContext()
    let bvA = mkBitVecVar[16]("x")

    let ctxB = newContext()
    let bvB: Z3BitVec[16] = translate(bvA, ctxB)
    check $bvA == $bvB

  test "Z3Real translates":
    let ctxA = newContext()
    let rA = mkReal(1, 2)

    let ctxB = newContext()
    let rB: Z3Real = translate(rA, ctxB)
    check $rA == $rB

suite "compatibleWith — predicate":
  test "two fresh same-config contexts are compatible":
    let ctxA = newContext()
    let ctxB = newContext()
    check compatibleWith(ctxA, ctxB)

suite "translate — end-to-end solver round-trip":
  test "constraint asserted in A, translated to B, B's solver decides identically":
    let ctxA = newContext()
    let xA = mkIntVar("x")
    let constraintA = (xA > mkInt(0)) and (xA < mkInt(100))

    let ctxB = newContext()
    let constraintB = translate(constraintA, ctxB)
    let solverB = newSolver()
    solverB.add constraintB
    check solverB.check() == zsSat

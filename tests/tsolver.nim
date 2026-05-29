## `z3/solver` tests — lifecycle, add, check, push/pop, reset.
## Model tests live in tmodel.nim.

import std/[unittest, strutils]
import z3

suite "Z3Solver — construction":
  test "newSolver uses current context":
    let ctx = newContext()
    let s = newSolver()
    check s.ctx == ctx
    check not s.raw.isNil

  test "newSolver(ctx) explicit form":
    let ctx = newContext()
    let s = newSolver(ctx)
    check s.ctx == ctx

  test "two solvers in one context coexist":
    let ctx = newContext()
    let s1 = newSolver()
    let s2 = newSolver()
    s1.add mkBoolVar("p")
    s2.add mkBoolVar("q")
    # Both should report sat independently
    check s1.check() == zsSat
    check s2.check() == zsSat

suite "Z3Solver — assertions":
  test "add a single constraint":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.add x > 0
    check ($s).contains("(> x 0)")

  test "add varargs form":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    s.add(x > 0, y > 0, x + y < 100)
    let str = $s
    check str.contains("(> x 0)")
    check str.contains("(> y 0)")

  test "assertConstraint alias works":
    let ctx = newContext()
    let s = newSolver()
    let p = mkBoolVar("p")
    s.assertConstraint(p)
    check s.check() == zsSat

suite "Z3Solver — check":
  test "trivially-true constraint is sat":
    let ctx = newContext()
    let s = newSolver()
    s.add mkTrue()
    check s.check() == zsSat

  test "trivially-false constraint is unsat":
    let ctx = newContext()
    let s = newSolver()
    s.add mkFalse()
    check s.check() == zsUnsat

  test "x == 1 and x == 2 is unsat":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.add x == 1
    s.add x == 2
    check s.check() == zsUnsat

  test "Pythagorean: x*x + y*y == 25 and x > 0 and y > 0 is sat":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    s.add(x * x + y * y == 25,
          x > 0, y > 0)
    check s.check() == zsSat

  test "reasonUnknown is callable (returns string)":
    let ctx = newContext()
    let s = newSolver()
    s.add mkTrue()
    discard s.check()
    # After a non-unknown check, reasonUnknown is unspecified but
    # callable. Just verify it returns a string of some kind.
    discard s.reasonUnknown()
    check true

suite "Z3Solver — push / pop scopes":
  test "constraints added inside push/pop are forgotten on pop":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.add x > 0
    check s.check() == zsSat

    s.push()
    s.add x < 0
    check s.check() == zsUnsat   # x > 0 AND x < 0 is unsat
    s.pop()
    check s.check() == zsSat     # only x > 0 remains

  test "withFrame template scopes correctly":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.add x > 0

    s.withFrame:
      s.add x > 100
      check s.check() == zsSat   # x > 0 AND x > 100 is sat (x = anything > 100)

    s.withFrame:
      s.add x < 0
      check s.check() == zsUnsat # x > 0 AND x < 0 is unsat
    # After the second withFrame, x < 0 is gone
    check s.check() == zsSat

  test "withFrame restores on exception":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.add x > 0

    try:
      s.withFrame:
        s.add x < 0
        raise newException(ValueError, "deliberate")
    except ValueError:
      discard
    # The inner constraint x < 0 should be gone
    check s.check() == zsSat

  test "pop(N) discards N frames":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.push()
    s.add x > 0
    s.push()
    s.add x < 0
    check s.check() == zsUnsat
    s.pop(2)  # discard both frames
    check s.check() == zsSat   # nothing asserted

suite "Z3Solver — reset":
  test "reset clears assertions and frames":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.push()
    s.add x > 0
    s.add x < 0
    check s.check() == zsUnsat
    s.reset()
    check s.check() == zsSat   # nothing asserted

suite "Z3Solver — pretty-print":
  test "$ contains the asserted constraints":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    s.add x + y == 10
    let str = $s
    check str.contains("declare-fun x")
    check str.contains("declare-fun y")
    check str.contains("(= (+ x y) 10)")

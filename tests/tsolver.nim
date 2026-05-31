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

suite "solver.pop(n) guard":
  test "pop(0) and pop(-1) are no-ops; assertion stack unchanged":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.push()
    s.add x == mkInt(5)
    # n <= 0 is silently ignored per the docstring contract.
    s.pop(0)
    s.pop(-1)
    # The frame is still open — x == 5 is still asserted.
    check s.check() == zsSat
    let m = s.model()
    check m.evalInt(x) == 5
    # A real pop(1) discards it.
    s.pop(1)
    s.add x == mkInt(7)
    check s.check() == zsSat

suite "Z3Solver — checkWith / check_assumptions":
  test "checkWith[p] makes the solver sat under p without committing":
    let ctx = newContext()
    let p = mkBoolVar("p")
    let q = mkBoolVar("q")
    let s = newSolver()
    # Background fact: p → q (encoded as ¬p ∨ q).
    s.add (not p) or q
    # Under assumption p, q must be true.
    check s.checkWith(@[p]) == zsSat
    let m = s.model()
    check m.evalBool(q) == true
    # Solver state did NOT commit p — a follow-up check() is also sat,
    # but a model now exists where p is false and q is unconstrained.
    check s.check() == zsSat

  test "checkWith[p, not q] yields unsat under contradictory assumptions":
    let ctx = newContext()
    let p = mkBoolVar("p")
    let q = mkBoolVar("q")
    let s = newSolver()
    s.add (not p) or q                # p → q
    check s.checkWith(@[p, not q]) == zsUnsat
    # Background still satisfiable without the contradiction.
    check s.check() == zsSat

  test "checkWith @[] is equivalent to plain check()":
    let ctx = newContext()
    let x = mkIntVar("x")
    let s = newSolver()
    s.add x > mkInt(0)
    check s.checkWith(@[]) == zsSat

suite "Z3Solver — getAssertions":
  test "getAssertions returns the typed assertion stack":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let s = newSolver()
    let a1 = x > mkInt(0)
    let a2 = y > mkInt(10)
    let a3 = x + y == mkInt(15)
    s.add a1
    s.add a2
    s.add a3
    let asserts = s.getAssertions()
    check asserts.len == 3
    # Each round-trips: asserts[i] is smtEquiv to the original.
    check smtEquiv(asserts[0], a1)
    check smtEquiv(asserts[1], a2)
    check smtEquiv(asserts[2], a3)

  test "fresh solver getAssertions is empty":
    let ctx = newContext()
    let s = newSolver()
    check s.getAssertions().len == 0

suite "Z3Solver — translate":
  test "translate carries assertions to the target context, both sat":
    let ctxA = newContext()
    let x = mkIntVar("x")
    let sA = newSolver()
    sA.add x > mkInt(5)
    sA.add x < mkInt(10)
    check sA.check() == zsSat
    let valA = sA.model().evalInt(x)

    let ctxB = newContext()
    let sB = sA.translate(ctxB)
    check sB.check() == zsSat
    # The translated solver sees the same constraint family in ctxB:
    # we don't need x from ctxB to inspect — getAssertions in ctxB
    # confirms the count survived.
    check sB.getAssertions().len == 2
    # Both models satisfy the bounds.
    let mB = sB.model()
    let asserts = sB.getAssertions()
    # Verify each translated assertion is sat in B's model.
    for a in asserts:
      check mB.evalBool(a) == true
    # Independent witnesses; both within (5, 10) exclusive.
    check valA > 5 and valA < 10

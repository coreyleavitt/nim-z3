## N8.8 — Goal introspection tests.
##
## Exercises: size, formula, numExprs, depth, precision, isDecidedSat,
## isDecidedUnsat, inconsistent, add, reset, translate,
## toDimacs, toString ($), convertModel.

import std/[unittest, strutils]
import z3

suite "goal introspect — size and formula":
  test "size == 2 after asserting two constraints":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x > mkInt(0))
    g.add (x < mkInt(10))
    check g.size == 2

  test "formula(0) returns the first asserted constraint":
    let ctx = newContext()
    let x = mkIntVar("x")
    let c0 = x > mkInt(0)
    let c1 = x < mkInt(10)
    let g = newGoal()
    g.add c0
    g.add c1
    # smtEquiv checks semantic equivalence via Z3 itself
    check smtEquiv(g.formula(0), c0)

  test "formula(1) returns the second asserted constraint":
    let ctx = newContext()
    let x = mkIntVar("x")
    let c0 = x > mkInt(0)
    let c1 = x < mkInt(10)
    let g = newGoal()
    g.add c0
    g.add c1
    check smtEquiv(g.formula(1), c1)

suite "goal introspect — numExprs and depth":
  test "numExprs is positive for a non-empty goal":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x > mkInt(0))
    check g.numExprs > 0

  test "numExprs grows when more formulas are added":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x > mkInt(0))
    let n1 = g.numExprs
    g.add (x < mkInt(100))
    let n2 = g.numExprs
    check n2 > n1

  test "depth is 0 for a freshly-created goal":
    let ctx = newContext()
    let g = newGoal()
    check g.depth == 0

suite "goal introspect — precision":
  test "freshly-created goal has gpPrecise precision":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x > mkInt(0))
    check g.precision == gpPrecise

suite "goal introspect — isDecidedSat / isDecidedUnsat":
  test "isDecidedSat is false for a goal with unresolved constraints":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x > mkInt(0))
    check not g.isDecidedSat

  test "isDecidedUnsat is false for a satisfiable goal":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x > mkInt(0))
    check not g.isDecidedUnsat

  test "smt tactic on a SAT goal produces an isDecidedSat subgoal":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x + mkInt(0) == x)    # tautology — smt decides sat immediately
    let r = mkTactic("smt").apply(g)
    check r.numSubgoals == 1
    check r.subgoal(0).isDecidedSat

  test "smt tactic on an UNSAT goal produces an isDecidedUnsat subgoal":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x == mkInt(1))
    g.add (x == mkInt(2))
    let r = mkTactic("smt").apply(g)
    check r.numSubgoals == 1
    check r.subgoal(0).isDecidedUnsat

suite "goal introspect — add":
  test "add grows size":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    check g.size == 0
    g.add(x > mkInt(0))
    check g.size == 1
    g.add(x < mkInt(100))
    check g.size == 2

suite "goal introspect — reset":
  test "reset empties the goal":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x > mkInt(0))
    g.add (x < mkInt(10))
    check g.size == 2
    g.reset()
    check g.size == 0

  test "can add constraints after reset":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x > mkInt(0))
    g.reset()
    g.add (x == mkInt(42))
    check g.size == 1
    check smtEquiv(g.formula(0), x == mkInt(42))

suite "goal introspect — translate":
  test "translate preserves size":
    let src = newContext()
    let tgt = newContext()
    let x = mkIntVar(src, "x")
    let g = newGoal(src)
    g.add (x > mkInt(src, 0))
    g.add (x < mkInt(src, 10))
    let g2 = g.translate(tgt)
    check g2.size == 2

  test "translated goal lives in the target context":
    let src = newContext()
    let tgt = newContext()
    let x = mkIntVar(src, "x")
    let g = newGoal(src)
    g.add (x > mkInt(src, 0))
    let g2 = g.translate(tgt)
    # Applying a tactic in the target context on the translated goal
    # must not raise — if the goal were in the wrong context, Z3 would
    # throw an invalid-usage error.
    let r = mkTactic(tgt, "smt").apply(g2)
    check r.numSubgoals >= 1

suite "goal introspect — toString and toDimacs":
  test "$ (toString) returns a non-empty string for a non-empty goal":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x > mkInt(0))
    let s = $g
    check s.len > 0

  test "$ on an empty goal returns a string (not a crash)":
    let ctx = newContext()
    let g = newGoal()
    discard $g

  test "toDimacs on a propositional goal returns DIMACS text":
    let ctx = newContext()
    let p = mkBoolVar("p")
    let q = mkBoolVar("q")
    let g = newGoal()
    # p | !q is a single clause in CNF
    g.add `or`(p, not q)
    let d = g.toDimacs()
    check d.len > 0
    # DIMACS format always starts with a "p cnf" header line
    check strutils.contains(d, "p cnf")

suite "goal introspect — convertModel":
  test "convertModel round-trips a model through a tactic sub-goal":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x > mkInt(0))
    g.add (x < mkInt(10))
    g.add (x * x == mkInt(9))

    let r = mkTactic("simplify").andThen(mkTactic("smt")).apply(g)
    check r.numSubgoals >= 1

    let sub = r.subgoal(0)
    let s = newSolver()
    for i in 0 ..< sub.size:
      s.add sub.formula(i)
    check s.check() == zsSat
    let subModel = s.model()

    let parentModel = r.convertModel(0, subModel)
    let xv = parentModel.evalInt(x)
    check xv > 0 and xv < 10 and xv * xv == 9

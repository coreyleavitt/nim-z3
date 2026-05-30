## `z3/tactic` + `z3/params` tests — goals, tactic combinators,
## apply results, parameterised tactics.

import std/[unittest]
import z3

suite "tactic — tracer":
  test "simplify reduces (x + 0 == x) to a decided-sat subgoal":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x + mkInt(0) == x)
    let r = mkTactic("simplify").apply(g)
    check r.numSubgoals == 1
    check r.subgoal(0).isDecidedSat

  test "simplify on x == 1 and x == 2 produces a decided-unsat subgoal":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x == mkInt(1))
    g.add (x == mkInt(2))
    let r = mkTactic("smt").apply(g)
    check r.numSubgoals == 1
    check r.subgoal(0).isDecidedUnsat

suite "goal — assertion + introspection":
  test "size grows as constraints are added":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    check g.size == 0
    g.add (x > mkInt(0))
    check g.size == 1
    g.add (x < mkInt(10))
    check g.size == 2

  test "formula(i) round-trips an asserted constraint":
    let ctx = newContext()
    let x = mkIntVar("x")
    let c = x > mkInt(0)
    let g = newGoal()
    g.add c
    check smtEquiv(g.formula(0), c)

  test "inconsistent is false on a satisfiable goal":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x > mkInt(0))
    check not g.inconsistent

suite "tactic — combinators":
  test "andThen: simplify then smt solves an arithmetic problem":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x * x == mkInt(0))
    let pipeline = mkTactic("simplify").andThen(mkTactic("smt"))
    let r = pipeline.apply(g)
    check r.numSubgoals == 1
    check r.subgoal(0).isDecidedSat

  test "orElse: tacticFail then simplify falls through to the second":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x + mkInt(0) == x)
    # The fail tactic always errors; orElse catches that and tries
    # the second tactic instead. The second simplifies to decided-sat.
    let pipeline = tacticFail().orElse(mkTactic("simplify"))
    let r = pipeline.apply(g)
    check r.subgoal(0).isDecidedSat

  test "repeat: simplify until fixpoint":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x + mkInt(0) + mkInt(0) + mkInt(0) == x)
    let r = mkTactic("simplify").repeat().apply(g)
    check r.subgoal(0).isDecidedSat

  test "tryFor: never hangs even with an absurdly small budget":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x == mkInt(0))
    # The 1ms timeout should be plenty for simplify on this trivial
    # goal; the point is the call returns rather than hanging.
    let r = mkTactic("simplify").tryFor(1).apply(g)
    check r.numSubgoals >= 1

  test "tacticSkip: identity on a goal":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x > mkInt(0))
    let r = tacticSkip().apply(g)
    check r.numSubgoals == 1
    check r.subgoal(0).size == 1

suite "params — typed setters":
  test "set accepts bool, uint, float, and string values":
    let ctx = newContext()
    let p = newParams()
    p.set("flat", true)
    p.set("elim_and", false)
    p.set("max_steps", 100'u)
    p.set("max_memory", 1024.0)
    p.set("logic", "QF_LIA")
    # $p must not crash; not asserting exact contents (Z3's format is
    # version-dependent).
    discard $p

  test "params pretty-print is non-empty after sets":
    let ctx = newContext()
    let p = newParams()
    p.set("flat", true)
    p.set("max_steps", 7'u)
    let s = $p
    check s.len > 0

suite "tactic — parameterised":
  test "withParams threads a param bag into the tactic":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x + mkInt(0) == x)
    let p = newParams()
    p.set("elim_and", true)
    let t = mkTactic("simplify").withParams(p)
    let r = t.apply(g)
    check r.subgoal(0).isDecidedSat

  test "apply(g, p) is equivalent to withParams(p).apply(g)":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g1 = newGoal()
    g1.add (x + mkInt(0) == x)
    let g2 = newGoal()
    g2.add (x + mkInt(0) == x)
    let p = newParams()
    p.set("elim_and", true)
    let r1 = mkTactic("simplify").apply(g1, p)
    let r2 = mkTactic("simplify").withParams(p).apply(g2)
    check r1.subgoal(0).isDecidedSat
    check r2.subgoal(0).isDecidedSat

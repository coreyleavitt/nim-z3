## N8.6 — Tactic parallel + conditional combinators.
##
## Tests for `parOr`, `parAndThen`, `cond`, and `tacticWhen`.

import std/[unittest]
import z3

suite "tactic — parOr":
  test "parOr of [smt] on a SAT goal produces a decided-sat subgoal":
    # A singleton parOr must behave identically to the tactic itself.
    # smt on this fully-constrained goal must decide SAT.
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x > mkInt(0))
    g.add (x < mkInt(10))
    let t = parOr(ctx, @[mkTactic("smt")])
    let r = t.apply(g)
    check r.numSubgoals >= 1
    check r.subgoal(0).isDecidedSat

  test "parOr current-context overload works without explicit ctx":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x == mkInt(5))
    let t = parOr(@[mkTactic("smt"), mkTactic("simplify")])
    let r = t.apply(g)
    check r.numSubgoals >= 1

suite "tactic — parAndThen":
  test "parAndThen(simplify, smt) decides an arithmetic goal as SAT":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x * x == mkInt(4))
    g.add (x > mkInt(0))
    let pipeline = parAndThen(mkTactic("simplify"), mkTactic("smt"))
    let r = pipeline.apply(g)
    check r.numSubgoals >= 1
    check r.subgoal(0).isDecidedSat

  test "parAndThen produces equivalent result to andThen for a trivial goal":
    let ctx = newContext()
    let x = mkIntVar("x")
    let g1 = newGoal()
    g1.add (x + mkInt(0) == x)
    let g2 = newGoal()
    g2.add (x + mkInt(0) == x)
    let sequential = mkTactic("simplify").andThen(mkTactic("smt")).apply(g1)
    let parallel   = parAndThen(mkTactic("simplify"), mkTactic("smt")).apply(g2)
    # Both must yield a decided-sat result for this trivially true goal.
    check sequential.subgoal(0).isDecidedSat
    check parallel.subgoal(0).isDecidedSat

suite "tactic — cond":
  test "cond dispatches to the then-branch when probe evaluates true":
    # Use probe `size > 0` (any non-empty goal has size >= 1).
    # then-branch: smt (will decide SAT)
    # else-branch: tacticFail (would crash if reached)
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x > mkInt(0))
    let probe = mkProbe("size") > 0.0
    let t = cond(probe, mkTactic("smt"), tacticFail())
    let r = t.apply(g)
    check r.numSubgoals >= 1
    check r.subgoal(0).isDecidedSat

  test "cond dispatches to the else-branch when probe evaluates false":
    # Probe `size > 1000` is false for a goal with one formula.
    # then-branch: tacticFail
    # else-branch: simplify (returns decided-sat for the trivial formula)
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x + mkInt(0) == x)
    let probe = mkProbe("size") > 1000.0
    let t = cond(probe, tacticFail(), mkTactic("simplify"))
    let r = t.apply(g)
    check r.subgoal(0).isDecidedSat

suite "tactic — tacticWhen":
  test "tacticWhen applies the tactic when the probe is true":
    # probe: size > 0 (true for any non-empty goal)
    # tactic: smt → decides SAT
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x > mkInt(0))
    let probe = mkProbe("size") > 0.0
    let t = tacticWhen(probe, mkTactic("smt"))
    let r = t.apply(g)
    check r.numSubgoals >= 1
    check r.subgoal(0).isDecidedSat

  test "tacticWhen acts as skip when the probe is false":
    # probe: size > 1000 (false for this single-formula goal)
    # tactic: tacticFail — but because probe is false, tacticWhen skips it.
    # skip returns the goal unchanged (not decided-sat, just the original).
    let ctx = newContext()
    let x = mkIntVar("x")
    let g = newGoal()
    g.add (x > mkInt(0))
    let probe = mkProbe("size") > 1000.0
    let t = tacticWhen(probe, tacticFail())
    let r = t.apply(g)
    # The goal was returned unchanged: one subgoal with our original formula.
    check r.numSubgoals == 1
    check r.subgoal(0).size == 1

## `z3/probe` tests — Probes + condTactic (v0.4 step 12).
##
## Behavior coverage:
##   1. `mkProbe("num-consts")` → tracer; empty goal scores 0.0.
##   2. `mkProbeConst(v)` evaluates to `v` on any goal.
##   3. Comparator composition (`<`, `<=`, `>`, `>=`, `==`) yields
##      probes returning 1.0 / 0.0.
##   4. Float-literal auto-lift on both sides of comparators.
##   5. Boolean `and` / `or` / `not` combinators.
##   6. Named probe sees structural changes (assert grows goal).
##   7. `condTactic` dispatches between two tactics by probe value.

import std/[unittest]
import z3

suite "Z3Probe — tracer":
  test "mkProbe('num-consts') applies to an empty goal and returns a float":
    let ctx = newContext()
    let probe = mkProbe("num-consts")
    let g = newGoal()
    let result = probe.apply(g)
    # Empty goal has zero free constants — result is 0.0.
    check result == 0.0

suite "Z3Probe — combinators":
  test "mkProbeConst evaluates to the given value on any goal":
    let ctx = newContext()
    let g = newGoal()
    check mkProbeConst(7.5).apply(g) == 7.5
    check mkProbeConst(0.0).apply(g) == 0.0

  test "comparator probes return 1.0 / 0.0 on goal":
    let ctx = newContext()
    let g = newGoal()
    let two = mkProbeConst(2.0)
    let ten = mkProbeConst(10.0)
    check (two < ten).apply(g) == 1.0
    check (ten < two).apply(g) == 0.0
    check (two <= two).apply(g) == 1.0
    check (ten > two).apply(g) == 1.0
    check (two >= ten).apply(g) == 0.0
    check (two == two).apply(g) == 1.0
    check (two == ten).apply(g) == 0.0

  test "float literals auto-lift on either side of comparators":
    let ctx = newContext()
    let g = newGoal()
    let p = mkProbeConst(3.0)
    check (p < 5.0).apply(g) == 1.0
    check (5.0 < p).apply(g) == 0.0
    check (p == 3.0).apply(g) == 1.0

  test "boolean combinators `and` / `or` / `not`":
    let ctx = newContext()
    let g = newGoal()
    let t = mkProbeConst(1.0)   # truthy
    let f = mkProbeConst(0.0)   # falsy
    check (t and t).apply(g) == 1.0
    check (t and f).apply(g) == 0.0
    check (t or f).apply(g) == 1.0
    check (f or f).apply(g) == 0.0
    check (`not`(f)).apply(g) == 1.0
    check (`not`(t)).apply(g) == 0.0

  test "named probe sees structural changes — num-consts grows with asserts":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let g = newGoal()
    g.add(x + y > mkInt(0))
    # Goal now has two free constants.
    let nc = mkProbe("num-consts").apply(g)
    check nc == 2.0
    # And comparators read naturally:
    check (mkProbe("num-consts") > 1.0).apply(g) == 1.0
    check (mkProbe("num-consts") > 10.0).apply(g) == 0.0

suite "Z3Probe — condTactic":
  test "condTactic dispatches between two tactics by probe value":
    # When the probe holds, apply the "ifTactic"; otherwise the
    # "elseTactic". We verify the dispatch by composing with the
    # solver and observing that the conditional pipeline produces
    # a satisfying model for a trivial query.
    # We make dispatch observable by giving one branch a complete
    # decision procedure (`smt`) and the other a `fail` tactic. The
    # branch chosen by the probe determines whether `check()` is
    # `zsSat` or `zsUnknown`.
    let ctx = newContext()
    let x = mkIntVar("x")

    # Probe true → ifT = smt → sat. Probe true → flipped → fail → unknown.
    let truePipe = condTactic(
      mkProbeConst(1.0) > 0.0,
      mkTactic("smt"),
      mkTactic("fail"))
    let sTrue = truePipe.toSolver()
    sTrue.add(x == mkInt(7))
    check sTrue.check() == zsSat
    check sTrue.model().eval(x).toInt == 7

    # Probe false → elseT = smt → sat.
    let falsePipe = condTactic(
      mkProbeConst(0.0) > 0.0,
      mkTactic("fail"),
      mkTactic("smt"))
    let sFalse = falsePipe.toSolver()
    sFalse.add(x == mkInt(11))
    check sFalse.check() == zsSat
    check sFalse.model().eval(x).toInt == 11

    # Sanity: when the chosen branch is `fail`, the solver does not
    # report sat — confirming dispatch is actually selecting branches.
    let alwaysFail = condTactic(
      mkProbeConst(1.0) > 0.0,
      mkTactic("fail"),
      mkTactic("smt"))
    let sFail = alwaysFail.toSolver()
    sFail.add(x == mkInt(3))
    check sFail.check() != zsSat

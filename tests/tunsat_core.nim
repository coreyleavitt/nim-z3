## `z3/solver` — assert_and_track + unsat-core extraction (v0.4 step 6).

import std/[unittest]
import z3

suite "Z3Solver — assertConstraintAndTrack + getUnsatCore tracer":
  test "two contradictory tracked constraints produce a 2-element core":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    let t1 = mkBoolVar("t1")
    let t2 = mkBoolVar("t2")
    s.assertConstraintAndTrack(x > mkInt(5), t1)
    s.assertConstraintAndTrack(x < mkInt(3), t2)
    check s.check() == zsUnsat
    let core = s.getUnsatCore()
    check core.len == 2

suite "Z3Solver — unsat core identifies the right trackers":
  test "core contains specifically t1 and t2 (semantic identity)":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    let t1 = mkBoolVar("t1")
    let t2 = mkBoolVar("t2")
    s.assertConstraintAndTrack(x > mkInt(5), t1)
    s.assertConstraintAndTrack(x < mkInt(3), t2)
    discard s.check()
    let core = s.getUnsatCore()
    # Both trackers appear; SMT-equality identifies each.
    var seenT1 = false
    var seenT2 = false
    for tr in core:
      if smtValid(tr == t1): seenT1 = true
      if smtValid(tr == t2): seenT2 = true
    check seenT1
    check seenT2

suite "Z3Solver — unsat core selectivity":
  test "irrelevant tracker is excluded from the core":
    # Set up: 3 tracked constraints; only 2 form the contradiction.
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let tBig = mkBoolVar("x-big")
    let tSmall = mkBoolVar("x-small")
    let tYpos = mkBoolVar("y-pos")
    s.assertConstraintAndTrack(x > mkInt(5), tBig)
    s.assertConstraintAndTrack(x < mkInt(3), tSmall)
    s.assertConstraintAndTrack(y > mkInt(0), tYpos)  # unrelated; sat in isolation
    discard s.check()
    let core = s.getUnsatCore()
    # Z3 may not minimise to exactly 2, but the irrelevant tracker
    # should not appear.
    var seenYpos = false
    for tr in core:
      if smtValid(tr == tYpos): seenYpos = true
    check not seenYpos

suite "Z3Solver — assertConstraintAndTrack return value":
  test "returns the tracker for fluent capture":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    let captured = s.assertConstraintAndTrack(x > mkInt(0), mkBoolVar("t"))
    # The returned tracker IS the tracker we passed in (smt-equal).
    s.assertConstraintAndTrack(x < mkInt(0), mkBoolVar("u"))
    discard s.check()
    let core = s.getUnsatCore()
    var seenCaptured = false
    for tr in core:
      if smtValid(tr == captured): seenCaptured = true
    check seenCaptured

suite "Z3Solver — track convenience helper":
  test "track(c, name) auto-creates a tracker and asserts":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    let t1 = s.track(x > mkInt(5), "x-big")
    let t2 = s.track(x < mkInt(3), "x-small")
    check s.check() == zsUnsat
    let core = s.getUnsatCore()
    check core.len == 2
    # Core trackers match the ones the helper returned.
    var seenT1 = false
    var seenT2 = false
    for tr in core:
      if smtValid(tr == t1): seenT1 = true
      if smtValid(tr == t2): seenT2 = true
    check seenT1
    check seenT2

suite "Z3Solver — getUnsatCore on a sat solver":
  test "returns an empty seq when check() is sat":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.track(x > mkInt(0), "positive")
    s.track(x < mkInt(100), "bounded")
    check s.check() == zsSat
    check s.getUnsatCore().len == 0

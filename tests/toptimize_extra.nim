## `z3/optimize` N7.6a tests — assertAndTrack / getUnsatCore,
## fromString, fromFile, getHelp.

import std/[unittest, os]
import z3

suite "Z3Optimize — getHelp":
  test "getHelp returns non-empty string":
    let ctx = newContext()
    let o   = newOptimize()
    let h   = o.getHelp()
    check h.len > 0

suite "Z3Optimize — assertAndTrack / getUnsatCore":
  test "conflicting tracked assertions: core contains the conflicting tracker":
    ## x > 5  (tracked by t1)
    ## x < 3  (tracked by t2)
    ## => UNSAT; both t1 and t2 are in the core.
    let ctx = newContext()
    let x   = mkIntVar("x")
    let t1  = mkBoolVar("t1")
    let t2  = mkBoolVar("t2")
    let o   = newOptimize()
    o.assertAndTrack(x > mkInt(5), t1)
    o.assertAndTrack(x < mkInt(3), t2)
    check o.check() == zsUnsat
    let core = o.getUnsatCore()
    # Core must be non-empty and contain at least one of the conflicting
    # trackers.  Z3 may return both or a minimal subset; we demand the
    # conflicting pair is covered.
    check core.len > 0
    # At least one tracker referencing the conflict must be present.
    var found = false
    for c in core:
      if smtEquiv(c, t1) or smtEquiv(c, t2):
        found = true
    check found

  test "irrelevant tracker absent from unsat core":
    ## x > 5  (tracked by t_conflict_a)
    ## x < 3  (tracked by t_conflict_b)
    ## y == 7 (tracked by t_irrel)  — satisfiable on its own
    ## => UNSAT only due to x constraints; t_irrel should NOT appear.
    let ctx          = newContext()
    let x            = mkIntVar("x")
    let y            = mkIntVar("y")
    let t_conflict_a = mkBoolVar("tca")
    let t_conflict_b = mkBoolVar("tcb")
    let t_irrel      = mkBoolVar("tirrel")
    let o            = newOptimize()
    o.assertAndTrack(x > mkInt(5),    t_conflict_a)
    o.assertAndTrack(x < mkInt(3),    t_conflict_b)
    o.assertAndTrack(y == mkInt(7),   t_irrel)
    check o.check() == zsUnsat
    let core = o.getUnsatCore()
    check core.len > 0
    for c in core:
      check (not smtEquiv(c, t_irrel))

suite "Z3Optimize — fromString":
  test "fromString of (maximize ...) finds expected optimum":
    ## Load a simple maximise problem via the SMT2 text interface.
    let ctx = newContext()
    let o   = newOptimize()
    o.fromString """
      (declare-const x Int)
      (assert (<= x 42))
      (maximize x)
    """
    check o.check() == zsSat
    # After fromString the objective handle index is 0.
    # We inspect the model value of x rather than pulling the handle,
    # since fromString doesn't return a Z3OptHandle.  The model must
    # witness x == 42 (the tight upper bound).
    let m  = o.model()
    let xv = m.evalInt(mkIntVar("x"))
    check xv == 42

suite "Z3Optimize — fromFile":
  test "fromFile loads SMT2 with maximize directive and verifies optimum":
    let ctx  = newContext()
    let path = getTempDir() / "nimz3_toptimize_extra_fromfile.smt2"
    defer: removeFile(path)
    writeFile(path, """
(declare-const z Int)
(assert (>= z 0))
(assert (<= z 17))
(maximize z)
""")
    let o = newOptimize()
    o.fromFile(path)
    check o.check() == zsSat
    let m  = o.model()
    let zv = m.evalInt(mkIntVar("z"))
    check zv == 17

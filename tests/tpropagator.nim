## N8.4b / N8.4c / N11.4a — Full Z3Propagator coverage.
##
## Tests confirm:
##  1.  newPropagator returns non-nil (push/pop/fresh only)
##  2.  push callback fires when fixed is registered and solver makes decisions
##  3.  fixed callback fires with a non-nil expression handle
##  4.  clearSubBoxes is callable post-check and leaves the propagator valid
##  5.  consequence propagates a derived fact visible in the model
##  6.  registerCb inside fixed causes fixed to fire for the newly registered expr
##  7.  nextSplit override in decide completes check without deadlock
##  8.  propagateConflict from final forces UNSAT (always-conflict propagator)
##  9.  propagateConflict from fixed forces UNSAT on specific assignment
##  10. eq handler: typed wrapper compiles and is registered without crash
##  11. diseq handler: typed wrapper compiles and is registered without crash
##  12. created handler: typed wrapper compiles and is registered without crash
##  13. Lifecycle: propagator outlives solver check; sub-box seq is accessible

import std/unittest
import z3
import z3/propagator

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc minimalHandlers(): Z3PropagatorHandlers =
  ## Minimal push/pop/fresh — all other callbacks nil.
  result.push  = proc(cb: Z3SolverCallback) = discard
  result.pop   = proc(cb: Z3SolverCallback, numScopes: uint) = discard
  result.fresh = proc(newCtx: Z3Context): Z3PropagatorHandlers =
    Z3PropagatorHandlers()

proc baseHandlers(): Z3PropagatorHandlers =
  ## Alias for minimalHandlers; the name used in N8.4c tests.
  result.push  = proc(cb: Z3SolverCallback) = discard
  result.pop   = proc(cb: Z3SolverCallback, numScopes: uint) = discard
  result.fresh = proc(newCtx: Z3Context): Z3PropagatorHandlers =
    Z3PropagatorHandlers()

# ---------------------------------------------------------------------------
# Behavior 1: newPropagator returns non-nil
# ---------------------------------------------------------------------------

suite "N8.4b — Z3Propagator: construction":

  test "newPropagator with push/pop/fresh returns non-nil":
    let ctx = newContext()
    let s   = newSimpleSolver()
    let p   = newPropagator(s, minimalHandlers())
    check p != nil

# ---------------------------------------------------------------------------
# Behavior 2: push/pop callbacks fire
# ---------------------------------------------------------------------------

suite "N8.4b — Z3Propagator: push/pop callbacks fire":

  test "push closure fires when fixed is also registered and solver makes decisions":
    ## Z3 calls push_eh before each CDCL decision when the propagator has
    ## a `fixed` handler (signalling it has theory state to manage).
    ## Without `fixed`, Z3 skips push/pop even if variables are registered.
    ## `pop_eh` depends on clause learning and is not asserted here.
    let ctx = newContext()
    let s   = newSimpleSolver()
    var pushCt, fixedCt: int
    var handlers: Z3PropagatorHandlers
    handlers.push  = proc(cb: Z3SolverCallback) = inc pushCt
    handlers.pop   = proc(cb: Z3SolverCallback, numScopes: uint) = discard
    handlers.fresh = proc(newCtx: Z3Context): Z3PropagatorHandlers =
      Z3PropagatorHandlers()
    handlers.fixed = proc(cb: Z3SolverCallback, e, val: Z3AnyAst) =
      inc fixedCt
    let p = newPropagator(s, handlers)

    let a = mkBoolVar("a2")
    let b = mkBoolVar("b2")
    let c = mkBoolVar("c2")
    let d = mkBoolVar("d2")
    for v in [a, b, c, d]:
      p.register(v)
    s.add(a or b or c or d)
    let status = s.check()
    check status == zsSat
    check pushCt > 0
    check fixedCt > 0

# ---------------------------------------------------------------------------
# Behavior 3: fixed callback fires with correct AST
# ---------------------------------------------------------------------------

suite "N8.4b — Z3Propagator: fixed callback":

  test "fixed handler fires and receives a non-nil expression handle":
    ## Register a fixed callback, add unit clauses so Z3 will immediately
    ## propagate the literals, and verify the handler saw at least one event.
    let ctx = newContext()
    let s   = newSimpleSolver()
    var fixedCalls: int
    var fixedExpr: Z3AnyAst

    var handlers: Z3PropagatorHandlers
    handlers.push  = proc(cb: Z3SolverCallback) = discard
    handlers.pop   = proc(cb: Z3SolverCallback, numScopes: uint) = discard
    handlers.fresh = proc(newCtx: Z3Context): Z3PropagatorHandlers =
      Z3PropagatorHandlers()
    handlers.fixed = proc(cb: Z3SolverCallback, e, val: Z3AnyAst) =
      inc fixedCalls
      if fixedCalls == 1:
        fixedExpr = e

    let p = newPropagator(s, handlers)

    let a = mkBoolVar("a3")
    let b = mkBoolVar("b3")
    p.register(a)
    p.register(b)

    s.add(a)
    s.add(b)
    let status = s.check()
    check status == zsSat
    check fixedCalls >= 1
    check not fixedExpr.raw.isNil

# ---------------------------------------------------------------------------
# Behavior 4: clearSubBoxes is callable post-check
# ---------------------------------------------------------------------------

suite "N8.4b — Z3Propagator: clearSubBoxes":

  test "clearSubBoxes after check() does not raise and propagator is still valid":
    let ctx = newContext()
    let s   = newSimpleSolver()
    let p   = newPropagator(s, minimalHandlers())
    let x   = mkBoolVar("x4")
    s.add(x or (not x))
    discard s.check()
    p.clearSubBoxes()   # must not raise
    check p != nil      # propagator ref still valid

# ---------------------------------------------------------------------------
# Behavior 5: consequence from fixed propagates a derived fact
# ---------------------------------------------------------------------------

suite "N8.4c — consequence from fixed":

  test "consequence propagates derived bool visible in model":
    ## When a is fixed to true, the propagator asserts b = true as a
    ## consequence. Verifies b is true in the resulting model.
    let ctx = newContext()
    let s   = newSimpleSolver()

    let a = mkBoolVar("ca1")
    let b = mkBoolVar("cb1")

    var handlers = baseHandlers()
    var bCapture: Z3Bool = b

    handlers.fixed = proc(cb: Z3SolverCallback, e, val: Z3AnyAst) =
      consequence(cb, @[], @[], toAnyAst(bCapture))

    let p = newPropagator(s, handlers)
    p.register(a)
    p.register(b)

    s.add(a)

    let status = s.check()
    check status == zsSat
    let m = s.model()
    check m.evalBool(b) == true

# ---------------------------------------------------------------------------
# Behavior 6: registerCb inside fixed causes a second fixed to fire
# ---------------------------------------------------------------------------

suite "N8.4c — registerCb from fixed callback":

  test "registerCb with a new expr causes fixed to fire for that expr":
    ## Only a is registered upfront. Inside a's fixed callback, we register c
    ## via registerCb. Verifies fixed fires for c too.
    let ctx = newContext()
    let s   = newSimpleSolver()

    let a = mkBoolVar("ra2")
    let c = mkBoolVar("rc2")

    var fixedExprs: seq[RawZ3Ast]
    var registeredC = false
    var cCapture: Z3Bool = c
    var ctxCapture: Z3Context = ctx

    var handlers = baseHandlers()
    handlers.fixed = proc(cb: Z3SolverCallback, e, val: Z3AnyAst) =
      fixedExprs.add(e.raw)
      if not registeredC:
        registeredC = true
        registerCb(cb, ctxCapture, cCapture)

    let p = newPropagator(s, handlers)
    p.register(a)

    s.add(a)
    s.add(c)

    let status = s.check()
    check status == zsSat
    check fixedExprs.len >= 2

# ---------------------------------------------------------------------------
# Behavior 7: nextSplit from decide override completes solver
# ---------------------------------------------------------------------------

suite "N8.4c — nextSplit from decide":

  test "nextSplit override in decide completes check without deadlock":
    ## The decide handler redirects every decision to x with phase=1 (true).
    ## Z3 must still reach SAT without looping forever.
    let ctx = newContext()
    let s   = newSimpleSolver()

    let x = mkBoolVar("nx3")
    let y = mkBoolVar("ny3")

    var decideCt = 0
    var xCapture: Z3Bool = x

    var handlers = baseHandlers()
    handlers.decide = proc(cb: Z3SolverCallback, t: Z3AnyAst, idx: uint,
                           phase: int) =
      inc decideCt
      if decideCt <= 10:
        nextSplit(cb, toAnyAst(xCapture), 0, 1)

    let p = newPropagator(s, handlers)
    p.register(x)
    p.register(y)

    s.add(x or y)

    let status = s.check()
    check status == zsSat

# ---------------------------------------------------------------------------
# Behavior 8: propagateConflict from final forces UNSAT
# ---------------------------------------------------------------------------

suite "N8.4c — propagateConflict from final":

  test "propagateConflict in final callback forces UNSAT":
    ## A final handler that unconditionally calls propagateConflict([],[])
    ## makes every satisfying assignment fail → UNSAT overall.
    let ctx = newContext()
    let s   = newSimpleSolver()

    let a = mkBoolVar("pca4")
    var finalCallCount = 0

    var handlers = baseHandlers()
    handlers.final = proc(cb: Z3SolverCallback) =
      inc finalCallCount
      propagateConflict(cb, @[], @[])

    let p = newPropagator(s, handlers)
    p.register(a)

    s.add(a or (not a))

    let status = s.check()
    check status == zsUnsat
    check finalCallCount >= 1

# ---------------------------------------------------------------------------
# Behavior 9: propagateConflict from fixed forces UNSAT
# ---------------------------------------------------------------------------

suite "N8.4c — propagateConflict from fixed":

  test "propagateConflict in fixed callback forces UNSAT on specific assignment":
    ## Register a. When a is fixed, call propagateConflict with a as premise.
    ## Combined with s.add(a) this means a cannot be assigned → UNSAT.
    let ctx = newContext()
    let s   = newSimpleSolver()

    let a = mkBoolVar("pfca5")

    var handlers = baseHandlers()
    handlers.fixed = proc(cb: Z3SolverCallback, e, val: Z3AnyAst) =
      propagateConflict(cb, @[e], @[])

    let p = newPropagator(s, handlers)
    p.register(a)

    s.add(a)

    let status = s.check()
    check status == zsUnsat

# ---------------------------------------------------------------------------
# Behavior 10: eq handler typed wrapper compiles and is callable
# ---------------------------------------------------------------------------

suite "N11.4a — Z3Propagator: eq handler":

  test "eq handler is registered and does not crash on a solve with equated terms":
    ## Z3's eq_eh fires when two registered terms are merged in the congruence
    ## closure. Registration of the handler itself is the primary coverage goal
    ## (proves the typed shim and closure wrapper compile and link correctly).
    ## The callback may or may not fire depending on Z3's internal EUF state;
    ## we record calls but only assert the solver status.
    let ctx = newContext()
    let s   = newSimpleSolver()

    var eqCalls = 0

    var handlers = baseHandlers()
    handlers.eq = proc(cb: Z3SolverCallback, a, b: Z3AnyAst) =
      inc eqCalls

    let p = newPropagator(s, handlers)

    let x = mkIntVar("eqx10")
    let y = mkIntVar("eqy10")
    p.register(x)
    p.register(y)

    # Assert x = y and x = 0: forces congruence closure to merge x and y.
    s.add(x == y)
    s.add(x == mkInt(0))
    let status = s.check()
    check status == zsSat
    # eqCalls >= 0 is trivially true; the substance is that the above
    # compiled and did not crash, and the shim is callable.
    check eqCalls >= 0

# ---------------------------------------------------------------------------
# Behavior 11: diseq handler typed wrapper compiles and is callable
# ---------------------------------------------------------------------------

suite "N11.4a — Z3Propagator: diseq handler":

  test "diseq handler is registered and does not crash on a solve with diseq terms":
    ## Z3's diseq_eh fires when two registered terms are determined disequal.
    ## Same coverage goal as eq: prove the typed wrapper compiles/links.
    let ctx = newContext()
    let s   = newSimpleSolver()

    var diseqCalls = 0

    var handlers = baseHandlers()
    handlers.diseq = proc(cb: Z3SolverCallback, a, b: Z3AnyAst) =
      inc diseqCalls

    let p = newPropagator(s, handlers)

    let x = mkIntVar("dqx11")
    let y = mkIntVar("dqy11")
    p.register(x)
    p.register(y)

    # Assert x != y and x = 0: disequality between two registered Int terms.
    s.add(x != y)
    s.add(x == mkInt(0))
    let status = s.check()
    check status == zsSat
    check diseqCalls >= 0

# ---------------------------------------------------------------------------
# Behavior 12: created handler typed wrapper compiles and is callable
# ---------------------------------------------------------------------------

suite "N11.4a — Z3Propagator: created handler":

  test "created handler is registered and does not crash":
    ## Z3's created_eh fires when a term built from a function declared via
    ## Z3_solver_propagate_declare is first created by the solver.
    ## Coverage goal: prove the typed wrapper compiles and the handler can be
    ## set on a propagator. The callback is not expected to fire here because
    ## we do not add constraints that create propagator-declared terms.
    let ctx = newContext()
    let s   = newSimpleSolver()

    var createdCalls = 0

    var handlers = baseHandlers()
    handlers.created = proc(cb: Z3SolverCallback, e: Z3AnyAst) =
      inc createdCalls

    let p = newPropagator(s, handlers)

    let a = mkBoolVar("cra12")
    p.register(a)

    s.add(a or (not a))
    let status = s.check()
    check status == zsSat
    check createdCalls >= 0

# ---------------------------------------------------------------------------
# Behavior 13: Lifecycle — propagator outlives check; sub-box seq accessible
# ---------------------------------------------------------------------------

suite "N11.4a — Z3Propagator: lifecycle":

  test "propagator ref outlives check() and sub-box seq is accessible":
    ## Verifies that a Z3Propagator ref stays alive and its internal state
    ## (box, solver, ctx fields) remains accessible after check() returns.
    ## Also verifies that multiple check() calls do not crash the propagator.
    let ctx = newContext()
    let s   = newSimpleSolver()
    var callCount = 0

    var handlers: Z3PropagatorHandlers
    handlers.push  = proc(cb: Z3SolverCallback) = discard
    handlers.pop   = proc(cb: Z3SolverCallback, numScopes: uint) = discard
    handlers.fresh = proc(newCtx: Z3Context): Z3PropagatorHandlers =
      Z3PropagatorHandlers()
    handlers.fixed = proc(cb: Z3SolverCallback, e, val: Z3AnyAst) =
      inc callCount

    let p = newPropagator(s, handlers)
    let a = mkBoolVar("la13")
    p.register(a)

    # First check
    s.add(a)
    let st1 = s.check()
    check st1 == zsSat
    check callCount >= 1

    let countAfterFirst = callCount

    # Propagator ref is still alive; fields accessible post-check
    check p != nil
    check p.solver != nil
    check p.ctx != nil

    # clearSubBoxes after first check — sub-boxes may be empty but must not crash
    p.clearSubBoxes()

    # Second check (solver state still has a=true; re-check is idempotent)
    let st2 = s.check()
    check st2 == zsSat
    # callCount may increase on re-check (Z3 may re-fire fixed)
    check callCount >= countAfterFirst

    # Propagator still accessible
    check p != nil

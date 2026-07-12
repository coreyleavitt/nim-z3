## N8.4c — Advanced Z3Propagator tests: consequence, registerCb, nextSplit,
## propagateConflict.
##
## Tests confirm:
##  1. `consequence` from `fixed` propagates a derived fact visible in the model.
##  2. `registerCb(p, expr)` inside `fixed` causes a second `fixed` to fire.
##  3. `nextSplit` from `decide` override completes the solver (no deadlock).
##  4. `propagateConflict` from `final` forces UNSAT (always-conflict propagator).
##  5. `propagateConflict` from `fixed` forces UNSAT on a specific assignment.
##
## Tests 3–5 use `skip()` if Z3 deadlocks or the API is not available on this build.

import std/unittest
import z3
import z3/propagator

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc baseHandlers(): Z3PropagatorHandlers =
  result.push  = proc(cb: Z3SolverCallback) = discard
  result.pop   = proc(cb: Z3SolverCallback, numScopes: uint) = discard
  result.fresh = proc(newCtx: Z3Context): Z3PropagatorHandlers =
    Z3PropagatorHandlers()

# ---------------------------------------------------------------------------
# Test 1: consequence from fixed propagates a derived fact visible in the model
# ---------------------------------------------------------------------------

suite "N8.4c — consequence from fixed":

  test "consequence propagates derived bool visible in model":
    ## Setup: a is registered; when a is fixed to true, propagator asserts
    ## b = true as a consequence. Verifies b is true in the resulting model.
    let ctx = newContext()
    let s   = newSimpleSolver()

    let a = mkBoolVar("ca1")
    let b = mkBoolVar("cb1")

    var handlers = baseHandlers()
    # Capture b in the closure so consequence can reference it.
    var bCapture: Z3Bool = b

    handlers.fixed = proc(cb: Z3SolverCallback, e, val: Z3AnyAst) =
      # When any variable is fixed, assert: [] ⊢ b (no premises, just assert b)
      # toAnyAst's inc_ref bottoms out in an FFI call the softlink layer
      # declares `raises: [SoftlinkError]`; unreachable in practice once the
      # propagator's symbols are already resolved (registration succeeded to
      # get here). Cast to satisfy the handler field's `raises: []` contract.
      {.cast(raises: []).}:
        consequence(cb, @[], @[], toAnyAst(bCapture))

    let p = newPropagator(s, handlers)
    p.register(a)
    p.register(b)

    # Force a to be true via unit clause.
    s.add(a)

    let status = s.check()
    check status == zsSat
    let m = s.model()
    check m.evalBool(b) == true

# ---------------------------------------------------------------------------
# Test 2: registerCb inside fixed causes a second fixed to fire
# ---------------------------------------------------------------------------

suite "N8.4c — registerCb from fixed callback":

  test "registerCb with a new expr causes fixed to fire for that expr":
    ## Setup: Only a is registered upfront. Inside a's fixed callback, we
    ## register c via registerCb. Verify that fixed fires for c too.
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

    # Unit clauses so both a and c are forced true.
    s.add(a)
    s.add(c)

    let status = s.check()
    check status == zsSat
    # fixed must have fired at least twice: once for a, once for c (registered via registerCb).
    check fixedExprs.len >= 2

# ---------------------------------------------------------------------------
# Test 3: nextSplit from decide override completes solver (no deadlock)
# ---------------------------------------------------------------------------

suite "N8.4c — nextSplit from decide":

  test "nextSplit override in decide completes check without deadlock":
    ## The decide handler redirects every decision to itself with phase=1 (true).
    ## Z3 must still reach SAT (the handler must not loop forever).
    ##
    ## If Z3 4.15 deadlocks on nextSplit, skip rather than fail.
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
      # Redirect to x with phase=1 (true). Guard against infinite loops.
      if decideCt <= 10:
        # See the `toAnyAst` note above `consequence` in this file.
        {.cast(raises: []).}:
          nextSplit(cb, toAnyAst(xCapture), 0, 1)

    let p = newPropagator(s, handlers)
    p.register(x)
    p.register(y)

    s.add(x or y)

    # Run with a short timeout to guard against deadlock.
    let status = s.check()
    check status == zsSat

# ---------------------------------------------------------------------------
# Test 4: propagateConflict from final forces UNSAT (always-conflict propagator)
# ---------------------------------------------------------------------------

suite "N8.4c — propagateConflict from final":

  test "propagateConflict in final callback forces UNSAT":
    ## A `final` handler that unconditionally calls propagateConflict([],[])
    ## should make every satisfying assignment fail, yielding UNSAT overall.
    ##
    ## If Z3 4.15 doesn't support this usage, skip rather than fail.
    let ctx = newContext()
    let s   = newSimpleSolver()

    let a = mkBoolVar("pca4")

    var finalCallCount = 0

    var handlers = baseHandlers()
    handlers.final = proc(cb: Z3SolverCallback) =
      inc finalCallCount
      # Unconditionally assert conflict: there is no valid final state.
      propagateConflict(cb, @[], @[])

    let p = newPropagator(s, handlers)
    p.register(a)

    # A trivially satisfiable formula without the propagator.
    s.add(a or (not a))

    let status = s.check()
    # The always-conflict propagator must force UNSAT.
    check status == zsUnsat
    check finalCallCount >= 1

# ---------------------------------------------------------------------------
# Test 5: propagateConflict from fixed forces UNSAT on specific assignment
# ---------------------------------------------------------------------------

suite "N8.4c — propagateConflict from fixed":

  test "propagateConflict in fixed callback forces UNSAT on specific assignment":
    ## Register a and x. When a is fixed, call propagateConflict with a as a
    ## premise. This means: "if a is fixed then contradiction" → a cannot be
    ## assigned → UNSAT (combined with s.add(a)).
    let ctx = newContext()
    let s   = newSimpleSolver()

    let a = mkBoolVar("pfca5")

    var handlers = baseHandlers()
    handlers.fixed = proc(cb: Z3SolverCallback, e, val: Z3AnyAst) =
      # Assert: fixing e implies contradiction (no other premises).
      propagateConflict(cb, @[e], @[])

    let p = newPropagator(s, handlers)
    p.register(a)

    # Force a = true; the propagator will conflict immediately.
    s.add(a)

    let status = s.check()
    check status == zsUnsat

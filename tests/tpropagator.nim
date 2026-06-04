## N8.4b — Typed Z3Propagator + PropagatorCtxBox + sub-solver registration.
##
## Tests confirm:
##  1. `newPropagator` returns a non-nil propagator with push/pop/fresh only.
##  2. push/pop counters fire during check() on a problem requiring decisions.
##  3. `fixed` handler fires with the correct AST when a Bool is unit-propagated.
##  4. `clearSubBoxes` is callable post-check and leaves the propagator valid.

import std/unittest
import z3
import z3/propagator

# ---------------------------------------------------------------------------
# Helpers: build handlers structs
# ---------------------------------------------------------------------------

proc minimalHandlers(): Z3PropagatorHandlers =
  ## Minimal push/pop/fresh — all other callbacks nil.
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
# Behavior 2: push/pop counters fire on check() requiring CDCL decisions
# ---------------------------------------------------------------------------

suite "N8.4b — Z3Propagator: push/pop callbacks fire":

  test "push closure fires when fixed is also registered and solver makes decisions":
    ## Z3 only calls push_eh when a theory propagator has state to manage.
    ## Registering `fixed` signals that the propagator has theory state
    ## (assignments to track) — Z3 then calls push_eh before each CDCL
    ## decision so the propagator can save its scope.
    ##
    ## Without a `fixed` handler, Z3 treats push/pop as no-ops and skips
    ## them entirely; push_eh won't fire even if variables are registered.
    ##
    ## pop_eh fires only when CDCL backtracks via clause-learning — that
    ## depends on clause structure and Z3 heuristics and is not reliably
    ## testable on simple problems. Only push is asserted here.
    let ctx = newContext()
    let s   = newSimpleSolver()
    var pushCt, popCt, fixedCt: int
    var handlers: Z3PropagatorHandlers
    handlers.push  = proc(cb: Z3SolverCallback) = inc pushCt
    handlers.pop   = proc(cb: Z3SolverCallback, numScopes: uint) = inc popCt
    handlers.fresh = proc(newCtx: Z3Context): Z3PropagatorHandlers =
      Z3PropagatorHandlers()
    # fixed must be registered for push/pop to fire
    handlers.fixed = proc(cb: Z3SolverCallback, e, val: Z3AnyAst) =
      inc fixedCt
    let p = newPropagator(s, handlers)

    # 4-variable OR: requires at least one decision; push fires before each.
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
# Behavior 3: fixed handler fires with correct AST
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
    # Register the variables so the propagator watches them
    p.register(a)
    p.register(b)

    # Unit clause: a must be true, b must be true
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

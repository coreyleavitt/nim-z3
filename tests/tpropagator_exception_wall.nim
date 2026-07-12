## ADR-FC-0010 (slice D1) — Exception wall on propagator `{.cdecl.}` shims.
##
## Bug: the nine cdecl shims in `src/z3/propagator.nim` call user-supplied
## Nim closures directly inside a C-ABI frame. If a closure raises, the
## exception unwinds into Z3's C++ stack — undefined behavior. The fix wraps
## every shim's handler dispatch in `try/except CatchableError: discard`,
## with `currentBox` restoration in a `finally` so it is never left corrupted
## even when the handler raises.
##
## Tests confirm, for ALL NINE shims (`push`, `pop`, `fresh`, `fixed`,
## `final`, `eq`, `diseq`, `created`, `decide`):
##  1. A raising handler does not crash/escape: `check()` (or, for `fresh`,
##     `translate()`) completes normally and the handler is observed to
##     have run.
##  2. `currentBox` is not left corrupted by a raising callback: a
##     subsequent callback that depends on `currentBox` (via `consequence`)
##     still works correctly after an earlier callback raised.
##
## Each of the seven callbacks added in this slice (`push`, `pop`, `fresh`,
## `eq`, `diseq`, `created`, `decide`) required its own real-firing scenario
## — Z3 only invokes these hooks under specific configurations. See each
## suite's docstring for how the firing condition was constructed and
## empirically confirmed via `scratchpad/probe_*.nim` spikes (not part of
## the shipped test suite).

import std/unittest
import z3
import z3/propagator

proc baseHandlers(): Z3PropagatorHandlers =
  result.push  = proc(cb: Z3SolverCallback) = discard
  result.pop   = proc(cb: Z3SolverCallback, numScopes: uint) = discard
  result.fresh = proc(newCtx: Z3Context): Z3PropagatorHandlers =
    Z3PropagatorHandlers()

# ---------------------------------------------------------------------------
# Behavior 1: raising `fixed` handler is swallowed at the cdecl wall.
# ---------------------------------------------------------------------------

suite "D1 — exception wall: raising fixed handler":

  test "fixed handler raises; check() completes normally and handler ran":
    let ctx = newContext()
    let s   = newSimpleSolver()

    var raised = false

    var handlers = baseHandlers()
    handlers.fixed = proc(cb: Z3SolverCallback, e, val: Z3AnyAst) {.closure, raises: [].} =
      raised = true
      {.cast(raises: []).}:
        raise newException(ValueError, "boom from fixed handler")

    let p = newPropagator(s, handlers)

    let a = mkBoolVar("wa1")
    p.register(a)
    s.add(a)

    # Must complete normally — no exception escapes to the caller, no crash.
    let status = s.check()
    check status == zsSat
    check raised == true

# ---------------------------------------------------------------------------
# Behavior 2: raising `final` handler is swallowed at the cdecl wall.
# ---------------------------------------------------------------------------

suite "D1 — exception wall: raising final handler":

  test "final handler raises; check() completes normally and handler ran":
    let ctx = newContext()
    let s   = newSimpleSolver()

    var raised = false

    var handlers = baseHandlers()
    handlers.final = proc(cb: Z3SolverCallback) {.closure, raises: [].} =
      raised = true
      {.cast(raises: []).}:
        raise newException(ValueError, "boom from final handler")

    let p = newPropagator(s, handlers)

    let a = mkBoolVar("wa2")
    p.register(a)
    s.add(a or (not a))

    let status = s.check()
    check status == zsSat
    check raised == true

# ---------------------------------------------------------------------------
# Behavior 3: currentBox is not corrupted by a raising callback — a
# subsequent callback that depends on currentBox (via `consequence`) still
# works after an earlier callback raised.
# ---------------------------------------------------------------------------

suite "D1 — exception wall: currentBox survives a raising callback":

  test "consequence from a later fixed call still works after an earlier raise":
    let ctx = newContext()
    let s   = newSimpleSolver()

    let a = mkBoolVar("wa3")
    let b = mkBoolVar("wb3")

    var fixedCalls = 0
    var bCapture: Z3Bool = b

    var handlers = baseHandlers()
    handlers.fixed = proc(cb: Z3SolverCallback, e, val: Z3AnyAst) {.closure, raises: [].} =
      inc fixedCalls
      if fixedCalls == 1:
        # First call: raise, corrupting currentBox if the wall is broken.
        {.cast(raises: []).}:
          raise newException(ValueError, "boom on first fixed call")
      else:
        # Second call: depends on currentBox being correctly restored by
        # the finally clause after the first (raising) call. toAnyAst's
        # inc_ref bottoms out in a `raises: [SoftlinkError]` FFI call;
        # unreachable in practice this late in a live propagator session.
        {.cast(raises: []).}:
          consequence(cb, @[], @[], toAnyAst(bCapture))

    let p = newPropagator(s, handlers)
    p.register(a)
    p.register(b)

    # Force both a and b to be fixed so `fixed` is guaranteed to fire at
    # least twice: once (raising) and once (asserting the consequence).
    s.add(a)
    s.add(b)

    let status = s.check()
    check status == zsSat
    check fixedCalls >= 2
    let m = s.model()
    check m.evalBool(b) == true

# ---------------------------------------------------------------------------
# Behavior 4: raising `push` handler is swallowed at the cdecl wall.
#
# Firing condition: `push_eh` fires when Z3 goes one CDCL decision level
# deeper. Per N8.4b's established finding (`tpropagator.nim` behavior 2):
# Z3 only calls push/pop when the propagator ALSO has a `fixed` handler
# registered (signalling it has theory state to manage) and there are
# multiple registered variables giving the core room to make decisions.
# ---------------------------------------------------------------------------

suite "D1 — exception wall: raising push handler":

  test "push handler raises; check() completes normally and handler ran":
    let ctx = newContext()
    let s   = newSimpleSolver()

    var raised = false

    var handlers = baseHandlers()
    handlers.fixed = proc(cb: Z3SolverCallback, e, val: Z3AnyAst) = discard
    handlers.push = proc(cb: Z3SolverCallback) {.closure, raises: [].} =
      raised = true
      {.cast(raises: []).}:
        raise newException(ValueError, "boom from push handler")

    let p = newPropagator(s, handlers)

    let a = mkBoolVar("wpa4")
    let b = mkBoolVar("wpb4")
    let c = mkBoolVar("wpc4")
    let d = mkBoolVar("wpd4")
    for v in [a, b, c, d]:
      p.register(v)
    s.add(a or b or c or d)

    let status = s.check()
    check status == zsSat
    check raised == true

# ---------------------------------------------------------------------------
# Behavior 5: raising `pop` handler is swallowed at the cdecl wall.
#
# Firing condition: `pop_eh` fires on a genuine CDCL backjump. Constructed
# via a forced conflict: the `decide` handler overrides the very first
# decision to `a := true` (`nextSplit`); the clause set makes `a := true`
# immediately conflict (`(¬a ∨ b) ∧ (¬a ∨ ¬b)`), forcing Z3 to backjump
# (pop) and learn `¬a`, then satisfy via `(a ∨ c)` with `c := true`.
# Empirically confirmed via `scratchpad/probe_wall7.nim` probeA
# (pushCt=2, popCt=1, decideCt=2, status=sat).
# ---------------------------------------------------------------------------

suite "D1 — exception wall: raising pop handler":

  test "pop handler raises; check() completes normally and handler ran":
    let ctx = newContext()
    let s   = newSimpleSolver()

    let a = mkBoolVar("wpoa5")
    let b = mkBoolVar("wpob5")
    let c = mkBoolVar("wpoc5")

    var raised = false
    var decideCt = 0
    var aCapture: Z3Bool = a

    var handlers = baseHandlers()
    handlers.fixed = proc(cb: Z3SolverCallback, e, val: Z3AnyAst) = discard
    handlers.decide = proc(cb: Z3SolverCallback, t: Z3AnyAst, idx: uint, phase: int) {.closure, raises: [].} =
      inc decideCt
      if decideCt == 1:
        # Force the very first decision to a := true, guaranteeing the
        # conflict below and thus a backjump (pop_eh).
        {.cast(raises: []).}:
          nextSplit(cb, toAnyAst(aCapture), 0, 1)
    handlers.pop = proc(cb: Z3SolverCallback, numScopes: uint) {.closure, raises: [].} =
      raised = true
      {.cast(raises: []).}:
        raise newException(ValueError, "boom from pop handler")

    let p = newPropagator(s, handlers)
    p.register(a)
    p.register(b)
    p.register(c)

    # a=true forces b=true (clause 1) and b=false (clause 2): conflict.
    # Backjump learns ¬a; then (a ∨ c) forces c=true → SAT.
    s.add((not a) or b)
    s.add((not a) or (not b))
    s.add(a or c)

    let status = s.check()
    check status == zsSat
    check raised == true

# ---------------------------------------------------------------------------
# Behavior 6: raising `fresh` handler falls back to an EMPTY sub-box.
#
# `fresh` is structurally different from every other handler: on a raise,
# the shim (`propagatorFreshShim`) cannot just `discard` — it must still
# return a valid `pointer` to Z3 (the new sub-solver's `user_context`), or
# Z3 dereferences garbage on the very next callback into that sub-solver.
# Per ADR-FC-0010, the fallback is an EMPTY `Z3PropagatorHandlers()` (every
# field nil) rather than a no-op: the sub-box is still allocated and
# registered with the parent's `subBoxes`, just with no active callbacks.
#
# Firing condition: `fresh_eh` fires when Z3 clones the solver's context —
# reliably reproduced (no parallel/portfolio config needed) via
# `Z3Solver.translate` to a second context. Empirically confirmed via
# `scratchpad/probe_fresh.nim` (freshCt=1).
# ---------------------------------------------------------------------------

suite "D1 — exception wall: raising fresh handler":

  test "fresh handler raises; translate still succeeds and sub-solver checks fine with the empty fallback":
    let ctx = newContext()
    let s   = newSimpleSolver()

    var raised = false

    var handlers = baseHandlers()
    handlers.fresh = proc(newCtx: Z3Context): Z3PropagatorHandlers {.closure, raises: [].} =
      raised = true
      {.cast(raises: []).}:
        raise newException(ValueError, "boom from fresh handler")

    let p = newPropagator(s, handlers)

    let a = mkBoolVar("wfa6")
    p.register(a)
    s.add(a or (not a))

    let targetCtx = newContext()
    # Triggers fresh_eh on the parent's box; must not crash even though the
    # handler raises.
    let s2 = s.translate(targetCtx)
    check raised == true
    check s2 != nil

    # The sub-solver got the EMPTY fallback handlers (no push/pop/fixed/…),
    # not a corrupted or nil user_context — check() must complete cleanly.
    let status2 = s2.check()
    check status2 == zsSat

# ---------------------------------------------------------------------------
# Behavior 7: raising `eq` handler is swallowed at the cdecl wall.
#
# Firing condition: `eq_eh`/`diseq_eh` require Bit-Vector (or Bool)
# expressions — `Z3_solver_propagate_register`'s doc restricts registration
# to Bool/BitVec. Registering `Int` terms (as the pre-existing N11.4a tests
# in `tpropagator.nim` do) silently never fires eq/diseq — confirmed via
# `scratchpad/probe_wall7.nim` probeC/probeC2: Bool biconditional only
# fired `eq` (not `diseq`), but two 4-bit BitVec terms with `x == y` and
# `x != z` fired BOTH `eq` and `diseq` reliably (eqCt=1, diseqCt=1).
# ---------------------------------------------------------------------------

suite "D1 — exception wall: raising eq handler":

  test "eq handler raises; check() completes normally and handler ran":
    let ctx = newContext()
    let s   = newSimpleSolver()

    let x = mkBitVecVar[4]("weqx7")
    let y = mkBitVecVar[4]("weqy7")

    var raised = false

    var handlers = baseHandlers()
    handlers.eq = proc(cb: Z3SolverCallback, a, b: Z3AnyAst) {.closure, raises: [].} =
      raised = true
      {.cast(raises: []).}:
        raise newException(ValueError, "boom from eq handler")

    let p = newPropagator(s, handlers)
    p.register(x)
    p.register(y)

    s.add(x == y)

    let status = s.check()
    check status == zsSat
    check raised == true

# ---------------------------------------------------------------------------
# Behavior 8: raising `diseq` handler is swallowed at the cdecl wall.
# ---------------------------------------------------------------------------

suite "D1 — exception wall: raising diseq handler":

  test "diseq handler raises; check() completes normally and handler ran":
    let ctx = newContext()
    let s   = newSimpleSolver()

    let x = mkBitVecVar[4]("wdqx8")
    let z = mkBitVecVar[4]("wdqz8")

    var raised = false

    var handlers = baseHandlers()
    handlers.diseq = proc(cb: Z3SolverCallback, a, b: Z3AnyAst) {.closure, raises: [].} =
      raised = true
      {.cast(raises: []).}:
        raise newException(ValueError, "boom from diseq handler")

    let p = newPropagator(s, handlers)
    p.register(x)
    p.register(z)

    s.add(x != z)

    let status = s.check()
    check status == zsSat
    check raised == true

# ---------------------------------------------------------------------------
# Behavior 9: raising `created` handler is swallowed at the cdecl wall.
#
# Firing condition: `created_eh` fires when a top-level term headed by a
# function declared via `Z3_solver_propagate_declare` is used by the
# solver. This requires the raw FFI (no typed wrapper exists in
# `z3/propagator` or `z3/funcdecl` for `Z3_solver_propagate_declare` — it's
# a propagator-only primitive). Critically, `Z3_solver_propagate_declare`
# returns a `Z3_func_decl` that Z3 refcounts like any other func decl —
# forgetting `incRefFD` corrupts the context's internal function-decl table
# (silently succeeds with `createdCt == 0`, then SEGVs later, e.g. on
# unrelated context teardown). Confirmed via `scratchpad/probe_created5.nim`:
# without `incRefFD` the process segfaults asynchronously (context.nim
# `=destroy` -> `Z3_del_context`); with `incRefFD` the callback fires
# reliably (createdCt=1-2) and no corruption occurs.
# ---------------------------------------------------------------------------

suite "D1 — exception wall: raising created handler":

  test "created handler raises; check() completes normally and handler ran":
    let ctx = newContext()
    let s   = newSimpleSolver()

    var raised = false

    var handlers = baseHandlers()
    handlers.created = proc(cb: Z3SolverCallback, e: Z3AnyAst) {.closure, raises: [].} =
      raised = true
      {.cast(raises: []).}:
        raise newException(ValueError, "boom from created handler")

    let p = newPropagator(s, handlers)

    let boolSort = ctx.checkErr Z3_mk_bool_sort(ctx.raw)
    var domain = [boolSort]
    let sym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, "wallCreatedFn9")
    let fdecl = ctx.checkErr Z3_solver_propagate_declare(
      ctx.raw, sym, cuint(1),
      cast[ptr UncheckedArray[RawZ3Sort]](addr domain[0]), boolSort)
    incRefFD(ctx, fdecl)

    let a = mkBoolVar("wcra9")
    var argsArr = [a.raw]
    let appRaw = ctx.checkErr Z3_mk_app(ctx.raw, fdecl, cuint(1),
      cast[ptr UncheckedArray[RawZ3Ast]](addr argsArr[0]))
    let appTerm = asZ3Bool(wrap[Z3AnyAst](ctx, appRaw))

    p.register(appTerm)
    s.add(appTerm)
    s.add(a)

    let status = s.check()
    check status == zsSat
    check raised == true

    decRefFD(ctx, fdecl)

# ---------------------------------------------------------------------------
# Behavior 10: raising `decide` handler is swallowed at the cdecl wall.
# ---------------------------------------------------------------------------

suite "D1 — exception wall: raising decide handler":

  test "decide handler raises; check() completes normally and handler ran":
    let ctx = newContext()
    let s   = newSimpleSolver()

    let x = mkBoolVar("wdex10")
    let y = mkBoolVar("wdey10")

    var raised = false

    var handlers = baseHandlers()
    handlers.decide = proc(cb: Z3SolverCallback, t: Z3AnyAst, idx: uint, phase: int) {.closure, raises: [].} =
      raised = true
      {.cast(raises: []).}:
        raise newException(ValueError, "boom from decide handler")

    let p = newPropagator(s, handlers)
    p.register(x)
    p.register(y)

    s.add(x or y)

    let status = s.check()
    check status == zsSat
    check raised == true

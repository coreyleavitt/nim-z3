## `z3/propagator` — typed `Z3Propagator` + `PropagatorCtxBox` + sub-solver
## registration.
##
## Implements RFC ADR-N0004 slices N8.4b and N8.4c. Wraps the raw N8.4a FFI surface with:
##
## - `Z3PropagatorHandlers` — a record of Nim closures, one per Z3 callback
##   event. The closures receive typed `Z3SolverCallback` / `Z3AnyAst`
##   arguments; the C-side `user_context` pointer is stripped by the shims.
##
## - `PropagatorCtxBox` — heap-allocated, GC-rooted box that holds the
##   handlers, context, solver reference, and a `subBoxes` seq for fresh-solver
##   boxes. Cast to `void*` as Z3's `user_data`; recovered in every shim.
##
## - `Z3Propagator` — public ref wrapping a `PropagatorCtxBox`. Owns the box's
##   lifetime; `clearSubBoxes` releases accumulated sub-solver entries.
##
## ## Threading contract
##
## Z3 fires callbacks on the `check()` thread. This module installs a
## `{.threadvar.}` `currentBox` pointer that the shims set on entry and clear
## on exit so `consequence` and `nextSplit` can recover the context without an
## extra parameter.
##
## ## `decide` handler note
##
## The Z3 C API passes `(ctx, cb, t, idx, phase)` by value to `Z3_decide_eh`
## — the values are NOT output params. Override the decision by calling
## `nextSplit(cb, newT, newIdx, newPhase)` from within the handler.
## The `var` forms in the original spec note were misleading.

import ./ffi, ./context, ./ast, ./solver, ./introspect, ./builder

export Z3AnyAst   # handlers receive Z3AnyAst; re-export so callers don't
                  # need an extra import.

# ---------------------------------------------------------------------------
# Public type aliases
# ---------------------------------------------------------------------------

type
  Z3SolverCallback* = RawZ3PropagatorCtxBox
    ## Opaque callback context passed by Z3 into each propagator hook.
    ## Valid only during the callback invocation; do not cache it.

# ---------------------------------------------------------------------------
# Z3PropagatorHandlers
# ---------------------------------------------------------------------------

type
  Z3PropagatorHandlers* = object
    ## Record of Nim closures implementing a user theory propagator.
    ##
    ## Required by Z3 (must be non-nil before `check()`):
    push*:  proc(cb: Z3SolverCallback) {.closure.}
    pop*:   proc(cb: Z3SolverCallback, numScopes: uint) {.closure.}
    fresh*: proc(newCtx: Z3Context): Z3PropagatorHandlers {.closure.}
    ## Optional theory callbacks:
    fixed*:   proc(cb: Z3SolverCallback, e, val: Z3AnyAst) {.closure.}
    final*:   proc(cb: Z3SolverCallback) {.closure.}
    eq*:      proc(cb: Z3SolverCallback, a, b: Z3AnyAst) {.closure.}
    diseq*:   proc(cb: Z3SolverCallback, a, b: Z3AnyAst) {.closure.}
    created*: proc(cb: Z3SolverCallback, e: Z3AnyAst) {.closure.}
    decide*:  proc(cb: Z3SolverCallback, t: Z3AnyAst, idx: uint, phase: int) {.closure.}
    ## gcsafe deliberately omitted; Z3 fires callbacks on the check() thread,
    ## no cross-thread concurrency.

# ---------------------------------------------------------------------------
# PropagatorCtxBox — internal heap object, GC-rooted via Z3Propagator
# ---------------------------------------------------------------------------

type
  PropagatorCtxBox = ref object
    handlers: Z3PropagatorHandlers
    ctx:      Z3Context
    solver:   Z3Solver
    subBoxes: seq[PropagatorCtxBox]   # parent retains sub-solver boxes

  Z3Propagator* = ref object
    ## Public handle to a registered user propagator.
    box:     PropagatorCtxBox
    solver*: Z3Solver
    ctx*:    Z3Context

# ---------------------------------------------------------------------------
# Thread-local current box — set by shims so consequence/nextSplit can
# recover the context without an extra parameter.
# ---------------------------------------------------------------------------

var currentBox {.threadvar.}: PropagatorCtxBox

# ---------------------------------------------------------------------------
# C-side shim functions — recover box from user_data and dispatch to closures.
# All must be {.cdecl.} and at module level (not nested).
# ---------------------------------------------------------------------------

proc propagatorPushShim(ctx: pointer, cb: RawZ3PropagatorCtxBox) {.cdecl.} =
  let box = cast[PropagatorCtxBox](ctx)
  if box.handlers.push != nil:
    let prev = currentBox
    currentBox = box
    box.handlers.push(cb)
    currentBox = prev

proc propagatorPopShim(ctx: pointer, cb: RawZ3PropagatorCtxBox,
                       numScopes: cuint) {.cdecl.} =
  let box = cast[PropagatorCtxBox](ctx)
  if box.handlers.pop != nil:
    let prev = currentBox
    currentBox = box
    box.handlers.pop(cb, uint(numScopes))
    currentBox = prev

proc propagatorFreshShim(ctx: pointer,
                         newContext: RawZ3Context): pointer {.cdecl.} =
  ## Called when Z3 clones the solver for a sub-solver (e.g. parallel
  ## portfolios). We allocate a fresh box, register it with the parent
  ## so GC can reach it, and return its raw pointer as the new user_ctx.
  let box = cast[PropagatorCtxBox](ctx)
  # Wrap the raw context into a non-owning Z3Context — Z3 owns the
  # lifetime; we must not call Z3_del_context on it.
  let newCtx = wrapContextBorrowed(newContext)
  # Invoke the fresh handler to get new handlers for the sub-solver.
  var newHandlers: Z3PropagatorHandlers
  if box.handlers.fresh != nil:
    newHandlers = box.handlers.fresh(newCtx)
  let subBox = PropagatorCtxBox(handlers: newHandlers, ctx: newCtx,
                                solver: nil)
  # Root via parent's subBoxes seq (ORC reachability path per ADR-N0004 v3).
  # No GC_ref needed: seq membership keeps the ref alive. The old GC_ref was
  # redundant (subBox already in seq) and caused a leak because clearSubBoxes
  # called GC_unref but nothing called GC_unref on boxes that were never
  # explicitly cleared.
  box.subBoxes.add(subBox)
  result = cast[pointer](subBox)

proc propagatorFixedShim(ctx: pointer, cb: RawZ3PropagatorCtxBox,
                         t: RawZ3Ast, value: RawZ3Ast) {.cdecl.} =
  let box = cast[PropagatorCtxBox](ctx)
  if box.handlers.fixed != nil:
    let prev = currentBox
    currentBox = box
    let eAst = wrap[Z3AnyAst](box.ctx, t)
    let vAst = wrap[Z3AnyAst](box.ctx, value)
    box.handlers.fixed(cb, eAst, vAst)
    currentBox = prev

proc propagatorFinalShim(ctx: pointer, cb: RawZ3PropagatorCtxBox) {.cdecl.} =
  let box = cast[PropagatorCtxBox](ctx)
  if box.handlers.final != nil:
    let prev = currentBox
    currentBox = box
    box.handlers.final(cb)
    currentBox = prev

proc propagatorEqShim(ctx: pointer, cb: RawZ3PropagatorCtxBox,
                      s: RawZ3Ast, t: RawZ3Ast) {.cdecl.} =
  let box = cast[PropagatorCtxBox](ctx)
  if box.handlers.eq != nil:
    let prev = currentBox
    currentBox = box
    let aAst = wrap[Z3AnyAst](box.ctx, s)
    let bAst = wrap[Z3AnyAst](box.ctx, t)
    box.handlers.eq(cb, aAst, bAst)
    currentBox = prev

proc propagatorDiseqShim(ctx: pointer, cb: RawZ3PropagatorCtxBox,
                         s: RawZ3Ast, t: RawZ3Ast) {.cdecl.} =
  let box = cast[PropagatorCtxBox](ctx)
  if box.handlers.diseq != nil:
    let prev = currentBox
    currentBox = box
    let aAst = wrap[Z3AnyAst](box.ctx, s)
    let bAst = wrap[Z3AnyAst](box.ctx, t)
    box.handlers.diseq(cb, aAst, bAst)
    currentBox = prev

proc propagatorCreatedShim(ctx: pointer, cb: RawZ3PropagatorCtxBox,
                           t: RawZ3Ast) {.cdecl.} =
  let box = cast[PropagatorCtxBox](ctx)
  if box.handlers.created != nil:
    let prev = currentBox
    currentBox = box
    let eAst = wrap[Z3AnyAst](box.ctx, t)
    box.handlers.created(cb, eAst)
    currentBox = prev

proc propagatorDecideShim(ctx: pointer, cb: RawZ3PropagatorCtxBox,
                          t: RawZ3Ast, idx: cuint, phase: bool) {.cdecl.} =
  let box = cast[PropagatorCtxBox](ctx)
  if box.handlers.decide != nil:
    let prev = currentBox
    currentBox = box
    let eAst = wrap[Z3AnyAst](box.ctx, t)
    let p = if phase: 1 else: -1
    box.handlers.decide(cb, eAst, uint(idx), p)
    currentBox = prev

# ---------------------------------------------------------------------------
# newPropagator
# ---------------------------------------------------------------------------

proc newPropagator*(s: Z3Solver, handlers: Z3PropagatorHandlers): Z3Propagator =
  ## Allocate a `PropagatorCtxBox`, register it with `s` via
  ## `Z3_solver_propagate_init`, and return the public `Z3Propagator` handle.
  ##
  ## The `box` is heap-allocated and GC-rooted through the returned
  ## `Z3Propagator` ref, which keeps it alive for the full duration of any
  ## subsequent `s.check()` invocations.
  ##
  ## Registration order follows ADR-N0004:
  ## 1. `Z3_solver_propagate_init` (push + pop + fresh) — mandatory.
  ## 2. Optional callbacks registered only when the handler is non-nil,
  ##    avoiding unnecessary overhead on Z3's callback dispatch.
  let box = PropagatorCtxBox(handlers: handlers, ctx: s.ctx, solver: s)
  # No GC_ref needed: `Z3Propagator` holds `box` as a `ref` field, giving
  # ORC the reachability path (ADR-N0004 v3). The extra GC_ref was redundant
  # and caused a leak because it was never matched with a GC_unref.
  let rawCtx    = cast[pointer](box)

  # Mandatory: push / pop / fresh
  Z3_solver_propagate_init(s.ctx.raw, s.raw, rawCtx,
                           propagatorPushShim,
                           propagatorPopShim,
                           propagatorFreshShim)

  # Optional callbacks — register only when provided
  if handlers.fixed != nil:
    Z3_solver_propagate_fixed(s.ctx.raw, s.raw, propagatorFixedShim)
  if handlers.final != nil:
    Z3_solver_propagate_final(s.ctx.raw, s.raw, propagatorFinalShim)
  if handlers.eq != nil:
    Z3_solver_propagate_eq(s.ctx.raw, s.raw, propagatorEqShim)
  if handlers.diseq != nil:
    Z3_solver_propagate_diseq(s.ctx.raw, s.raw, propagatorDiseqShim)
  if handlers.created != nil:
    Z3_solver_propagate_created(s.ctx.raw, s.raw, propagatorCreatedShim)
  if handlers.decide != nil:
    Z3_solver_propagate_decide(s.ctx.raw, s.raw, propagatorDecideShim)

  Z3Propagator(box: box, solver: s, ctx: s.ctx)

# ---------------------------------------------------------------------------
# register / register_cb — register expressions for propagation events
# ---------------------------------------------------------------------------

proc register*[T: Z3Term](p: Z3Propagator, e: T) =
  ## Register expression `e` for propagation events (fixed / eq / diseq).
  ## Call outside an active callback. Once registered, Z3 will invoke the
  ## relevant handler whenever it assigns or equates `e`.
  Z3_solver_propagate_register(p.ctx.raw, p.solver.raw, e.raw)

proc registerCb*[T: Z3Term](cb: Z3SolverCallback, ctx: Z3Context, e: T) =
  ## Like `register` but callable from within a callback (uses the callback
  ## context rather than the solver handle).
  Z3_solver_propagate_register_cb(ctx.raw, cb, e.raw)

# ---------------------------------------------------------------------------
# consequence — assert a theory consequence inside a callback
# ---------------------------------------------------------------------------

proc consequence*(cb: Z3SolverCallback, lits: seq[Z3AnyAst],
                  eqs: seq[(Z3AnyAst, Z3AnyAst)], conseq: Z3AnyAst) =
  ## Assert that `conseq` follows from the premises `lits` (fixed literals)
  ## and `eqs` (pairs of equal ASTs). Valid only inside a callback; the
  ## context is recovered from the thread-local `currentBox`.
  ##
  ## `eqs` is a seq of `(lhs, rhs)` tuples — the tuple type enforces the
  ## pairing invariant at compile time (no runtime doAssert needed).
  ## `Z3_solver_propagate_consequence` takes separate lhs/rhs arrays;
  ## they are split internally just before the FFI call.
  doAssert currentBox != nil,
    "consequence: called outside a propagator callback (currentBox is nil)"
  let ctx = currentBox.ctx

  var fixedRaws = newSeq[RawZ3Ast](lits.len)
  for i, l in lits:
    fixedRaws[i] = l.raw

  let numEqs = eqs.len
  var eqLhs  = newSeq[RawZ3Ast](numEqs)
  var eqRhs  = newSeq[RawZ3Ast](numEqs)
  for i, pair in eqs:
    eqLhs[i] = pair[0].raw
    eqRhs[i] = pair[1].raw

  let fixedPtr: ptr UncheckedArray[RawZ3Ast] =
    if fixedRaws.len > 0:
      cast[ptr UncheckedArray[RawZ3Ast]](addr fixedRaws[0])
    else: nil
  let lhsPtr: ptr UncheckedArray[RawZ3Ast] =
    if numEqs > 0: cast[ptr UncheckedArray[RawZ3Ast]](addr eqLhs[0])
    else: nil
  let rhsPtr: ptr UncheckedArray[RawZ3Ast] =
    if numEqs > 0: cast[ptr UncheckedArray[RawZ3Ast]](addr eqRhs[0])
    else: nil

  discard Z3_solver_propagate_consequence(
    ctx.raw, cb,
    cuint(fixedRaws.len), fixedPtr,
    cuint(numEqs), lhsPtr, rhsPtr,
    conseq.raw)

# ---------------------------------------------------------------------------
# nextSplit — override Z3's next decision from within a decide callback
# ---------------------------------------------------------------------------

proc nextSplit*(cb: Z3SolverCallback, t: Z3AnyAst, idx: uint, phase: int) =
  ## Override the next decision variable and phase. Call from within a
  ## `decide` handler. `phase` should be -1 (false), 0 (undef), or 1 (true),
  ## matching `Z3LBool`.
  ##
  ## Returns false internally if `t` is already assigned; the return value
  ## is not surfaced here since there is no meaningful action the caller can
  ## take in that case.
  doAssert currentBox != nil,
    "nextSplit: called outside a propagator callback (currentBox is nil)"
  let ctx   = currentBox.ctx
  let lbool = Z3LBool(phase)
  discard Z3_solver_next_split(ctx.raw, cb, t.raw, cuint(idx), lbool)

# ---------------------------------------------------------------------------
# propagateConflict — assert a contradiction inside a callback
# ---------------------------------------------------------------------------

proc propagateConflict*(cb: Z3SolverCallback, lits: seq[Z3AnyAst],
                        eqs: seq[(Z3AnyAst, Z3AnyAst)] = @[]) =
  ## Assert a contradiction (UNSAT) by propagating `false` as the consequence
  ## of the given premises. Equivalent to calling `consequence` with
  ## `conseq = mkFalse(ctx)`.
  ##
  ## `lits` — fixed literals that, together with `eqs`, imply contradiction.
  ## `eqs`  — equal pairs `(lhs, rhs)` that, together with `lits`, imply
  ##           contradiction. Defaults to empty (most common case).
  ##
  ## Valid only inside a callback; the context is recovered from the
  ## thread-local `currentBox`.
  doAssert currentBox != nil,
    "propagateConflict: called outside a propagator callback (currentBox is nil)"
  let ctx = currentBox.ctx
  let falseLit = mkFalse(ctx)
  consequence(cb, lits, eqs, toAnyAst(falseLit))

# ---------------------------------------------------------------------------
# clearSubBoxes — release accumulated sub-solver boxes
# ---------------------------------------------------------------------------

proc clearSubBoxes*(p: Z3Propagator) =
  ## Release accumulated sub-solver `PropagatorCtxBox` entries.
  ##
  ## Safe to call only OUTSIDE an active `check()` — calling during a callback
  ## invalidates Z3 pointers. Sub-boxes are also released automatically when
  ## `p` is collected (ORC drops them with the seq); this proc is for explicit
  ## eager cleanup only.
  p.box.subBoxes.setLen(0)

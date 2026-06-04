## N8.4a — Propagator FFI surface smoke tests.
##
## Tests confirm:
##  1. All eight callback typedefs compile (no-op proc declarations of each shape).
##  2. `Z3_solver_propagate_init` is callable with nil function pointers and
##     does not crash.
##  3. All remaining FFI entries link (compilation succeeds).
##
## No semantic tests — those land in N8.4b with the typed Z3Propagator wrapper.

import std/unittest
import z3/ffi

# ---------------------------------------------------------------------------
# No-op {.cdecl.} procs — one for each callback typedef shape.
# These confirm the type definitions are callable across the C ABI boundary.
# ---------------------------------------------------------------------------

proc noopPush(ctx: pointer, cb: RawZ3PropagatorCtxBox) {.cdecl.} =
  discard

proc noopPop(ctx: pointer, cb: RawZ3PropagatorCtxBox, numScopes: cuint) {.cdecl.} =
  discard

proc noopFresh(ctx: pointer, newContext: RawZ3Context): pointer {.cdecl.} =
  result = nil

proc noopFixed(ctx: pointer, cb: RawZ3PropagatorCtxBox,
               t: RawZ3Ast, value: RawZ3Ast) {.cdecl.} =
  discard

proc noopEq(ctx: pointer, cb: RawZ3PropagatorCtxBox,
            s: RawZ3Ast, t: RawZ3Ast) {.cdecl.} =
  discard

proc noopFinal(ctx: pointer, cb: RawZ3PropagatorCtxBox) {.cdecl.} =
  discard

proc noopCreated(ctx: pointer, cb: RawZ3PropagatorCtxBox, t: RawZ3Ast) {.cdecl.} =
  discard

proc noopDecide(ctx: pointer, cb: RawZ3PropagatorCtxBox,
                t: RawZ3Ast, idx: cuint, phase: bool) {.cdecl.} =
  discard

# ---------------------------------------------------------------------------

suite "N8.4a — Propagator FFI: callback typedef shapes compile":

  test "Z3PropagatorPushEh: no-op proc declared without error":
    let fn: Z3PropagatorPushEh = noopPush
    check fn != nil

  test "Z3PropagatorPopEh: no-op proc declared without error":
    let fn: Z3PropagatorPopEh = noopPop
    check fn != nil

  test "Z3PropagatorFreshEh: no-op proc declared without error":
    let fn: Z3PropagatorFreshEh = noopFresh
    check fn != nil

  test "Z3PropagatorFixedEh: no-op proc declared without error":
    let fn: Z3PropagatorFixedEh = noopFixed
    check fn != nil

  test "Z3PropagatorEqEh (eq): no-op proc declared without error":
    let fn: Z3PropagatorEqEh = noopEq
    check fn != nil

  test "Z3PropagatorEqEh (diseq shares same type): no-op proc declared without error":
    # diseq reuses Z3PropagatorEqEh per ADR-N0004 / z3_api.h
    let fn: Z3PropagatorEqEh = noopEq
    check fn != nil

  test "Z3PropagatorFinalEh: no-op proc declared without error":
    let fn: Z3PropagatorFinalEh = noopFinal
    check fn != nil

  test "Z3PropagatorCreatedEh: no-op proc declared without error":
    let fn: Z3PropagatorCreatedEh = noopCreated
    check fn != nil

  test "Z3PropagatorDecideEh: no-op proc declared without error":
    let fn: Z3PropagatorDecideEh = noopDecide
    check fn != nil

suite "N8.4a — Propagator FFI: Z3_solver_propagate_init smoke":

  test "Z3_solver_propagate_init with no-op callbacks does not crash":
    ## Register concrete no-op callbacks and do not query the solver.
    ## Z3 stores the callbacks but never fires them without a solve call,
    ## so no segfault should occur. Tests the registration path + cleanup.
    discard loadZ3()
    let cfg = Z3_mk_config()
    let c = Z3_mk_context_rc(cfg)
    let s = Z3_mk_solver(c)
    Z3_solver_inc_ref(c, s)
    Z3_solver_propagate_init(c, s, nil, noopPush, noopPop, noopFresh)
    Z3_solver_dec_ref(c, s)
    Z3_del_context(c)
    Z3_del_config(cfg)
    check true

suite "N8.4a — Propagator FFI: remaining entries link":
  ## Taking the address of a softlink-dynlib proc yields a nimcall proc, not
  ## a cdecl proc — so we verify linkage by casting to pointer and checking
  ## non-nil. Compilation + link success is the substance of these tests.

  test "Z3_solver_propagate_fixed links":
    check cast[pointer](Z3_solver_propagate_fixed) != nil

  test "Z3_solver_propagate_final links":
    check cast[pointer](Z3_solver_propagate_final) != nil

  test "Z3_solver_propagate_eq links":
    check cast[pointer](Z3_solver_propagate_eq) != nil

  test "Z3_solver_propagate_diseq links":
    check cast[pointer](Z3_solver_propagate_diseq) != nil

  test "Z3_solver_propagate_created links":
    check cast[pointer](Z3_solver_propagate_created) != nil

  test "Z3_solver_propagate_decide links":
    check cast[pointer](Z3_solver_propagate_decide) != nil

  test "Z3_solver_next_split links":
    check cast[pointer](Z3_solver_next_split) != nil

  test "Z3_solver_propagate_declare links":
    check cast[pointer](Z3_solver_propagate_declare) != nil

  test "Z3_solver_propagate_register links":
    check cast[pointer](Z3_solver_propagate_register) != nil

  test "Z3_solver_propagate_register_cb links":
    check cast[pointer](Z3_solver_propagate_register_cb) != nil

  test "Z3_solver_propagate_consequence links":
    check cast[pointer](Z3_solver_propagate_consequence) != nil

## N7.8 — Fixedpoint callback FFI stubs.
##
## Smoke tests for the four raw-pointer wrapper procs:
##   `init`, `setReduceAssignCallback`, `setReduceAppCallback`, `addCallback`
##
## Typed-closure wrappers are explicitly deferred; these tests confirm
## the raw {.cdecl.} function-pointer surface compiles, links, and
## doesn't crash when called with concrete no-op callbacks.

import std/unittest
import z3

# ---------------------------------------------------------------------------
# Concrete no-op callbacks for the non-nil smoke tests.
# All must be {.cdecl.} so they can cross the C ABI boundary.
# ---------------------------------------------------------------------------

proc noopReduceAssign(state: pointer, decl: RawZ3FuncDecl,
                      numIn: cuint, inArgs: pointer,
                      numOut: cuint, outArgs: pointer)
    {.cdecl.} =
  discard

proc noopReduceApp(state: pointer, decl: RawZ3FuncDecl,
                   numArgs: cuint, args: pointer,
                   res: ptr RawZ3Ast)
    {.cdecl.} =
  discard

proc noopNewLemma(state: pointer, lemma: RawZ3Ast, level: cuint) {.cdecl.} =
  discard

proc noopPredecessor(state: pointer) {.cdecl.} =
  discard

proc noopUnfold(state: pointer) {.cdecl.} =
  discard

# ---------------------------------------------------------------------------

suite "Z3Fixedpoint N7.8 — callback stubs: nil smoke":
  test "init(fp, nil) compiles and does not raise":
    let ctx = newContext()
    let fp  = newFixedpoint()
    fp.init(nil)
    check true

  test "setReduceAssignCallback(fp, nil, nil) compiles and does not raise":
    let ctx = newContext()
    let fp  = newFixedpoint()
    fp.setReduceAssignCallback(nil, nil)
    check true

  test "setReduceAppCallback(fp, nil, nil) compiles and does not raise":
    let ctx = newContext()
    let fp  = newFixedpoint()
    fp.setReduceAppCallback(nil, nil)
    check true

  test "addCallback(fp, nil, nil, nil, nil) compiles and does not raise":
    let ctx = newContext()
    let fp  = newFixedpoint()
    fp.addCallback(nil, nil, nil, nil)
    check true

suite "Z3Fixedpoint N7.8 — callback stubs: non-nil callbacks":
  test "setReduceAssignCallback with a no-op cdecl proc — Z3 accepts it":
    let ctx = newContext()
    let fp  = newFixedpoint()
    fp.init(nil)
    fp.setReduceAssignCallback(nil, noopReduceAssign)
    check true

  test "setReduceAppCallback with a no-op cdecl proc — Z3 accepts it":
    let ctx = newContext()
    let fp  = newFixedpoint()
    fp.init(nil)
    fp.setReduceAppCallback(nil, noopReduceApp)
    check true

  test "addCallback with no-op cdecl procs + datalog query completes":
    ## Register all three no-op callbacks, run a trivial datalog query;
    ## Z3 must not segfault or raise. The callbacks are never fired
    ## by the datalog engine for a simple ground-fact query, but the
    ## registration path (including `init`) must be exercised without
    ## crashing.
    ##
    ## The datalog engine requires finite-domain sorts; we use Z3BitVec[32]
    ## (matching the pattern in tfixedpoint_extra.nim's addFact tests).
    let ctx = newContext()
    let fp  = newFixedpoint()
    let p   = newParams()
    p.set("fp.engine", "datalog")
    fp.setParams(p)

    fp.init(nil)
    fp.addCallback(nil, noopNewLemma, noopPredecessor, noopUnfold)

    let rel = mkFuncDecl[(Z3BitVec[32],), Z3Bool]("cb_rel")
    fp.registerRelation(rel)
    fp.addFact(rel, @[1u])

    let status = fp.query(rel(mkBitVec[32](1)))
    check status == zsSat

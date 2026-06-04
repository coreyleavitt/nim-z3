## Tests for `emitOpaqueOps` macro — verifies that `isNil`, `==`, and `!=`
## work correctly for both existing opaque handle types and the four new
## raw handle types added in N0.1 (`RawZ3AstMap`, `RawZ3RcfNum`,
## `RawZ3Simplifier`, `RawZ3PropagatorCtxBox`).
##
## Strategy: We can exercise the *procs* (isNil, ==, !=) purely at the
## Nim-type level without actually calling into libz3 for the new types
## (which have no FFI bindings yet). For existing types we do a minimal
## live check (load + mk_config) to confirm a real non-nil handle passes
## the isNil gate correctly.

import std/unittest
import softlink
import z3

suite "ffi opaque ops — pointer semantics (existing types)":
  test "RawZ3Config: non-nil handle passes isNil/==/!= correctly":
    discard loadZ3()
    let cfg = Z3_mk_config()
    check not cfg.isNil
    check cfg == cfg
    check not (cfg != cfg)
    Z3_del_config(cfg)

  test "RawZ3Solver: freshly created solver is not nil":
    discard loadZ3()
    let cfg = Z3_mk_config()
    let ctx = Z3_mk_context_rc(cfg)
    defer:
      Z3_del_context(ctx); Z3_del_config(cfg)
    let s = Z3_mk_solver(ctx)
    Z3_solver_inc_ref(ctx, s)
    check not s.isNil
    check s == s
    check not (s != s)
    Z3_solver_dec_ref(ctx, s)

suite "ffi opaque ops — nil value semantics (existing types)":
  test "RawZ3Config nil value: isNil returns true":
    let nilCfg = default(RawZ3Config)
    check nilCfg.isNil
    check nilCfg == nilCfg
    check not (nilCfg != nilCfg)

  test "RawZ3Solver nil value: isNil returns true":
    let nilS = default(RawZ3Solver)
    check nilS.isNil

suite "ffi opaque ops — new N0.1 handle types (nil-value / type-level)":
  ## These types have no FFI bindings yet; we exercise only the ops
  ## that `emitOpaqueOps` generates, using zero-value instances.

  test "RawZ3AstMap: nil default; isNil/==/!= compile and behave":
    let x = default(RawZ3AstMap)
    check x.isNil
    check x == x
    check not (x != x)

  test "RawZ3RcfNum: nil default; isNil/==/!= compile and behave":
    let x = default(RawZ3RcfNum)
    check x.isNil
    check x == x
    check not (x != x)

  test "RawZ3Simplifier: nil default; isNil/==/!= compile and behave":
    let x = default(RawZ3Simplifier)
    check x.isNil
    check x == x
    check not (x != x)

  test "RawZ3PropagatorCtxBox: nil default; isNil/==/!= compile and behave":
    let x = default(RawZ3PropagatorCtxBox)
    check x.isNil
    check x == x
    check not (x != x)

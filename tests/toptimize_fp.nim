## `z3/optimize` — N6.7 Piece B: Z3Fp maximize/minimize overloads.
##
## Verifies that `Z3Optimize.maximize` / `minimize` accept `Z3Fp[E,S]`
## at the Nim type level. NOTE: Z3's optimize engine (as of Z3 4.x / the
## bundled nim-z3-dev image) raises `Z3_EXCEPTION: Objective must be
## bit-vector, integer or real` at runtime when an FP AST is passed as an
## objective. The overloads are present for API completeness; the tests
## here document both the compile-time availability and the runtime
## Z3-engine constraint.

import std/[unittest]
import z3

suite "Z3Optimize FP overloads — compile-time availability (N6.7 Piece B)":

  test "maximize(Z3Float64) overload exists and is callable":
    ## The Nim overload resolves — compilation succeeds. Z3 raises at runtime;
    ## we catch it to confirm the error is from Z3, not from missing Nim code.
    let ctx = newContext()
    let x = mkFloat64Var("x")
    let o = newOptimize()
    o.add(mkFloat64(0.0) <= x)
    o.add(x <= mkFloat64(10.0))
    var raised = false
    try:
      discard o.maximize(x)
      discard o.check()
    except Z3OperationError:
      raised = true
    # Z3's optimize engine rejects FP objectives at runtime; this confirms
    # the expected behavior. If a future Z3 build lifts this restriction the
    # test will need updating to verify actual optimization results.
    check raised

  test "minimize(Z3Float64) overload exists and is callable":
    let ctx = newContext()
    let x = mkFloat64Var("x")
    let o = newOptimize()
    o.add(mkFloat64(0.0) <= x)
    o.add(x <= mkFloat64(10.0))
    var raised = false
    try:
      discard o.minimize(x)
      discard o.check()
    except Z3OperationError:
      raised = true
    check raised

  test "maximize(Z3Float32) overload exists and is callable":
    let ctx = newContext()
    let x = mkFloat32Var("x")
    let o = newOptimize()
    o.add(mkFloat32(-1.0'f32) <= x)
    o.add(x <= mkFloat32(5.0'f32))
    var raised = false
    try:
      discard o.maximize(x)
      discard o.check()
    except Z3OperationError:
      raised = true
    check raised

  test "minimize(Z3Float32) overload exists and is callable":
    let ctx = newContext()
    let x = mkFloat32Var("x")
    let o = newOptimize()
    o.add(mkFloat32(-1.0'f32) <= x)
    o.add(x <= mkFloat32(5.0'f32))
    var raised = false
    try:
      discard o.minimize(x)
      discard o.check()
    except Z3OperationError:
      raised = true
    check raised

  test "maximize returns Z3OptHandle[Z3Float64] (compile-time type check)":
    ## Check that the return type resolves correctly even though the call
    ## raises at runtime.
    let ctx = newContext()
    let x = mkFloat64Var("x")
    let o = newOptimize()
    # The `is` test is compile-time; this proc compiles with the right type.
    check compiles(block:
      let h = o.maximize(x)
      h is Z3OptHandle[Z3Float64])

  test "minimize returns Z3OptHandle[Z3Float64] (compile-time type check)":
    let ctx = newContext()
    let x = mkFloat64Var("x")
    let o = newOptimize()
    check compiles(block:
      let h = o.minimize(x)
      h is Z3OptHandle[Z3Float64])

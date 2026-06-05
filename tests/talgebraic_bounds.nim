## `z3/algebraic` bound-variable tests -- mkBoundReal.
##
## `mkBoundReal(ctx, index)` returns a `Z3Real` (NOT `Z3AlgebraicNum`).
## It is the polynomial indeterminate for `algebraicRoots` / `algebraicEval`.

import std/unittest
import z3

suite "mkBoundReal -- basic":
  test "mkBoundReal returns a Z3Real (not Z3AlgebraicNum)":
    let ctx = newContext()
    let x: Z3Real = mkBoundReal(ctx, 0)
    check not x.raw.isNil

  test "mkBoundReal index 0 can be used in arithmetic":
    let ctx = newContext()
    let x = mkBoundReal(ctx, 0)
    let p = x * x - mkReal(ctx, 2)
    check not p.raw.isNil

  test "mkBoundReal index 1 is distinct from index 0":
    let ctx = newContext()
    let x0 = mkBoundReal(ctx, 0)
    let x1 = mkBoundReal(ctx, 1)
    check not astEqual(x0, x1)

suite "mkBoundReal -- used with algebraicRoots":
  test "x^2 - 2 has 2 real roots":
    let ctx = newContext()
    let x = mkBoundReal(ctx, 0)
    let p = x * x - mkReal(ctx, 2)
    let roots = algebraicRoots(p, [])
    check roots.len == 2

  test "x^2 - 2 roots are all algebraic values":
    let ctx = newContext()
    let x = mkBoundReal(ctx, 0)
    let p = x * x - mkReal(ctx, 2)
    let roots = algebraicRoots(p, [])
    for r in roots:
      check algebraicIsValue(r)

  test "x^3 - 2 has exactly 1 real root (cbrt(2))":
    let ctx = newContext()
    let x = mkBoundReal(ctx, 0)
    let p = x * x * x - mkReal(ctx, 2)
    let roots = algebraicRoots(p, [])
    check roots.len == 1

  test "x^2 + 1 has no real roots":
    let ctx = newContext()
    let x = mkBoundReal(ctx, 0)
    let p = x * x + mkReal(ctx, 1)
    let roots = algebraicRoots(p, [])
    check roots.len == 0

  test "roots of x^2 - 2 satisfy p(r) == 0 via algebraicEval":
    let ctx = newContext()
    let x = mkBoundReal(ctx, 0)
    let p = x * x - mkReal(ctx, 2)
    let roots = algebraicRoots(p, [])
    check roots.len == 2
    for r in roots:
      check algebraicEval(p, [r]) == 0

suite "mkBoundReal -- string representation":
  test "mkBoundReal(ctx, 0) has non-empty string form":
    let ctx = newContext()
    let x = mkBoundReal(ctx, 0)
    let s = $x
    check s.len > 0

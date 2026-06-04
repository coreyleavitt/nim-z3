## `z3/simplifier` tests — N8.7
##
## Covers: mkSimplifier, addSimplifier, andThen (simplifier composition),
## usingParams, getParamDescrs, getHelp, $, round-trip sat check.

import std/[unittest]
import z3
import z3/simplifier

suite "Z3Simplifier — construction":
  test "mkSimplifier returns non-nil":
    let ctx = newContext()
    let simp = mkSimplifier(ctx, "simplify")
    check not simp.isNil
    check not simp.raw.isNil

  test "mkSimplifier current-context overload":
    let ctx = newContext()
    let simp = mkSimplifier("simplify")
    check not simp.isNil

  test "$ returns non-empty string":
    let ctx = newContext()
    let simp = mkSimplifier(ctx, "simplify")
    let s = $simp
    check s.len > 0

suite "Z3Simplifier — addSimplifier":
  test "addSimplifier on a solver returns non-nil":
    let ctx = newContext()
    let s = newSolver(ctx)
    let simp = mkSimplifier(ctx, "simplify")
    let s2 = addSimplifier(s, simp)
    check not s2.isNil

  test "solver with simplifier still solves sat":
    let ctx = newContext()
    let s = addSimplifier(newSolver(ctx), mkSimplifier(ctx, "simplify"))
    let x = mkIntVar("x")
    s.add(x > mkInt(0))
    check s.check() == zsSat

  test "solver with simplifier still solves unsat":
    let ctx = newContext()
    let s = addSimplifier(newSolver(ctx), mkSimplifier(ctx, "simplify"))
    let x = mkIntVar("x")
    s.add(x > mkInt(5))
    s.add(x < mkInt(3))
    check s.check() == zsUnsat

suite "Z3Simplifier — andThen composition":
  test "andThen returns non-nil":
    let ctx = newContext()
    let s1 = mkSimplifier(ctx, "simplify")
    let s2 = mkSimplifier(ctx, "simplify")
    let composed = andThen(s1, s2)
    check not composed.isNil

  test "composed simplifier can be attached to solver":
    let ctx = newContext()
    let s1 = mkSimplifier(ctx, "simplify")
    let s2 = mkSimplifier(ctx, "simplify")
    let composed = andThen(s1, s2)
    let slv = addSimplifier(newSolver(ctx), composed)
    let x = mkIntVar("x")
    slv.add(x > mkInt(0))
    check slv.check() == zsSat

suite "Z3Simplifier — params + schema":
  test "usingParams returns non-nil":
    let ctx = newContext()
    let simp = mkSimplifier(ctx, "simplify")
    let p = newParams(ctx)
    let simp2 = usingParams(simp, p)
    check not simp2.isNil

  test "getParamDescrs returns non-nil":
    let ctx = newContext()
    let simp = mkSimplifier(ctx, "simplify")
    let pd = simp.getParamDescrs()
    check not pd.isNil

  test "getHelp returns non-empty string":
    let ctx = newContext()
    let simp = mkSimplifier(ctx, "simplify")
    let h = simp.getHelp()
    check h.len > 0

suite "Z3Simplifier — round-trip sat check":
  test "simplify simplifier preserves sat result":
    ## Build a solver with simplify simplifier, assert a simple
    ## satisfiable problem, verify same answer as plain solver.
    let ctx = newContext()
    let s = addSimplifier(newSolver(ctx), mkSimplifier(ctx, "simplify"))
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    s.add(x > mkInt(0))
    s.add(y > mkInt(0))
    s.add(x + y < mkInt(100))
    check s.check() == zsSat

## N8.1 — Solver trail / units / nonUnits / levels / setInitialValue
##
## Tests for the SAT-engine introspection surface added by RFC N8.1.
## trail / units / nonUnits / levels require `newSimpleSolver` (the raw
## CDCL engine); the default `newSolver` wraps tactics and cannot expose
## trail state (Z3 raises Z3_EXCEPTION if you try).

import std/unittest
import z3

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

proc satSetup(): (Z3Context, Z3Solver, Z3Bool, Z3Bool) =
  ## Use `newSimpleSolver` so trail/units/levels introspection works.
  let ctx = newContext()
  let s   = newSimpleSolver()
  let p   = mkBoolVar("p")
  let q   = mkBoolVar("q")
  # p OR q — trivially satisfiable; gives CDCL something to propagate.
  s.add(p or q)
  doAssert s.check() == zsSat
  (ctx, s, p, q)

# ---------------------------------------------------------------------------
# trail / units / nonUnits
# ---------------------------------------------------------------------------

suite "Z3Solver — trail / units / nonUnits (N8.1)":

  test "trail returns a non-nil Z3AstVector after sat check":
    let (ctx, s, p, q) = satSetup()
    let t = s.trail()
    check not t.raw.isNil

  test "units returns a non-nil Z3AstVector after sat check":
    let (ctx, s, p, q) = satSetup()
    let u = s.units()
    check not u.raw.isNil

  test "nonUnits returns a non-nil Z3AstVector after sat check":
    let (ctx, s, p, q) = satSetup()
    let nu = s.nonUnits()
    check not nu.raw.isNil

  test "trail + units + nonUnits are each bound to the solver's context":
    let (ctx, s, p, q) = satSetup()
    check s.trail().ctx == ctx
    check s.units().ctx == ctx
    check s.nonUnits().ctx == ctx

# ---------------------------------------------------------------------------
# levels
# ---------------------------------------------------------------------------

suite "Z3Solver — levels (N8.1)":

  test "levels on units returns seq[uint] of correct length":
    ## newSimpleSolver required for trail/levels introspection.
    let ctx = newContext()
    let s   = newSimpleSolver()
    let p   = mkBoolVar("p")
    let q   = mkBoolVar("q")
    s.add(p or q)
    doAssert s.check() == zsSat
    let u = s.units()
    let lvs = s.levels(u)
    check lvs.len == u.len

  test "levels on empty vector returns empty seq":
    let ctx = newContext()
    let s   = newSimpleSolver()
    s.add(mkTrue())
    doAssert s.check() == zsSat
    let empty = newAstVector(ctx)
    let lvs   = s.levels(empty)
    check lvs.len == 0

# ---------------------------------------------------------------------------
# setInitialValue
# ---------------------------------------------------------------------------

suite "Z3Solver — setInitialValue (N8.1)":

  test "setInitialValue(x, 42) does not crash before check":
    let ctx = newContext()
    let s   = newSolver()
    let x   = mkIntVar("x")
    s.add(x > mkInt(0))
    s.setInitialValue(x, mkInt(42))
    check s.check() == zsSat

  test "post-check model is valid after setInitialValue hint":
    let ctx = newContext()
    let s   = newSolver()
    let x   = mkIntVar("x")
    s.add(x > mkInt(0))
    s.add(x < mkInt(100))
    s.setInitialValue(x, mkInt(42))
    doAssert s.check() == zsSat
    let m = s.model()
    let v = m.evalInt(x)
    check v > 0
    check v < 100

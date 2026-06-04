## `z3/optimize` N7.6b tests — getStatistics, getAssertions, getObjectives,
## setInitialValue, getLowerAsVector, getUpperAsVector.
##
## Z3_optimize_register_model_eh is FFI-stub-only; no test.

import std/[unittest]
import z3

# ---------------------------------------------------------------------------
# getAssertions
# ---------------------------------------------------------------------------
suite "Z3Optimize — getAssertions":
  test "getAssertions returns vector with N constraints after adding N":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let o = newOptimize()
    o.add(x >= mkInt(0))
    o.add(y >= mkInt(0))
    o.add(x + y == mkInt(10))
    let v = o.getAssertions()
    check v.len == 3

  test "getAssertions returns empty vector on fresh optimiser":
    let ctx = newContext()
    let o = newOptimize()
    let v = o.getAssertions()
    check v.len == 0

# ---------------------------------------------------------------------------
# getObjectives
# ---------------------------------------------------------------------------
suite "Z3Optimize — getObjectives":
  test "getObjectives returns vector with K objectives after K maximize calls":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let o = newOptimize()
    o.add(x <= mkInt(10))
    o.add(y <= mkInt(5))
    discard o.maximize(x)
    discard o.maximize(y)
    let v = o.getObjectives()
    check v.len == 2

  test "getObjectives counts addSoft objective":
    let ctx = newContext()
    let x = mkIntVar("x")
    let o = newOptimize()
    discard o.addSoft(x == mkInt(1))
    let v = o.getObjectives()
    check v.len >= 1

# ---------------------------------------------------------------------------
# getStatistics
# ---------------------------------------------------------------------------
suite "Z3Optimize — getStatistics":
  test "getStatistics returns non-nil stats handle after check()":
    let ctx = newContext()
    let x = mkIntVar("x")
    let o = newOptimize()
    o.add(x <= mkInt(10))
    discard o.maximize(x)
    check o.check() == zsSat
    let s = o.getStatistics()
    # Z3Stats.len may be 0 on trivial problems but the handle is valid.
    # We check that the call doesn't crash and the object is renderable.
    discard ($s)
    check true

# ---------------------------------------------------------------------------
# setInitialValue
# ---------------------------------------------------------------------------
suite "Z3Optimize — setInitialValue":
  test "setInitialValue smoke: post-check yields valid result":
    ## Z3 treats the hint as a warm-start suggestion; it may be ignored
    ## but must not crash or invalidate the result.
    let ctx = newContext()
    let x = mkIntVar("x")
    let o = newOptimize()
    o.add(x >= mkInt(0))
    o.add(x <= mkInt(20))
    discard o.maximize(x)
    # Provide an initial-value hint before solving.
    o.setInitialValue(x.toAnyAst, mkInt(15).toAnyAst)
    check o.check() == zsSat
    let m = o.model()
    let xv = m.evalInt(x)
    check xv == 20

# ---------------------------------------------------------------------------
# getLowerAsVector / getUpperAsVector
# ---------------------------------------------------------------------------
suite "Z3Optimize — getLowerAsVector / getUpperAsVector":
  test "getLowerAsVector(0) returns non-empty vector after maximize check":
    let ctx = newContext()
    let x = mkIntVar("x")
    let o = newOptimize()
    o.add(x >= mkInt(3))
    o.add(x <= mkInt(10))
    discard o.maximize(x)
    check o.check() == zsSat
    let v = o.getLowerAsVector(0)
    check v.len > 0

  test "getUpperAsVector(0) returns non-empty vector after maximize check":
    let ctx = newContext()
    let x = mkIntVar("x")
    let o = newOptimize()
    o.add(x >= mkInt(3))
    o.add(x <= mkInt(10))
    discard o.maximize(x)
    check o.check() == zsSat
    let v = o.getUpperAsVector(0)
    check v.len > 0

  test "getUpperAsVector minimize: returns non-empty vector after minimize check":
    let ctx = newContext()
    let x = mkIntVar("x")
    let o = newOptimize()
    o.add(x >= mkInt(0))
    o.add(x <= mkInt(7))
    discard o.minimize(x)
    check o.check() == zsSat
    let v = o.getUpperAsVector(0)
    check v.len > 0

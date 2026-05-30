## `z3/optimize` tests — Z3Optimize with hard / soft constraints,
## maximize / minimize, upper / lower, push / pop, scoped multi-
## objective.

import std/[unittest]
import z3

suite "Z3Optimize — tracer":
  test "maximize x subject to x <= 10 yields upper 10":
    let ctx = newContext()
    let x = mkIntVar("x")
    let o = newOptimize()
    o.add(x <= mkInt(10))
    let h = o.maximize(x)
    check o.check() == zsSat
    check smtEquiv(h.upper, mkInt(10))

  test "minimize x subject to x >= 5 yields lower 5":
    let ctx = newContext()
    let x = mkIntVar("x")
    let o = newOptimize()
    o.add(x >= mkInt(5))
    let h = o.minimize(x)
    check o.check() == zsSat
    check smtEquiv(h.lower, mkInt(5))

suite "Z3Optimize — multi-objective":
  test "default lex mode: maximize x then y under x + y == 10":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let o = newOptimize()
    o.add(x >= mkInt(0))
    o.add(y >= mkInt(0))
    o.add(x + y == mkInt(10))
    let hx = o.maximize(x)
    let hy = o.maximize(y)
    check o.check() == zsSat
    # Z3 defaults to lexicographic (priority="lex"): maximise x to 10
    # first, then maximise y subject to x's optimum, leaving y at 0.
    # Box/Pareto modes require setting Z3_optimize_set_params with a
    # typed Z3Params object — deferred to v0.2 step-1-carryover §8.
    check smtEquiv(hx.upper, mkInt(10))
    check smtEquiv(hy.upper, mkInt(0))

  test "model satisfies hard constraints":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let o = newOptimize()
    o.add(x >= mkInt(0))
    o.add(y >= mkInt(0))
    o.add(x + y == mkInt(10))
    discard o.maximize(x)
    check o.check() == zsSat
    let m = o.model()
    let xv = m.evalInt(x)
    let yv = m.evalInt(y)
    check xv >= 0 and yv >= 0 and xv + yv == 10

suite "Z3Optimize — BV objectives":
  test "maximize x: BV[8] subject to bvult(x, 100) → upper is 99":
    let ctx = newContext()
    let x = mkBitVecVar[8]("x")
    let o = newOptimize()
    o.add(bvult(x, mkBitVec(100'u8, 8)))
    let h = o.maximize(x)
    check o.check() == zsSat
    check h.upper is Z3BitVec[8]
    check smtEquiv(h.upper, mkBitVec(99'u8, 8))

  test "minimize x: BV[8] subject to bvugt(x, 200) → lower is 201":
    let ctx = newContext()
    let x = mkBitVecVar[8]("x")
    let o = newOptimize()
    o.add(bvugt(x, mkBitVec(200'u8, 8)))
    let h = o.minimize(x)
    check o.check() == zsSat
    check smtEquiv(h.lower, mkBitVec(201'u8, 8))

suite "Z3Optimize — soft constraints":
  test "three conflicting soft constraints: at most one survives":
    # x can't simultaneously equal 1, 2, and 3 — Z3 picks one to
    # satisfy, leaving the other two violated.
    let ctx = newContext()
    let x = mkIntVar("x")
    let o = newOptimize()
    discard o.addSoft(x == mkInt(1))
    discard o.addSoft(x == mkInt(2))
    discard o.addSoft(x == mkInt(3))
    check o.check() == zsSat
    let m = o.model()
    let xv = m.evalInt(x)
    check xv == 1 or xv == 2 or xv == 3

  test "weighted soft constraint: higher weight wins":
    let ctx = newContext()
    let x = mkIntVar("x")
    let o = newOptimize()
    # Equal-weight conflict between x==1 and x==2 — Z3 picks one.
    # Then weight x==99 at 10.0 — heavy enough to dominate everything.
    discard o.addSoft(x == mkInt(1), weight = 1.0)
    discard o.addSoft(x == mkInt(2), weight = 1.0)
    discard o.addSoft(x == mkInt(99), weight = 10.0)
    check o.check() == zsSat
    let m = o.model()
    check m.evalInt(x) == 99

suite "Z3Optimize — push / pop":
  test "constraint asserted inside push/pop is forgotten on pop":
    let ctx = newContext()
    let x = mkIntVar("x")
    let o = newOptimize()
    o.add(x <= mkInt(100))
    let h = o.maximize(x)
    check o.check() == zsSat
    check smtEquiv(h.upper, mkInt(100))

    o.push()
    o.add(x <= mkInt(50))
    let h2 = o.maximize(x)
    check o.check() == zsSat
    check smtEquiv(h2.upper, mkInt(50))
    o.pop()

    # After pop, the inner constraint and inner objective are both
    # gone. Re-maximise to verify the outer bound is restored.
    let h3 = o.maximize(x)
    check o.check() == zsSat
    check smtEquiv(h3.upper, mkInt(100))

suite "Z3Optimize — reasonUnknown":
  test "reasonUnknown returns a string after any check":
    let ctx = newContext()
    let x = mkIntVar("x")
    let o = newOptimize()
    o.add(x == mkInt(0))
    discard o.check()
    # After a non-unknown check the value is unspecified but the call
    # must not crash.
    discard o.reasonUnknown()
    check true

suite "Z3Optimize — priority modes (setParams)":
  test "priority=box makes both objectives reach 10 independently":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let o = newOptimize()
    let p = newParams()
    p.set("priority", "box")
    o.setParams(p)
    o.add(x >= mkInt(0))
    o.add(y >= mkInt(0))
    o.add(x + y == mkInt(10))
    let hx = o.maximize(x)
    let hy = o.maximize(y)
    check o.check() == zsSat
    # Box mode: each objective gets its true maximum independently —
    # x can reach 10 (with y at 0), y can reach 10 (with x at 0).
    # Compare with the default lex test in this file where hy → 0.
    check smtEquiv(hx.upper, mkInt(10))
    check smtEquiv(hy.upper, mkInt(10))

  test "priority=pareto enumerates frontier points then returns unsat":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let o = newOptimize()
    let p = newParams()
    p.set("priority", "pareto")
    o.setParams(p)
    o.add(x >= mkInt(0))
    o.add(x <= mkInt(3))
    o.add(y >= mkInt(0))
    o.add(y <= mkInt(3))
    o.add(x + y >= mkInt(2))   # leave some interior so Pareto has
                               # multiple frontier points
    discard o.maximize(x)
    discard o.maximize(y)

    # Pareto: repeatedly call check() until it returns unsat.
    var frontier = 0
    while o.check() == zsSat:
      inc frontier
      if frontier > 100: break   # safety: never spin forever
    check frontier >= 1          # at least one Pareto-optimal point
    check frontier <= 100        # frontier eventually exhausted
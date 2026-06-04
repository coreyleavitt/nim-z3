## `z3/io` — parse-modify-serialize round-trip integration tests (N11.8).
##
## End-to-end integration exercising `z3/io`, `z3/translate`, and
## `z3/optimize` together across three sorts: arithmetic (Int/Real),
## bit-vectors, and floating-point.
##
## Each scenario follows the same spine:
##   1. Parse an SMT-LIB2 string into a solver / optimize.
##   2. Modify the loaded state (add a new constraint, push/pop, etc.).
##   3. Serialize back to SMT-LIB2 (`smt2Script` / `$`).
##   4. Re-parse the serialized form and verify SAT status is preserved.
##
## The translate scenario additionally verifies that assertions migrated
## across contexts with `translate` remain satisfiable in the target.

import std/[unittest, strutils]
import z3

# ---------------------------------------------------------------------------
# Helper — parse `source`, add each assertion to a fresh solver, check SAT.
# ---------------------------------------------------------------------------

proc checkSat(ctx: Z3Context, source: string): Z3Status =
  let s = newSolver(ctx)
  s.loadSmt2String source
  s.check()

# ============================================================================
# Arith (Int) — parse, modify, serialize, re-parse
# ============================================================================

suite "N11.8 round-trip — arith (Int)":

  test "parse Int constraint, add bound, serialize, re-parse: SAT preserved":
    ## Tracer: the simplest full-cycle case.
    ## Load  x > 0, add x < 100, round-trip through smt2Script.
    let ctx = newContext()
    let s = newSolver(ctx)
    s.loadSmt2String "(declare-const x Int) (assert (> x 0))"
    # Modify: add upper bound.
    let x = mkIntVar("x")
    s.add x < mkInt(100)
    check s.check() == zsSat

    # Serialize and re-parse.
    let script = smt2Script(s)
    check script.contains("check-sat")

    let ctx2 = newContext()
    let s2 = newSolver(ctx2)
    s2.loadSmt2String script
    check s2.check() == zsSat
    # Model satisfies both bounds.
    let m = s2.model()
    # We can't directly reach x from ctx2, but the script declares x,
    # so we re-declare via parseSmt2String to get a handle we can eval.
    let decl = mkIntVar("x")
    let xv = m.evalInt(decl)
    check xv > 0 and xv < 100

  test "parse contradictory Int constraints: round-trip stays UNSAT":
    let ctx = newContext()
    let s = newSolver(ctx)
    s.loadSmt2String "(declare-const x Int) (assert (> x 0))"
    let x = mkIntVar("x")
    s.add x < mkInt(0)
    check s.check() == zsUnsat

    let script = smt2Script(s)
    let ctx2 = newContext()
    let s2 = newSolver(ctx2)
    s2.loadSmt2String script
    check s2.check() == zsUnsat

  test "push/pop inside a loaded solver: outer frame SAT after pop":
    let ctx = newContext()
    let s = newSolver(ctx)
    s.loadSmt2String "(declare-const x Int) (assert (> x 0))"
    # Push a contradictory inner frame.
    let x = mkIntVar("x")
    s.push()
    s.add x < mkInt(0)
    check s.check() == zsUnsat
    s.pop()
    # Outer frame (x > 0) must be sat and serialize correctly.
    check s.check() == zsSat
    let script = smt2Script(s)
    let ctx2 = newContext()
    let s2 = newSolver(ctx2)
    s2.loadSmt2String script
    check s2.check() == zsSat

# ============================================================================
# BV sort — parse, modify, serialize, re-parse
# ============================================================================

suite "N11.8 round-trip — BV[8]":

  test "parse BV[8] constraint, add upper bound, round-trip: SAT preserved":
    let ctx = newContext()
    let s = newSolver(ctx)
    # x > 0 in unsigned BV[8] — `bvugt`
    s.loadSmt2String """
      (declare-const x (_ BitVec 8))
      (assert (bvugt x #x00))
    """
    # Modify: add x < 50 (unsigned).
    let x = mkBitVecVar[8]("x")
    s.add bvult(x, mkBitVec[8](50'u8))
    check s.check() == zsSat

    let script = smt2Script(s)
    check script.contains("BitVec")

    let ctx2 = newContext()
    let s2 = newSolver(ctx2)
    s2.loadSmt2String script
    check s2.check() == zsSat
    let xv = s2.model().evalUint(mkBitVecVar[8]("x"))
    check xv > 0 and xv < 50

  test "parse BV[16] equality, round-trip: UNSAT stays UNSAT":
    let ctx = newContext()
    let s = newSolver(ctx)
    s.loadSmt2String """
      (declare-const x (_ BitVec 16))
      (assert (= x #x000A))
    """
    let x = mkBitVecVar[16]("x")
    # x == 10 AND x == 20 is unsat.
    s.add x == mkBitVec[16](20'u16)
    check s.check() == zsUnsat

    let script = smt2Script(s)
    let ctx2 = newContext()
    let s2 = newSolver(ctx2)
    s2.loadSmt2String script
    check s2.check() == zsUnsat

# ============================================================================
# FP sort — parse, modify, serialize, re-parse
# ============================================================================

suite "N11.8 round-trip — FP (Float64)":

  test "parse Float64 isFinite+positive, add upper bound, round-trip: SAT":
    ## The SMT-LIB rendering of `isFinite(x) and (x > +0)` produced by
    ## `smt2Script` round-trips through `loadSmt2String`.  We add an upper
    ## bound in Nim, serialize, re-parse, and confirm SAT is preserved.
    let ctx = newContext()
    let x = mkFloat64Var("x")
    let s = newSolver(ctx)
    s.add isFinite(x)
    s.add x > mkFloat64(0.0)
    check s.check() == zsSat

    # Serialize — this is the "state after load" form.
    let script = smt2Script(s)
    check script.contains("FloatingPoint")

    # Re-parse and verify SAT.
    let ctx2 = newContext()
    let s2 = newSolver(ctx2)
    s2.loadSmt2String script
    check s2.check() == zsSat
    # Model has a positive finite float.
    let xv = s2.model().evalFloat64(mkFloat64Var("x"))
    check xv > 0.0

  test "parseSmt2String FP source → add NaN constraint → UNSAT round-trip":
    ## isFinite(x) is SAT; isFinite(x) AND isNaN(x) is UNSAT (NaN is
    ## not finite). Serialize the UNSAT state and confirm re-parse stays UNSAT.
    let ctx = newContext()
    # Start from the serialized SAT state.
    let satSrc = """
      (declare-fun x () (_ FloatingPoint 11 53))
      (assert (and (not (fp.isNaN x)) (not (fp.isInfinite x))))
      (assert (fp.gt x (_ +zero 11 53)))
    """
    let s = newSolver(ctx)
    s.loadSmt2String satSrc
    # Add an incompatible constraint: x must also be NaN.
    let x = mkFloat64Var("x")
    s.add isNaN(x)
    check s.check() == zsUnsat

    let script = smt2Script(s)
    let ctx2 = newContext()
    let s2 = newSolver(ctx2)
    s2.loadSmt2String script
    check s2.check() == zsUnsat

# ============================================================================
# Translate — cross-context preservation
# ============================================================================

suite "N11.8 round-trip — translate across contexts":

  test "arith: parse in ctx A, translate assertion to ctx B, SAT in both":
    ## Demonstrates the translate API as a cross-context preservation
    ## mechanism: parsed assertions migrate intact to a fresh context.
    let ctxA = newContext()
    let asserts = parseSmt2String(ctxA,
      "(declare-const x Int) (declare-const y Int) " &
      "(assert (> (+ x y) 5)) (assert (< x 10))")
    check asserts.len == 2

    let sA = newSolver(ctxA)
    for a in asserts: sA.add a
    check sA.check() == zsSat

    # Translate each assertion to ctxB and verify there too.
    let ctxB = newContext()
    check compatibleWith(ctxA, ctxB)
    let sB = newSolver(ctxB)
    for a in asserts:
      sB.add translate(a, ctxB)
    check sB.check() == zsSat
    # Models in both contexts are consistent with the bounds.
    let mA = sA.model()
    let xA = mA.evalInt(mkIntVar("x"))
    check xA < 10

    let mB = sB.model()
    let xB = mB.evalInt(mkIntVar("x"))
    check xB < 10

  test "BV: translate BV assertion cross-context, SAT preserved":
    let ctxA = newContext()
    let bv = mkBitVecVar[8]("b")
    let sA = newSolver(ctxA)
    sA.add bvult(bv, mkBitVec[8](100'u8))
    check sA.check() == zsSat

    let ctxB = newContext()
    let assertions = sA.getAssertions()
    let sB = newSolver(ctxB)
    for a in assertions:
      sB.add translate(a, ctxB)
    check sB.check() == zsSat
    let bv2 = mkBitVecVar[8]("b")
    check sB.model().evalUint(bv2) < 100

  test "model values from translated solver match original constraint family":
    ## After translating a solver to ctxB, the model witnesses in ctxB
    ## independently satisfy the same numeric property.
    let ctxA = newContext()
    let xA = mkIntVar("x")
    let sA = newSolver(ctxA)
    sA.add xA > mkInt(5)
    sA.add xA < mkInt(10)
    check sA.check() == zsSat

    let ctxB = newContext()
    let sB = sA.translate(ctxB)
    check sB.check() == zsSat
    check sB.getAssertions().len == 2
    let xB = mkIntVar("x")
    let xBv = sB.model().evalInt(xB)
    check xBv > 5 and xBv < 10

# ============================================================================
# Optimize — parse-modify-serialize
# ============================================================================

suite "N11.8 round-trip — Z3Optimize parse-modify-serialize":

  test "fromString + maximize + serialize via $ + re-parse: SAT preserved":
    ## `Z3Optimize.fromString` ingests an SMT-LIB2 script; `$` serializes
    ## current state (including objectives); `loadSmt2String` on a fresh
    ## solver re-checks satisfiability.
    let ctx = newContext()
    let o = newOptimize(ctx)
    o.fromString """
      (declare-const x Int)
      (assert (>= x 0))
      (assert (<= x 20))
    """
    let x = mkIntVar("x")
    let h = o.maximize(x)
    check o.check() == zsSat
    check smtEquiv(h.upper, mkInt(20))

    # Serialize optimiser state.
    let oStr = $o
    check oStr.len > 0

    # A plain solver re-parsing the hard constraints from the optimize
    # string representation can verify SAT (the objective directives
    # are ignored by the solver; the hard constraints survive).
    let ctx2 = newContext()
    let s2 = newSolver(ctx2)
    # parseSmt2String strips non-assertion forms; the hard constraints persist.
    let asserts = parseSmt2String(ctx2, oStr)
    check asserts.len >= 1
    for a in asserts: s2.add a
    check s2.check() == zsSat

  test "optimize fromString with UNSAT hard constraints: stays UNSAT":
    let ctx = newContext()
    let o = newOptimize(ctx)
    o.fromString """
      (declare-const x Int)
      (assert (> x 10))
      (assert (< x 5))
    """
    check o.check() == zsUnsat

  test "optimize push/pop inside parse-modify cycle":
    let ctx = newContext()
    let o = newOptimize(ctx)
    o.fromString "(declare-const x Int) (assert (>= x 0))"
    let x = mkIntVar("x")
    o.push()
    o.add x > mkInt(50)
    check o.check() == zsSat
    let m1 = o.model()
    check m1.evalInt(x) > 50
    o.pop()
    # After pop the x > 50 constraint is gone; x >= 0 is still present.
    o.add x == mkInt(3)
    check o.check() == zsSat
    check o.model().evalInt(x) == 3

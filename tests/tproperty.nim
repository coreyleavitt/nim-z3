## Property-based dogfooding via proptest. Step 11 of the
## IMPLEMENTATION_PLAN: we use proptest to stress-test the nim-z3
## wrapper's invariants — soundness, arithmetic equivalences,
## BV ↔ native-int agreement, SMT2 round-trip.
##
## Two flavours of property:
##
## - **Input-driven** — random `k` / `(a, b)` drives the test and
##   directly exercises real coverage (mkInt, bvadd wraparound, etc.).
## - **Shape-driven** — random Z3 expression *trees* (generated as
##   pure Nim ADT recipes and interpreted against a context) assert
##   algebraic laws hold for arbitrary tree shapes. Genuine PBT in
##   the shape space: every iteration exercises a different wrapper
##   code path.
##
## ## Context sharing across iterations
##
## Each `test` creates **one** Z3 context up front and shares it
## across every iteration of `forAll`. Z3's hash-consing keeps growth
## sub-linear in iteration count (duplicate ASTs collapse), so memory
## stays bounded; a per-iteration `newContext()` would otherwise churn
## a context per call and OOM the test process under depth-3 recipes.
## Wrapper ASTs are still iteration-local Nim refs and `=destroy` runs
## at the end of each closure call — only the context itself is shared.

import std/[unittest]
import proptest
import z3
# `./recipes` is a private test helper carrying the recipe ADTs +
# strategies + interpreters. v0.2 step 8 promotes it to the public
# `src/z3/strategies` module behind a `-d:z3WithProptest` flag.
import ./recipes

# ============================================================================
# Input-driven properties
# ============================================================================

suite "property: tracer":
  test "any int32 literal round-trips through solver+model":
    let ctx = newContext()
    let report = forAll(
      integers(low(int32).int, high(int32).int),
      proc(k: int) =
        let x = mkIntVar("x")
        let s = newSolver()
        s.add x == mkInt(k)
        ensure s.check() == zsSat
        let m = s.model()
        ensure m[x].toInt == k)
    check report.outcome == otPassed

suite "smtValid / smtEquiv":
  test "smtValid distinguishes tautology from contradiction":
    let ctx = newContext()
    check smtValid(mkTrue())
    check not smtValid(mkFalse())
    let p = mkBoolVar("p")
    check smtValid(p or not p)
    check not smtValid(p and not p)

  test "smtEquiv detects SMT-level equivalence":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    check smtEquiv(x + y, y + x)
    check smtEquiv((x + y) + mkInt(1), x + (y + mkInt(1)))
    check not smtEquiv(x, y)

suite "property: BV ↔ native arithmetic":
  test "bvadd on BV[8] agrees with native uint8 modular addition":
    let ctx = newContext()
    let report = forAll(
      tuples2(integers(0, 255), integers(0, 255)),
      proc(p: (int, int)) =
        # Concrete bvadd of two BV literals doesn't auto-simplify into
        # a numeral; we ask the solver to evaluate it. That also
        # mirrors the realistic user path (assert + check + extract).
        let r = mkBitVecVar[8]("r")
        let s = newSolver()
        s.add r == (mkBitVec(uint32(p[0]), 8) + mkBitVec(uint32(p[1]), 8))
        ensure s.check() == zsSat
        let got = s.model()[r].toUint
        let expected = uint64(uint8(p[0]) + uint8(p[1]))
        ensure got == expected)
    check report.outcome == otPassed

  test "bvsub on BV[8] agrees with native uint8 modular subtraction":
    let ctx = newContext()
    let report = forAll(
      tuples2(integers(0, 255), integers(0, 255)),
      proc(p: (int, int)) =
        let r = mkBitVecVar[8]("r")
        let s = newSolver()
        s.add r == (mkBitVec(uint32(p[0]), 8) - mkBitVec(uint32(p[1]), 8))
        ensure s.check() == zsSat
        let got = s.model()[r].toUint
        let expected = uint64(uint8(p[0]) - uint8(p[1]))
        ensure got == expected)
    check report.outcome == otPassed

  test "bvmul on BV[8] agrees with native uint8 modular multiplication":
    let ctx = newContext()
    let report = forAll(
      tuples2(integers(0, 255), integers(0, 255)),
      proc(p: (int, int)) =
        let r = mkBitVecVar[8]("r")
        let s = newSolver()
        s.add r == (mkBitVec(uint32(p[0]), 8) * mkBitVec(uint32(p[1]), 8))
        ensure s.check() == zsSat
        let got = s.model()[r].toUint
        let expected = uint64(uint8(p[0]) * uint8(p[1]))
        ensure got == expected)
    check report.outcome == otPassed

suite "property: SMT2 round-trip":
  test "smt2Script → parseSmt2 preserves sat value":
    let ctx = newContext()
    let report = forAll(
      integers(-1000, 1000),
      proc(k: int) =
        let x = mkIntVar("x")
        let s1 = newSolver()
        s1.add x == mkInt(k)
        let script = smt2Script(s1)

        let asserts = parseSmt2(ctx, script)
        let s2 = newSolver()
        for a in asserts: s2.add a
        ensure s2.check() == zsSat
        ensure s2.model()[x].toInt == k)
    check report.outcome == otPassed

# ============================================================================
# Shape-driven properties — random expression trees, algebraic laws
# ============================================================================

suite "property: shape — algebraic laws over random int trees":
  test "e + 0 ≡ e for random int expression":
    let ctx = newContext()
    let prop = proc(r: IntRecipe) =
      let e = interpret(r, ctx)
      ensure smtEquiv(e + mkInt(0), e)
    let report = forAll(intRecipes(maxDepth = 3), prop, fewExamples())
    check report.outcome == otPassed

  test "e - e ≡ 0 for random int expression":
    let ctx = newContext()
    let prop = proc(r: IntRecipe) =
      let e = interpret(r, ctx)
      ensure smtEquiv(e - e, mkInt(0))
    let report = forAll(intRecipes(maxDepth = 3), prop, fewExamples())
    check report.outcome == otPassed

  test "commutativity: e1 + e2 ≡ e2 + e1":
    let ctx = newContext()
    let prop = proc(p: (IntRecipe, IntRecipe)) =
      let a = interpret(p[0], ctx)
      let b = interpret(p[1], ctx)
      ensure smtEquiv(a + b, b + a)
    let report = forAll(
      tuples2(intRecipes(maxDepth = 2), intRecipes(maxDepth = 2)),
      prop, fewExamples())
    check report.outcome == otPassed

  test "associativity: (e1+e2)+e3 ≡ e1+(e2+e3)":
    let ctx = newContext()
    let prop = proc(p: (IntRecipe, (IntRecipe, IntRecipe))) =
      let a = interpret(p[0], ctx)
      let b = interpret(p[1][0], ctx)
      let c = interpret(p[1][1], ctx)
      ensure smtEquiv((a + b) + c, a + (b + c))
    let report = forAll(
      tuples2(intRecipes(maxDepth = 2),
              tuples2(intRecipes(maxDepth = 2), intRecipes(maxDepth = 2))),
      prop, fewExamples())
    check report.outcome == otPassed

  test "e * 0 ≡ 0":
    let ctx = newContext()
    let prop = proc(r: IntRecipe) =
      let e = interpret(r, ctx)
      ensure smtEquiv(e * mkInt(0), mkInt(0))
    let report = forAll(intRecipes(maxDepth = 3), prop, fewExamples())
    check report.outcome == otPassed

  test "e * 1 ≡ e":
    let ctx = newContext()
    let prop = proc(r: IntRecipe) =
      let e = interpret(r, ctx)
      ensure smtEquiv(e * mkInt(1), e)
    let report = forAll(intRecipes(maxDepth = 3), prop, fewExamples())
    check report.outcome == otPassed

  test "double negation: --e ≡ e":
    let ctx = newContext()
    let prop = proc(r: IntRecipe) =
      let e = interpret(r, ctx)
      ensure smtEquiv(-(-e), e)
    let report = forAll(intRecipes(maxDepth = 3), prop, fewExamples())
    check report.outcome == otPassed

suite "property: shape — algebraic laws over random bool trees":
  test "double negation: not (not p) ≡ p":
    let ctx = newContext()
    let prop = proc(r: BoolRecipe) =
      let p = interpret(r, ctx)
      ensure smtEquiv(not (not p), p)
    let report = forAll(boolRecipes(maxDepth = 3), prop, fewExamples())
    check report.outcome == otPassed

  test "de Morgan: not (a and b) ≡ (not a) or (not b)":
    let ctx = newContext()
    let prop = proc(p: (BoolRecipe, BoolRecipe)) =
      let a = interpret(p[0], ctx)
      let b = interpret(p[1], ctx)
      ensure smtEquiv(not (a and b), (not a) or (not b))
    let report = forAll(
      tuples2(boolRecipes(maxDepth = 2), boolRecipes(maxDepth = 2)),
      prop, fewExamples())
    check report.outcome == otPassed

  test "de Morgan: not (a or b) ≡ (not a) and (not b)":
    let ctx = newContext()
    let prop = proc(p: (BoolRecipe, BoolRecipe)) =
      let a = interpret(p[0], ctx)
      let b = interpret(p[1], ctx)
      ensure smtEquiv(not (a or b), (not a) and (not b))
    let report = forAll(
      tuples2(boolRecipes(maxDepth = 2), boolRecipes(maxDepth = 2)),
      prop, fewExamples())
    check report.outcome == otPassed

  test "commutativity of and / or / xor":
    let ctx = newContext()
    let prop = proc(p: (BoolRecipe, BoolRecipe)) =
      let a = interpret(p[0], ctx)
      let b = interpret(p[1], ctx)
      ensure smtEquiv(a and b, b and a)
      ensure smtEquiv(a or b,  b or  a)
      ensure smtEquiv(a xor b, b xor a)
    let report = forAll(
      tuples2(boolRecipes(maxDepth = 2), boolRecipes(maxDepth = 2)),
      prop, fewExamples())
    check report.outcome == otPassed

  test "idempotence: p and p ≡ p, p or p ≡ p":
    let ctx = newContext()
    let prop = proc(r: BoolRecipe) =
      let p = interpret(r, ctx)
      ensure smtEquiv(p and p, p)
      ensure smtEquiv(p or p, p)
    let report = forAll(boolRecipes(maxDepth = 3), prop, fewExamples())
    check report.outcome == otPassed

  test "absorption: p and (p or q) ≡ p":
    let ctx = newContext()
    let prop = proc(pq: (BoolRecipe, BoolRecipe)) =
      let p = interpret(pq[0], ctx)
      let q = interpret(pq[1], ctx)
      ensure smtEquiv(p and (p or q), p)
      ensure smtEquiv(p or (p and q), p)
    let report = forAll(
      tuples2(boolRecipes(maxDepth = 2), boolRecipes(maxDepth = 2)),
      prop, fewExamples())
    check report.outcome == otPassed

suite "property: shape — algebraic laws over random BV[8] trees":
  test "commutativity: a + b ≡ b + a":
    let ctx = newContext()
    let prop = proc(p: (BvRecipe, BvRecipe)) =
      let a = interpret(p[0], ctx)
      let b = interpret(p[1], ctx)
      ensure smtEquiv(a + b, b + a)
    let report = forAll(
      tuples2(bvRecipes(maxDepth = 2), bvRecipes(maxDepth = 2)),
      prop, fewExamples())
    check report.outcome == otPassed

  test "commutativity of bitwise: a and b, a or b, a xor b":
    let ctx = newContext()
    let prop = proc(p: (BvRecipe, BvRecipe)) =
      let a = interpret(p[0], ctx)
      let b = interpret(p[1], ctx)
      ensure smtEquiv(a and b, b and a)
      ensure smtEquiv(a or b,  b or  a)
      ensure smtEquiv(a xor b, b xor a)
    let report = forAll(
      tuples2(bvRecipes(maxDepth = 2), bvRecipes(maxDepth = 2)),
      prop, fewExamples())
    check report.outcome == otPassed

  test "involutions: not (not e) ≡ e, -(-e) ≡ e":
    let ctx = newContext()
    let prop = proc(r: BvRecipe) =
      let e = interpret(r, ctx)
      ensure smtEquiv(not (not e), e)
      ensure smtEquiv(-(-e), e)
    let report = forAll(bvRecipes(maxDepth = 2), prop, fewExamples())
    check report.outcome == otPassed

  test "full-width extract is identity: e.extract(7, 0) ≡ e":
    let ctx = newContext()
    let prop = proc(r: BvRecipe) =
      let e = interpret(r, ctx)
      ensure smtEquiv(e.extract(7, 0), e)
    let report = forAll(bvRecipes(maxDepth = 2), prop, fewExamples())
    check report.outcome == otPassed

  test "split-then-concat round-trips: concat(hi, lo) ≡ e":
    let ctx = newContext()
    let prop = proc(r: BvRecipe) =
      let e = interpret(r, ctx)
      let hi = e.extract(7, 4)
      let lo = e.extract(3, 0)
      ensure smtEquiv(concat(hi, lo), e)
    let report = forAll(bvRecipes(maxDepth = 2), prop, fewExamples())
    check report.outcome == otPassed

  test "zeroExtend then extract recovers the value":
    let ctx = newContext()
    let prop = proc(r: BvRecipe) =
      let e = interpret(r, ctx)
      let wide = e.zeroExtend(8)        # Z3BitVec[16]
      ensure smtEquiv(wide.extract(7, 0), e)
    let report = forAll(bvRecipes(maxDepth = 2), prop, fewExamples())
    check report.outcome == otPassed

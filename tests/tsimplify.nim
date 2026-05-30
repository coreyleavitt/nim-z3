## `z3/simplify` tests — Z3_simplify wrapped with phantom-type
## preservation. Tracer + algebraic invariants.

import std/[unittest]
import proptest
import z3
import ./recipes

suite "simplify — tracer":
  test "simplify(2 + 3) is a literal numeral with value 5":
    let ctx = newContext()
    let r = simplify(mkInt(2) + mkInt(3))
    check r.toInt == 5

suite "simplify — algebraic identities":
  test "true and p simplifies to a form equivalent to p":
    let ctx = newContext()
    let p = mkBoolVar("p")
    let r = simplify(mkTrue() and p)
    check smtEquiv(r, p)

  test "x + 0 simplifies to a form equivalent to x":
    let ctx = newContext()
    let x = mkIntVar("x")
    let r = simplify(x + mkInt(0))
    check smtEquiv(r, x)

  test "simplify is idempotent":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let e = (x + y) * mkInt(0) + ((x + mkInt(0)) * y)
    let r1 = simplify(e)
    let r2 = simplify(r1)
    # Idempotence is structural: simplifying a fixed-point input gives
    # the same AST id back. `astEqual` is the pointer-level identity
    # check exposed by z3/ast.
    check astEqual(r1, r2)

  test "BV bitwise folding: 0xAB and 0xF0 simplifies to 0xA0":
    let ctx = newContext()
    let r = simplify(mkBitVec(0xAB'u8, 8) and mkBitVec(0xF0'u8, 8))
    check r.toUint == 0xA0'u64

suite "simplify — phantom type preservation":
  test "simplify of Z3Int stays Z3Int":
    let ctx = newContext()
    let r = simplify(mkIntVar("x") + mkInt(1))
    check r is Z3Int

  test "simplify of Z3Bool stays Z3Bool":
    let ctx = newContext()
    let r = simplify(mkBoolVar("p") and mkTrue())
    check r is Z3Bool

  test "simplify of Z3Real stays Z3Real":
    let ctx = newContext()
    let r = simplify(mkRealVar("x") + mkReal(1, 2))
    check r is Z3Real

  test "simplify of Z3BitVec[8] stays Z3BitVec[8]":
    let ctx = newContext()
    let r = simplify(mkBitVecVar[8]("b") + mkBitVec(1'u8, 8))
    check r is Z3BitVec[8]

  test "simplify of Z3BitVec[16] stays Z3BitVec[16]":
    let ctx = newContext()
    let r = simplify(mkBitVecVar[16]("b"))
    check r is Z3BitVec[16]

suite "simplify — semantic preservation over random trees":
  test "e ≡ simplify(e) for random int expression trees":
    let ctx = newContext()
    let prop = proc(r: IntRecipe) =
      let e = interpret(r, ctx)
      ensure smtEquiv(e, simplify(e))
    let report = forAll(intRecipes(maxDepth = 3), prop, fewExamples())
    check report.outcome == otPassed

  test "p ≡ simplify(p) for random bool expression trees":
    let ctx = newContext()
    let prop = proc(r: BoolRecipe) =
      let p = interpret(r, ctx)
      ensure smtEquiv(p, simplify(p))
    let report = forAll(boolRecipes(maxDepth = 3), prop, fewExamples())
    check report.outcome == otPassed

  test "b ≡ simplify(b) for random BV[8] expression trees":
    let ctx = newContext()
    let prop = proc(r: BvRecipe) =
      let b = interpret(r, ctx)
      ensure smtEquiv(b, simplify(b))
    let report = forAll(bvRecipes(maxDepth = 2), prop, fewExamples())
    check report.outcome == otPassed

suite "simplify — params-customised":
  test "simplify(e, params) preserves SMT equivalence":
    let ctx = newContext()
    let x = mkIntVar("x")
    let p = newParams()
    p.set("arith_lhs", true)
    let e = (x + mkInt(0)) * mkInt(2) + mkInt(3)
    check smtEquiv(e, simplify(e, p))

  test "simplify(_, params) preserves equivalence over random int trees":
    let ctx = newContext()
    let p = newParams()
    p.set("arith_lhs", true)
    let prop = proc(r: IntRecipe) =
      let e = interpret(r, ctx)
      ensure smtEquiv(e, simplify(e, p))
    let report = forAll(intRecipes(maxDepth = 3), prop, fewExamples())
    check report.outcome == otPassed

  test "simplify(_, params) preserves equivalence over random bool trees":
    let ctx = newContext()
    let p = newParams()
    p.set("elim_and", true)
    let prop = proc(r: BoolRecipe) =
      let b = interpret(r, ctx)
      ensure smtEquiv(b, simplify(b, p))
    let report = forAll(boolRecipes(maxDepth = 3), prop, fewExamples())
    check report.outcome == otPassed

  test "simplify(_, params) preserves equivalence over random BV[8] trees":
    let ctx = newContext()
    let p = newParams()
    p.set("bv_le_extra", true)
    let prop = proc(r: BvRecipe) =
      let b = interpret(r, ctx)
      ensure smtEquiv(b, simplify(b, p))
    let report = forAll(bvRecipes(maxDepth = 2), prop, fewExamples())
    check report.outcome == otPassed

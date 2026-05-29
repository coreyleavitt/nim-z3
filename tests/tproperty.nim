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

# ============================================================================
# Recipe ADTs — pure Nim, proptest-friendly
# ============================================================================
#
# Strategies generate recipes; the property body interprets the recipe
# against a shared context. Keeping recipes pure means proptest can
# shrink them via the choice-sequence mechanism without touching Z3
# state.

type
  IntRecipeKind = enum irkLit, irkVar, irkNeg, irkAdd, irkSub, irkMul
  IntRecipe = ref object
    case kind: IntRecipeKind
    of irkLit: lit: int
    of irkVar: name: string
    of irkNeg: e: IntRecipe
    of irkAdd, irkSub, irkMul: l, r: IntRecipe

const varNames = @["x", "y", "z"]

proc intRecipeBase(): Strategy[IntRecipe] =
  oneOf(@[
    integers(-100, 100).map(
      proc(n: int): IntRecipe = IntRecipe(kind: irkLit, lit: n)),
    sampledFrom(varNames).map(
      proc(n: string): IntRecipe = IntRecipe(kind: irkVar, name: n))
  ])

proc intRecipeExtend(child: Strategy[IntRecipe]): Strategy[IntRecipe] =
  oneOf(@[
    intRecipeBase(),
    child.map(proc(e: IntRecipe): IntRecipe =
      IntRecipe(kind: irkNeg, e: e)),
    tuples2(child, child).map(proc(p: (IntRecipe, IntRecipe)): IntRecipe =
      IntRecipe(kind: irkAdd, l: p[0], r: p[1])),
    tuples2(child, child).map(proc(p: (IntRecipe, IntRecipe)): IntRecipe =
      IntRecipe(kind: irkSub, l: p[0], r: p[1])),
    tuples2(child, child).map(proc(p: (IntRecipe, IntRecipe)): IntRecipe =
      IntRecipe(kind: irkMul, l: p[0], r: p[1])),
  ])

proc intRecipes(maxDepth = 3): Strategy[IntRecipe] =
  recursive(intRecipeBase(), intRecipeExtend, maxDepth)

type
  BoolRecipeKind = enum brkLit, brkVar, brkNot, brkAnd, brkOr, brkXor,
                        brkEq, brkLt
  BoolRecipe = ref object
    case kind: BoolRecipeKind
    of brkLit: lit: bool
    of brkVar: name: string
    of brkNot: e: BoolRecipe
    of brkAnd, brkOr, brkXor: l, r: BoolRecipe
    of brkEq, brkLt: il, ir: IntRecipe   # comparisons over int recipes

const boolVarNames = @["p", "q", "r"]

proc boolRecipeBase(): Strategy[BoolRecipe] =
  oneOf(@[
    booleans().map(
      proc(b: bool): BoolRecipe = BoolRecipe(kind: brkLit, lit: b)),
    sampledFrom(boolVarNames).map(
      proc(n: string): BoolRecipe = BoolRecipe(kind: brkVar, name: n))
  ])

proc boolRecipeExtend(child: Strategy[BoolRecipe]): Strategy[BoolRecipe] =
  oneOf(@[
    boolRecipeBase(),
    child.map(proc(e: BoolRecipe): BoolRecipe =
      BoolRecipe(kind: brkNot, e: e)),
    tuples2(child, child).map(proc(p: (BoolRecipe, BoolRecipe)): BoolRecipe =
      BoolRecipe(kind: brkAnd, l: p[0], r: p[1])),
    tuples2(child, child).map(proc(p: (BoolRecipe, BoolRecipe)): BoolRecipe =
      BoolRecipe(kind: brkOr, l: p[0], r: p[1])),
    tuples2(child, child).map(proc(p: (BoolRecipe, BoolRecipe)): BoolRecipe =
      BoolRecipe(kind: brkXor, l: p[0], r: p[1])),
    tuples2(intRecipes(maxDepth = 1), intRecipes(maxDepth = 1)).map(
      proc(p: (IntRecipe, IntRecipe)): BoolRecipe =
        BoolRecipe(kind: brkEq, il: p[0], ir: p[1])),
    tuples2(intRecipes(maxDepth = 1), intRecipes(maxDepth = 1)).map(
      proc(p: (IntRecipe, IntRecipe)): BoolRecipe =
        BoolRecipe(kind: brkLt, il: p[0], ir: p[1])),
  ])

proc boolRecipes(maxDepth = 3): Strategy[BoolRecipe] =
  recursive(boolRecipeBase(), boolRecipeExtend, maxDepth)

type
  BvRecipeKind = enum bvrkLit, bvrkVar, bvrkNeg, bvrkNot,
                      bvrkAdd, bvrkSub, bvrkMul,
                      bvrkAnd, bvrkOr, bvrkXor
  # Width-8 only for v0.1 — covers the BV operator surface without
  # exploding the recipe ADT into a width parameter. Wider widths
  # follow the same pattern when we want them.
  BvRecipe = ref object
    case kind: BvRecipeKind
    of bvrkLit: lit: uint8
    of bvrkVar: name: string
    of bvrkNeg, bvrkNot: e: BvRecipe
    of bvrkAdd, bvrkSub, bvrkMul,
       bvrkAnd, bvrkOr, bvrkXor: l, r: BvRecipe

const bvVarNames = @["bx", "by", "bz"]

proc bvRecipeBase(): Strategy[BvRecipe] =
  oneOf(@[
    integers(0, 255).map(
      proc(n: int): BvRecipe = BvRecipe(kind: bvrkLit, lit: uint8(n))),
    sampledFrom(bvVarNames).map(
      proc(n: string): BvRecipe = BvRecipe(kind: bvrkVar, name: n))
  ])

proc bvRecipeExtend(child: Strategy[BvRecipe]): Strategy[BvRecipe] =
  oneOf(@[
    bvRecipeBase(),
    child.map(proc(e: BvRecipe): BvRecipe = BvRecipe(kind: bvrkNeg, e: e)),
    child.map(proc(e: BvRecipe): BvRecipe = BvRecipe(kind: bvrkNot, e: e)),
    tuples2(child, child).map(proc(p: (BvRecipe, BvRecipe)): BvRecipe =
      BvRecipe(kind: bvrkAdd, l: p[0], r: p[1])),
    tuples2(child, child).map(proc(p: (BvRecipe, BvRecipe)): BvRecipe =
      BvRecipe(kind: bvrkSub, l: p[0], r: p[1])),
    tuples2(child, child).map(proc(p: (BvRecipe, BvRecipe)): BvRecipe =
      BvRecipe(kind: bvrkMul, l: p[0], r: p[1])),
    tuples2(child, child).map(proc(p: (BvRecipe, BvRecipe)): BvRecipe =
      BvRecipe(kind: bvrkAnd, l: p[0], r: p[1])),
    tuples2(child, child).map(proc(p: (BvRecipe, BvRecipe)): BvRecipe =
      BvRecipe(kind: bvrkOr, l: p[0], r: p[1])),
    tuples2(child, child).map(proc(p: (BvRecipe, BvRecipe)): BvRecipe =
      BvRecipe(kind: bvrkXor, l: p[0], r: p[1])),
  ])

proc bvRecipes(maxDepth = 3): Strategy[BvRecipe] =
  recursive(bvRecipeBase(), bvRecipeExtend, maxDepth)

proc interpret(r: IntRecipe, ctx: Z3Context): Z3Int =
  ## Build the Z3Int AST for `r` under `ctx`. Variables of the same
  ## name resolve to the same Z3 constant (Z3 hash-conses constants by
  ## sort + name), so `x + x` from two `irkVar("x")` interpretations is
  ## the same expression a hand-rolled `let x = mkIntVar("x"); x + x`
  ## would produce.
  case r.kind
  of irkLit: mkInt(ctx, r.lit)
  of irkVar: mkIntVar(ctx, r.name)
  of irkNeg: -interpret(r.e, ctx)
  of irkAdd: interpret(r.l, ctx) + interpret(r.r, ctx)
  of irkSub: interpret(r.l, ctx) - interpret(r.r, ctx)
  of irkMul: interpret(r.l, ctx) * interpret(r.r, ctx)

proc interpret(r: BvRecipe, ctx: Z3Context): Z3BitVec[8] =
  case r.kind
  of bvrkLit: mkBitVec(ctx, uint32(r.lit), 8)
  of bvrkVar: mkBitVecVar[8](ctx, r.name)
  of bvrkNeg: -interpret(r.e, ctx)
  of bvrkNot: not interpret(r.e, ctx)
  of bvrkAdd: interpret(r.l, ctx) + interpret(r.r, ctx)
  of bvrkSub: interpret(r.l, ctx) - interpret(r.r, ctx)
  of bvrkMul: interpret(r.l, ctx) * interpret(r.r, ctx)
  of bvrkAnd: interpret(r.l, ctx) and interpret(r.r, ctx)
  of bvrkOr:  interpret(r.l, ctx) or  interpret(r.r, ctx)
  of bvrkXor: interpret(r.l, ctx) xor interpret(r.r, ctx)

proc interpret(r: BoolRecipe, ctx: Z3Context): Z3Bool =
  case r.kind
  of brkLit: mkBool(ctx, r.lit)
  of brkVar: mkBoolVar(ctx, r.name)
  of brkNot: not interpret(r.e, ctx)
  of brkAnd: interpret(r.l, ctx) and interpret(r.r, ctx)
  of brkOr:  interpret(r.l, ctx) or  interpret(r.r, ctx)
  of brkXor: interpret(r.l, ctx) xor interpret(r.r, ctx)
  of brkEq:  interpret(r.il, ctx) == interpret(r.ir, ctx)
  of brkLt:  interpret(r.il, ctx) <  interpret(r.ir, ctx)

# ============================================================================
# Settings — fewer examples for SMT-heavy shape tests
# ============================================================================
#
# BV equivalence checks are heavier than int/bool (Z3 must bit-blast),
# so we dial down example count for shape tests. The shape coverage is
# still meaningful: 25–50 distinct expression shapes per property
# exercise plenty of wrapper paths, and any law that fails will
# reliably surface at this scale just as it would at 250.

proc fewExamples(): Settings =
  result = defaultSettings()
  result.maxExamples = 25

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

## Shared recipe ADTs + proptest strategies + interpreters for
## property tests that need random Z3 expression trees.
##
## **Private test helper**, not a public module. v0.2 step 8 promotes
## this to `src/z3/strategies.nim` behind a `-d:z3WithProptest`
## compile flag, at which point the wrapper API gets these as a
## first-class public surface. Until then they live here and any test
## that wants random shape coverage imports them via relative path.
##
## ## Design (extracted from v0.1 tests/tproperty.nim)
##
## Strategies generate recipes; properties interpret the recipe against
## a shared context. Keeping recipes pure means proptest can shrink
## them via the choice-sequence mechanism without touching Z3 state.
## See v0.1's `tests/tproperty.nim` doc comment for the context-
## sharing-across-iterations rationale (memory pressure under per-
## iteration newContext()).

import proptest
import z3

# ============================================================================
# IntRecipe — integer expression trees
# ============================================================================

type
  IntRecipeKind* = enum irkLit, irkVar, irkNeg, irkAdd, irkSub, irkMul
  IntRecipe* = ref object
    case kind*: IntRecipeKind
    of irkLit: lit*: int
    of irkVar: name*: string
    of irkNeg: e*: IntRecipe
    of irkAdd, irkSub, irkMul: l*, r*: IntRecipe

const intVarNames* = @["x", "y", "z"]

proc intRecipeBase*(): Strategy[IntRecipe] =
  oneOf(@[
    integers(-100, 100).map(
      proc(n: int): IntRecipe = IntRecipe(kind: irkLit, lit: n)),
    sampledFrom(intVarNames).map(
      proc(n: string): IntRecipe = IntRecipe(kind: irkVar, name: n))
  ])

proc intRecipeExtend*(child: Strategy[IntRecipe]): Strategy[IntRecipe] =
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

proc intRecipes*(maxDepth = 3): Strategy[IntRecipe] =
  recursive(intRecipeBase(), intRecipeExtend, maxDepth)

# ============================================================================
# BoolRecipe — boolean expression trees
# ============================================================================

type
  BoolRecipeKind* = enum brkLit, brkVar, brkNot, brkAnd, brkOr, brkXor,
                         brkEq, brkLt
  BoolRecipe* = ref object
    case kind*: BoolRecipeKind
    of brkLit: lit*: bool
    of brkVar: name*: string
    of brkNot: e*: BoolRecipe
    of brkAnd, brkOr, brkXor: l*, r*: BoolRecipe
    of brkEq, brkLt: il*, ir*: IntRecipe   # comparisons over int recipes

const boolVarNames* = @["p", "q", "r"]

proc boolRecipeBase*(): Strategy[BoolRecipe] =
  oneOf(@[
    booleans().map(
      proc(b: bool): BoolRecipe = BoolRecipe(kind: brkLit, lit: b)),
    sampledFrom(boolVarNames).map(
      proc(n: string): BoolRecipe = BoolRecipe(kind: brkVar, name: n))
  ])

proc boolRecipeExtend*(child: Strategy[BoolRecipe]): Strategy[BoolRecipe] =
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

proc boolRecipes*(maxDepth = 3): Strategy[BoolRecipe] =
  recursive(boolRecipeBase(), boolRecipeExtend, maxDepth)

# ============================================================================
# BvRecipe — width-8 BV expression trees
# ============================================================================
#
# Width-8 only at this layer. Wider widths follow the same pattern;
# when v0.2 step 8 promotes recipes to the public surface we'll
# generalise on W.

type
  BvRecipeKind* = enum bvrkLit, bvrkVar, bvrkNeg, bvrkNot,
                       bvrkAdd, bvrkSub, bvrkMul,
                       bvrkAnd, bvrkOr, bvrkXor
  BvRecipe* = ref object
    case kind*: BvRecipeKind
    of bvrkLit: lit*: uint8
    of bvrkVar: name*: string
    of bvrkNeg, bvrkNot: e*: BvRecipe
    of bvrkAdd, bvrkSub, bvrkMul,
       bvrkAnd, bvrkOr, bvrkXor: l*, r*: BvRecipe

const bvVarNames* = @["bx", "by", "bz"]

proc bvRecipeBase*(): Strategy[BvRecipe] =
  oneOf(@[
    integers(0, 255).map(
      proc(n: int): BvRecipe = BvRecipe(kind: bvrkLit, lit: uint8(n))),
    sampledFrom(bvVarNames).map(
      proc(n: string): BvRecipe = BvRecipe(kind: bvrkVar, name: n))
  ])

proc bvRecipeExtend*(child: Strategy[BvRecipe]): Strategy[BvRecipe] =
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

proc bvRecipes*(maxDepth = 3): Strategy[BvRecipe] =
  recursive(bvRecipeBase(), bvRecipeExtend, maxDepth)

# ============================================================================
# Interpreters — recipe → AST under a given context
# ============================================================================

proc interpret*(r: IntRecipe, ctx: Z3Context): Z3Int =
  ## Build the Z3Int AST for `r` under `ctx`. Variables of the same
  ## name resolve to the same Z3 constant (Z3 hash-conses constants by
  ## sort + name), so `x + x` from two `irkVar("x")` interpretations
  ## is identity-equal to a hand-rolled `let x = mkIntVar("x"); x + x`.
  case r.kind
  of irkLit: mkInt(ctx, r.lit)
  of irkVar: mkIntVar(ctx, r.name)
  of irkNeg: -interpret(r.e, ctx)
  of irkAdd: interpret(r.l, ctx) + interpret(r.r, ctx)
  of irkSub: interpret(r.l, ctx) - interpret(r.r, ctx)
  of irkMul: interpret(r.l, ctx) * interpret(r.r, ctx)

proc interpret*(r: BvRecipe, ctx: Z3Context): Z3BitVec[8] =
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

proc interpret*(r: BoolRecipe, ctx: Z3Context): Z3Bool =
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
# Test-run settings preset
# ============================================================================

proc fewExamples*(): Settings =
  ## 25-example preset for SMT-heavy shape tests. Z3's bit-blasting
  ## under random BV expressions is the heaviest path; we cap there
  ## and use the same setting for int/bool shapes for consistency.
  ## Any law that fails surfaces reliably at 25 just as it would at 250.
  result = defaultSettings()
  result.maxExamples = 25

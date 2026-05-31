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
# FuncDeclRecipe — application trees over a fixed uninterpreted `f: Int → Int`
# ============================================================================
#
# The function `f` is **not** part of the recipe — it's supplied at
# interpret time (the test owns it). Recipes describe the *shape*
# of an `f` application tree: a leaf is an `IntRecipe`; a branch is
# `f(child)`. This separation lets a single property test reuse one
# `f` declaration across all iterations (Z3's hash-consing then keeps
# the assertion graph compact).

type
  FuncDeclRecipeKind* = enum fdrkLeaf, fdrkApp
  FuncDeclRecipe* = ref object
    case kind*: FuncDeclRecipeKind
    of fdrkLeaf: ileaf*: IntRecipe
    of fdrkApp:  arg*: FuncDeclRecipe

proc fdRecipeBase*(): Strategy[FuncDeclRecipe] =
  intRecipes(maxDepth = 2).map(
    proc(i: IntRecipe): FuncDeclRecipe =
      FuncDeclRecipe(kind: fdrkLeaf, ileaf: i))

proc fdRecipeExtend*(child: Strategy[FuncDeclRecipe]):
    Strategy[FuncDeclRecipe] =
  oneOf(@[
    fdRecipeBase(),
    child.map(proc(e: FuncDeclRecipe): FuncDeclRecipe =
      FuncDeclRecipe(kind: fdrkApp, arg: e)),
  ])

proc fdRecipes*(maxDepth = 3): Strategy[FuncDeclRecipe] =
  recursive(fdRecipeBase(), fdRecipeExtend, maxDepth)

# ============================================================================
# StringRecipe — string expression trees
# ============================================================================
#
# Generates trees over `Z3String` operations. Literal strings are
# constrained to short alphabetic content so concat / substr exercise
# the wrapper's encoded-length paths without producing degenerate
# huge ASTs at depth-3 recipes.

type
  StringRecipeKind* = enum srkLit, srkVar, srkConcat
  StringRecipe* = ref object
    case kind*: StringRecipeKind
    of srkLit:    lit*: string
    of srkVar:    name*: string
    of srkConcat: l*, r*: StringRecipe

const stringVarNames* = @["s", "t", "u"]
const stringLitChoices* = @["", "a", "ab", "abc", "ba"]

proc stringRecipeBase*(): Strategy[StringRecipe] =
  oneOf(@[
    sampledFrom(stringLitChoices).map(
      proc(s: string): StringRecipe =
        StringRecipe(kind: srkLit, lit: s)),
    sampledFrom(stringVarNames).map(
      proc(n: string): StringRecipe =
        StringRecipe(kind: srkVar, name: n)),
  ])

proc stringRecipeExtend*(child: Strategy[StringRecipe]):
    Strategy[StringRecipe] =
  oneOf(@[
    stringRecipeBase(),
    tuples2(child, child).map(
      proc(p: (StringRecipe, StringRecipe)): StringRecipe =
        StringRecipe(kind: srkConcat, l: p[0], r: p[1])),
  ])

proc stringRecipes*(maxDepth = 3): Strategy[StringRecipe] =
  recursive(stringRecipeBase(), stringRecipeExtend, maxDepth)

# ============================================================================
# SeqRecipe — Z3Seq[Z3Int] expression trees
# ============================================================================
#
# Element-parameterised at the type level (Z3Seq[E]) but pinned to E =
# Z3Int at the recipe level for simplicity — the algebraic laws hold
# for every element type; one concrete instantiation is sufficient
# coverage at the property layer.

type
  SeqRecipeKind* = enum sqrkEmpty, sqrkUnit, sqrkVar, sqrkConcat
  SeqRecipe* = ref object
    case kind*: SeqRecipeKind
    of sqrkEmpty:  discard
    of sqrkUnit:   elt*: IntRecipe
    of sqrkVar:    name*: string
    of sqrkConcat: l*, r*: SeqRecipe

const seqVarNames* = @["xs", "ys", "zs"]

proc seqRecipeBase*(): Strategy[SeqRecipe] =
  oneOf(@[
    sampledFrom(@[SeqRecipe(kind: sqrkEmpty)]),
    intRecipes(maxDepth = 1).map(
      proc(i: IntRecipe): SeqRecipe =
        SeqRecipe(kind: sqrkUnit, elt: i)),
    sampledFrom(seqVarNames).map(
      proc(n: string): SeqRecipe =
        SeqRecipe(kind: sqrkVar, name: n)),
  ])

proc seqRecipeExtend*(child: Strategy[SeqRecipe]):
    Strategy[SeqRecipe] =
  oneOf(@[
    seqRecipeBase(),
    tuples2(child, child).map(
      proc(p: (SeqRecipe, SeqRecipe)): SeqRecipe =
        SeqRecipe(kind: sqrkConcat, l: p[0], r: p[1])),
  ])

proc seqRecipes*(maxDepth = 3): Strategy[SeqRecipe] =
  recursive(seqRecipeBase(), seqRecipeExtend, maxDepth)

# ============================================================================
# RegexRecipe — Z3Regex[Z3String] expression trees
# ============================================================================
#
# Regex recipes are over the String basis (`Z3Regex[Z3String]`). Leaf
# = singleton-string regex `mkRegex(mkString(s))`; branches are unary
# (star/plus/option) and binary (union/concat) combinators. We skip
# `complement` and `intersect` to keep the property tests'
# decidability bounded — Z3's regex theory is decidable but
# intersection/complement can blow up DFA sizes adversarially.

type
  RegexRecipeKind* = enum
    rrxLitSingleton  ## `mkRegex(mkString(s))`
    rrxStar
    rrxPlus
    rrxOption
    rrxConcat
    rrxUnion
  RegexRecipe* = ref object
    case kind*: RegexRecipeKind
    of rrxLitSingleton:           lit*: string
    of rrxStar, rrxPlus, rrxOption: e*: RegexRecipe
    of rrxConcat, rrxUnion:         l*, r*: RegexRecipe

const regexLitChoices* = @["a", "b", "ab", "ba"]

proc regexRecipeBase*(): Strategy[RegexRecipe] =
  sampledFrom(regexLitChoices).map(
    proc(s: string): RegexRecipe =
      RegexRecipe(kind: rrxLitSingleton, lit: s))

proc regexRecipeExtend*(child: Strategy[RegexRecipe]):
    Strategy[RegexRecipe] =
  oneOf(@[
    regexRecipeBase(),
    child.map(proc(e: RegexRecipe): RegexRecipe =
      RegexRecipe(kind: rrxStar, e: e)),
    child.map(proc(e: RegexRecipe): RegexRecipe =
      RegexRecipe(kind: rrxPlus, e: e)),
    child.map(proc(e: RegexRecipe): RegexRecipe =
      RegexRecipe(kind: rrxOption, e: e)),
    tuples2(child, child).map(
      proc(p: (RegexRecipe, RegexRecipe)): RegexRecipe =
        RegexRecipe(kind: rrxConcat, l: p[0], r: p[1])),
    tuples2(child, child).map(
      proc(p: (RegexRecipe, RegexRecipe)): RegexRecipe =
        RegexRecipe(kind: rrxUnion, l: p[0], r: p[1])),
  ])

proc regexRecipes*(maxDepth = 2): Strategy[RegexRecipe] =
  ## Default depth = 2 (one level shallower than other families).
  ## Z3's regex membership is decidable but solver time can blow up
  ## adversarially on deep nesting; cap at 2 to keep the property
  ## test budget reasonable.
  recursive(regexRecipeBase(), regexRecipeExtend, maxDepth)

# ============================================================================
# FpRecipe — Z3Float32 expression trees
# ============================================================================
#
# IEEE 754 makes naïve algebraic laws fail on NaN / ±Inf. Properties
# using FpRecipe are universally quantified with an `isFinite`-shaped
# precondition: `forall x. isFinite(x) implies law(x)`. This isolates
# the algebraic identities we actually want to assert from IEEE's
# infinitary edge cases.
#
# Restricted to Z3Float32 to keep the BV bit-blasting cost bounded;
# the same laws hold for any IEEE width.

type
  FpRecipeKind* = enum fprkLit, fprkVar, fprkNeg, fprkAbs,
                       fprkAdd, fprkSub, fprkMul
  FpRecipe* = ref object
    case kind*: FpRecipeKind
    of fprkLit:  lit*: float32
    of fprkVar:  name*: string
    of fprkNeg, fprkAbs: e*: FpRecipe
    of fprkAdd, fprkSub, fprkMul: l*, r*: FpRecipe

const fpVarNames* = @["fx", "fy", "fz"]
const fpLitChoices* = @[0.0'f32, 1.0'f32, -1.0'f32, 2.5'f32, -3.75'f32]

proc fpRecipeBase*(): Strategy[FpRecipe] =
  oneOf(@[
    sampledFrom(fpLitChoices).map(
      proc(v: float32): FpRecipe = FpRecipe(kind: fprkLit, lit: v)),
    sampledFrom(fpVarNames).map(
      proc(n: string): FpRecipe = FpRecipe(kind: fprkVar, name: n)),
  ])

proc fpRecipeExtend*(child: Strategy[FpRecipe]): Strategy[FpRecipe] =
  oneOf(@[
    fpRecipeBase(),
    child.map(proc(e: FpRecipe): FpRecipe = FpRecipe(kind: fprkNeg, e: e)),
    child.map(proc(e: FpRecipe): FpRecipe = FpRecipe(kind: fprkAbs, e: e)),
    tuples2(child, child).map(
      proc(p: (FpRecipe, FpRecipe)): FpRecipe =
        FpRecipe(kind: fprkAdd, l: p[0], r: p[1])),
    tuples2(child, child).map(
      proc(p: (FpRecipe, FpRecipe)): FpRecipe =
        FpRecipe(kind: fprkSub, l: p[0], r: p[1])),
    tuples2(child, child).map(
      proc(p: (FpRecipe, FpRecipe)): FpRecipe =
        FpRecipe(kind: fprkMul, l: p[0], r: p[1])),
  ])

proc fpRecipes*(maxDepth = 3): Strategy[FpRecipe] =
  recursive(fpRecipeBase(), fpRecipeExtend, maxDepth)

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
  of bvrkLit: mkBitVec[8](ctx, uint32(r.lit))
  of bvrkVar: mkBitVecVar[8](ctx, r.name)
  of bvrkNeg: -interpret(r.e, ctx)
  of bvrkNot: not interpret(r.e, ctx)
  of bvrkAdd: interpret(r.l, ctx) + interpret(r.r, ctx)
  of bvrkSub: interpret(r.l, ctx) - interpret(r.r, ctx)
  of bvrkMul: interpret(r.l, ctx) * interpret(r.r, ctx)
  of bvrkAnd: interpret(r.l, ctx) and interpret(r.r, ctx)
  of bvrkOr:  interpret(r.l, ctx) or  interpret(r.r, ctx)
  of bvrkXor: interpret(r.l, ctx) xor interpret(r.r, ctx)

proc interpret*(r: FpRecipe, ctx: Z3Context): Z3Float32 =
  ## Build the Z3Float32 AST for `r` under `ctx`. Uses `Z3Float32`
  ## (= `Z3Fp[8, 24]`) for all leaves and intermediate results.
  case r.kind
  of fprkLit:  mkFloat32(ctx, r.lit)
  of fprkVar:  mkFloat32Var(ctx, r.name)
  of fprkNeg:
    # No `-` unary operator on Z3Fp at the public surface; use the
    # canonical `0 - e` pattern (Z3 simplifies this if needed).
    mkFloat32(ctx, 0.0'f32) - interpret(r.e, ctx)
  of fprkAbs:  abs(interpret(r.e, ctx))
  of fprkAdd:  interpret(r.l, ctx) + interpret(r.r, ctx)
  of fprkSub:  interpret(r.l, ctx) - interpret(r.r, ctx)
  of fprkMul:  interpret(r.l, ctx) * interpret(r.r, ctx)

proc interpret*(r: RegexRecipe, ctx: Z3Context): Z3Regex[Z3String] =
  ## Build the Z3Regex[Z3String] AST for `r` under `ctx`.
  case r.kind
  of rrxLitSingleton: mkRegex(mkString(ctx, r.lit))
  of rrxStar:   star(interpret(r.e, ctx))
  of rrxPlus:   plus(interpret(r.e, ctx))
  of rrxOption: option(interpret(r.e, ctx))
  of rrxConcat: concat(interpret(r.l, ctx), interpret(r.r, ctx))
  of rrxUnion:  union(interpret(r.l, ctx), interpret(r.r, ctx))

proc interpret*(r: SeqRecipe, ctx: Z3Context): Z3Seq[Z3Int] =
  ## Build the Z3Seq[Z3Int] AST for `r` under `ctx`.
  case r.kind
  of sqrkEmpty:  mkSeqEmpty[Z3Int](ctx)
  of sqrkUnit:   mkSeqUnit(interpret(r.elt, ctx))
  of sqrkVar:    mkSeqVar[Z3Int](ctx, r.name)
  of sqrkConcat: concat(interpret(r.l, ctx), interpret(r.r, ctx))

proc interpret*(r: StringRecipe, ctx: Z3Context): Z3String =
  ## Build the Z3String AST for `r` under `ctx`.
  case r.kind
  of srkLit:    mkString(ctx, r.lit)
  of srkVar:    mkStringVar(ctx, r.name)
  of srkConcat: concat(interpret(r.l, ctx), interpret(r.r, ctx))

proc interpret*(r: FuncDeclRecipe, f: Z3FuncDecl[(Z3Int,), Z3Int],
                ctx: Z3Context): Z3Int =
  ## Build the Z3Int AST for `r` under `ctx`, applying `f` at each
  ## `fdrkApp` node. The fixed `f` is supplied by the caller so all
  ## iterations of a property test reuse the same uninterpreted
  ## function (and Z3 hash-conses the resulting AST graph compactly).
  case r.kind
  of fdrkLeaf: interpret(r.ileaf, ctx)
  of fdrkApp:  f(interpret(r.arg, f, ctx))

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

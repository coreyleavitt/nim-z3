## `z3/introspect` — N2.4c: AST-level predicates, identity ids,
## global param descriptors, and type-variable sort construction.

import std/[unittest]
import z3

suite "AST predicates — isWellSorted / isApp / isNumeralAst":
  test "isWellSorted: a well-typed numeral is well-sorted":
    let ctx = newContext()
    check isWellSorted(ctx, mkInt(42).raw)

  test "isApp: a binary operation is an application":
    let ctx = newContext()
    check isApp(ctx, (mkInt(42) + mkInt(1)).raw)

  test "isNumeralAst: a numeral literal is a numeral":
    let ctx = newContext()
    check isNumeralAst(ctx, mkInt(42).raw)

  test "isNumeralAst: a free variable is not a numeral":
    let ctx = newContext()
    check not isNumeralAst(ctx, mkIntVar("x").raw)

suite "AST identity — astId / sortId":
  test "astId is stable: same AST returns the same id":
    let ctx = newContext()
    let a = mkInt(42)
    check astId(ctx, a.raw) == astId(ctx, a.raw)

  test "astId distinguishes structurally-different ASTs":
    let ctx = newContext()
    let a = mkInt(42)
    let b = mkInt(99)
    check astId(ctx, a.raw) != astId(ctx, b.raw)

  test "sortId is stable: same sort returns the same id":
    let ctx = newContext()
    let s = sortOfType[Z3Int](ctx)
    check sortId(ctx, s) == sortId(ctx, s)

suite "Bound-variable index — indexValue":
  test "indexValue on a de-Bruijn-0 bound var returns 0":
    let ctx = newContext()
    # Build a quantifier whose body references the bound variable.
    # Z3_mk_bound creates a fresh bound variable with a given de-Bruijn index.
    let bv = mkBound(ctx, 0, sortOfType[Z3Int](ctx))
    check indexValue(ctx, bv.raw) == 0

suite "Global param descriptors — globalParamDescrs":
  test "globalParamDescrs returns a non-nil Z3ParamDescrs":
    let ctx = newContext()
    let pd = globalParamDescrs(ctx)
    check not pd.isNil

  test "globalParamDescrs schema is non-empty":
    let ctx = newContext()
    let pd = globalParamDescrs(ctx)
    check pd.len > 0

suite "Type variable sort — mkTypeVariable":
  test "mkTypeVariable returns a non-nil sort handle":
    let ctx = newContext()
    let s = mkTypeVariable(ctx, "T")
    check not cast[pointer](s).isNil

  test "mkTypeVariable sort has skTypeVar kind":
    let ctx = newContext()
    let s = mkTypeVariable(ctx, "T")
    check getSortKind(ctx, s) == skTypeVar

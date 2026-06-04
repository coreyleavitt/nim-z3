## `z3/datatypes` — `mkEnumerationSort` convenience wrapper (N7.1).
##
## Tests the `Z3_mk_enumeration_sort` surface: sort construction,
## constant application, recognizer (tester) application, and
## distinctness.
##
## Enum sort values have no typed Nim wrapper — `mkEnumerationSort`
## works at the raw level — so we wrap intermediate ASTs as
## `Z3Ast[stUninterpreted]` to keep refcounts live through the test.

import std/[unittest]
import z3

suite "mkEnumerationSort — tracer":
  test "Color sort returns non-nil sort + correct lengths":
    let ctx = newContext()
    let (sort, consts, testers) =
      mkEnumerationSort(ctx, "Color", @["Red", "Green", "Blue"])
    check not sort.isNil
    check consts.len == 3
    check testers.len == 3

suite "mkEnumerationSort — const application":
  test "applying consts[0] (Red) produces a managed AST; solver reports SAT":
    let ctx = newContext()
    let (_, consts, _) =
      mkEnumerationSort(ctx, "Color", @["Red", "Green", "Blue"])
    let redVal = wrap[Z3Ast[stUninterpreted]](ctx,
      ctx.checkErr Z3_mk_app(ctx.raw, consts[0], 0,
        cast[ptr UncheckedArray[RawZ3Ast]](nil)))
    check not redVal.raw.isNil
    let s = ctx.newSolver()
    check s.check() == zsSat

  test "is-Red tester applied to Red constant is valid":
    let ctx = newContext()
    let (_, consts, testers) =
      mkEnumerationSort(ctx, "Color", @["Red", "Green", "Blue"])
    let redVal = wrap[Z3Ast[stUninterpreted]](ctx,
      ctx.checkErr Z3_mk_app(ctx.raw, consts[0], 0,
        cast[ptr UncheckedArray[RawZ3Ast]](nil)))
    var redRaw = redVal.raw
    let isRedVal = wrap[Z3Bool](ctx,
      ctx.checkErr Z3_mk_app(ctx.raw, testers[0], 1,
        cast[ptr UncheckedArray[RawZ3Ast]](addr redRaw)))
    check smtValid(isRedVal)

suite "mkEnumerationSort — distinctness":
  test "Red != Green is valid":
    let ctx = newContext()
    let (_, consts, _) =
      mkEnumerationSort(ctx, "Color", @["Red", "Green", "Blue"])
    let redVal = wrap[Z3Ast[stUninterpreted]](ctx,
      ctx.checkErr Z3_mk_app(ctx.raw, consts[0], 0,
        cast[ptr UncheckedArray[RawZ3Ast]](nil)))
    let greenVal = wrap[Z3Ast[stUninterpreted]](ctx,
      ctx.checkErr Z3_mk_app(ctx.raw, consts[1], 0,
        cast[ptr UncheckedArray[RawZ3Ast]](nil)))
    var args: array[2, RawZ3Ast] = [redVal.raw, greenVal.raw]
    let distinct2 = wrap[Z3Bool](ctx,
      ctx.checkErr Z3_mk_distinct(ctx.raw, 2,
        cast[ptr UncheckedArray[RawZ3Ast]](addr args[0])))
    check smtValid(distinct2)

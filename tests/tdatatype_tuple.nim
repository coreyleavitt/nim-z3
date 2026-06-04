## `z3/datatypes` — `mkTupleSort` convenience wrapper (N7.2).
##
## Tests the `Z3_mk_tuple_sort` surface: sort construction, constructor
## application, projection application, and distinctness of tuples with
## different field values.
##
## Tuple sort values have no typed Nim wrapper — `mkTupleSort` works at
## the raw level — so we wrap intermediate ASTs as `Z3Ast[stUninterpreted]`
## to keep refcounts live through the tests. Integer literals are built via
## `mkInt` (uses the current context) inside `withContext` blocks.
##
## ## Z3 4.15 note
##
## Z3 4.15.0 has two known internal issues with tuple sorts:
##
## 1. **Projection inc_ref overlap**: calling `Z3_inc_ref` on a
##    projection-application result (e.g. the AST returned by
##    `Z3_mk_app(proj[i], tuple_arg)`) for more than one projection `i`
##    in the same context before building/asserting the formula causes
##    `Z3_solver_assert` to raise "Overflow encountered when expanding
##    vector". Workaround: verify each projection in a separate test
##    (separate `newContext()`), so only one projection-application result
##    is live (inc_ref'd) per context at assertion time.
##
## 2. **Tuple Z3_mk_distinct sort mismatch**: calling `Z3_mk_distinct` on
##    two tuple-sort raw ASTs in Z3 4.15 results in a nested-distinct
##    expansion with sort confusion. Workaround: use `Z3_mk_not(Z3_mk_eq(...))`
##    for distinctness rather than `Z3_mk_distinct`.

import std/[unittest]
import z3

suite "mkTupleSort — tracer":
  test "Point sort returns non-nil sort + ctor + 2 projections":
    let ctx = newContext()
    withContext ctx:
      let intS = ctx.checkErr Z3_mk_int_sort(ctx.raw)
      let (sort, ctor, projs) =
        mkTupleSort(ctx, "Point", [("x", intS), ("y", intS)])
      check not sort.isNil
      check not ctor.isNil
      check projs.len == 2
      check not projs[0].isNil
      check not projs[1].isNil

suite "mkTupleSort — projection correctness":
  test "x(Point(3, 4)) == 3 via solver SAT":
    ## x-projection: build Point(3,4) then apply proj[0]; result should == 3.
    let ctx = newContext()
    withContext ctx:
      let intS = ctx.checkErr Z3_mk_int_sort(ctx.raw)
      let (_, ctor, projs) =
        mkTupleSort(ctx, "Point", [("x", intS), ("y", intS)])
      let three = mkInt(3)
      let four  = mkInt(4)
      var ctorArgs: array[2, RawZ3Ast] = [three.raw, four.raw]
      let pRaw = ctx.checkErr Z3_mk_app(ctx.raw, ctor, 2,
        cast[ptr UncheckedArray[RawZ3Ast]](addr ctorArgs[0]))
      let p = wrap[Z3Ast[stUninterpreted]](ctx, pRaw)
      var pArg = p.raw
      let xRaw = ctx.checkErr Z3_mk_app(ctx.raw, projs[0], 1,
        cast[ptr UncheckedArray[RawZ3Ast]](addr pArg))
      let xVal = wrap[Z3Int](ctx, xRaw)
      check smtValid(xVal == three)

  test "y(Point(3, 4)) == 4 via solver SAT":
    ## y-projection in a fresh context — see file header Z3 4.15 note.
    let ctx = newContext()
    withContext ctx:
      let intS = ctx.checkErr Z3_mk_int_sort(ctx.raw)
      let (_, ctor, projs) =
        mkTupleSort(ctx, "Point", [("x", intS), ("y", intS)])
      let three = mkInt(3)
      let four  = mkInt(4)
      var ctorArgs: array[2, RawZ3Ast] = [three.raw, four.raw]
      let pRaw = ctx.checkErr Z3_mk_app(ctx.raw, ctor, 2,
        cast[ptr UncheckedArray[RawZ3Ast]](addr ctorArgs[0]))
      let p = wrap[Z3Ast[stUninterpreted]](ctx, pRaw)
      var pArg = p.raw
      let yRaw = ctx.checkErr Z3_mk_app(ctx.raw, projs[1], 1,
        cast[ptr UncheckedArray[RawZ3Ast]](addr pArg))
      let yVal = wrap[Z3Int](ctx, yRaw)
      check smtValid(yVal == four)

suite "mkTupleSort — distinctness":
  test "Point(1, 2) != Point(1, 3) is valid":
    ## Two tuples with different y-fields are not equal.
    ## The raw tuple-application results must be inc_ref'd IMMEDIATELY after
    ## each Z3_mk_app call — before any subsequent Z3 API call — to prevent
    ## Z3 4.15's internal GC from recycling the slot and aliasing both raw
    ## handles to the same underlying node. We balance with dec_ref after the
    ## formula is built and the references are no longer needed.
    let ctx = newContext()
    withContext ctx:
      let intS = ctx.checkErr Z3_mk_int_sort(ctx.raw)
      let (_, ctor, _) =
        mkTupleSort(ctx, "Point", [("x", intS), ("y", intS)])
      let one   = mkInt(1)
      let two   = mkInt(2)
      let three = mkInt(3)
      var args12: array[2, RawZ3Ast] = [one.raw, two.raw]
      let p12Raw = ctx.checkErr Z3_mk_app(ctx.raw, ctor, 2,
        cast[ptr UncheckedArray[RawZ3Ast]](addr args12[0]))
      Z3_inc_ref(ctx.raw, p12Raw)  # pin before next Z3 call
      var args13: array[2, RawZ3Ast] = [one.raw, three.raw]
      let p13Raw = ctx.checkErr Z3_mk_app(ctx.raw, ctor, 2,
        cast[ptr UncheckedArray[RawZ3Ast]](addr args13[0]))
      Z3_inc_ref(ctx.raw, p13Raw)  # pin before next Z3 call
      let eqRaw = ctx.checkErr Z3_mk_eq(ctx.raw, p12Raw, p13Raw)
      Z3_dec_ref(ctx.raw, p12Raw)  # no longer need raw handle
      Z3_dec_ref(ctx.raw, p13Raw)
      let neq = wrap[Z3Bool](ctx, ctx.checkErr Z3_mk_not(ctx.raw, eqRaw))
      check smtValid(neq)

suite "mkTupleSort — context-free overload":
  test "mkTupleSort without explicit ctx compiles and returns correct shapes":
    let ctx = newContext()
    withContext ctx:
      let intS = ctx.checkErr Z3_mk_int_sort(ctx.raw)
      let (sort, ctor, projs) =
        mkTupleSort("Pair", [("fst", intS), ("snd", intS)])
      check not sort.isNil
      check not ctor.isNil
      check projs.len == 2

## N2.3 — Datatype sort introspection tests.
##
## `numConstructors` / `constructor` / `recognizer` / `constructorAccessor`
## on `Z3DatatypeDecl[T]`.  Uses a classic singly-linked `List` type
## (`nil | cons(head: Z3Int, tail: List)`) as the canonical example.

import std/[unittest]
import z3

type List = object  ## marker for the self-recursive List datatype

# ---------------------------------------------------------------------------
# Helpers: build the List decl fresh inside each test to avoid cross-context
# contamination.
# ---------------------------------------------------------------------------

template withList(body: untyped) =
  let ctx {.inject.} = newContext()
  let listDt {.inject.} = declareDatatype[List](@[
    constructor("nil"),
    constructor("cons", @[
      field("head", Z3Int),
      selfField("tail")])
  ])
  body

suite "N2.3 — numConstructors":
  test "List has exactly 2 constructors":
    withList:
      check listDt.numConstructors == 2

  test "numConstructors is stable across repeated calls":
    withList:
      check listDt.numConstructors == listDt.numConstructors

suite "N2.3 — constructor (index overload)":
  test "constructor(0) returns a non-nil func_decl":
    withList:
      let nilCon = listDt.constructor(0)
      check not nilCon.isNil

  test "constructor(1) returns a non-nil func_decl":
    withList:
      let consCon = listDt.constructor(1)
      check not consCon.isNil

  test "constructor(0) and constructor(1) are distinct":
    withList:
      let c0 = listDt.constructor(0)
      let c1 = listDt.constructor(1)
      check c0 != c1

  test "constructor out-of-range raises Z3Error":
    withList:
      expect Z3Error:
        discard listDt.constructor(2)

  test "constructor negative index raises Z3Error":
    withList:
      expect Z3Error:
        discard listDt.constructor(-1)

suite "N2.3 — recognizer (index overload)":
  test "recognizer(0) returns a non-nil func_decl":
    withList:
      let recog0 = listDt.recognizer(0)
      check not recog0.isNil

  test "recognizer(1) returns a non-nil func_decl":
    withList:
      let recog1 = listDt.recognizer(1)
      check not recog1.isNil

  test "recognizer(0) and recognizer(1) are distinct":
    withList:
      let r0 = listDt.recognizer(0)
      let r1 = listDt.recognizer(1)
      check r0 != r1

  test "recognizer(0) is callable on a nil value — result is SMT-valid":
    ## Apply the raw recognizer func_decl directly via Z3_mk_app
    ## to confirm Z3 accepts the application, then SMT-check validity.
    withList:
      let nilVal = listDt.con("nil").apply()
      let recog0 = listDt.recognizer(0)
      # Build the recognizer application manually using Z3_mk_app.
      # This validates that the raw RawZ3FuncDecl is well-formed.
      var arg = nilVal.raw
      let appRaw = ctx.checkErr Z3_mk_app(ctx.raw, recog0,
                                          1.cuint,
                                          cast[ptr UncheckedArray[RawZ3Ast]](addr arg))
      check not appRaw.isNil
      # Wrap and SMT-check: `is-nil(nil)` must be valid.
      let appBool = wrap[Z3Bool](ctx, appRaw)
      check smtValid(appBool)

  test "recognizer(1) applied to a cons value is SMT-valid":
    withList:
      let consVal = listDt.con("cons").apply(mkInt(42),
                                             listDt.con("nil").apply())
      let recog1 = listDt.recognizer(1)
      var arg = consVal.raw
      let appRaw = ctx.checkErr Z3_mk_app(ctx.raw, recog1,
                                          1.cuint,
                                          cast[ptr UncheckedArray[RawZ3Ast]](addr arg))
      let appBool = wrap[Z3Bool](ctx, appRaw)
      check smtValid(appBool)

  test "recognizer(0) applied to a cons value is SMT-unsatisfiable (negated)":
    ## is-nil(cons(42, nil)) is false; its negation is valid.
    withList:
      let consVal = listDt.con("cons").apply(mkInt(42),
                                             listDt.con("nil").apply())
      let recog0 = listDt.recognizer(0)
      var arg = consVal.raw
      let appRaw = ctx.checkErr Z3_mk_app(ctx.raw, recog0,
                                          1.cuint,
                                          cast[ptr UncheckedArray[RawZ3Ast]](addr arg))
      let appBool = wrap[Z3Bool](ctx, appRaw)
      # `is-nil(cons(...))` is false, so `not` of it is valid.
      check smtValid(not appBool)

  test "recognizer out-of-range raises Z3Error":
    withList:
      expect Z3Error:
        discard listDt.recognizer(3)

suite "N2.3 — constructorAccessor":
  test "constructorAccessor(1, 0) returns a non-nil func_decl (head)":
    ## ctor 1 = cons; accessor 0 = head (first field)
    withList:
      let headAcc = listDt.constructorAccessor(1, 0)
      check not headAcc.isNil

  test "constructorAccessor(1, 1) returns a non-nil func_decl (tail)":
    ## ctor 1 = cons; accessor 1 = tail (second field)
    withList:
      let tailAcc = listDt.constructorAccessor(1, 1)
      check not tailAcc.isNil

  test "constructorAccessor(1, 0) and (1, 1) are distinct":
    withList:
      let headAcc = listDt.constructorAccessor(1, 0)
      let tailAcc = listDt.constructorAccessor(1, 1)
      check headAcc != tailAcc

  test "constructorAccessor(1, 0) applied to cons(42, nil) reads back 42":
    ## Apply the head accessor raw func_decl to cons(42, nil) and
    ## verify the result is SMT-equivalent to mkInt(42).
    withList:
      let consVal = listDt.con("cons").apply(mkInt(42),
                                             listDt.con("nil").apply())
      let headAcc = listDt.constructorAccessor(1, 0)
      var arg = consVal.raw
      let appRaw = ctx.checkErr Z3_mk_app(ctx.raw, headAcc,
                                          1.cuint,
                                          cast[ptr UncheckedArray[RawZ3Ast]](addr arg))
      check not appRaw.isNil
      let headVal = wrap[Z3Int](ctx, appRaw)
      check smtEquiv(headVal, mkInt(42))

  test "constructorAccessor ctor out-of-range raises Z3Error":
    withList:
      expect Z3Error:
        discard listDt.constructorAccessor(5, 0)

  test "constructorAccessor ctor negative index raises Z3Error":
    withList:
      expect Z3Error:
        discard listDt.constructorAccessor(-1, 0)

suite "N2.3 — name-keyed vs index-keyed parity":
  test "name-keyed recognizer and index recognizer(1) agree on cons value":
    ## The name-keyed `recognizer` uses the Nim-side cache; the index form
    ## queries Z3 directly. Both must produce SMT-equivalent results.
    withList:
      let consVal = listDt.con("cons").apply(mkInt(7),
                                             listDt.con("nil").apply())
      # Name-keyed path
      let namedRecog = listDt.recognizer("cons")
      let namedResult = namedRecog.test(consVal)
      # Index-keyed path: ctor 1 is "cons"
      let rawRecog1 = listDt.recognizer(1)
      var arg = consVal.raw
      let appRaw = ctx.checkErr Z3_mk_app(ctx.raw, rawRecog1,
                                          1.cuint,
                                          cast[ptr UncheckedArray[RawZ3Ast]](addr arg))
      let indexResult = wrap[Z3Bool](ctx, appRaw)
      # Both should be valid (i.e. is-cons(cons(7, nil)) is true).
      check smtValid(namedResult)
      check smtValid(indexResult)

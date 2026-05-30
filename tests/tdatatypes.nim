## `z3/datatypes` tests — phantom-typed inductive sums.
##
## Phantom design: `Z3DatatypeValue[T]` with `T` a Nim marker type.
## Each `declareDatatype[Foo](...)` produces a `Z3DatatypeDecl[Foo]`
## whose values are typed `Z3DatatypeValue[Foo]`, distinct from
## `Z3DatatypeValue[Bar]` for any other marker.

import std/[unittest]
import z3

type Maybe = object   # marker for the datatype declared below

suite "datatypes — tracer":
  test "Maybe with Just(42) is recognised as just":
    let ctx = newContext()
    let MaybeDt = declareDatatype[Maybe](@[
      constructor("nothing"),
      constructor("just", @[field("value", Z3Int)])
    ])
    let just = MaybeDt.con("just")
    let isJust = MaybeDt.recognizer("just")
    let v = just.apply(mkInt(42))
    check smtValid(isJust.test(v))

  test "accessor reads the field back as the original value":
    let ctx = newContext()
    let MaybeDt = declareDatatype[Maybe](@[
      constructor("nothing"),
      constructor("just", @[field("value", Z3Int)])
    ])
    let just = MaybeDt.con("just")
    let value = MaybeDt.accessor("just", "value", Z3Int)
    let v = just.apply(mkInt(42))
    check smtEquiv(value.read(v), mkInt(42))

  test "nothing is recognised as nothing, not just":
    let ctx = newContext()
    let MaybeDt = declareDatatype[Maybe](@[
      constructor("nothing"),
      constructor("just", @[field("value", Z3Int)])
    ])
    let nothing = MaybeDt.con("nothing")
    let isJust = MaybeDt.recognizer("just")
    let isNothing = MaybeDt.recognizer("nothing")
    let v = nothing.apply()
    check smtValid(isNothing.test(v))
    check smtValid(not isJust.test(v))

  test "two just(42) values are SMT-equal":
    let ctx = newContext()
    let MaybeDt = declareDatatype[Maybe](@[
      constructor("nothing"),
      constructor("just", @[field("value", Z3Int)])
    ])
    let just = MaybeDt.con("just")
    let a = just.apply(mkInt(42))
    let b = just.apply(mkInt(42))
    check smtValid(a == b)

  test "just(1) and just(2) are SMT-distinct":
    let ctx = newContext()
    let MaybeDt = declareDatatype[Maybe](@[
      constructor("nothing"),
      constructor("just", @[field("value", Z3Int)])
    ])
    let just = MaybeDt.con("just")
    check smtValid(just.apply(mkInt(1)) != just.apply(mkInt(2)))

type IntList = object

suite "datatypes — recursive (IntList)":
  test "cons(1, cons(2, nil)) walks via head/tail accessors":
    let ctx = newContext()
    let L = declareDatatype[IntList](@[
      constructor("nil"),
      constructor("cons", @[
        field("head", Z3Int),
        selfField("tail")
      ])
    ])
    let nilC = L.con("nil")
    let consC = L.con("cons")
    let head = L.accessor("cons", "head", Z3Int)
    let tail = L.accessor("cons", "tail", Z3DatatypeValue[IntList])
    let isCons = L.recognizer("cons")
    let isNil = L.recognizer("nil")

    let myList = consC.apply(mkInt(1), consC.apply(mkInt(2), nilC.apply()))
    check smtValid(isCons.test(myList))
    check smtEquiv(head.read(myList), mkInt(1))

    let rest = tail.read(myList)
    check smtValid(isCons.test(rest))
    check smtEquiv(head.read(rest), mkInt(2))

    let last = tail.read(rest)
    check smtValid(isNil.test(last))

  test "cons(1, nil) is SMT-distinct from cons(2, nil)":
    let ctx = newContext()
    let L = declareDatatype[IntList](@[
      constructor("nil"),
      constructor("cons", @[
        field("head", Z3Int),
        selfField("tail")
      ])
    ])
    let nilC = L.con("nil")
    let consC = L.con("cons")
    let a = consC.apply(mkInt(1), nilC.apply())
    let b = consC.apply(mkInt(2), nilC.apply())
    check smtValid(a != b)

  test "solver: find a list whose head is 7":
    let ctx = newContext()
    let L = declareDatatype[IntList](@[
      constructor("nil"),
      constructor("cons", @[
        field("head", Z3Int),
        selfField("tail")
      ])
    ])
    let head = L.accessor("cons", "head", Z3Int)
    let isCons = L.recognizer("cons")

    let x = L.mkDatatypeVar("x")
    let s = newSolver()
    s.add isCons.test(x)
    s.add head.read(x) == mkInt(7)
    check s.check() == zsSat

suite "datatypes — phantom type distinction":
  test "Maybe-recognizer cannot be applied to an IntList value":
    let ctx = newContext()
    let MaybeDt = declareDatatype[Maybe](@[
      constructor("nothing"),
      constructor("just", @[field("value", Z3Int)])
    ])
    let L = declareDatatype[IntList](@[
      constructor("nil"),
      constructor("cons", @[
        field("head", Z3Int),
        selfField("tail")
      ])
    ])
    let isJust = MaybeDt.recognizer("just")
    let nilList = L.con("nil").apply()
    # Pass an IntList value to a Maybe recognizer — phantom type
    # mismatch caught at compile time.
    check not compiles(isJust.test(nilList))
    # Sanity: matching phantom still compiles.
    let nothing = MaybeDt.con("nothing").apply()
    check compiles(isJust.test(nothing))

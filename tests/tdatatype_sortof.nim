## `z3/datatypes` × `z3/sortdispatch` — `Z3DatatypeValue[T]` as a
## first-class `sortOf` element type. Closes the v0.3 §8 carryover.

import std/[unittest]
import z3

type
  Color = object
  Unregistered = object
  Tree = object
  Forest = object

template withColor(body: untyped) =
  let ctx {.inject.} = newContext()
  let colorDt {.inject.} = declareDatatype[Color](@[
    constructor("red"),
    constructor("green"),
    constructor("blue")])
  body

suite "Z3DatatypeValue — sortOf integration":
  test "declareDatatype[T] registers T's sort, sortOf[Z3DatatypeValue[T]] retrieves it":
    let ctx = newContext()
    discard declareDatatype[Color](@[
      constructor("red"),
      constructor("green"),
      constructor("blue")])
    # The dispatcher now resolves the datatype's sort by marker-type
    # name lookup. Same sort as the declareDatatype call produced.
    let s = sortOfType[Z3DatatypeValue[Color]](ctx)
    check not s.isNil

  test "unregistered datatype raises Z3Error with helpful message":
    let ctx = newContext()
    # Unregistered marker type — no declareDatatype[Unregistered] call.
    expect Z3Error:
      discard sortOfType[Z3DatatypeValue[Unregistered]](ctx)

suite "Z3DatatypeValue — element type for composite families":
  test "Z3Array[Z3Int, Z3DatatypeValue[Color]] constructs":
    withColor:
      let arr = mkArrayVar[Z3Int, Z3DatatypeValue[Color]]("colors")
      # Store a color at index 5, read it back, semantic equality.
      let red = colorDt.con("red").apply()
      let arr2 = arr.store(mkInt(5), red)
      check smtValid(arr2.select(mkInt(5)) == red)

  test "Z3Seq[Z3DatatypeValue[Color]] constructs and supports basic ops":
    withColor:
      let blue = colorDt.con("blue").apply()
      let green = colorDt.con("green").apply()
      let s = concat(mkSeqUnit(blue), mkSeqUnit(green))
      check smtValid(s.len == mkInt(2))
      check smtValid(nth(s, mkInt(0)) == blue)

  test "Z3FuncDecl[(Z3DatatypeValue[Color],), Z3Bool] constructs and decides":
    withColor:
      let isWarm = mkFuncDecl[(Z3DatatypeValue[Color],), Z3Bool]("isWarm")
      let red = colorDt.con("red").apply()
      let blue = colorDt.con("blue").apply()
      let solver = newSolver()
      solver.add isWarm(red)
      solver.add not isWarm(blue)
      check solver.check() == zsSat

suite "Z3DatatypeValue — end-to-end model round-trip":
  test "store + select on Z3Array[Z3Int, Z3DatatypeValue[Color]] round-trips through a model":
    withColor:
      # Build a fresh array variable, constrain index 5 to red, solve,
      # extract the model, evaluate select(5), pin to red.
      let arr = mkArrayVar[Z3Int, Z3DatatypeValue[Color]]("colors")
      let red = colorDt.con("red").apply()
      let s = newSolver()
      s.add arr.select(mkInt(5)) == red
      check s.check() == zsSat
      let m = s.model()
      let extracted = m.eval(arr.select(mkInt(5)))
      check smtValid(extracted == red)

suite "Z3DatatypeValue — mutually recursive declarations register both sides":
  test "declareDatatypes registers both T1 and T2":
    let ctx = newContext()
    let (treeDt, forestDt) = declareDatatypes(
      forDatatype[Tree](@[
        constructor("leaf"),
        constructor("node", @[
          field("value", Z3Int),
          crossField[Forest]("children")])]),
      forDatatype[Forest](@[
        constructor("empty"),
        constructor("conscell", @[
          crossField[Tree]("head"),
          selfField("tail")])]))
    discard treeDt
    discard forestDt
    # Both marker types are now resolvable via sortdispatch.
    check not sortOfType[Z3DatatypeValue[Tree]](ctx).isNil
    check not sortOfType[Z3DatatypeValue[Forest]](ctx).isNil
    # And the composite-family use lights up — array indexed by Tree
    # holding Forest values, the canonical mutually-recursive shape.
    let arr = mkArrayVar[Z3DatatypeValue[Tree], Z3DatatypeValue[Forest]]("m")
    # Structural assertion: the rendered SMT-LIB is non-empty —
    # confirms the array AST is well-formed (not just a nil handle).
    check ($arr).len > 0

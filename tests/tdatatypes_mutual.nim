## `z3/datatypes` — mutually recursive declarations.
##
## The canonical example: `Tree = leaf | node(value: Int, children: Forest)`,
## `Forest = empty | conscell(head: Tree, tail: Forest)`. Both reference
## each other; both go through `Z3_mk_datatypes` (plural) in one call.

import std/[unittest]
import z3

type Tree = object
type Forest = object

suite "mutually recursive datatypes — tracer":
  test "node(7, empty) is recognised as a node":
    let ctx = newContext()
    let (treeDt, forestDt) = declareDatatypes(
      forDatatype[Tree](@[
        constructor("leaf"),
        constructor("node", @[
          field("value", Z3Int),
          crossField[Forest]("children")
        ])
      ]),
      forDatatype[Forest](@[
        constructor("empty"),
        constructor("conscell", @[
          crossField[Tree]("head"),
          selfField("tail")
        ])
      ])
    )
    let node = treeDt.con("node")
    let empty = forestDt.con("empty")
    let isNode = treeDt.recognizer("node")

    let v = node.apply(mkInt(7), empty.apply())
    check smtValid(isNode.test(v))

# Outside the suite so we can reuse this datatype in multiple tests
# without paying the declareDatatypes cost each test.
proc treeForestDecls(): (Z3DatatypeDecl[Tree], Z3DatatypeDecl[Forest]) =
  declareDatatypes(
    forDatatype[Tree](@[
      constructor("leaf"),
      constructor("node", @[
        field("value", Z3Int),
        crossField[Forest]("children")
      ])
    ]),
    forDatatype[Forest](@[
      constructor("empty"),
      constructor("conscell", @[
        crossField[Tree]("head"),
        selfField("tail")
      ])
    ])
  )

suite "mutually recursive datatypes — accessors":
  test "read value field from a node yields the original int":
    let ctx = newContext()
    let (treeDt, forestDt) = treeForestDecls()
    let node = treeDt.con("node")
    let empty = forestDt.con("empty")
    let value = treeDt.accessor("node", "value", Z3Int)
    let v = node.apply(mkInt(42), empty.apply())
    check smtEquiv(value.read(v), mkInt(42))

  test "read children field yields a Forest, recognised as empty":
    let ctx = newContext()
    let (treeDt, forestDt) = treeForestDecls()
    let node = treeDt.con("node")
    let empty = forestDt.con("empty")
    let children = treeDt.accessor(
      "node", "children", Z3DatatypeValue[Forest])
    let isEmpty = forestDt.recognizer("empty")
    let v = node.apply(mkInt(42), empty.apply())
    let kids = children.read(v)
    check kids is Z3DatatypeValue[Forest]
    check smtValid(isEmpty.test(kids))

  test "conscell head reads back as the original Tree":
    let ctx = newContext()
    let (treeDt, forestDt) = treeForestDecls()
    let leaf = treeDt.con("leaf")
    let empty = forestDt.con("empty")
    let conscell = forestDt.con("conscell")
    let headA = forestDt.accessor(
      "conscell", "head", Z3DatatypeValue[Tree])
    let isLeaf = treeDt.recognizer("leaf")
    let f = conscell.apply(leaf.apply(), empty.apply())
    check smtValid(isLeaf.test(headA.read(f)))

  test "conscell tail (selfField) reads back as a Forest":
    let ctx = newContext()
    let (treeDt, forestDt) = treeForestDecls()
    let leaf = treeDt.con("leaf")
    let empty = forestDt.con("empty")
    let conscell = forestDt.con("conscell")
    let tailA = forestDt.accessor(
      "conscell", "tail", Z3DatatypeValue[Forest])
    let isEmpty = forestDt.recognizer("empty")
    let f = conscell.apply(leaf.apply(), empty.apply())
    check smtValid(isEmpty.test(tailA.read(f)))

suite "mutually recursive datatypes — solver":
  test "find a Tree node whose value is 7":
    let ctx = newContext()
    let (treeDt, forestDt) = treeForestDecls()
    let isNode = treeDt.recognizer("node")
    let value = treeDt.accessor("node", "value", Z3Int)
    let x = treeDt.mkDatatypeVar("x")
    let s = newSolver()
    s.add isNode.test(x)
    s.add value.read(x) == mkInt(7)
    check s.check() == zsSat

suite "mutually recursive datatypes — phantom distinction":
  test "Tree-recognizer applied to Forest value is a compile error":
    let ctx = newContext()
    let (treeDt, forestDt) = treeForestDecls()
    let isNode = treeDt.recognizer("node")
    let isEmpty = forestDt.recognizer("empty")
    let leaf = treeDt.con("leaf")
    let empty = forestDt.con("empty")
    let treeVal = leaf.apply()
    let forestVal = empty.apply()
    # Matching phantom compiles.
    check compiles(isNode.test(treeVal))
    check compiles(isEmpty.test(forestVal))
    # Crossing phantom doesn't.
    check not compiles(isNode.test(forestVal))
    check not compiles(isEmpty.test(treeVal))

# Three-datatype cycle: A holds a B; B holds a C; C holds an A.
type DtA = object
type DtB = object
type DtC = object

suite "mutually recursive datatypes — 3-tuple":
  test "A→B→C→A cycle declared and walked (with base cases)":
    # Z3 requires every mutually recursive datatype family to be
    # well-founded — at least one constructor in *each* datatype must
    # not require the recursive cycle to bottom out. Without that
    # `Z3_mk_datatypes` fails with "datatype is not well-founded."
    # Here every member gets a `nil*` base case.
    let ctx = newContext()
    let (aDt, bDt, cDt) = declareDatatypes(
      forDatatype[DtA](@[
        constructor("nilA"),
        constructor("mkA", @[crossField[DtB]("b")])
      ]),
      forDatatype[DtB](@[
        constructor("nilB"),
        constructor("mkB", @[crossField[DtC]("c")])
      ]),
      forDatatype[DtC](@[
        constructor("nilC"),
        constructor("mkC", @[crossField[DtA]("a"), field("tag", Z3Int)])
      ])
    )
    let mkA = aDt.con("mkA")
    let mkB = bDt.con("mkB")
    let mkC = cDt.con("mkC")
    let nilA = aDt.con("nilA")
    let bField = aDt.accessor("mkA", "b", Z3DatatypeValue[DtB])
    let cField = bDt.accessor("mkB", "c", Z3DatatypeValue[DtC])
    let aField = cDt.accessor("mkC", "a", Z3DatatypeValue[DtA])
    let tag    = cDt.accessor("mkC", "tag", Z3Int)

    let cVal = mkC.apply(nilA.apply(), mkInt(99))
    let bVal = mkB.apply(cVal)
    let aVal = mkA.apply(bVal)

    check smtValid(aField.read(cField.read(bField.read(aVal))) ==
                   nilA.apply())
    check smtEquiv(tag.read(cField.read(bField.read(aVal))), mkInt(99))

type StrandingX = object
type StrandingY = object

suite "mutually recursive datatypes — error paths":
  test "crossField in single declareDatatype raises Z3Error":
    let ctx = newContext()
    # `crossField[Y]` references a sibling that's not in this batch —
    # `declareDatatype` (singular) has no sibling table, so the
    # cross-reference can't resolve. We surface a clear Z3Error.
    expect Z3Error:
      discard declareDatatype[StrandingX](@[
        constructor("foo", @[crossField[StrandingY]("dangling")])
      ])

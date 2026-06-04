## `z3/datatypes` — `updateField` functional record update (N7.4).
##
## `updateField(accessor, record, newVal)` wraps `Z3_datatype_update_field`:
## given a typed `Z3AccessorDecl[T, Ret]`, a record value, and a new field
## value of sort `Ret`, it returns a new `Z3DatatypeValue[T]` in which the
## named field has been replaced while all other fields are preserved.
##
## The test uses a two-field `Point` record (`x: int`, `y: int`) declared
## via `declareDatatype`.  After `p = Point(3, 4)` and
## `p2 = updateField(xAccessor, p, mkInt(10))`, the solver must confirm
## `x(p2) == 10` and `y(p2) == 4`.

import std/[unittest]
import z3

type Point = object   # marker for the Point datatype

suite "updateField — tracer":
  test "updateField replaces targeted field; other field is preserved":
    let ctx = newContext()
    let PointDt = declareDatatype[Point](@[
      constructor("mkPoint", @[
        field("x", Z3Int),
        field("y", Z3Int)
      ])
    ])
    let mkPointC = PointDt.con("mkPoint")
    let xAcc     = PointDt.accessor("mkPoint", "x", Z3Int)
    let yAcc     = PointDt.accessor("mkPoint", "y", Z3Int)

    # Build p = Point(3, 4)
    let p = mkPointC.apply(mkInt(3), mkInt(4))

    # Functional update: p2 = {p with x = 10}
    let p2 = updateField(xAcc, p, mkInt(10))

    # x(p2) must be 10
    check smtEquiv(xAcc.read(p2), mkInt(10))
    # y(p2) must still be 4
    check smtEquiv(yAcc.read(p2), mkInt(4))

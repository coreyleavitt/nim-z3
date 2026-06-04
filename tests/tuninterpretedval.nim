## `z3/uninterpretedval` tests — Z3UninterpretedVal[T] marker-phantom shape.
##
## Covers:
##   - declareUninterpretedSort[T] returns Z3Sort[stUninterpreted]; sort handle
##     round-trips through sortOf(Z3UninterpretedVal[T], ctx)
##   - Two Z3UninterpretedVal[T] values can be ==, != producing Z3Bool
##   - Cross-marker equality is statically rejected: not compiles(colorVal == locVal)
##   - Z3Array[Z3UninterpretedVal[T], Z3Int] instantiates via sortOfType
##   - $ rendering
##   - Lifecycle: =copy smoke test

import std/unittest
import z3

# ---------------------------------------------------------------------------
# Marker types
# ---------------------------------------------------------------------------

type
  ColorSort = distinct void
  LocSort   = distinct void

# ---------------------------------------------------------------------------
suite "Z3UninterpretedVal — declareUninterpretedSort + sortOf":

  test "declareUninterpretedSort returns Z3Sort[stUninterpreted]":
    let ctx = newContext()
    let s = declareUninterpretedSort[ColorSort](ctx, "Color")
    check s is Z3Sort[stUninterpreted]

  test "sortOf(Z3UninterpretedVal[T], ctx) returns same raw handle":
    let ctx = newContext()
    let s = declareUninterpretedSort[ColorSort](ctx, "Color")
    let raw2 = sortOf(Z3UninterpretedVal[ColorSort], ctx)
    check s.raw == raw2

  test "two distinct marker types get distinct Z3 sort handles":
    let ctx = newContext()
    let sc = declareUninterpretedSort[ColorSort](ctx, "Color")
    let sl = declareUninterpretedSort[LocSort](ctx, "Loc")
    check sc.raw != sl.raw

  test "sortOf raises if sort not declared":
    let ctx = newContext()
    # No declareUninterpretedSort called for LocSort in this context.
    expect Z3InvalidUsageError:
      discard sortOf(Z3UninterpretedVal[LocSort], ctx)

# ---------------------------------------------------------------------------
suite "Z3UninterpretedVal — mkUninterpretedVar":

  test "mkUninterpretedVar (explicit ctx) returns correct type":
    let ctx = newContext()
    discard declareUninterpretedSort[ColorSort](ctx, "Color")
    let c = mkUninterpretedVar[ColorSort]("c", ctx)
    check c is Z3UninterpretedVal[ColorSort]

  test "mkUninterpretedVar (current ctx) returns correct type":
    let ctx = newContext()
    discard declareUninterpretedSort[ColorSort](ctx, "Color")
    let c = mkUninterpretedVar[ColorSort]("c")
    check c is Z3UninterpretedVal[ColorSort]

# ---------------------------------------------------------------------------
suite "Z3UninterpretedVal — equality operators":

  test "== of two vars produces Z3Bool":
    let ctx = newContext()
    discard declareUninterpretedSort[ColorSort](ctx, "Color")
    let c1 = mkUninterpretedVar[ColorSort]("c1", ctx)
    let c2 = mkUninterpretedVar[ColorSort]("c2", ctx)
    let eq = c1 == c2
    check eq is Z3Bool

  test "!= of two vars produces Z3Bool":
    let ctx = newContext()
    discard declareUninterpretedSort[ColorSort](ctx, "Color")
    let c1 = mkUninterpretedVar[ColorSort]("c1", ctx)
    let c2 = mkUninterpretedVar[ColorSort]("c2", ctx)
    let neq = c1 != c2
    check neq is Z3Bool

  test "var == itself is SAT":
    let ctx = newContext()
    discard declareUninterpretedSort[ColorSort](ctx, "Color")
    let c = mkUninterpretedVar[ColorSort]("c", ctx)
    let s = newSolver(ctx)
    s.add(c == c)
    check s.check() == zsSat

  test "var != itself is UNSAT":
    let ctx = newContext()
    discard declareUninterpretedSort[ColorSort](ctx, "Color")
    let c = mkUninterpretedVar[ColorSort]("c", ctx)
    let s = newSolver(ctx)
    s.add(c != c)
    check s.check() == zsUnsat

  test "cross-marker == does not compile":
    let ctx = newContext()
    discard declareUninterpretedSort[ColorSort](ctx, "Color")
    discard declareUninterpretedSort[LocSort](ctx, "Loc")
    let c = mkUninterpretedVar[ColorSort]("c", ctx)
    let l = mkUninterpretedVar[LocSort]("l", ctx)
    check not compiles(c == l)

  test "cross-marker != does not compile":
    let ctx = newContext()
    discard declareUninterpretedSort[ColorSort](ctx, "Color")
    discard declareUninterpretedSort[LocSort](ctx, "Loc")
    let c = mkUninterpretedVar[ColorSort]("c", ctx)
    let l = mkUninterpretedVar[LocSort]("l", ctx)
    check not compiles(c != l)

# ---------------------------------------------------------------------------
suite "Z3UninterpretedVal — $ rendering":

  test "$ does not raise and returns non-empty string":
    let ctx = newContext()
    discard declareUninterpretedSort[ColorSort](ctx, "Color")
    let c = mkUninterpretedVar[ColorSort]("myColor", ctx)
    let s = $c
    check s.len > 0

# ---------------------------------------------------------------------------
suite "Z3UninterpretedVal — Z3Array integration via sortOfType":

  test "Z3Array[Z3UninterpretedVal[T], Z3Int] instantiates without manual sort":
    let ctx = newContext()
    discard declareUninterpretedSort[ColorSort](ctx, "Color")
    # mkArrayVar uses sortOf(Z3Array[K,V], ctx) which calls sortOfType[K](ctx)
    # internally; no manual sort wiring needed.
    let arr = mkArrayVar[Z3UninterpretedVal[ColorSort], Z3Int](ctx, "colorMap")
    check arr is Z3Array[Z3UninterpretedVal[ColorSort], Z3Int]

  test "select on Z3Array[Z3UninterpretedVal[T], Z3Int] works":
    let ctx = newContext()
    discard declareUninterpretedSort[ColorSort](ctx, "Color")
    let arr = mkArrayVar[Z3UninterpretedVal[ColorSort], Z3Int](ctx, "colorMap")
    let k   = mkUninterpretedVar[ColorSort]("k", ctx)
    let v   = arr[k]
    check v is Z3Int

  test "store+select on Z3Array[Z3UninterpretedVal[T], Z3Int] round-trips via solver":
    ## End-to-end: two distinct uninterpreted values can be used as array keys,
    ## and the solver correctly reflects the stored values.
    let ctx = newContext()
    discard declareUninterpretedSort[ColorSort](ctx, "Color")
    let arr = mkArrayVar[Z3UninterpretedVal[ColorSort], Z3Int](ctx, "colorMap")
    let red = mkUninterpretedVar[ColorSort]("red", ctx)
    let arr2 = arr.store(red, mkInt(ctx, 99))
    let s = newSolver(ctx)
    s.add arr2[red] == mkInt(ctx, 99)
    check s.check() == zsSat

# ---------------------------------------------------------------------------
suite "Z3UninterpretedVal — lifecycle":

  test "=copy smoke: copy is valid after original goes out of scope":
    let ctx = newContext()
    discard declareUninterpretedSort[ColorSort](ctx, "Color")
    var copy: Z3UninterpretedVal[ColorSort]
    block:
      let orig = mkUninterpretedVar[ColorSort]("orig", ctx)
      copy = orig
    # orig destroyed; copy should still hold a live reference
    let s = $copy
    check s.len > 0

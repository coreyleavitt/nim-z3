## N2.4b — Decl parameter introspection.
##
## Tests for `declNumParameters` and `declParameter` on `RawZ3FuncDecl`
## values obtained from a `Z3_mk_extract` application.  BV `extract`
## is one of the few Z3-internal decls that carries two int parameters
## (hi and lo), making it the canonical vehicle for this slice.

import std/[unittest]
import z3

suite "N2.4b — declNumParameters":
  test "extract(7, 0) on BV[8] decl has 2 parameters":
    let ctx = newContext()
    let bv = mkBitVecVar[8](ctx, "x")
    let e = bv.extract(7, 0)
    let d = getAppDecl(e)
    check declNumParameters(ctx, d) == 2

  test "a plain user funcDecl has 0 parameters":
    let ctx = newContext()
    let f = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "F")
    check declNumParameters(ctx, f.raw) == 0

suite "N2.4b — declParameter":
  test "extract(7, 0): parameter 0 is pkInt with value 7 (hi)":
    let ctx = newContext()
    let bv = mkBitVecVar[8](ctx, "x")
    let e = bv.extract(7, 0)
    let d = getAppDecl(e)
    let p = declParameter(ctx, d, 0)
    check p.kind == pkInt
    check p.intVal == 7

  test "extract(7, 0): parameter 1 is pkInt with value 0 (lo)":
    let ctx = newContext()
    let bv = mkBitVecVar[8](ctx, "x")
    let e = bv.extract(7, 0)
    let d = getAppDecl(e)
    let p = declParameter(ctx, d, 1)
    check p.kind == pkInt
    check p.intVal == 0

  test "extract(5, 2): parameter 0 is pkInt with value 5 (hi)":
    let ctx = newContext()
    let bv = mkBitVecVar[8](ctx, "x")
    let e = bv.extract(5, 2)
    let d = getAppDecl(e)
    let p = declParameter(ctx, d, 0)
    check p.kind == pkInt
    check p.intVal == 5

  test "extract(5, 2): parameter 1 is pkInt with value 2 (lo)":
    let ctx = newContext()
    let bv = mkBitVecVar[8](ctx, "x")
    let e = bv.extract(5, 2)
    let d = getAppDecl(e)
    let p = declParameter(ctx, d, 1)
    check p.kind == pkInt
    check p.intVal == 2

  test "out-of-range parameter index raises":
    let ctx = newContext()
    let bv = mkBitVecVar[8](ctx, "x")
    let e = bv.extract(7, 0)
    let d = getAppDecl(e)
    expect AssertionDefect:
      discard declParameter(ctx, d, 2)

  test "negative parameter index raises":
    let ctx = newContext()
    let bv = mkBitVecVar[8](ctx, "x")
    let e = bv.extract(7, 0)
    let d = getAppDecl(e)
    expect AssertionDefect:
      discard declParameter(ctx, d, -1)

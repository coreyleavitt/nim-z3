## `z3/fp` sort-constructor tests — N6.2
## `mkFpSortHalf / Single / Double / Quadruple` return typed `Z3Sort[stFp]`
## and produce the same sort as the corresponding `sortOf[Z3FpXxx](ctx)` path.

import std/unittest
import z3

suite "FP sort constructors":
  test "mkFpSortHalf returns non-nil Z3Sort[stFp]":
    let ctx = newContext()
    let s = ctx.mkFpSortHalf()
    check s.raw != default(RawZ3Sort)

  test "mkFpSortSingle returns non-nil Z3Sort[stFp]":
    let ctx = newContext()
    let s = ctx.mkFpSortSingle()
    check s.raw != default(RawZ3Sort)

  test "mkFpSortDouble returns non-nil Z3Sort[stFp]":
    let ctx = newContext()
    let s = ctx.mkFpSortDouble()
    check s.raw != default(RawZ3Sort)

  test "mkFpSortQuadruple returns non-nil Z3Sort[stFp]":
    let ctx = newContext()
    let s = ctx.mkFpSortQuadruple()
    check s.raw != default(RawZ3Sort)

suite "FP sort constructors — sort ID equality with sortOf":
  test "mkFpSortHalf matches sortOf[Z3Float16]":
    let ctx = newContext()
    let s = ctx.mkFpSortHalf()
    check sortId(ctx, s.raw) == sortId(ctx, sortOf(Z3Float16, ctx))

  test "mkFpSortSingle matches sortOf[Z3Float32]":
    let ctx = newContext()
    let s = ctx.mkFpSortSingle()
    check sortId(ctx, s.raw) == sortId(ctx, sortOf(Z3Float32, ctx))

  test "mkFpSortDouble matches sortOf[Z3Float64]":
    let ctx = newContext()
    let s = ctx.mkFpSortDouble()
    check sortId(ctx, s.raw) == sortId(ctx, sortOf(Z3Float64, ctx))

  test "mkFpSortQuadruple matches sortOf[Z3Float128]":
    let ctx = newContext()
    let s = ctx.mkFpSortQuadruple()
    check sortId(ctx, s.raw) == sortId(ctx, sortOf(Z3Float128, ctx))

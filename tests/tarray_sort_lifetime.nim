## `sortOf(Z3Array[K, V])` must hold the key and value sorts it builds
## until `Z3_mk_array_sort` has read them.
##
## In a ref-counted context Z3 keeps only its LAST API result alive. A sort
## that no live term references (a float sort before any float term exists,
## an array sort) is therefore freed by the next API call that returns an
## AST. `Z3_mk_array_sort(c, sortOf(K), sortOf(V))` evaluates its two
## arguments in an order the language leaves open: the C backend evaluates
## them left to right, C++ compilers commonly right to left. Whichever sort
## is built first is freed when the second is built, and the array sort is
## made over a dangling sort. The tests build arrays in both argument orders
## and check the resulting sort's domain and range.

import std/unittest
import z3

proc checkFp(ctx: Z3Context; s: RawZ3Sort; e, sb: int) =
  check getSortKind(ctx, s) == skFp
  if getSortKind(ctx, s) == skFp:
    check fpEbits(ctx, s) == e
    check fpSbits(ctx, s) == sb

proc sortOfArr[K, V](ctx: Z3Context; a: Z3Array[K, V]): RawZ3Sort =
  ctx.checkErr Z3_get_sort(ctx.raw, a.raw)

suite "sortOf(Z3Array) holds both sorts while it builds the array sort":
  test "float32 key, float64 value":
    let ctx = newContext()
    let a = mkArrayVar[Z3Float32, Z3Float64]("a")
    let s = sortOfArr(ctx, a)
    checkFp(ctx, arrayKey(ctx, s), 8, 24)
    checkFp(ctx, arrayRange(ctx, s), 11, 53)

  test "float64 key, float32 value":
    let ctx = newContext()
    let a = mkArrayVar[Z3Float64, Z3Float32]("a")
    let s = sortOfArr(ctx, a)
    checkFp(ctx, arrayKey(ctx, s), 11, 53)
    checkFp(ctx, arrayRange(ctx, s), 8, 24)

  test "a nested array value under a float key":
    let ctx = newContext()
    let a = mkArrayVar[Z3Float32, Z3Array[Z3Float64, Z3Float32]]("a")
    let s = sortOfArr(ctx, a)
    checkFp(ctx, arrayKey(ctx, s), 8, 24)
    let inner = arrayRange(ctx, s)
    check getSortKind(ctx, inner) == skArray
    if getSortKind(ctx, inner) == skArray:
      checkFp(ctx, arrayKey(ctx, inner), 11, 53)
      checkFp(ctx, arrayRange(ctx, inner), 8, 24)

  test "a select is solvable at the built sorts":
    let ctx = newContext()
    let a = mkArrayVar[Z3Float32, Z3Float64]("a")
    let s = newSolver()
    s.add select(a, mkFloat32(1.5'f32)) == mkFloat64(2.25)
    check s.check() == zsSat

proc checkDecl(ctx: Z3Context; d: RawZ3FuncDecl; dom: seq[(int, int)];
               rng: (int, int)) =
  check int(Z3_get_domain_size(ctx.raw, d)) == dom.len
  for i, (e, sb) in dom:
    checkFp(ctx, Z3_get_domain(ctx.raw, d, cuint(i)), e, sb)
  checkFp(ctx, Z3_get_range(ctx.raw, d), rng[0], rng[1])

suite "function declarations hold their domain and range sorts":
  test "mkFuncDecl over float sorts":
    let ctx = newContext()
    let f = mkFuncDecl[(Z3Float32, Z3Float64), Z3Float32]("f")
    checkDecl(ctx, f.raw, @[(8, 24), (11, 53)], (8, 24))

  test "freshFuncDecl over float sorts":
    let ctx = newContext()
    let f = freshFuncDecl[(Z3Float64, Z3Float32), Z3Float64]("g")
    checkDecl(ctx, f.raw, @[(11, 53), (8, 24)], (11, 53))

  test "defineFun over float sorts":
    let ctx = newContext()
    let f = defineFun[Z3Float32, Z3Float64, Z3Float32]("h",
      proc(a: Z3Float32, b: Z3Float64): Z3Float32 = a)
    checkDecl(ctx, f.raw, @[(8, 24), (11, 53)], (8, 24))

  test "defineRecFun over float sorts":
    let ctx = newContext()
    let f = defineRecFun[Z3Float64, Z3Float32, Z3Float64]("r",
      proc(self: Z3FuncDecl[(Z3Float64, Z3Float32), Z3Float64];
           a: Z3Float64, b: Z3Float32): Z3Float64 = a)
    checkDecl(ctx, f.raw, @[(11, 53), (8, 24)], (11, 53))

type FPair = object

suite "datatype constructors hold their field sorts":
  test "a constructor over two float fields":
    let ctx = newContext()
    let dt = declareDatatype[FPair](ctx, @[
      constructor("mk", @[field("a", Z3Float32), field("b", Z3Float64)])])
    let c = constructor(dt, 0)
    check int(Z3_get_domain_size(ctx.raw, c)) == 2
    checkFp(ctx, Z3_get_domain(ctx.raw, c, 0), 8, 24)
    checkFp(ctx, Z3_get_domain(ctx.raw, c, 1), 11, 53)

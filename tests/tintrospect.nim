## `z3/introspect` tests — structural introspection (AST kinds + sort
## kinds + typed lifters from the erased `Z3AnyAst`).

import std/[unittest]
import z3

suite "Z3AnyAst — tracer":
  test "toAnyAst(mkInt(42)) constructs an erased AST handle":
    let ctx = newContext()
    let i = mkInt(42)
    let a = toAnyAst(i)
    # Observable via introspection: the erased handle reports the same
    # kind as the typed one would.
    check getAstKind(a) == akNumeral

suite "AST introspection — getAstKind":
  test "numerals classify as akNumeral":
    let ctx = newContext()
    check getAstKind(mkInt(42)) == akNumeral
    check getAstKind(mkBool(true)) == akApp
      # NOTE: Z3 represents Bool literals as 0-arity applications of
      # the `true` / `false` constants, not as akNumeral. Test pins
      # the observable behaviour; semantically users expect both
      # routes to "this is a constant."
    check getAstKind(mkReal(1, 2)) == akNumeral

  test "applications classify as akApp":
    let ctx = newContext()
    check getAstKind(mkInt(2) + mkInt(3)) == akApp
    check getAstKind(mkBoolVar("p") and mkBoolVar("q")) == akApp

  test "free constants classify as akApp (Z3 wraps them as 0-arity apps)":
    let ctx = newContext()
    check getAstKind(mkIntVar("x")) == akApp

  test "quantifiers classify as akQuantifier":
    let ctx = newContext()
    let x = mkIntVar("x")
    let q = forall(x, x == x)
    check getAstKind(q) == akQuantifier

suite "AST introspection — app decomposition":
  test "getAppNumArgs counts subterms":
    let ctx = newContext()
    let sum = mkInt(2) + mkInt(3)
    check getAppNumArgs(sum) == 2

  test "getAppArg returns the i-th subterm as a Z3AnyAst":
    let ctx = newContext()
    let sum = mkInt(2) + mkInt(3)
    let arg0 = getAppArg(sum, 0)
    let arg1 = getAppArg(sum, 1)
    check getAstKind(arg0) == akNumeral
    check getAstKind(arg1) == akNumeral

  test "unpackApp returns (decl, args) tuple":
    let ctx = newContext()
    let sum = mkInt(2) + mkInt(3)
    let (decl, args) = unpackApp(sum)
    check not decl.isNil
    check args.len == 2
    check getAstKind(args[0]) == akNumeral

  test "getNumeralString round-trips Int + Real numerals":
    let ctx = newContext()
    check getNumeralString(mkInt(42)) == "42"
    check getNumeralString(mkReal(1, 2)) == "1/2"

suite "Sort introspection — getSortKind dispatch":
  test "scalar sorts classify correctly":
    let ctx = newContext()
    check getSortKind(ctx, getSort(mkInt(0))) == skInt
    check getSortKind(ctx, getSort(mkBool(true))) == skBool
    check getSortKind(ctx, getSort(mkReal(0, 1))) == skReal

  test "BV sort and width":
    let ctx = newContext()
    let s = getSort(mkBitVec[32](0'u32))
    check getSortKind(ctx, s) == skBitVec
    check bitVecWidth(ctx, s) == 32

  test "Array sort, key, range":
    let ctx = newContext()
    let s = sortOfType[Z3Array[Z3Int, Z3Bool]](ctx)
    check getSortKind(ctx, s) == skArray
    check getSortKind(ctx, arrayKey(ctx, s)) == skInt
    check getSortKind(ctx, arrayRange(ctx, s)) == skBool

  test "Seq sort + element":
    let ctx = newContext()
    let s = sortOfType[Z3Seq[Z3Int]](ctx)
    check getSortKind(ctx, s) == skSeq
    check getSortKind(ctx, seqElement(ctx, s)) == skInt

  test "FP sort + ebits/sbits":
    let ctx = newContext()
    let s = getSort(mkFloat32(0.0'f32))
    check getSortKind(ctx, s) == skFp
    check fpEbits(ctx, s) == 8
    check fpSbits(ctx, s) == 24

  test "Char sort":
    let ctx = newContext()
    check getSortKind(ctx, getSort(mkChar('a'))) == skChar

suite "Typed lifters — asZ3X round-trips":
  test "asZ3Int lifts a Z3AnyAst carrying an Int back to Z3Int":
    let ctx = newContext()
    let i = mkInt(42)
    let any = toAnyAst(i)
    let back: Z3Int = asZ3Int(any)
    check smtValid(back == i)

  test "asZ3Bool / asZ3Real round-trip":
    let ctx = newContext()
    let b = mkBool(true)
    let r = mkReal(1, 2)
    check smtValid(asZ3Bool(toAnyAst(b)) == b)
    check smtValid(asZ3Real(toAnyAst(r)) == r)

  test "asZ3BitVec[W] verifies width":
    let ctx = newContext()
    let bv = mkBitVec[8](0xAA'u8)
    let any = toAnyAst(bv)
    let back: Z3BitVec[8] = asZ3BitVec[8](any)
    check smtValid(back == bv)

  test "asZ3Fp[E, S] verifies E and S":
    let ctx = newContext()
    let f = mkFloat32(3.5'f32)
    let any = toAnyAst(f)
    let back: Z3Float32 = asZ3Fp[8, 24](any)
    check smtValid(back == f)

suite "Typed lifters — error cases":
  test "asZ3Int on a Bool raises Z3Error":
    let ctx = newContext()
    let any = toAnyAst(mkBool(true))
    expect Z3Error:
      discard asZ3Int(any)

  test "asZ3BitVec[16] on a Z3BitVec[8] raises Z3Error":
    let ctx = newContext()
    let bv8 = mkBitVec[8](0xAA'u8)
    let any = toAnyAst(bv8)
    expect Z3Error:
      discard asZ3BitVec[16](any)

  test "asZ3Fp[11, 53] on a Z3Float32 raises Z3Error":
    let ctx = newContext()
    let f32 = mkFloat32(1.0'f32)
    let any = toAnyAst(f32)
    expect Z3Error:
      discard asZ3Fp[11, 53](any)

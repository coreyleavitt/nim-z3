## `z3/bitvec` — BV theory conversion tests (N3.3).
##
## `bvToInt` / `intToBv` are theory-level conversions producing Int-sorted
## or BV-sorted ASTs (contrast with the model-extractor `.toInt` / `.toUint`
## which extract Nim values from concrete BV literals).
##
## `toBitVec(b: Z3Bool): Z3BitVec[1]` is derived via `ite(b, bv1(1), bv1(0))`;
## no Z3 primitive, but semantically sound.

import std/[unittest]
import z3

suite "Z3BitVec — theory conversions (N3.3)":

  test "bvToInt: unsigned BV[8](42) == mkInt(42)":
    ## Z3_mk_bv2int(bv42, signed=false) should produce the Int-sorted value 42.
    let ctx = newContext()
    let bv = mkBitVec[8](42)
    let asInt = bvToInt(bv, signed = false)
    check smtEquiv(asInt, mkInt(42))

  test "bvToInt: signed BV[8](-1) == mkInt(-1) with signed=true":
    ## 0xFF interpreted as signed two's-complement = -1.
    let ctx = newContext()
    let bv = mkBitVec[8](-1'i32)
    let asInt = bvToInt(bv, signed = true)
    check smtEquiv(asInt, mkInt(-1))

  test "bvToInt: unsigned BV[8](-1) == mkInt(255) with signed=false":
    ## 0xFF interpreted as unsigned = 255.
    let ctx = newContext()
    let bv = mkBitVec[8](-1'i32)
    let asInt = bvToInt(bv, signed = false)
    check smtEquiv(asInt, mkInt(255))

  test "intToBv: mkInt(42) → Z3BitVec[8] == mkBitVec[8](42)":
    ## Z3_mk_int2bv(8, mkInt(42)) should produce a BV[8] equal to 42.
    let ctx = newContext()
    let bv = intToBv(mkInt(42), Z3BitVec[8])
    check smtEquiv(bv, mkBitVec[8](42))

  test "toBitVec: mkTrue() → BV[1] with toUint == 1":
    ## ite(true, bv1(1), bv1(0)) should simplify to 1.
    let ctx = newContext()
    let result = toBitVec(mkTrue())
    check result.toUint == 1

  test "toBitVec: mkFalse() → BV[1] with toUint == 0":
    ## ite(false, bv1(1), bv1(0)) should simplify to 0.
    let ctx = newContext()
    let result = toBitVec(mkFalse())
    check result.toUint == 0

  test "round-trip: intToBv(bvToInt(x, false), Z3BitVec[8]) == x for all x":
    ## For any 8-bit BV x, interpreting it as unsigned and converting back
    ## to BV[8] should yield the original value.
    let ctx = newContext()
    let x = mkBitVecVar[8]("x")
    let roundTripped = intToBv(bvToInt(x, false), Z3BitVec[8])
    check smtEquiv(roundTripped, x)

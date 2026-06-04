## `z3/fp` — N6.7 rename verification tests.
##
## Confirms that renamed symbols compile under their new names and that
## the old names are no longer available. Covers:
##   mkNaN   → mkFpNaN
##   mkInf   → mkFpInf   (negative: bool param)
##   mkZero  → mkFpZero  (negative: bool param)
##   toFp(bv, _: typedesc[Z3Fp]) → bvToFpBits
## The lossy `toFp(rm, fp, _: typedesc)` keeps its name — verified here too.

import std/[unittest]
import z3

suite "Z3Fp renames — N6.7 Piece A":

  test "mkFpNaN[11,53](ctx) builds a NaN":
    let ctx = newContext()
    let nan = mkFpNaN[11, 53](ctx)
    check isNumeralNaN(nan)

  test "mkFpNaN[11,53]() (current-context form) builds a NaN":
    let ctx = newContext()
    let nan = mkFpNaN[11, 53]()
    check isNumeralNaN(nan)

  test "mkFpNaN isNaN is true under the solver":
    let ctx = newContext()
    check smtValid(isNaN(mkFpNaN[8, 24]()))

  test "mkFpInf[11,53](ctx, negative=false) builds +Inf":
    let ctx = newContext()
    let inf = mkFpInf[11, 53](ctx, negative = false)
    check isNumeralInf(inf)
    check isNumeralPositive(inf)

  test "mkFpInf[11,53](ctx, negative=true) builds -Inf":
    let ctx = newContext()
    let inf = mkFpInf[11, 53](ctx, negative = true)
    check isNumeralInf(inf)
    check isNumeralNegative(inf)

  test "mkFpInf[8,24]() (current-context, +Inf) builds +Inf":
    let ctx = newContext()
    let inf = mkFpInf[8, 24]()
    check isNumeralInf(inf)

  test "mkFpInf symbolic isInf":
    let ctx = newContext()
    check smtValid(isInf(mkFpInf[8, 24]()))
    check smtValid(isInf(mkFpInf[8, 24](negative = true)))

  test "mkFpZero[11,53](ctx, negative=false) builds +0":
    let ctx = newContext()
    let z = mkFpZero[11, 53](ctx, negative = false)
    check isNumeralZero(z)
    check isNumeralPositive(z)

  test "mkFpZero[11,53](ctx, negative=true) builds -0":
    let ctx = newContext()
    let z = mkFpZero[11, 53](ctx, negative = true)
    check isNumeralZero(z)
    check isNumeralNegative(z)

  test "mkFpZero[8,24]() (current-context, +0)":
    let ctx = newContext()
    let z = mkFpZero[8, 24]()
    check isNumeralZero(z)

  test "mkFpZero symbolic +0 == -0 under IEEE":
    let ctx = newContext()
    check smtValid(mkFpZero[8, 24]() == mkFpZero[8, 24](negative = true))

  test "bvToFpBits(mkBitVec[64](pattern), Z3Float64) round-trips a float64":
    ## IEEE 754 binary64 bit pattern for 1.5 = 0x3FF8000000000000
    let ctx = newContext()
    let pattern = 0x3FF8000000000000'u64
    let bv = mkBitVec[64](pattern)
    let fp = bvToFpBits(bv, Z3Float64)
    # The bit pattern is exact — fp should equal 1.5 under the solver.
    check smtValid(fp == mkFloat64(1.5))

  test "bvToFpBits(mkBitVec[32](pattern), Z3Float32) round-trips a float32":
    ## IEEE 754 binary32 bit pattern for 3.5 = 0x40600000
    let ctx = newContext()
    let pattern = 0x40600000'u32
    let bv = mkBitVec[32](pattern)
    let fp = bvToFpBits(bv, Z3Float32)
    check smtValid(fp == mkFloat32(3.5'f32))

  test "toFp(rm, fp, typedesc) still compiles (lossy form keeps name)":
    ## The lossy FP-to-FP conversion must still be reachable as `toFp`.
    let ctx = newContext()
    let f32 = mkFloat32(3.5'f32)
    let f64 = toFp(rmRNE(), f32, Z3Float64)
    check smtValid(f64 == mkFloat64(3.5))

  test "old names do not compile (mkNaN, mkInf, mkZero, toFp(bv,...))":
    ## Negative compile-time check: old names must be undefined.
    check not compiles(mkNaN[8, 24]())
    check not compiles(mkInf[8, 24]())
    check not compiles(mkZero[8, 24]())
    ## bv-form toFp is also gone; lossy toFp is still present so we need
    ## to specifically check the bv-based form via a BitVec argument.
    let ctx = newContext()
    let bv = mkBitVec[32](0'u32)
    check not compiles(toFp(bv, Z3Float32))

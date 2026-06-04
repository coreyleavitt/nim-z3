## `z3/fp` — `mkFpFromParts` tests (N6.3)
##
## `Z3_mk_fpa_fp(c, sgn, exp, sig)` assembles an FP value from three
## bit-vectors: a 1-bit sign, an E-bit biased exponent, and an (S-1)-bit
## explicit significand (the hidden bit is implicit, per IEEE 754).
## No rounding mode — this is bit-exact assembly.

import std/unittest
import z3

suite "mkFpFromParts — N6.3":

  test "sgn=0, exp=0x7F, sig=0 → equals 1.0 (Float32)":
    ## IEEE 754 binary32: sign=0, biased exponent=127 (=0x7F → actual exp 0),
    ## mantissa=0  ⇒  1.0  (the canonical "1.0" bit pattern).
    let ctx = newContext()
    let sgn = mkBitVec[1](0'u32)
    let exp = mkBitVec[8](0x7F'u32)
    let sig = mkBitVec[23](0'u32)
    let fp  = mkFpFromParts[8, 24](sgn, exp, sig)
    check smtValid(fp == mkFloat32(1.0'f32))

  test "sgn=0, exp=0xFF, sig=nonzero → isNaN":
    ## exp=0xFF (all-ones), sig≠0 ⇒ NaN per IEEE 754 binary32 encoding.
    let ctx = newContext()
    let sgn = mkBitVec[1](0'u32)
    let exp = mkBitVec[8](0xFF'u32)
    let sig = mkBitVec[23](1'u32)  # any nonzero mantissa → NaN
    let fp  = mkFpFromParts[8, 24](sgn, exp, sig)
    check smtValid(isNaN(fp))

  test "sgn=0, exp=0xFF, sig=0 → positive infinity":
    ## exp=all-ones, sig=0, sign=0 ⇒ +∞ per IEEE 754.
    let ctx = newContext()
    let sgn = mkBitVec[1](0'u32)
    let exp = mkBitVec[8](0xFF'u32)
    let sig = mkBitVec[23](0'u32)
    let fp  = mkFpFromParts[8, 24](sgn, exp, sig)
    check smtValid(fp == mkFpInf[8, 24]())

  test "sgn=1, exp=0, sig=0 → negative zero (isZero AND isNegative)":
    ## sign=1, exp=0, sig=0 ⇒ −0 per IEEE 754.
    ## isZero(−0) is true; isNegative(−0) is true.
    let ctx = newContext()
    let sgn = mkBitVec[1](1'u32)
    let exp = mkBitVec[8](0'u32)
    let sig = mkBitVec[23](0'u32)
    let fp  = mkFpFromParts[8, 24](sgn, exp, sig)
    check smtValid(isZero(fp))
    check smtValid(isNegative(fp))

## `z3/bitvec` extensions for `W > 64` — string-form construction and
## extraction. The values exceed every native Nim integer type, so
## the API surface for big BVs is decimal-string-based.

import std/[unittest]
import z3

suite "big BV — tracer":
  test "128-bit literal round-trips via mkBigBitVec → toBigUintStr":
    let ctx = newContext()
    let s = "12345678901234567890"
    let bv = mkBigBitVec[128](s)
    check bv.toBigUintStr == s

  test "256-bit literal round-trips":
    let ctx = newContext()
    let s = "115792089237316195423570985008687907853269984665640564039457"
    let bv = mkBigBitVec[256](s)
    check bv.toBigUintStr == s

  test "mkBitVec works for W > 64 with small native values":
    let ctx = newContext()
    # v0.1 required mkBigBitVec for W > 64 even with tiny values; v0.2
    # drops that artificial cap because Z3 itself handles any W.
    let bv = mkBitVec(42'u, 128)
    check bv is Z3BitVec[128]
    check bv.toBigUintStr == "42"

  test "mkBigBitVec preserves Z3BitVec[W] phantom":
    let ctx = newContext()
    let bv = mkBigBitVec[200]("1")
    check bv is Z3BitVec[200]

suite "big BV — signed extraction":
  test "toBigIntStr on BV[8] with MSB set is the v0.1 signed value":
    let ctx = newContext()
    # 0xFF on BV[8] is -1 signed. v0.1's toInt returned -1 for W=8;
    # the string form should agree.
    let bv = mkBitVec(0xFF'u, 8)
    check bv.toBigIntStr == "-1"
    check bv.toBigUintStr == "255"

  test "toBigIntStr on BV[8] without MSB is the unsigned value":
    let ctx = newContext()
    let bv = mkBitVec(42'u, 8)
    check bv.toBigIntStr == "42"

  test "toBigIntStr on a 128-bit BV with MSB set is large-negative":
    let ctx = newContext()
    # All ones on BV[128] = -1 signed.
    let allOnes = mkBigBitVec[128]("340282366920938463463374607431768211455")
    check allOnes.toBigIntStr == "-1"
    check allOnes.toBigUintStr == "340282366920938463463374607431768211455"

  test "toBigIntStr round-trips a 128-bit negative literal":
    let ctx = newContext()
    # -100 mod 2^128 (the value Z3 stores for the BV literal of "-100")
    # is 2^128 - 100. Going in via mkBigBitVec with the unsigned form
    # and reading out signed should give "-100".
    let unsignedForm =
      "340282366920938463463374607431768211356"   # = 2^128 - 100
    let bv = mkBigBitVec[128](unsignedForm)
    check bv.toBigIntStr == "-100"

suite "big BV — operator surface":
  test "128-bit addition via the solver round-trips":
    let ctx = newContext()
    let a = mkBigBitVec[128]("12345678901234567890")
    let b = mkBigBitVec[128]("100000000000000000000")
    let r = mkBitVecVar[128]("r")
    let s = newSolver()
    s.add r == (a + b)
    check s.check() == zsSat
    let m = s.model()
    check m[r].toBigUintStr == "112345678901234567890"

  test "128-bit modular overflow wraps":
    let ctx = newContext()
    # 2^128 - 1 + 1 = 0 mod 2^128.
    let maxBV = mkBigBitVec[128]("340282366920938463463374607431768211455")
    let one = mkBigBitVec[128]("1")
    let r = mkBitVecVar[128]("r")
    let s = newSolver()
    s.add r == (maxBV + one)
    check s.check() == zsSat
    check s.model()[r].toBigUintStr == "0"

  test "extract narrows a 128-bit BV to BV[64] keeping low bits":
    let ctx = newContext()
    let big = mkBigBitVec[128]("18446744073709551616")   # 2^64
    let lo = big.extract(63, 0)
    check lo is Z3BitVec[64]
    check lo.toUint == 0'u64    # low 64 bits of 2^64 are zero

  test "concat works across widths > 64":
    let ctx = newContext()
    let hi = mkBigBitVec[128]("1")
    let lo = mkBigBitVec[128]("0")
    let r = concat(hi, lo)
    check r is Z3BitVec[256]
    # value = 2^128
    check r.toBigUintStr == "340282366920938463463374607431768211456"

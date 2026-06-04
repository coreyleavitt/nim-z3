## `z3/fp` — N6.4b: FPA numeral decomposition.
##
## `getNumeralSign`, `getNumeralSignificandString`,
## `getNumeralSignificandBv`, `getNumeralSignificandUint64`,
## `getNumeralExponentString`, `getNumeralExponentInt64`,
## `getNumeralExponentBv` — extract sign/significand/exponent from
## *concrete* FP numerals. Functions returning `Option[T]` yield `none`
## when the argument is not a numeral (e.g. a free variable).

import std/[unittest, options]
import z3

# ---------------------------------------------------------------------------
# getNumeralSign
# ---------------------------------------------------------------------------

suite "getNumeralSign — N6.4b":

  test "positive 1.0 → some(false)":
    let ctx = newContext()
    check getNumeralSign(mkFloat64(1.0)) == some(false)

  test "negative -1.0 → some(true)":
    let ctx = newContext()
    check getNumeralSign(mkFloat64(-1.0)) == some(true)

  test "symbolic var → none (not a numeral)":
    let ctx = newContext()
    let x = mkFloat64Var("x")
    check getNumeralSign(x) == none(bool)

  test "+0 → some(false)":
    let ctx = newContext()
    check getNumeralSign(mkFpZero[11, 53]()) == some(false)

  test "-0 → some(true)":
    let ctx = newContext()
    check getNumeralSign(mkFpZero[11, 53](negative = true)) == some(true)

# ---------------------------------------------------------------------------
# getNumeralSignificandUint64
# ---------------------------------------------------------------------------

suite "getNumeralSignificandUint64 — N6.4b":

  test "2.0 (float64) → some value (is some)":
    ## float64: 2.0 = 1.0 × 2^1; explicit significand bits = 0.
    ## The function returns the explicit bits without the hidden bit, so 0.
    let ctx = newContext()
    let r = getNumeralSignificandUint64(mkFloat64(2.0))
    check r.isSome
    check r.get == 0'u64

  test "symbolic var → none":
    let ctx = newContext()
    let x = mkFloat64Var("y")
    check getNumeralSignificandUint64(x) == none(uint64)

  test "1.5 (float64) significand uint64":
    ## 1.5 = 1.1 binary = 1.5 × 2^0; explicit significand bits:
    ## float64 has 52 explicit bits; 1.5 → 0x8000000000000 (top bit set).
    let ctx = newContext()
    let r = getNumeralSignificandUint64(mkFloat64(1.5))
    check r.isSome
    check r.get == 0x8000000000000'u64

# ---------------------------------------------------------------------------
# getNumeralExponentInt64
# ---------------------------------------------------------------------------

suite "getNumeralExponentInt64 — N6.4b":

  test "2.0 unbiased exponent → some(1)":
    ## 2.0 = 1.0 × 2^1; unbiased (raw) exponent = 1.
    let ctx = newContext()
    check getNumeralExponentInt64(mkFloat64(2.0), biased = false) == some(1'i64)

  test "1.0 unbiased exponent → some(0)":
    ## 1.0 = 1.0 × 2^0; unbiased exponent = 0.
    let ctx = newContext()
    check getNumeralExponentInt64(mkFloat64(1.0), biased = false) == some(0'i64)

  test "2.0 biased exponent (float64) → some(1024)":
    ## float64: bias = 1023, so biased = 1023 + 1 = 1024.
    let ctx = newContext()
    check getNumeralExponentInt64(mkFloat64(2.0), biased = true) == some(1024'i64)

  test "symbolic var → none":
    let ctx = newContext()
    let x = mkFloat64Var("z")
    check getNumeralExponentInt64(x) == none(int64)

# ---------------------------------------------------------------------------
# getNumeralExponentBv
# ---------------------------------------------------------------------------

suite "getNumeralExponentBv — N6.4b":

  test "2.0 (float32) biased exponent → Z3BitVec[8] value 128":
    ## float32: E=8, bias=127; biased exponent of 2.0 = 127 + 1 = 128.
    let ctx = newContext()
    let bv = getNumeralExponentBv(mkFloat32(2.0'f32), biased = true)
    check bv.toUint == 128'u64

  test "1.0 (float32) biased exponent → Z3BitVec[8] value 127":
    ## float32: bias=127; biased exponent of 1.0 = 127 + 0 = 127.
    let ctx = newContext()
    let bv = getNumeralExponentBv(mkFloat32(1.0'f32), biased = true)
    check bv.toUint == 127'u64

  test "2.0 (float32) unbiased exponent → Z3BitVec[8] value 1 (sign-extended)":
    ## Unbiased exponent of 2.0 is 1; as an 8-bit BV, toUint = 1.
    let ctx = newContext()
    let bv = getNumeralExponentBv(mkFloat32(2.0'f32), biased = false)
    check bv.toUint == 1'u64

# ---------------------------------------------------------------------------
# getNumeralSignificandString
# ---------------------------------------------------------------------------

suite "getNumeralSignificandString — N6.4b":

  test "3.5 (float32) significand string is '1.75'":
    ## 3.5 = 1.75 × 2^1; Z3 returns the significand in [0, 2), so 1.75.
    let ctx = newContext()
    let s = getNumeralSignificandString(mkFloat32(3.5'f32))
    check s == "1.75"

  test "1.0 significand string is '1'":
    ## 1.0 = 1.0 × 2^0; significand in [0, 2) = 1.0, rendered as "1".
    let ctx = newContext()
    let s = getNumeralSignificandString(mkFloat64(1.0))
    check s == "1"

# ---------------------------------------------------------------------------
# getNumeralExponentString
# ---------------------------------------------------------------------------

suite "getNumeralExponentString — N6.4b":

  test "2.0 (float64) unbiased exponent string is '1'":
    let ctx = newContext()
    let s = getNumeralExponentString(mkFloat64(2.0), biased = false)
    check s == "1"

  test "2.0 (float64) biased exponent string is '1024'":
    ## float64 bias=1023; biased = 1023 + 1 = 1024.
    let ctx = newContext()
    let s = getNumeralExponentString(mkFloat64(2.0), biased = true)
    check s == "1024"

# ---------------------------------------------------------------------------
# getNumeralSignificandBv
# ---------------------------------------------------------------------------

suite "getNumeralSignificandBv — N6.4b":

  test "2.0 (float64) significand BV has width S-1 = 52 and value 0":
    ## 2.0: explicit significand bits = 0 (hidden bit implicit).
    let ctx = newContext()
    let bv = getNumeralSignificandBv(mkFloat64(2.0))
    check bv.toUint == 0'u64

  test "1.5 (float32) significand BV width S-1 = 23, value = 1 shl 22":
    ## float32: S=24, so BV width = 23.
    ## 1.5 = 1.1 binary; explicit bits: top bit = 1, rest = 0.
    ## As a 23-bit BV: bit 22 is set → value = 2^22 = 4194304.
    let ctx = newContext()
    let bv = getNumeralSignificandBv(mkFloat32(1.5'f32))
    check bv.toUint == (1'u64 shl 22)

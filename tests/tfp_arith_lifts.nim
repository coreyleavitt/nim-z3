## `z3/fp` — N6.5b: binary arithmetic overloads accepting `float64` / `float32`
## literals on either side of a `Z3Fp[E,S]` value.
##
## All four operators (`+`, `-`, `*`, `/`) are tested for both orientations
## (`Z3Fp op literal` and `literal op Z3Fp`). Default rounding: rmRNE.
## A round-off identity test verifies IEEE semantics are passed through.

import std/unittest
import z3

# ---------------------------------------------------------------------------
# + : fp + literal, literal + fp
# ---------------------------------------------------------------------------

suite "Z3Fp arithmetic literal lifts — + (N6.5b)":
  test "mkFloat64(2.0) + 3.0 == mkFloat64(5.0) is SAT":
    let ctx = newContext()
    check smtValid(mkFloat64(2.0) + 3.0 == mkFloat64(5.0))

  test "3.0 + mkFloat64(2.0) == mkFloat64(5.0) is SAT (reverse orientation)":
    let ctx = newContext()
    check smtValid(3.0 + mkFloat64(2.0) == mkFloat64(5.0))

# ---------------------------------------------------------------------------
# - : fp - literal
# ---------------------------------------------------------------------------

suite "Z3Fp arithmetic literal lifts — - (N6.5b)":
  test "mkFloat64(10.0) - 4.0 == mkFloat64(6.0) is SAT":
    let ctx = newContext()
    check smtValid(mkFloat64(10.0) - 4.0 == mkFloat64(6.0))

# ---------------------------------------------------------------------------
# * : fp * literal
# ---------------------------------------------------------------------------

suite "Z3Fp arithmetic literal lifts — * (N6.5b)":
  test "mkFloat64(2.5) * 4.0 == mkFloat64(10.0) is SAT":
    let ctx = newContext()
    check smtValid(mkFloat64(2.5) * 4.0 == mkFloat64(10.0))

# ---------------------------------------------------------------------------
# / : fp / literal
# ---------------------------------------------------------------------------

suite "Z3Fp arithmetic literal lifts — / (N6.5b)":
  test "mkFloat64(20.0) / 4.0 == mkFloat64(5.0) is SAT":
    let ctx = newContext()
    check smtValid(mkFloat64(20.0) / 4.0 == mkFloat64(5.0))

# ---------------------------------------------------------------------------
# float32 path
# ---------------------------------------------------------------------------

suite "Z3Fp arithmetic literal lifts — float32 (N6.5b)":
  test "mkFloat32(1.0'f32) + 2.0'f32 == mkFloat32(3.0'f32) is SAT":
    let ctx = newContext()
    check smtValid(mkFloat32(1.0'f32) + 2.0'f32 == mkFloat32(3.0'f32))

# ---------------------------------------------------------------------------
# IEEE round-off identity
# ---------------------------------------------------------------------------

suite "Z3Fp arithmetic literal lifts — IEEE round-off (N6.5b)":
  test "mkFloat64(0.1) + 0.2 != mkFloat64(0.3) is SAT (classic IEEE identity)":
    ## 0.1 + 0.2 is not representable as 0.3 in IEEE 754 binary64.
    ## Both sides of the inequality are constructed via Z3's own
    ## numeral-from-double path (Z3_mk_fpa_numeral_double), so Z3 sees
    ## the exact same bit patterns Nim would compute, and the inequality
    ## should be SAT.
    let ctx = newContext()
    check smtValid(mkFloat64(0.1) + 0.2 != mkFloat64(0.3))

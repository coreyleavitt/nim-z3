## `z3/fp` — N6.5a: binary comparison overloads accepting `float64` / `float32`
## literals on either side of a `Z3Fp[E,S]` value.
##
## All six comparisons (`==`, `!=`, `<`, `<=`, `>`, `>=`) are tested for
## both orientations (`Z3Fp op literal` and `literal op Z3Fp`). IEEE
## semantics: `==` uses `Z3_mk_fpa_eq` so NaN≠NaN and +0==−0.

import std/unittest
import z3

# ---------------------------------------------------------------------------
# < : fp < literal, literal < fp
# ---------------------------------------------------------------------------

suite "Z3Fp literal lifts — < (N6.5a)":
  test "mkFloat64(1.0) < 2.0 is SAT (true)":
    let ctx = newContext()
    check smtValid(mkFloat64(1.0) < 2.0)

  test "1.0 < mkFloat64(2.0) is SAT (true)":
    let ctx = newContext()
    check smtValid(1.0 < mkFloat64(2.0))

  test "mkFloat64(2.0) < 1.0 is UNSAT (false)":
    let ctx = newContext()
    check smtValid(not (mkFloat64(2.0) < 1.0))

# ---------------------------------------------------------------------------
# <= : fp <= literal, literal <= fp
# ---------------------------------------------------------------------------

suite "Z3Fp literal lifts — <= (N6.5a)":
  test "mkFloat64(1.0) <= 1.0 is SAT (equal case)":
    let ctx = newContext()
    check smtValid(mkFloat64(1.0) <= 1.0)

  test "mkFloat64(1.0) <= 2.0 is SAT (strict case)":
    let ctx = newContext()
    check smtValid(mkFloat64(1.0) <= 2.0)

  test "1.0 <= mkFloat64(2.0) is SAT":
    let ctx = newContext()
    check smtValid(1.0 <= mkFloat64(2.0))

  test "mkFloat32(1.0'f32) <= 2.0'f32 is SAT":
    let ctx = newContext()
    check smtValid(mkFloat32(1.0'f32) <= 2.0'f32)

# ---------------------------------------------------------------------------
# > : fp > literal, literal > fp
# ---------------------------------------------------------------------------

suite "Z3Fp literal lifts — > (N6.5a)":
  test "mkFloat64(2.0) > 1.0 is SAT":
    let ctx = newContext()
    check smtValid(mkFloat64(2.0) > 1.0)

  test "1.0 > mkFloat64(2.0) is UNSAT (false)":
    let ctx = newContext()
    check smtValid(not (1.0 > mkFloat64(2.0)))

# ---------------------------------------------------------------------------
# >= : fp >= literal, literal >= fp
# ---------------------------------------------------------------------------

suite "Z3Fp literal lifts — >= (N6.5a)":
  test "mkFloat64(2.0) >= 1.0 is SAT":
    let ctx = newContext()
    check smtValid(mkFloat64(2.0) >= 1.0)

  test "mkFloat64(1.0) >= 1.0 is SAT (equal case)":
    let ctx = newContext()
    check smtValid(mkFloat64(1.0) >= 1.0)

  test "1.0 >= mkFloat64(2.0) is UNSAT":
    let ctx = newContext()
    check smtValid(not (1.0 >= mkFloat64(2.0)))

# ---------------------------------------------------------------------------
# == : IEEE equality with float64 literal (uses Z3_mk_fpa_eq)
# ---------------------------------------------------------------------------

suite "Z3Fp literal lifts — == IEEE (N6.5a)":
  test "mkFloat64(1.0) == 1.0 is SAT":
    let ctx = newContext()
    check smtValid(mkFloat64(1.0) == 1.0)

  test "1.0 == mkFloat64(1.0) is SAT":
    let ctx = newContext()
    check smtValid(1.0 == mkFloat64(1.0))

  test "mkFloat64(1.0) == 2.0 is UNSAT":
    let ctx = newContext()
    check smtValid(not (mkFloat64(1.0) == 2.0))

  test "NaN == 0.0 is UNSAT (IEEE NaN semantics)":
    ## mkFpNaN[Z3Float64] expressed via existing mkFpNaN[11, 53]()
    let ctx = newContext()
    let nan = mkFpNaN[11, 53]()
    check smtValid(not (nan == 0.0))

  test "+0 == -0 via literal lift (IEEE +0 == -0)":
    let ctx = newContext()
    let negZero = mkFpZero[11, 53](negative = true)
    check smtValid(negZero == 0.0)

# ---------------------------------------------------------------------------
# != : IEEE non-equality
# ---------------------------------------------------------------------------

suite "Z3Fp literal lifts — != IEEE (N6.5a)":
  test "mkFloat64(1.0) != 2.0 is SAT":
    let ctx = newContext()
    check smtValid(mkFloat64(1.0) != 2.0)

  test "1.0 != mkFloat64(2.0) is SAT":
    let ctx = newContext()
    check smtValid(1.0 != mkFloat64(2.0))

  test "mkFloat64(1.0) != 1.0 is UNSAT":
    let ctx = newContext()
    check smtValid(not (mkFloat64(1.0) != 1.0))

  test "NaN != NaN is SAT via literal (NaN != anything)":
    let ctx = newContext()
    let nan = mkFpNaN[11, 53]()
    check smtValid(nan != 0.0)

# ---------------------------------------------------------------------------
# float32 lifts — spot-check <, ==
# ---------------------------------------------------------------------------

suite "Z3Fp float32 literal lifts (N6.5a)":
  test "mkFloat32(1.0'f32) < 2.0'f32 is SAT":
    let ctx = newContext()
    check smtValid(mkFloat32(1.0'f32) < 2.0'f32)

  test "2.0'f32 < mkFloat32(1.0'f32) is UNSAT":
    let ctx = newContext()
    check smtValid(not (2.0'f32 < mkFloat32(1.0'f32)))

  test "mkFloat32(1.0'f32) == 1.0'f32 is SAT (IEEE eq)":
    let ctx = newContext()
    check smtValid(mkFloat32(1.0'f32) == 1.0'f32)

  test "1.0'f32 == mkFloat32(1.0'f32) is SAT":
    let ctx = newContext()
    check smtValid(1.0'f32 == mkFloat32(1.0'f32))

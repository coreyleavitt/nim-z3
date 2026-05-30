## `z3/fp` tests — IEEE 754 / SMT-LIB FloatingPoint theory.

import std/[unittest, math]
import z3

suite "Z3Fp — tracer":
  test "round-trip: assert x == mkFloat32(3.5), model gives 3.5":
    let ctx = newContext()
    let x = mkFloat32Var("x")
    let s = newSolver()
    s.add x == mkFloat32(3.5'f32)
    check s.check() == zsSat
    let m = s.model()
    check m.evalFloat32(x) == 3.5'f32

suite "Z3Fp — width aliases":
  test "Z3Float16 / 32 / 64 / 128 all constructible and distinct":
    let ctx = newContext()
    check compiles(mkFp[5, 11](0.0))
    check compiles(mkFp[8, 24](0.0'f32))
    check compiles(mkFp[11, 53](0.0))
    check compiles(mkFp[15, 113](0.0))
    # Widths are reflected in toIeeeBv result widths.
    check compiles((mkFloat32(0.0'f32).toIeeeBv == mkBitVec[32](0'u32)))
    check compiles((mkFloat64(0.0).toIeeeBv == mkBitVec[64](0'u64)))

suite "Z3Fp — special values + predicates":
  test "isNaN(mkNaN()) is true; isNaN of a normal value is false":
    let ctx = newContext()
    check smtValid(isNaN(mkNaN[8, 24]()))
    check smtValid(not isNaN(mkFloat32(1.0'f32)))

  test "isInf / +Inf / -Inf":
    let ctx = newContext()
    check smtValid(isInf(mkInf[8, 24]()))
    check smtValid(isInf(mkInf[8, 24](negative = true)))
    check smtValid(not isInf(mkFloat32(0.0'f32)))

  test "isZero on +0 and -0":
    let ctx = newContext()
    check smtValid(isZero(mkZero[8, 24]()))
    check smtValid(isZero(mkZero[8, 24](negative = true)))

  test "isPositive / isNegative":
    let ctx = newContext()
    check smtValid(isPositive(mkFloat32(3.5'f32)))
    check smtValid(isNegative(mkFloat32(-3.5'f32)))

  test "isNormal / isSubnormal":
    let ctx = newContext()
    # 1.0 is normal; 2^-150 (below float32 min normal) is subnormal.
    check smtValid(isNormal(mkFloat32(1.0'f32)))
    check smtValid(isSubnormal(mkFloat32(1.0e-40'f32)))

suite "Z3Fp — IEEE equality semantics":
  test "NaN == NaN is FALSE under IEEE (the headline divergence)":
    let ctx = newContext()
    let nan = mkNaN[8, 24]()
    check smtValid(not (nan == nan))
    check smtValid(nan != nan)

  test "+0 == -0 is TRUE":
    let ctx = newContext()
    let pZero = mkZero[8, 24]()
    let nZero = mkZero[8, 24](negative = true)
    check smtValid(pZero == nZero)

  test "normal values equate structurally":
    let ctx = newContext()
    check smtValid(mkFloat32(3.5'f32) == mkFloat32(3.5'f32))
    check smtValid(mkFloat32(3.5'f32) != mkFloat32(3.6'f32))

suite "Z3Fp — signaling comparisons":
  test "ordering on normal values":
    let ctx = newContext()
    check smtValid(mkFloat32(1.0'f32) < mkFloat32(2.0'f32))
    check smtValid(mkFloat32(2.0'f32) > mkFloat32(1.0'f32))
    check smtValid(mkFloat32(1.0'f32) <= mkFloat32(1.0'f32))
    check smtValid(mkFloat32(1.0'f32) >= mkFloat32(1.0'f32))

  test "NaN ordered with nothing":
    let ctx = newContext()
    let nan = mkNaN[8, 24]()
    let one = mkFloat32(1.0'f32)
    check smtValid(not (nan < one))
    check smtValid(not (nan > one))
    check smtValid(not (nan <= one))
    check smtValid(not (nan >= one))

suite "Z3Fp — arithmetic (default RM = rmRNE)":
  test "+ - * /":
    let ctx = newContext()
    check smtValid(mkFloat32(1.0'f32) + mkFloat32(2.0'f32) == mkFloat32(3.0'f32))
    check smtValid(mkFloat32(5.0'f32) - mkFloat32(2.0'f32) == mkFloat32(3.0'f32))
    check smtValid(mkFloat32(3.0'f32) * mkFloat32(4.0'f32) == mkFloat32(12.0'f32))
    check smtValid(mkFloat32(8.0'f32) / mkFloat32(4.0'f32) == mkFloat32(2.0'f32))

  test "unary - flips sign":
    let ctx = newContext()
    check smtValid(-mkFloat32(3.5'f32) == mkFloat32(-3.5'f32))

  test "abs":
    let ctx = newContext()
    check smtValid(abs(mkFloat32(-3.5'f32)) == mkFloat32(3.5'f32))
    check smtValid(abs(mkFloat32(3.5'f32)) == mkFloat32(3.5'f32))

  test "min / max":
    let ctx = newContext()
    check smtValid(min(mkFloat32(1.0'f32), mkFloat32(2.0'f32)) == mkFloat32(1.0'f32))
    check smtValid(max(mkFloat32(1.0'f32), mkFloat32(2.0'f32)) == mkFloat32(2.0'f32))

  test "sqrt (default rmRNE)":
    let ctx = newContext()
    check smtValid(sqrt(mkFloat32(9.0'f32)) == mkFloat32(3.0'f32))
    check smtValid(sqrt(mkFloat32(2.0'f32)) == mkFloat32(sqrt(2.0'f32)))

  test "fma — fused multiply-add":
    let ctx = newContext()
    check smtValid(
      fma(mkFloat32(2.0'f32), mkFloat32(3.0'f32), mkFloat32(1.0'f32)) ==
      mkFloat32(7.0'f32))

suite "Z3Fp — explicit rounding modes":
  test "rmRTZ truncates 0.1 + 0.2 differently than rmRNE":
    let ctx = newContext()
    # On float32, 0.1 + 0.2 isn't exactly representable; RTZ vs RNE
    # produce different results for the sum.
    let a = mkFloat32(0.1'f32)
    let b = mkFloat32(0.2'f32)
    let rne_sum = fpAdd(rmRNE, a, b)
    let rtz_sum = fpAdd(rmRTZ, a, b)
    # They differ on this canonical "FP can't add a tenth" example.
    check smtValid(rne_sum != rtz_sum)

  test "rmRTP rounds 1/3 upward, rmRTN downward":
    let ctx = newContext()
    let one = mkFloat32(1.0'f32)
    let three = mkFloat32(3.0'f32)
    let up = fpDiv(rmRTP, one, three)
    let down = fpDiv(rmRTN, one, three)
    check smtValid(up > down)

  test "Z3RoundingMode AST form accepts the same modes":
    let ctx = newContext()
    let rne = mkRoundingMode(rmRNE)
    check smtValid(
      fpAdd(rne, mkFloat32(1.0'f32), mkFloat32(2.0'f32)) == mkFloat32(3.0'f32))

suite "Z3Fp — rem (no rounding)":
  test "rem is IEEE remainder":
    let ctx = newContext()
    # IEEE rem(7, 3) = 7 - round_to_even(7/3) * 3 = 7 - 2*3 = 1
    check smtValid(rem(mkFloat32(7.0'f32), mkFloat32(3.0'f32)) == mkFloat32(1.0'f32))

suite "Z3Fp — roundToIntegral":
  test "RTZ truncates":
    let ctx = newContext()
    check smtValid(
      roundToIntegral(rmRTZ, mkFloat32(3.7'f32)) == mkFloat32(3.0'f32))
    check smtValid(
      roundToIntegral(rmRTZ, mkFloat32(-3.7'f32)) == mkFloat32(-3.0'f32))

  test "RTP rounds up; RTN rounds down":
    let ctx = newContext()
    check smtValid(
      roundToIntegral(rmRTP, mkFloat32(3.2'f32)) == mkFloat32(4.0'f32))
    check smtValid(
      roundToIntegral(rmRTN, mkFloat32(3.7'f32)) == mkFloat32(3.0'f32))

suite "Z3Fp — conversions":
  test "toIeeeBv + toFp(bv) round-trips":
    let ctx = newContext()
    let f = mkFloat32(3.5'f32)
    let bv = f.toIeeeBv
    let f2 = toFp(bv, Z3Float32)
    check smtValid(f == f2)

  test "toReal of a representable FP":
    let ctx = newContext()
    let f = mkFloat32(0.5'f32)
    check smtValid(toReal(f) == mkReal(1, 2))

  test "Real → Fp via toFp":
    let ctx = newContext()
    let r = mkReal(7, 2)         # 3.5
    let f = toFp(r, Z3Float32)
    check smtValid(f == mkFloat32(3.5'f32))

  test "FP → signed BV round-trip":
    let ctx = newContext()
    let f = mkFloat32(-42.0'f32)
    let bv = toSbv[8, 24, 32](f)   # explicit widths
    let f2 = toFpFromSigned(bv, Z3Float32)
    check smtValid(f == f2)

suite "Z3Fp — model extraction":
  test "toFloat32 round-trips a literal":
    let ctx = newContext()
    check mkFloat32(3.14'f32).toFloat32 == 3.14'f32

  test "toFloat64 round-trips a literal":
    let ctx = newContext()
    check mkFloat64(1.0e-100).toFloat64 == 1.0e-100

  test "evalFloat32 / evalFloat64 from a solver":
    let ctx = newContext()
    let x = mkFloat64Var("x")
    let s = newSolver()
    s.add x == mkFloat64(2.718281828459045)
    discard s.check()
    let m = s.model()
    check m.evalFloat64(x) == 2.718281828459045

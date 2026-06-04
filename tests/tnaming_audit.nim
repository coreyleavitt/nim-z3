## N10.2 — Cross-theory conversion naming audit.
##
## This file is the standing audit for RFC N10.2 (cross-theory conversion
## naming consistency pass).  It compile-checks the full manifest of
## cross-theory conversions and verifies that:
##
##   1. All `<srcType>To<destType>` free-proc conversions are present under
##      their canonical names.
##   2. The deprecated old names (`strToInt`, `intToStr`, and the old `toFp`
##      BV overload) do NOT compile.
##   3. `Z3Int.toInt64` (N4.4) exists; `Z3Int.toInt` does NOT.
##   4. `Z3String.toInt` and `Z3Int.toStr` (N5.7) are present; their old
##      names are absent.
##
## Naming convention (ADR-N0005 + N3.3 rationale):
##   - Theory-level cross-theory conversions use `srcTypeToDestType` free
##     procs (e.g. `bvToInt`, `intToBv`, `intToReal`, `realToInt`,
##     `bvToFpBits`).
##   - UFCS-style `.toX` names are reserved for method-style calls that
##     were deliberately kept that way in earlier slices (N5.7 `toInt`,
##     `toStr` on strings/chars; N6.7 `toFp`, `toSbv`, `toUbv`,
##     `toIeeeBv`, `toReal` on FP).  These are not errors — they were
##     conscious decisions documented in those ADRs.
##
## Cross-theory conversion manifest (all entry points as of N10.2):
##
##   Arith:
##     intToReal(Z3Int) → Z3Real                         (arith.nim)
##     realToInt(Z3Real) → Z3Int                         (arith.nim)
##
##   BitVec ↔ Int:
##     bvToInt[W](Z3BitVec[W], signed) → Z3Int          (bitvec.nim, N3.3)
##     intToBv[W](Z3Int, typedesc) → Z3BitVec[W]        (bitvec.nim, N3.3)
##
##   BitVec ↔ FP (bit-pattern):
##     bvToFpBits[Bw,E,S](Z3BitVec[Bw], typedesc) → Z3Fp (fp.nim, N6.7)
##
##   FP ↔ BV (value conversions; kept UFCS-style per N6.7 decision):
##     Z3Fp.toIeeeBv → Z3BitVec[E+S]
##     Z3Fp.toSbv[W](rm) → Z3BitVec[W]
##     Z3Fp.toUbv[W](rm) → Z3BitVec[W]
##     Z3Fp.toReal → Z3Real
##
##   BV → FP (signed/unsigned value conversions; kept with qualifier suffix):
##     toFpFromSigned(bv, rm, typedesc) → Z3Fp
##     toFpFromUnsigned(bv, rm, typedesc) → Z3Fp
##
##   FP → FP and Real → FP:
##     toFp(rm, fp, typedesc) → Z3Fp
##     toFp(rm, real, typedesc) → Z3Fp
##
##   String ↔ Int (UFCS-style per N5.7):
##     Z3String.toInt → Z3Int
##     Z3Int.toStr → Z3String
##
##   Char ↔ Int / BV (UFCS-style per N5.x):
##     Z3Char.toInt → Z3Int
##     Z3Char.toBitVec → Z3BitVec[UnicodeCharWidth]
##
##   BV → String:
##     toString[W](Z3BitVec[W], signed) → Z3String      (strings.nim, N5.2)
##
##   Bool → BV:
##     toBitVec(Z3Bool) → Z3BitVec[1]                   (bitvec.nim, N3.3)

import std/[unittest]
import z3

suite "N10.2 — cross-theory conversion naming audit":

  # -------------------------------------------------------------------------
  # 1. `srcToTgt` free-proc family: present under canonical names
  # -------------------------------------------------------------------------

  test "intToReal and realToInt compile":
    let ctx = newContext()
    let i = mkInt(3)
    let r = mkReal(1, 2)
    check compiles(intToReal(i))
    check compiles(realToInt(r))

  test "bvToInt and intToBv compile":
    let ctx = newContext()
    let bv = mkBitVec[8](42)
    let i = mkInt(42)
    check compiles(bvToInt(bv, false))
    check compiles(intToBv(i, Z3BitVec[8]))

  test "bvToFpBits compiles (N6.7 rename)":
    let ctx = newContext()
    let bv = mkBitVec[32](0'u32)
    check compiles(bvToFpBits(bv, Z3Float32))

  # -------------------------------------------------------------------------
  # 2. Old names are absent (N5.7, N6.7 hard breaks)
  # -------------------------------------------------------------------------

  test "strToInt does NOT compile (renamed to Z3String.toInt in N5.7)":
    check not compiles(strToInt(mkString("42")))

  test "intToStr does NOT compile (renamed to Z3Int.toStr in N5.7)":
    check not compiles(intToStr(mkInt(42)))

  test "toFp(bv, typedesc) does NOT compile (renamed to bvToFpBits in N6.7)":
    ## The BV-overload of toFp is gone; the lossy float/real overload remains.
    let ctx = newContext()
    let bv = mkBitVec[32](0'u32)
    check not compiles(toFp(bv, Z3Float32))

  # -------------------------------------------------------------------------
  # 3. Z3Int model-extractor shape: toInt64 present, toInt absent
  # -------------------------------------------------------------------------

  test "Z3Int.toInt64 exists (N4.4 model extractor)":
    let ctx = newContext()
    let s = newSolver()
    s.add(mkInt(7) == mkInt(7))
    let sat = s.check
    doAssert sat == zsSat
    let m = s.model
    let v = m.eval(mkInt(7))
    check compiles(v.toInt64)
    check v.toInt64 == 7'i64

  test "Z3Int.toInt does NOT exist as a model extractor":
    ## Only Z3BitVec[W].toInt exists (returning Nim int64 from BV numerals).
    ## Z3Int has toInt64 (and toIntOpt), not toInt, to avoid confusion with
    ## the theory-level Z3Char.toInt and Z3String.toInt conversions.
    let ctx = newContext()
    let s = newSolver()
    s.add(mkInt(7) == mkInt(7))
    doAssert s.check == zsSat
    let v = s.model.eval(mkInt(7))
    check not compiles(v.toInt)

  # -------------------------------------------------------------------------
  # 4. Z3String.toInt and Z3Int.toStr present (N5.7)
  # -------------------------------------------------------------------------

  test "Z3String.toInt compiles (N5.7)":
    let ctx = newContext()
    let s = mkString("42")
    check compiles(s.toInt)

  test "Z3Int.toStr compiles (N5.7)":
    let ctx = newContext()
    let i = mkInt(42)
    check compiles(i.toStr)

  # -------------------------------------------------------------------------
  # 5. FP UFCS conversions present (kept per N6.7 design decision)
  # -------------------------------------------------------------------------

  test "Z3Fp.toIeeeBv, toSbv, toUbv, toReal all compile":
    let ctx = newContext()
    let f = mkFloat32(1.0'f32)
    check compiles(f.toIeeeBv)
    check compiles(toSbv[8, 24, 8](f))
    check compiles(toUbv[8, 24, 8](f))
    check compiles(f.toReal)

  test "toFpFromSigned and toFpFromUnsigned compile":
    let ctx = newContext()
    let bv = mkBitVec[8](42)
    check compiles(toFpFromSigned(bv, Z3Float32))
    check compiles(toFpFromUnsigned(bv, Z3Float32))

  test "toFp (lossy FP→FP and Real→FP) still compiles":
    let ctx = newContext()
    let f32 = mkFloat32(1.5'f32)
    let r = mkReal(3, 2)
    check compiles(toFp(rmRNE(), f32, Z3Float64))
    check compiles(toFp(rmRNE(), r, Z3Float64))

  # -------------------------------------------------------------------------
  # 6. Remaining cross-theory procs compile
  # -------------------------------------------------------------------------

  test "Z3Char.toInt and Z3Char.toBitVec compile":
    let ctx = newContext()
    let c = mkChar('a')
    check compiles(c.toInt)
    check compiles(c.toBitVec)

  test "toString(Z3BitVec, signed) compiles":
    let ctx = newContext()
    let bv = mkBitVec[8](42)
    check compiles(toString(bv, false))
    check compiles(toString(bv, true))

  test "toBitVec(Z3Bool) compiles":
    let ctx = newContext()
    check compiles(toBitVec(mkTrue()))

## BitVec example — solves a couple of small modular-arithmetic
## puzzles that show off the width-tracked `Z3BitVec[W]` type and the
## sign-explicit operator surface.
##
## Puzzles:
##
## 1. **Multiplicative factoring under mod 256.** Find `a, b ∈ BV[8]`
##    with `a * b == 0xF0`, both > 1. Tests modular multiplication;
##    Z3 should pick something like 0xF0 = 0x18 * 0x0A (24 * 10) or
##    similar mod-256 solution.
##
## 2. **Bitwise reconstruction.** Find `lo, hi ∈ BV[4]` such that
##    `concat(hi, lo) == 0xAB` on BV[8]. Tests width-typed concat:
##    the static type system enforces hi gives the high bits, lo the
##    low.
##
## 3. **Signed vs unsigned.** Find `x ∈ BV[8]` such that
##    `bvult(x, 0)` is unsat (no value is unsigned-less-than 0) but
##    `bvslt(x, 0)` is sat (any value with MSB set is signed-less-than
##    zero). Asserting the contradictions surfaces the sign distinction.

import std/[strformat]
import z3

proc main() =
  let ctx = newContext()

  block puzzle_factoring:
    let a = mkBitVecVar[8]("a")
    let b = mkBitVecVar[8]("b")
    let s = newSolver()
    # bvugt: a > 1 unsigned; same for b.
    s.add bvugt(a, mkBitVec(1'u8, 8))
    s.add bvugt(b, mkBitVec(1'u8, 8))
    s.add a * b == mkBitVec(0xF0'u8, 8)
    doAssert s.check() == zsSat
    let m = s.model()
    let av = m[a].toUint
    let bv = m[b].toUint
    echo &"factoring under mod 256: {av} * {bv} mod 256 = {(av * bv) and 0xFF}"
    doAssert ((av * bv) and 0xFF) == 0xF0

  block puzzle_concat:
    let lo = mkBitVecVar[4]("lo")
    let hi = mkBitVecVar[4]("hi")
    let s = newSolver()
    # concat[W1, W2]: BV[W1] × BV[W2] → BV[W1 + W2]. Width discipline
    # is checked at compile time.
    s.add concat(hi, lo) == mkBitVec(0xAB'u8, 8)
    doAssert s.check() == zsSat
    let m = s.model()
    echo &"concat: hi=0x{m[hi].toUint:x} lo=0x{m[lo].toUint:x} (expect A, B)"
    doAssert m[hi].toUint == 0xA
    doAssert m[lo].toUint == 0xB

  block puzzle_signed:
    let x = mkBitVecVar[8]("x")
    let s = newSolver()
    # bvslt with MSB=1 means signed-less-than zero — 0xFF interprets
    # as -1. Asserting bvslt finds an x with the sign bit set.
    s.add bvslt(x, mkBitVec(0'u8, 8))
    s.add x == mkBitVec(0xFF'u8, 8)   # pin to test the interpretation
    doAssert s.check() == zsSat
    echo "signed: 0xFF < 0 (signed) — yes"

    # bvult never finds an x < 0 unsigned (every BV is >= 0 unsigned).
    let s2 = newSolver()
    s2.add bvult(x, mkBitVec(0'u8, 8))
    doAssert s2.check() == zsUnsat
    echo "unsigned: no x < 0 (unsigned) — confirmed unsat"

when isMainModule:
  main()

## `z3/bitvec` tests — width-tracked BitVec phantom types + ops.

import std/[unittest]
import z3

suite "Z3BitVec — tracer":
  test "round-trip: assert x == 5 on BV[8], model gives 5":
    let ctx = newContext()
    let x = mkBitVecVar[8]("x")
    let s = newSolver()
    s.add x == mkBitVec(5'u32, 8)
    check s.check() == zsSat
    let m = s.model()
    check m[x].toUint == 5'u64

suite "Z3BitVec — width safety":
  test "equality across mismatched widths is a compile error":
    let ctx = newContext()
    # Same-width OK; different widths must not compile.
    check compiles((mkBitVec(0'u8, 8) == mkBitVec(0'u8, 8)))
    check not compiles((mkBitVec(0'u8, 8) == mkBitVec(0'u16, 16)))

  test "addition across mismatched widths is a compile error":
    let ctx = newContext()
    # Same-width OK; different widths must not.
    check compiles((mkBitVec(0'u8, 8) + mkBitVec(0'u8, 8)))
    check not compiles((mkBitVec(0'u8, 8) + mkBitVec(0'u16, 16)))

suite "Z3BitVec — modular arithmetic":
  test "addition wraps mod 2^W (255 + 1 == 0 on BV[8])":
    let ctx = newContext()
    let s = newSolver()
    let r = mkBitVec(255'u32, 8) + mkBitVec(1'u32, 8)
    s.add r == mkBitVec(0'u32, 8)
    check s.check() == zsSat

  test "subtraction wraps (0 - 1 == 255 on BV[8])":
    let ctx = newContext()
    let s = newSolver()
    let r = mkBitVec(0'u32, 8) - mkBitVec(1'u32, 8)
    s.add r == mkBitVec(255'u32, 8)
    check s.check() == zsSat

  test "unary negation (-x is 256 - x mod 2^8)":
    let ctx = newContext()
    let s = newSolver()
    let x = mkBitVec(3'u32, 8)
    s.add (-x) == mkBitVec(253'u32, 8)
    check s.check() == zsSat

  test "multiplication wraps (16 * 16 == 0 on BV[8])":
    let ctx = newContext()
    let s = newSolver()
    let r = mkBitVec(16'u32, 8) * mkBitVec(16'u32, 8)
    s.add r == mkBitVec(0'u32, 8)
    check s.check() == zsSat

suite "Z3BitVec — division and remainder (sign-explicit)":
  test "bvudiv: 200 udiv 3 == 66":
    let ctx = newContext()
    let s = newSolver()
    s.add bvudiv(mkBitVec(200'u32, 8), mkBitVec(3'u32, 8)) ==
          mkBitVec(66'u32, 8)
    check s.check() == zsSat

  test "bvurem: 200 urem 3 == 2":
    let ctx = newContext()
    let s = newSolver()
    s.add bvurem(mkBitVec(200'u32, 8), mkBitVec(3'u32, 8)) ==
          mkBitVec(2'u32, 8)
    check s.check() == zsSat

  test "bvudiv treats 0xFF as 255 (unsigned)":
    # 255 udiv 16 == 15
    let ctx = newContext()
    let s = newSolver()
    s.add bvudiv(mkBitVec(255'u32, 8), mkBitVec(16'u32, 8)) ==
          mkBitVec(15'u32, 8)
    check s.check() == zsSat

  test "no `div` overload on BitVec (must use bvudiv/bvsdiv)":
    # Sign-dependent ops are NOT overloaded — picking unsigned or signed
    # by default would silently bury the choice.
    check not compiles((mkBitVec(0'u32, 8) div mkBitVec(0'u32, 8)))
    check not compiles((mkBitVec(0'u32, 8) mod mkBitVec(0'u32, 8)))

  test "bvsdiv treats 0xFF as -1 (signed)":
    # -7 sdiv 2 == -3 in BV[8] = 0xFD
    let ctx = newContext()
    let s = newSolver()
    s.add bvsdiv(mkBitVec(-7'i32, 8), mkBitVec(2'u32, 8)) ==
          mkBitVec(-3'i32, 8)
    check s.check() == zsSat

  test "bvsrem sign matches dividend (-7 srem 2 == -1)":
    let ctx = newContext()
    let s = newSolver()
    s.add bvsrem(mkBitVec(-7'i32, 8), mkBitVec(2'u32, 8)) ==
          mkBitVec(-1'i32, 8)
    check s.check() == zsSat

  test "bvsmod sign matches divisor (-7 smod 2 == 1)":
    let ctx = newContext()
    let s = newSolver()
    s.add bvsmod(mkBitVec(-7'i32, 8), mkBitVec(2'u32, 8)) ==
          mkBitVec(1'i32, 8)
    check s.check() == zsSat

suite "Z3BitVec — bitwise":
  test "and / or / xor":
    let ctx = newContext()
    let s = newSolver()
    s.add (mkBitVec(0b1100'u32, 8) and mkBitVec(0b1010'u32, 8)) ==
          mkBitVec(0b1000'u32, 8)
    s.add (mkBitVec(0b1100'u32, 8) or  mkBitVec(0b1010'u32, 8)) ==
          mkBitVec(0b1110'u32, 8)
    s.add (mkBitVec(0b1100'u32, 8) xor mkBitVec(0b1010'u32, 8)) ==
          mkBitVec(0b0110'u32, 8)
    check s.check() == zsSat

  test "unary not flips all bits":
    let ctx = newContext()
    let s = newSolver()
    s.add (not mkBitVec(0x0F'u32, 8)) == mkBitVec(0xF0'u32, 8)
    check s.check() == zsSat

suite "Z3BitVec — shifts (logical vs arithmetic right made explicit)":
  test "shl: 0x01 << 4 == 0x10":
    let ctx = newContext()
    let s = newSolver()
    s.add (mkBitVec(0x01'u32, 8) shl mkBitVec(4'u32, 8)) ==
          mkBitVec(0x10'u32, 8)
    check s.check() == zsSat

  test "lshr: 0x80 lshr 4 == 0x08 (zero-filled)":
    let ctx = newContext()
    let s = newSolver()
    s.add lshr(mkBitVec(0x80'u32, 8), mkBitVec(4'u32, 8)) ==
          mkBitVec(0x08'u32, 8)
    check s.check() == zsSat

  test "ashr: 0x80 ashr 4 == 0xF8 (sign-bit-filled)":
    let ctx = newContext()
    let s = newSolver()
    s.add ashr(mkBitVec(0x80'u32, 8), mkBitVec(4'u32, 8)) ==
          mkBitVec(0xF8'u32, 8)
    check s.check() == zsSat

  test "no `shr` overload on BitVec (must use lshr/ashr)":
    check not compiles((mkBitVec(0x80'u32, 8) shr mkBitVec(4'u32, 8)))

suite "Z3BitVec — comparisons (sign-explicit)":
  test "unsigned: 0xFF is the largest (bvult/bvule/bvugt/bvuge)":
    let ctx = newContext()
    let s = newSolver()
    s.add bvult(mkBitVec(0'u32, 8), mkBitVec(255'u32, 8))
    s.add bvule(mkBitVec(255'u32, 8), mkBitVec(255'u32, 8))
    s.add bvugt(mkBitVec(255'u32, 8), mkBitVec(0'u32, 8))
    s.add bvuge(mkBitVec(255'u32, 8), mkBitVec(255'u32, 8))
    check s.check() == zsSat

  test "signed: 0xFF is the smallest (bvslt/bvsle/bvsgt/bvsge)":
    let ctx = newContext()
    let s = newSolver()
    s.add bvslt(mkBitVec(255'u32, 8), mkBitVec(0'u32, 8))   # -1 <s 0
    s.add bvsle(mkBitVec(-128'i32, 8), mkBitVec(127'u32, 8)) # INT_MIN <s INT_MAX
    s.add bvsgt(mkBitVec(0'u32, 8), mkBitVec(255'u32, 8))    # 0 >s -1
    s.add bvsge(mkBitVec(127'u32, 8), mkBitVec(127'u32, 8))
    check s.check() == zsSat

  test "signed and unsigned disagree on the sign bit":
    let ctx = newContext()
    let s = newSolver()
    # 0xFF: signed -1, unsigned 255. 0x01: 1 either way.
    let neg = mkBitVec(0xFF'u32, 8)
    let one = mkBitVec(0x01'u32, 8)
    s.add bvslt(neg, one)         # signed: -1 < 1
    s.add bvugt(neg, one)         # unsigned: 255 > 1
    check s.check() == zsSat

  test "no `<` overload on BitVec":
    check not compiles((mkBitVec(0'u32, 8) <  mkBitVec(0'u32, 8)))
    check not compiles((mkBitVec(0'u32, 8) <= mkBitVec(0'u32, 8)))
    check not compiles((mkBitVec(0'u32, 8) >  mkBitVec(0'u32, 8)))
    check not compiles((mkBitVec(0'u32, 8) >= mkBitVec(0'u32, 8)))

suite "Z3BitVec — inequality":
  test "!= is the negation of ==":
    let ctx = newContext()
    let s = newSolver()
    s.add mkBitVec(1'u32, 8) != mkBitVec(2'u32, 8)
    check s.check() == zsSat
    s.add mkBitVec(1'u32, 8) != mkBitVec(1'u32, 8)
    check s.check() == zsUnsat

suite "Z3BitVec — extract":
  test "extract low nibble of 0xAB == 0xB":
    let ctx = newContext()
    let s = newSolver()
    let r = mkBitVec(0xAB'u32, 8).extract(3, 0)
    s.add r == mkBitVec(0xB'u32, 4)
    check s.check() == zsSat

  test "extract high nibble of 0xAB == 0xA":
    let ctx = newContext()
    let s = newSolver()
    let r = mkBitVec(0xAB'u32, 8).extract(7, 4)
    s.add r == mkBitVec(0xA'u32, 4)
    check s.check() == zsSat

  test "extract result width = hi - lo + 1":
    let ctx = newContext()
    # extract(15, 8) from a BV[16] returns a BV[8]
    let r = mkBitVec(0xAABB'u32, 16).extract(15, 8)
    check r is Z3BitVec[8]

  test "out-of-bounds extract is a compile error":
    let ctx = newContext()
    # hi >= W is forbidden; lo > hi is forbidden.
    check not compiles((mkBitVec(0'u32, 8).extract(8, 0)))
    check not compiles((mkBitVec(0'u32, 8).extract(3, 5)))

suite "Z3BitVec — concat":
  test "concat: 0xAB ++ 0xCD == 0xABCD on BV[8] + BV[8] → BV[16]":
    let ctx = newContext()
    let s = newSolver()
    let r = concat(mkBitVec(0xAB'u32, 8), mkBitVec(0xCD'u32, 8))
    check r is Z3BitVec[16]
    s.add r == mkBitVec(0xABCD'u32, 16)
    check s.check() == zsSat

suite "Z3BitVec — extend / repeat":
  test "zeroExtend pads with zeros (0xF0 BV[8] zext 8 == 0x00F0 BV[16])":
    let ctx = newContext()
    let s = newSolver()
    let r = mkBitVec(0xF0'u32, 8).zeroExtend(8)
    check r is Z3BitVec[16]
    s.add r == mkBitVec(0x00F0'u32, 16)
    check s.check() == zsSat

  test "signExtend pads with sign bit (0xF0 BV[8] sext 8 == 0xFFF0 BV[16])":
    let ctx = newContext()
    let s = newSolver()
    let r = mkBitVec(0xF0'u32, 8).signExtend(8)
    check r is Z3BitVec[16]
    s.add r == mkBitVec(0xFFF0'u32, 16)
    check s.check() == zsSat

  test "repeat: 0xAB repeated 2x is 0xABAB on BV[16]":
    let ctx = newContext()
    let s = newSolver()
    let r = mkBitVec(0xAB'u32, 8).repeat(2)
    check r is Z3BitVec[16]
    s.add r == mkBitVec(0xABAB'u32, 16)
    check s.check() == zsSat

suite "Z3BitVec — polymorphic":
  test "ite selects on a Z3Bool":
    let ctx = newContext()
    let s = newSolver()
    let cond = mkBoolVar("c")
    let r = ite(cond, mkBitVec(0x55'u32, 8), mkBitVec(0xAA'u32, 8))
    s.add cond
    s.add r == mkBitVec(0x55'u32, 8)
    check s.check() == zsSat

  test "mkDistinct on BV vars finds all-distinct assignment":
    let ctx = newContext()
    let s = newSolver()
    var v: array[3, Z3BitVec[8]]
    for i in 0..2:
      v[i] = mkBitVecVar[8]("v" & $i)
      s.add bvult(v[i], mkBitVec(3'u32, 8))   # v[i] < 3
    s.add mkDistinct(v[0], v[1], v[2])
    check s.check() == zsSat

suite "Z3BitVec — literal lifts":
  test "bv + uint literal":
    let ctx = newContext()
    let s = newSolver()
    let x = mkBitVec(5'u32, 8)
    s.add (x + 3'u32) == mkBitVec(8'u32, 8)
    s.add (3'u32 + x) == mkBitVec(8'u32, 8)
    check s.check() == zsSat

  test "bv == uint literal":
    let ctx = newContext()
    let s = newSolver()
    let x = mkBitVec(7'u32, 8)
    s.add x == 7'u32
    s.add 7'u32 == x
    check s.check() == zsSat

suite "Z3BitVec — signed extraction":
  test "toInt: 0xFF on BV[8] is -1 signed, 255 unsigned":
    let ctx = newContext()
    let bv = mkBitVec(0xFF'u32, 8)
    check bv.toUint == 255'u64
    check bv.toInt == -1'i64

  test "toInt round-trips through solver":
    let ctx = newContext()
    let x = mkBitVecVar[8]("x")
    let s = newSolver()
    s.add x == mkBitVec(-42'i32, 8)
    check s.check() == zsSat
    let m = s.model()
    check m[x].toInt == -42'i64

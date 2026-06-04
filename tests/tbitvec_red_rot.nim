## `z3/bitvec` — reduction ops and extended rotation tests (N3.2).
##
## `redAnd`/`redOr` reduce a BV to a 1-bit result via AND/OR across all bits.
## `extRotateLeft`/`extRotateRight` rotate by a symbolic (BV-typed) shift amount.
##
## Tests use `toUint` on concrete expressions: Z3 simplifies the tree before
## extraction, so no solver is needed for constant folding.

import std/[unittest]
import z3

suite "Z3BitVec — reduction ops (N3.2)":

  test "redAnd: all bits set (0xFF) → 1":
    ## 0b1111_1111: AND of all 8 bits is 1.
    let ctx = newContext()
    let result = redAnd(mkBitVec[8](255))
    check result.toUint == 1

  test "redAnd: bit 0 cleared (0xFE) → 0":
    ## 0b1111_1110: AND of all 8 bits is 0 because bit 0 is 0.
    let ctx = newContext()
    let result = redAnd(mkBitVec[8](254))
    check result.toUint == 0

  test "redOr: all bits clear (0x00) → 0":
    ## 0b0000_0000: OR of all 8 bits is 0.
    let ctx = newContext()
    let result = redOr(mkBitVec[8](0))
    check result.toUint == 0

  test "redOr: one bit set (0x01) → 1":
    ## 0b0000_0001: OR of all 8 bits is 1.
    let ctx = newContext()
    let result = redOr(mkBitVec[8](1))
    check result.toUint == 1

suite "Z3BitVec — extended rotations (N3.2)":

  test "extRotateLeft: 0b00001111 rotated left by 4 → 0b11110000":
    ## Low nibble shifts to high nibble.
    let ctx = newContext()
    let result = extRotateLeft(mkBitVec[8](0b00001111), mkBitVec[8](4))
    check result.toUint == 0b11110000

  test "extRotateRight: 0b10000001 rotated right by 1 → 0b11000000":
    ## MSB wraps to bit 7; bit 0 shifts to bit 7 as well (both bits 7 and 0
    ## become bit 7 and 6 respectively in the result).
    ## 0b10000001 >> 1 (rotate): bit 0 wraps to MSB → 0b11000000.
    let ctx = newContext()
    let result = extRotateRight(mkBitVec[8](0b10000001), mkBitVec[8](1))
    check result.toUint == 0b11000000

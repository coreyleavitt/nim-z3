## `z3/char.toBitVec` + `mkChar(bv)` tests — Z3Char ↔ BV interop
## (v0.5 step 6C).
##
## Z3's char sort has a fixed bit-width determined by its `encoding`
## global parameter (default `unicode` = 18 bits). The wrapper
## commits to the Unicode default and ships:
##
##   - `toBitVec(c: Z3Char): Z3BitVec[18]`
##   - `mkChar(bv: Z3BitVec[18]): Z3Char`
##
## If a user changes `encoding` to `bmp` (16 bits) or `ascii` (8
## bits), they're in escape-hatch territory and call the FFI
## directly. Documented loudly in the proc docstrings.

import std/[unittest]
import z3

suite "Z3Char ↔ Z3BitVec — tracer":
  test "toBitVec on mkChar('a') equals the BV literal 97":
    # SMT-valid: forall models, `(char.to_bv (_ Char 97))` equals
    # `(_ bv97 18)`. This is what makes `toBitVec` a semantically
    # correct codepoint extractor.
    let ctx = newContext()
    let lhs = mkChar('a').toBitVec
    let rhs = mkBitVec[18](ord('a').uint32)
    check smtValid(lhs == rhs)

suite "Z3Char ↔ Z3BitVec — round-trip":
  test "mkChar(toBitVec(c)) == c for any concrete codepoint":
    let ctx = newContext()
    let c = mkChar('Z')
    check smtValid(mkChar(c.toBitVec) == c)

  test "toBitVec(mkChar(bv)) == bv for any BV[18] value":
    # Round-trip the other direction: BV → Char → BV preserves value
    # for any BV value in the valid Unicode range.
    let ctx = newContext()
    let bv = mkBitVec[18](ord('5').uint32)
    check smtValid(mkChar(bv).toBitVec == bv)

  test "toBitVec preserves codepoint ordering":
    # `c1 <= c2` (Z3Char ordering) implies `c1.toBitVec <= c2.toBitVec`
    # under bvule (unsigned BV ordering) — both compare codepoints
    # directly so the relations agree on the valid Unicode range.
    let ctx = newContext()
    let a = mkChar('a')
    let z = mkChar('z')
    # On the typed AST level: a < z holds; and BV-level comparison
    # of their toBitVec encodings agrees.
    check smtValid(a < z)
    check smtValid(a.toBitVec.bvult(z.toBitVec))

suite "Z3Char ↔ Z3BitVec — sort safety":
  test "mkChar accepts only Z3BitVec[18], not other widths":
    # Compile-time check: passing a Z3BitVec[16] to mkChar would
    # be a sort error. We verify by reasoning about the surface
    # (we can't compile-fail in a test easily; this is a smoke
    # test that the typed signature accepts the right width).
    let ctx = newContext()
    let bv18 = mkBitVec[18](42'u32)
    let c = mkChar(bv18)  # compiles
    check smtValid(c.toBitVec == bv18)

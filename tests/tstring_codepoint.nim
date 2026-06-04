## `z3/strings` — codepoint conversion + BV-to-string (N5.2).
##
## Covers:
##   - `toCode(s)`      — Z3_mk_string_to_code; first codepoint of a
##                        single-char string, or -1 for empty string.
##   - `fromCode(ctx, c)` — Z3_mk_string_from_code; single-char string
##                          from a codepoint integer.
##   - `toString(bv, signed)` — Z3_mk_ubv_to_str / Z3_mk_sbv_to_str;
##                              BV to its decimal string representation.

import std/[unittest]
import z3

suite "Z3String — codepoint conversion (N5.2)":
  test "toCode(\"A\") evaluates to 65":
    let ctx = newContext()
    check smtValid(toCode(mkString("A")) == mkInt(65))

  test "fromCode(65) evaluates to \"A\"":
    let ctx = newContext()
    check smtValid(fromCode(ctx, mkInt(65)) == mkString("A"))

  test "toCode(\"\") is -1 per Z3 spec":
    let ctx = newContext()
    check smtValid(toCode(mkString("")) == mkInt(-1))

  test "round-trip: fromCode(toCode(\"Z\")) == \"Z\"":
    let ctx = newContext()
    check smtValid(fromCode(ctx, toCode(mkString("Z"))) == mkString("Z"))

suite "Z3BitVec — BV-to-string conversion (N5.2)":
  test "toString(mkBitVec[8](42), signed=false) evaluates to \"42\"":
    let ctx = newContext()
    check smtValid(toString(mkBitVec[8](42), signed = false) == mkString("42"))

  test "toString(mkBitVec[8](-1), signed=true) evaluates to \"-1\"":
    let ctx = newContext()
    check smtValid(toString(mkBitVec[8](-1'i8), signed = true) == mkString("-1"))

  test "toString(mkBitVec[8](-1), signed=false) evaluates to \"255\"":
    let ctx = newContext()
    check smtValid(toString(mkBitVec[8](-1'i8), signed = false) == mkString("255"))

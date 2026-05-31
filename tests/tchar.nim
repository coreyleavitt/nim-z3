## `z3/chars` tests — SMT-LIB Char sort.
##
## Covers what Z3 actually ships on the Char theory: codepoint literal
## construction, ordering (`<=`, `<`), digit predicate, and the
## AST-level codepoint extractor (`toInt`).

import std/[unittest]
import z3

suite "Z3Char — construction and equality":
  test "mkChar(codepoint) builds a Z3Char":
    let ctx = newContext()
    check smtValid(mkChar(0x61) == mkChar('a'))
    check smtValid(mkChar('a') != mkChar('b'))

  test "out-of-range codepoint rejected at the boundary":
    let ctx = newContext()
    expect AssertionDefect:
      discard mkChar(-1)
    expect AssertionDefect:
      discard mkChar(0x110000)

suite "Z3Char — ordering and predicates":
  test "<= is codepoint ordering":
    let ctx = newContext()
    check smtValid(mkChar('a') <= mkChar('z'))
    check smtValid(mkChar('a') <= mkChar('a'))
    check smtValid(not (mkChar('z') <= mkChar('a')))

  test "< is strict codepoint ordering":
    let ctx = newContext()
    check smtValid(mkChar('a') < mkChar('z'))
    check smtValid(not (mkChar('a') < mkChar('a')))
    check smtValid(not (mkChar('z') < mkChar('a')))

  test "isDigit recognises ASCII '0'..'9'":
    let ctx = newContext()
    check smtValid(mkChar('5').isDigit)
    check smtValid(not mkChar('a').isDigit)
    check smtValid(not mkChar(' ').isDigit)

suite "Z3Char — codepoint extraction":
  test "toInt returns the codepoint as a Z3Int":
    let ctx = newContext()
    check smtValid(mkChar('a').toInt == mkInt(0x61))
    check smtValid(mkChar(0x1F600).toInt == mkInt(0x1F600))   # 😀

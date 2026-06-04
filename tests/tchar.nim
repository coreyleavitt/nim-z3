## `z3/chars` tests — SMT-LIB Char sort.
##
## Covers the full Z3Char surface: codepoint literal construction,
## equality and inequality, full ordering (`<`, `<=`, `>`, `>=`),
## digit predicate, AST-level codepoint extractor (`toInt`),
## free char variables (`mkCharVar`), model-level extractor
## (`evalChar`), and edge cases (codepoint 0, ASCII boundaries,
## max codepoint).

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

suite "Z3Char — equality and inequality":
  test "== is true for identical codepoints":
    let ctx = newContext()
    check smtValid(mkChar('x') == mkChar('x'))
    check smtValid(mkChar(0) == mkChar(0))
    check smtValid(mkChar(0x10FFFF) == mkChar(0x10FFFF))

  test "!= is true for distinct codepoints":
    let ctx = newContext()
    check smtValid(mkChar('a') != mkChar('b'))
    check smtValid(mkChar(0) != mkChar(1))
    check smtValid(mkChar(0x10FFFE) != mkChar(0x10FFFF))

  test "== and != are complementary":
    let ctx = newContext()
    check smtValid(not (mkChar('p') == mkChar('q')))
    check smtValid(mkChar('p') != mkChar('q'))

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

  test "> is strict codepoint ordering (arg-swap of <)":
    let ctx = newContext()
    check smtValid(mkChar('z') > mkChar('a'))
    check smtValid(not (mkChar('a') > mkChar('a')))
    check smtValid(not (mkChar('a') > mkChar('z')))

  test ">= is reflexive codepoint ordering (arg-swap of <=)":
    let ctx = newContext()
    check smtValid(mkChar('z') >= mkChar('a'))
    check smtValid(mkChar('a') >= mkChar('a'))
    check smtValid(not (mkChar('a') >= mkChar('z')))

  test "< and > are consistent: a < b iff b > a":
    let ctx = newContext()
    check smtValid(mkChar('A') < mkChar('Z'))
    check smtValid(mkChar('Z') > mkChar('A'))

  test "<= and >= are consistent: a <= b iff b >= a":
    let ctx = newContext()
    check smtValid(mkChar('A') <= mkChar('Z'))
    check smtValid(mkChar('Z') >= mkChar('A'))
    check smtValid(mkChar('M') <= mkChar('M'))
    check smtValid(mkChar('M') >= mkChar('M'))

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

  test "toInt at codepoint 0 (null character)":
    let ctx = newContext()
    check smtValid(mkChar(0).toInt == mkInt(0))

  test "toInt at max codepoint 0x10FFFF":
    let ctx = newContext()
    check smtValid(mkChar(0x10FFFF).toInt == mkInt(0x10FFFF))

  test "toInt at ASCII boundaries":
    let ctx = newContext()
    check smtValid(mkChar(0x20).toInt == mkInt(0x20))   # space
    check smtValid(mkChar(0x7E).toInt == mkInt(0x7E))   # '~', last printable ASCII
    check smtValid(mkChar(0x7F).toInt == mkInt(0x7F))   # DEL

suite "Z3Char — free variable and model extraction":
  test "mkCharVar produces a free Z3Char variable usable as a constraint":
    let ctx = newContext()
    let c = mkCharVar("c")
    let s = newSolver()
    s.add c == mkChar('a')
    check s.check() == zsSat

  test "mkCharVar can be constrained by ordering":
    let ctx = newContext()
    let c = mkCharVar("cv")
    let s = newSolver()
    s.add c > mkChar('a')
    s.add c < mkChar('z')
    check s.check() == zsSat

  test "evalChar extracts the concrete codepoint from a model":
    let ctx = newContext()
    let c = mkCharVar("ch")
    let s = newSolver()
    s.add c == mkChar('A')
    check s.check() == zsSat
    check evalChar(s.model(), c) == ord('A')

  test "evalChar at codepoint 0":
    let ctx = newContext()
    let c = mkCharVar("ch0")
    let s = newSolver()
    s.add c == mkChar(0)
    check s.check() == zsSat
    check evalChar(s.model(), c) == 0i64

  test "evalChar at max codepoint":
    let ctx = newContext()
    let c = mkCharVar("chmax")
    let s = newSolver()
    s.add c == mkChar(0x10FFFF)
    check s.check() == zsSat
    check evalChar(s.model(), c) == int64(0x10FFFF)

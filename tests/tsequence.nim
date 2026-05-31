## `z3/seq` tests — SMT-LIB Sequence theory `(Seq E)`.
##
## Sequences are the generalisation of strings (which Z3 defines as
## `(Seq Char)`). The wrapper surfaces them as `Z3Seq[E]`, phantom-
## typed over the element AST family. Every `seq.*` op Z3 ships lives
## here; `z3/strings`'s previously-string-specific surface migrates to
## use these.

import std/[unittest]
import z3

suite "Z3Seq — tracer":
  test "round-trip: assert x == seq.unit(5) on Z3Seq[Z3Int]":
    let ctx = newContext()
    let x = mkSeqVar[Z3Int]("x")
    let s = newSolver()
    s.add x == mkSeqUnit(mkInt(5))
    check s.check() == zsSat
    let m = s.model()
    check m.evalInt(nth(m[x], mkInt(0))) == 5

suite "Z3Seq — primitive ops":
  test "empty sequence has length 0":
    let ctx = newContext()
    check smtValid(mkSeqEmpty[Z3Int]().len == mkInt(0))

  test "unit sequence has length 1; nth(s, 0) is the element":
    let ctx = newContext()
    let s = mkSeqUnit(mkInt(42))
    check smtValid(s.len == mkInt(1))
    check smtValid(nth(s, mkInt(0)) == mkInt(42))

  test "concat builds longer sequences":
    let ctx = newContext()
    let s = concat(mkSeqUnit(mkInt(1)), mkSeqUnit(mkInt(2)), mkSeqUnit(mkInt(3)))
    check smtValid(s.len == mkInt(3))
    check smtValid(nth(s, mkInt(1)) == mkInt(2))

  test "& operator is two-arg concat":
    let ctx = newContext()
    let s = mkSeqUnit(mkInt(1)) & mkSeqUnit(mkInt(2))
    check smtValid(s.len == mkInt(2))
    check smtValid(nth(s, mkInt(1)) == mkInt(2))

  test "[i] operator aliases nth":
    let ctx = newContext()
    let s = concat(mkSeqUnit(mkInt(10)), mkSeqUnit(mkInt(20)))
    check smtValid(s[mkInt(0)] == mkInt(10))
    check smtValid(s[mkInt(1)] == mkInt(20))

  test "at(s, i) is a 1-element sub-sequence (not the element)":
    let ctx = newContext()
    let s = concat(mkSeqUnit(mkInt(7)), mkSeqUnit(mkInt(8)))
    let one = at(s, mkInt(1))
    check smtValid(one == mkSeqUnit(mkInt(8)))
    check smtValid(one.len == mkInt(1))

  test "substr(offset, length) extracts a slice":
    let ctx = newContext()
    let s = concat(mkSeqUnit(mkInt(1)), mkSeqUnit(mkInt(2)),
                   mkSeqUnit(mkInt(3)), mkSeqUnit(mkInt(4)))
    let slice = substr(s, mkInt(1), mkInt(2))
    check smtValid(slice == concat(mkSeqUnit(mkInt(2)), mkSeqUnit(mkInt(3))))

  test "contains decides positive + negative":
    let ctx = newContext()
    let s = concat(mkSeqUnit(mkInt(1)), mkSeqUnit(mkInt(2)), mkSeqUnit(mkInt(3)))
    check smtValid(s.contains(mkSeqUnit(mkInt(2))))
    check smtValid(not s.contains(mkSeqUnit(mkInt(99))))

  test "startsWith / endsWith":
    let ctx = newContext()
    let s = concat(mkSeqUnit(mkInt(1)), mkSeqUnit(mkInt(2)), mkSeqUnit(mkInt(3)))
    check smtValid(s.startsWith(mkSeqUnit(mkInt(1))))
    check smtValid(not s.startsWith(mkSeqUnit(mkInt(2))))
    check smtValid(s.endsWith(mkSeqUnit(mkInt(3))))
    check smtValid(not s.endsWith(mkSeqUnit(mkInt(1))))

  test "indexOf returns position; -1 when missing; honors start":
    let ctx = newContext()
    let s = concat(mkSeqUnit(mkInt(1)), mkSeqUnit(mkInt(2)),
                   mkSeqUnit(mkInt(1)), mkSeqUnit(mkInt(3)))
    check smtValid(indexOf(s, mkSeqUnit(mkInt(1))) == mkInt(0))
    check smtValid(indexOf(s, mkSeqUnit(mkInt(1)), mkInt(1)) == mkInt(2))
    check smtValid(indexOf(s, mkSeqUnit(mkInt(99))) == mkInt(-1))

  test "replace is first-occurrence":
    let ctx = newContext()
    let s = concat(mkSeqUnit(mkInt(1)), mkSeqUnit(mkInt(2)), mkSeqUnit(mkInt(1)))
    let r = replace(s, mkSeqUnit(mkInt(1)), mkSeqUnit(mkInt(99)))
    check smtValid(r == concat(
      mkSeqUnit(mkInt(99)), mkSeqUnit(mkInt(2)), mkSeqUnit(mkInt(1))))

suite "Z3Seq — equality":
  test "== and != reduce identical sequences":
    let ctx = newContext()
    let a = concat(mkSeqUnit(mkInt(1)), mkSeqUnit(mkInt(2)))
    let b = concat(mkSeqUnit(mkInt(1)), mkSeqUnit(mkInt(2)))
    check smtValid(a == b)
    check smtValid(not (a != b))
    let c = concat(mkSeqUnit(mkInt(1)), mkSeqUnit(mkInt(3)))
    check smtValid(a != c)

suite "Z3Seq — various element types":
  test "Z3Seq[Z3Bool]":
    let ctx = newContext()
    let s = concat(mkSeqUnit(mkTrue()), mkSeqUnit(mkFalse()), mkSeqUnit(mkTrue()))
    check smtValid(s.len == mkInt(3))
    check smtValid(nth(s, mkInt(0)) == mkTrue())
    check smtValid(nth(s, mkInt(1)) == mkFalse())

  test "Z3Seq[Z3BitVec[8]]":
    let ctx = newContext()
    let s = concat(mkSeqUnit(mkBitVec[8](0xAA'u8)),
                   mkSeqUnit(mkBitVec[8](0xBB'u8)))
    check smtValid(s.len == mkInt(2))
    check smtValid(nth(s, mkInt(0)) == mkBitVec[8](0xAA'u8))

  test "Z3Seq[Z3Char]":
    let ctx = newContext()
    let s = mkSeqUnit(mkChar('a')) & mkSeqUnit(mkChar('b'))
    check smtValid(s.len == mkInt(2))
    check smtValid(nth(s, mkInt(0)) == mkChar('a'))

suite "Z3Seq — nesting":
  test "Z3Seq[Z3Seq[Z3Int]] — sequence of sequences":
    let ctx = newContext()
    let inner1 = concat(mkSeqUnit(mkInt(1)), mkSeqUnit(mkInt(2)))
    let inner2 = mkSeqUnit(mkInt(3))
    let outer = mkSeqUnit(inner1) & mkSeqUnit(inner2)
    check smtValid(outer.len == mkInt(2))
    # Outer element [0] is the first inner seq; its element [0] is 1.
    check smtValid(nth(nth(outer, mkInt(0)), mkInt(0)) == mkInt(1))
    check smtValid(nth(outer, mkInt(1)).len == mkInt(1))

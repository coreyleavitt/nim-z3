## `z3/sequence` — int-literal index lifts (N5.6).
##
## Every proc that takes a `Z3Int` index also accepts a plain `int`.
## The lift is transparent — `at(s, 1)` is identical in effect to
## `at(s, mkInt(1))`.

import std/[unittest]
import z3

suite "Z3Seq — int-literal index lifts":
  test "at(s, int) returns a 1-element sub-sequence":
    let ctx = newContext()
    # "hello" as Z3String (= Z3Seq[Z3Char]); at(s, 1) must equal "e"
    check smtValid(at(mkString("hello"), 1) == mkString("e"))

  test "substr(s, int, int) extracts a slice":
    let ctx = newContext()
    check smtValid(substr(mkString("hello"), 1, 3) == mkString("ell"))

  test "indexOf(s, sub, int) finds first occurrence from int offset":
    let ctx = newContext()
    check smtValid(indexOf(mkString("hello world"), mkString("world"), 0) == mkInt(6))

  test "nth(s, int) on Z3Seq[Z3Int] returns the element":
    let ctx = newContext()
    let s = concat(mkSeqUnit(mkInt(10)), mkSeqUnit(mkInt(20)), mkSeqUnit(mkInt(30)))
    check smtValid(nth(s, 1) == mkInt(20))

  test "[int] operator lifts on Z3Seq[Z3Int]":
    let ctx = newContext()
    let s = concat(mkSeqUnit(mkInt(7)), mkSeqUnit(mkInt(8)))
    check smtValid(s[0] == mkInt(7))
    check smtValid(s[1] == mkInt(8))

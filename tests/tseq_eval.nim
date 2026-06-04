## `z3/seq` eval shortcut tests — N5.7.
##
## Covers:
##   - `evalSeq(m, s: Z3Seq[Z3Int]): seq[int64]` — extract concrete sequence
##   - `evalStr(m, s: Z3String): string` — existing string extraction (regression)
##   - Empty sequence case
##   - After rename: `Z3String.toInt` and `Z3Int.toStr` (was `strToInt`/`intToStr`)

import std/[unittest]
import z3

suite "evalSeq — Z3Seq[Z3Int]":
  test "forced @[1, 2, 3] → evalSeq returns @[1'i64, 2, 3]":
    let ctx = newContext()
    let s = mkSeqVar[Z3Int]("s")
    let target = concat(mkSeqUnit(mkInt(1)), mkSeqUnit(mkInt(2)), mkSeqUnit(mkInt(3)))
    let slv = newSolver()
    slv.add s == target
    check slv.check() == zsSat
    let m = slv.model()
    check m.evalSeq(s) == @[1'i64, 2, 3]

  test "forced @[] → evalSeq returns @[]":
    let ctx = newContext()
    let s = mkSeqVar[Z3Int]("s")
    let slv = newSolver()
    slv.add s == mkSeqEmpty[Z3Int]()
    check slv.check() == zsSat
    let m = slv.model()
    check m.evalSeq(s) == newSeq[int64](0)

  test "forced @[42] singleton → evalSeq returns @[42'i64]":
    let ctx = newContext()
    let s = mkSeqVar[Z3Int]("s")
    let slv = newSolver()
    slv.add s == mkSeqUnit(mkInt(42))
    check slv.check() == zsSat
    let m = slv.model()
    check m.evalSeq(s) == @[42'i64]

suite "evalStr — Z3String (regression)":
  test "forced \"alice\" → evalStr returns \"alice\"":
    let ctx = newContext()
    let name = mkStringVar("name")
    let slv = newSolver()
    slv.add name == mkString("alice")
    check slv.check() == zsSat
    let m = slv.model()
    check m.evalStr(name) == "alice"

  test "forced empty string → evalStr returns \"\"":
    let ctx = newContext()
    let name = mkStringVar("name")
    let slv = newSolver()
    slv.add name == mkString("")
    check slv.check() == zsSat
    let m = slv.model()
    check m.evalStr(name) == ""

suite "Z3String.toInt and Z3Int.toStr (renamed from strToInt / intToStr)":
  test "Z3String.toInt: digit string → non-negative integer":
    let ctx = newContext()
    check smtValid(mkString("42").toInt == mkInt(42))

  test "Z3String.toInt: non-digit string → -1":
    let ctx = newContext()
    check smtValid(mkString("abc").toInt == mkInt(-1))

  test "Z3Int.toStr: integer → digit string":
    let ctx = newContext()
    check smtValid(mkInt(42).toStr == mkString("42"))

  test "Z3Int.toStr: negative integer → empty string":
    let ctx = newContext()
    check smtValid(mkInt(-5).toStr == mkString(""))

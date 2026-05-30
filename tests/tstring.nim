## `z3/string` tests — String theory (sequence of unicode chars).
##
## Strings in SMT-LIB are `(Seq Char)`; in Z3 they're exposed as a
## first-class sort with dedicated builders (`Z3_mk_string`,
## `Z3_mk_seq_*` over the string sort). The wrapper surfaces them as a
## phantom-typed `Z3String` family — same pattern as `Z3Array[K, V]`
## and `Z3DatatypeValue[T]`, no `SortTag` entry, slots into `Z3Term`.

import std/[unittest]
import z3

suite "Z3String — tracer":
  test "round-trip: assert x == \"hello\", model gives \"hello\"":
    let ctx = newContext()
    let x = mkStringVar("x")
    let s = newSolver()
    s.add x == mkString("hello")
    check s.check() == zsSat
    let m = s.model()
    check m.evalStr(x) == "hello"

suite "Z3String — primitive ops":
  test "len of a literal is the byte length":
    let ctx = newContext()
    check smtValid(mkString("hi").len == mkInt(2))
    check smtValid(mkString("").len == mkInt(0))
    check smtValid(mkString("hello").len == mkInt(5))

  test "concat via varargs builds the concatenation":
    let ctx = newContext()
    check smtValid(concat(mkString("foo"), mkString("bar")) == mkString("foobar"))
    check smtValid(
      concat(mkString("a"), mkString("b"), mkString("c")) == mkString("abc"))

  test "& operator is two-arg concat sugar":
    let ctx = newContext()
    check smtValid((mkString("hello") & mkString(" world")) == mkString("hello world"))

  test "contains decides positive + negative cases":
    let ctx = newContext()
    check smtValid(mkString("hello").contains(mkString("ell")))
    check smtValid(not mkString("hello").contains(mkString("xyz")))

  test "substr extracts (offset, length)":
    let ctx = newContext()
    check smtValid(mkString("hello").substr(mkInt(1), mkInt(3)) == mkString("ell"))
    check smtValid(mkString("hello").substr(mkInt(0), mkInt(5)) == mkString("hello"))

  test "startsWith / endsWith":
    let ctx = newContext()
    check smtValid(mkString("hello").startsWith(mkString("hel")))
    check smtValid(not mkString("hello").startsWith(mkString("ell")))
    check smtValid(mkString("hello").endsWith(mkString("llo")))
    check smtValid(not mkString("hello").endsWith(mkString("hel")))

  test "indexOf returns position; -1 when not found":
    let ctx = newContext()
    check smtValid(indexOf(mkString("hello"), mkString("ell")) == mkInt(1))
    check smtValid(indexOf(mkString("hello"), mkString("xyz")) == mkInt(-1))
    check smtValid(indexOf(mkString("foofoo"), mkString("foo"), mkInt(1)) == mkInt(3))

  test "replace is first-occurrence":
    let ctx = newContext()
    check smtValid(
      replace(mkString("foofoo"), mkString("foo"), mkString("bar")) ==
      mkString("barfoo"))

  test "at returns the single-codepoint substring":
    let ctx = newContext()
    check smtValid(at(mkString("abc"), mkInt(1)) == mkString("b"))
    check smtValid(at(mkString("abc"), mkInt(10)) == mkString(""))

  test "strToInt / intToStr round-trip":
    let ctx = newContext()
    check smtValid(strToInt(mkString("42")) == mkInt(42))
    check smtValid(strToInt(mkString("abc")) == mkInt(-1))
    check smtValid(intToStr(mkInt(42)) == mkString("42"))

suite "Z3String — Nim-literal lifts":
  test "x == \"literal\" compiles and produces a Z3Bool":
    let ctx = newContext()
    let x = mkStringVar("x")
    let s = newSolver()
    s.add x == "hello"          # lift on the RHS
    check s.check() == zsSat

  test "\"prefix\" & x compiles and concats":
    let ctx = newContext()
    let x = mkStringVar("x")
    let s = newSolver()
    s.add x == "world"
    s.add (("hello " & x) == mkString("hello world"))
    check s.check() == zsSat

  test "contains / startsWith / endsWith lift on either side":
    let ctx = newContext()
    let x = mkStringVar("x")
    let s = newSolver()
    s.add contains(x, "ell")
    s.add startsWith(x, "h")
    s.add endsWith(x, "o")
    s.add x.len == mkInt(5)
    s.add x == "hello"
    check s.check() == zsSat

## `z3/sequence` + `z3/regex` tests — N5.4 slice:
##   `lastIndexOf`, `replaceAll`, `replaceRe`.
##
## `replaceAll` and `replaceRe` are gated: compile with
## `-d:z3WithSeqReplaceAll` / `-d:z3WithSeqReplaceRe` on Z3 builds
## that ship `Z3_mk_seq_replace_all` / `Z3_mk_seq_replace_re`.

import std/[unittest]
import z3

suite "lastIndexOf":
  test "lastIndexOf finds last occurrence":
    ## "abcabc".lastIndexOf("b") == 4
    let ctx = newContext()
    let s = mkString("abcabc")
    let sub = mkString("b")
    check smtValid(lastIndexOf(s, sub) == mkInt(4))

  test "lastIndexOf returns -1 when not found":
    let ctx = newContext()
    let s = mkString("abc")
    let sub = mkString("z")
    check smtValid(lastIndexOf(s, sub) == mkInt(-1))

when defined(z3WithSeqReplaceAll):
  suite "replaceAll":
    test "replaceAll replaces every occurrence":
      ## "aaa".replaceAll("a", "b") == "bbb"
      let ctx = newContext()
      let s = mkString("aaa")
      let old = mkString("a")
      let neu = mkString("b")
      check smtValid(replaceAll(s, old, neu) == mkString("bbb"))

    test "replaceAll is no-op when pattern absent":
      ## "abc".replaceAll("z", "y") == "abc"
      let ctx = newContext()
      let s = mkString("abc")
      let old = mkString("z")
      let neu = mkString("y")
      check smtValid(replaceAll(s, old, neu) == mkString("abc"))

when defined(z3WithSeqReplaceRe):
  suite "replaceRe":
    test "replaceRe replaces first regex match":
      ## "abc123def".replaceRe(digit+, "X") == "abcXdef"
      let ctx = newContext()
      let s = mkString("abc123def")
      let digitRe = range("0", "9").plus
      let replacement = mkString("X")
      check smtValid(replaceRe(s, digitRe, replacement) == mkString("abcXdef"))

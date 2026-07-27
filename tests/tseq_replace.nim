## `z3/sequence` tests — N5.4 slice: `lastIndexOf`, `replaceAll`.
##
## `replaceAll` is gated: compile with `-d:z3WithSeqReplaceAll` on Z3 builds
## that ship `Z3_mk_seq_replace_all`.
##
## The regex-replace wrappers (`replaceRe` / `replaceReAll`) are intentionally
## not shipped — Z3's solver returns `unknown` on `str.replace_re{,_all}` even
## for concrete inputs, so they can't be verified with `smtValid`. Deferred
## pending upstream Z3 (see docs/RFC-regex-index.md §7, GOTCHAS #24).

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

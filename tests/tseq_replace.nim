## `z3/sequence` + `z3/regex` tests — N5.4 slice: `lastIndexOf`, `replaceAll`,
## and the regex-replace wrappers `replaceRe` / `replaceReAll`.
##
## `replaceAll` is gated: compile with `-d:z3WithSeqReplaceAll` on Z3 builds
## that ship `Z3_mk_seq_replace_all`.
##
## `replaceRe` / `replaceReAll` are gated behind `-d:z3WithSeqReplaceRe` /
## `-d:z3WithSeqReplaceReAll` respectively. Both build CORRECT
## `str.replace_re{,_all}` terms (verified via the SMT-LIB rendering below),
## but Z3's solver currently answers `zsUnknown` — in BOTH directions,
## equality and inequality — on these constraints even for fully concrete
## inputs (empirically probed on Z3 4.16.0; see docs/RFC-regex-index.md §7
## and GOTCHAS #19, #24). So these suites verify TERM CONSTRUCTION rather
## than `smtValid`/solver-decided equalities. The two `Z3_mk_seq_replace_re
## {,_all}` C functions are also absent below ~4.15.8 — the tests below
## branch at runtime on `Available()` to exercise both the present-symbol
## path (term built + rendered) and the absent-symbol path
## (`Z3FeatureUnavailableError` raised), so the suite is green whether or
## not the loaded libz3 has the symbols.

import std/[unittest, strutils]
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
    test "builds a correct str.replace_re term when available; raises when not":
      let ctx = newContext()
      let s = mkString("abc123def")
      let digitRe = range("0", "9").plus
      let replacement = mkString("X")
      if not Z3_mk_seq_replace_reAvailable():
        expect Z3FeatureUnavailableError:
          discard replaceRe(s, digitRe, replacement)
      else:
        let term = replaceRe(s, digitRe, replacement)
        let rendered = $term
        check rendered.contains("str.replace_re")
        check rendered.contains("abc123def")
        check rendered.contains("X")

    test "solver-opacity: concrete equality is zsUnknown, not decided (regression guard)":
      ## Documents the caveat in the docstring/GOTCHAS: if Z3 ever starts
      ## deciding `str.replace_re` on concrete inputs, this test should be
      ## upgraded to `smtValid` and the caveat text relaxed accordingly.
      let ctx = newContext()
      if Z3_mk_seq_replace_reAvailable():
        let s = mkString("abc123def")
        let digitRe = range("0", "9").plus
        let replacement = mkString("X")
        let term = replaceRe(s, digitRe, replacement)
        let solver = newSolver()
        solver.add(term == mkString("abcXdef"))
        check solver.check() == zsUnknown
      else:
        skip()

when defined(z3WithSeqReplaceReAll):
  suite "replaceReAll":
    test "builds a correct str.replace_re_all term when available; raises when not":
      let ctx = newContext()
      let s = mkString("a1b2c3")
      let digitRe = range("0", "9").plus
      let replacement = mkString("X")
      if not Z3_mk_seq_replace_re_allAvailable():
        expect Z3FeatureUnavailableError:
          discard replaceReAll(s, digitRe, replacement)
      else:
        let term = replaceReAll(s, digitRe, replacement)
        let rendered = $term
        check rendered.contains("str.replace_re_all")
        check rendered.contains("a1b2c3")
        check rendered.contains("X")

    test "solver-opacity: concrete inequality is zsUnknown, not decided (regression guard)":
      ## Mirrors the `replaceRe` regression guard above but probes the
      ## other direction (`!=`) to document both directions are opaque.
      let ctx = newContext()
      if Z3_mk_seq_replace_re_allAvailable():
        let s = mkString("a1b2c3")
        let digitRe = range("0", "9").plus
        let replacement = mkString("X")
        let term = replaceReAll(s, digitRe, replacement)
        let solver = newSolver()
        solver.add(term != mkString("aXbXcX"))
        check solver.check() == zsUnknown
      else:
        skip()

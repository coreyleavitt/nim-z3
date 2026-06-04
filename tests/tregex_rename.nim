## `tregex_rename` — verifies the N10.11 rename `mkRegexAll` → `mkRegexAllChar`.
##
## Two behavioural tests confirm `mkRegexAllChar` works correctly as the
## single-character wildcard.  A compile-time guard confirms the old name is
## gone — if `mkRegexAll` were still exported the `when compiles(...)` branch
## would fire and `doAssert false` would abort the suite.

import std/[unittest]
import z3

suite "N10.11 — mkRegexAllChar rename":

  test "mkRegexAllChar matches any single codepoint":
    let ctx = newContext()
    let r = mkRegexAllChar[Z3String]()
    check smtValid(matches(mkString("a"), r))
    check smtValid(matches(mkString("Z"), r))
    check smtValid(matches(mkString("!"), r))

  test "mkRegexAllChar rejects empty and multi-char strings":
    let ctx = newContext()
    let r = mkRegexAllChar[Z3String]()
    check smtValid(not matches(mkString(""), r))
    check smtValid(not matches(mkString("ab"), r))
    check smtValid(not matches(mkString("abc"), r))

  test "mkRegexAll is no longer exported (compile-time guard)":
    when compiles(mkRegexAll[Z3String]()):
      doAssert false, "mkRegexAll must not exist after N10.11 rename"
    check true  # old name is gone

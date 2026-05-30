## `z3/regex` tests — SMT-LIB regular expressions over the String sort.
##
## Regex sorts are parameterised over their basis sequence sort: a
## regex over strings is `(RegEx String)`. The wrapper expresses this
## as `Z3Regex[Basis]`. For v0.3 step 4 the only constructible basis is
## `Z3String`; step 5 (sequences) generalises to `Z3Regex[Z3Seq[E]]`.

import std/[unittest]
import z3

suite "Z3Regex — tracer":
  test "singleton regex matches its own string":
    let ctx = newContext()
    let r = mkRegex(mkString("abc"))
    check smtValid(matches(mkString("abc"), r))
    check smtValid(not matches(mkString("ab"), r))

suite "Z3Regex — unary combinators":
  test "star accepts zero or more reps":
    let ctx = newContext()
    let r = mkRegex(mkString("ab")).star
    check smtValid(matches(mkString(""), r))
    check smtValid(matches(mkString("ab"), r))
    check smtValid(matches(mkString("abab"), r))
    check smtValid(not matches(mkString("a"), r))

  test "plus requires at least one rep":
    let ctx = newContext()
    let r = mkRegex(mkString("ab")).plus
    check smtValid(not matches(mkString(""), r))
    check smtValid(matches(mkString("ab"), r))
    check smtValid(matches(mkString("abab"), r))

  test "option accepts empty + the regex":
    let ctx = newContext()
    let r = mkRegex(mkString("ab")).option
    check smtValid(matches(mkString(""), r))
    check smtValid(matches(mkString("ab"), r))
    check smtValid(not matches(mkString("abab"), r))

  test "complement rejects what the inner regex accepts":
    let ctx = newContext()
    let r = mkRegex(mkString("abc")).complement
    check smtValid(not matches(mkString("abc"), r))
    check smtValid(matches(mkString("xyz"), r))

suite "Z3Regex — n-ary combinators":
  test "concat builds a sequence":
    let ctx = newContext()
    let r = concat(mkRegex(mkString("a")), mkRegex(mkString("b")), mkRegex(mkString("c")))
    check smtValid(matches(mkString("abc"), r))
    check smtValid(not matches(mkString("ab"), r))

  test "union accepts any of the alternatives":
    let ctx = newContext()
    let r = union(mkRegex(mkString("foo")), mkRegex(mkString("bar")))
    check smtValid(matches(mkString("foo"), r))
    check smtValid(matches(mkString("bar"), r))
    check smtValid(not matches(mkString("baz"), r))

  test "intersect narrows":
    let ctx = newContext()
    # Strings starting with "ab" intersected with strings ending in "cd"
    let ab_star = concat(mkRegex(mkString("ab")), mkRegexAll[Z3String]().star)
    let star_cd = concat(mkRegexAll[Z3String]().star, mkRegex(mkString("cd")))
    let both = intersect(ab_star, star_cd)
    check smtValid(matches(mkString("abcd"), both))
    check smtValid(matches(mkString("abxcd"), both))
    check smtValid(not matches(mkString("abxy"), both))

suite "Z3Regex — ranges and counted repetition":
  test "range plus matches strings of lowercase letters":
    let ctx = newContext()
    let r = range("a", "z").plus
    check smtValid(matches(mkString("hello"), r))
    check smtValid(not matches(mkString("Hello"), r))   # capital rejected
    check smtValid(not matches(mkString(""), r))

  test "loop(r, lo, hi) bounds the rep count":
    let ctx = newContext()
    let r = mkRegex(mkString("a")).loop(2, 4)
    check smtValid(not matches(mkString("a"), r))
    check smtValid(matches(mkString("aa"), r))
    check smtValid(matches(mkString("aaaa"), r))
    check smtValid(not matches(mkString("aaaaa"), r))

  test "power(r, n) requires exactly n reps":
    let ctx = newContext()
    let r = mkRegex(mkString("a")).power(3)
    check smtValid(not matches(mkString("aa"), r))
    check smtValid(matches(mkString("aaa"), r))
    check smtValid(not matches(mkString("aaaa"), r))

suite "Z3Regex — universals":
  test "mkRegexEmpty accepts nothing":
    let ctx = newContext()
    let r = mkRegexEmpty[Z3String]()
    check smtValid(not matches(mkString(""), r))
    check smtValid(not matches(mkString("anything"), r))

  test "mkRegexFull accepts every string":
    let ctx = newContext()
    let r = mkRegexFull[Z3String]()
    check smtValid(matches(mkString(""), r))
    check smtValid(matches(mkString("any"), r))

  test "mkRegexAll accepts exactly single-codepoint strings":
    let ctx = newContext()
    let r = mkRegexAll[Z3String]()
    check smtValid(not matches(mkString(""), r))
    check smtValid(matches(mkString("a"), r))
    check smtValid(not matches(mkString("ab"), r))

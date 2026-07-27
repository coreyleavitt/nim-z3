## `z3/regex` index-helper tests — `matchStartsAt` / `containsRe` / the
## `re in s` sugar (RFC-regex-index.md §4.1 / §4.1a, slice 1).
##
## These are nim-z3's first *encoded* (non-1:1) helpers — see the
## `## Encoded (no native op):` marker in `regex.nim`. Tests here pin
## the exact soundness/completeness contract each encoding promises.

import std/[unittest, strutils]
import z3

suite "matchStartsAt — concrete positions":
  test "leftmost-vs-not: match at position 0 vs not at position 1":
    let ctx = newContext()
    let s = mkString("abcabc")
    let re = mkRegex(mkString("abc"))
    check smtValid(matchStartsAt(s, re, 0))
    check smtValid(not matchStartsAt(s, re, 1))
    check smtValid(matchStartsAt(s, re, 3))

  test "no-match case: pattern absent entirely":
    let ctx = newContext()
    let s = mkString("xyz")
    let re = mkRegex(mkString("abc"))
    check smtValid(not matchStartsAt(s, re, 0))
    check smtValid(not matchStartsAt(s, re, 1))
    check smtValid(not matchStartsAt(s, re, 2))

  test "nullable re: ε-match is identically true at EVERY position, in-range and out":
    let ctx = newContext()
    let s = mkString("abc")
    # `re` is nullable: matches(mkSeqEmpty[E](ctx), re) holds (mkString("") ∈ L(re)).
    let re = mkRegex(mkString(""))
    check smtValid(matches(mkSeqEmpty[Z3Char](ctx), re))
    # In-range positions:
    check smtValid(matchStartsAt(s, re, 0))
    check smtValid(matchStartsAt(s, re, 1))
    check smtValid(matchStartsAt(s, re, 3))
    # Out-of-range positions — still true (§4.1 ε-domain caveat).
    check smtValid(matchStartsAt(s, re, 4))
    check smtValid(matchStartsAt(s, re, 100))
    check smtValid(matchStartsAt(s, re, -1))

  test "nullable re via star: ε-match is identically true at every position":
    let ctx = newContext()
    let s = mkString("abc")
    let re = mkRegex(mkString("ab")).star
    check smtValid(matches(mkSeqEmpty[Z3Char](ctx), re))
    check smtValid(matchStartsAt(s, re, 0))
    check smtValid(matchStartsAt(s, re, 2))
    check smtValid(matchStartsAt(s, re, 10))

  test "out-of-range i (i > len(s)) with a non-nullable re is false":
    let ctx = newContext()
    let s = mkString("abc")
    let re = mkRegex(mkString("abc"))
    check smtValid(not matches(mkSeqEmpty[Z3Char](ctx), re))
    check smtValid(not matchStartsAt(s, re, 4))
    check smtValid(not matchStartsAt(s, re, 100))

  test "M5: i == len(s) exactly, non-nullable re is false (empty suffix can't match)":
    let ctx = newContext()
    let s = mkString("abc")  # len 3
    let re = mkRegex(mkString("abc"))
    check smtValid(not matchStartsAt(s, re, 3))

  test "M5: negative i with a non-nullable re is false":
    let ctx = newContext()
    let s = mkString("abc")
    let re = mkRegex(mkString("abc"))
    check smtValid(not matchStartsAt(s, re, -1))

suite "containsRe — sound-and-complete existence predicate":
  test "present: pattern occurs somewhere in s":
    let ctx = newContext()
    let s = mkString("xxabcxx")
    let re = mkRegex(mkString("abc"))
    check smtValid(containsRe(s, re))

  test "absent: pattern occurs nowhere in s":
    let ctx = newContext()
    let s = mkString("xxxxxxx")
    let re = mkRegex(mkString("abc"))
    check smtValid(not containsRe(s, re))

  test "substring-not-prefix: match not at position 0 differs from matchStartsAt(.,.,0)":
    let ctx = newContext()
    let s = mkString("xxabcxx")
    let re = mkRegex(mkString("abc"))
    check smtValid(containsRe(s, re))
    check smtValid(not matchStartsAt(s, re, 0))

  test "ε regex ⇒ containsRe trivially true":
    let ctx = newContext()
    let s = mkString("anything")
    let re = mkRegex(mkString(""))
    check smtValid(matches(mkSeqEmpty[Z3Char](ctx), re))
    check smtValid(containsRe(s, re))

suite "re in s / re notin s — sugar agrees with containsRe":
  test "in / notin resolve via the new contains(s, re) overload and agree with containsRe":
    let ctx = newContext()
    let s = mkString("xxabcxx")
    let present = mkRegex(mkString("abc"))
    let absent = mkRegex(mkString("zzz"))
    check smtValid(present in s)
    check smtValid(absent notin s)
    # Agreement with containsRe:
    check smtValid((present in s) == containsRe(s, present))
    check smtValid((absent in s) == containsRe(s, absent))

suite "matchStartsAt / containsRe — non-string basis (Z3Seq[Z3Int])":
  test "matchStartsAt over Z3Seq[Z3Int]":
    let ctx = newContext()
    let s = concat(mkSeqUnit(mkInt(1)), mkSeqUnit(mkInt(2)), mkSeqUnit(mkInt(3)))
    let re = mkRegex(concat(mkSeqUnit(mkInt(2)), mkSeqUnit(mkInt(3))))
    check smtValid(matchStartsAt(s, re, 1))
    check smtValid(not matchStartsAt(s, re, 0))

  test "containsRe over Z3Seq[Z3Int]":
    let ctx = newContext()
    let s = concat(mkSeqUnit(mkInt(1)), mkSeqUnit(mkInt(2)), mkSeqUnit(mkInt(3)))
    let present = mkRegex(concat(mkSeqUnit(mkInt(2)), mkSeqUnit(mkInt(3))))
    let absent = mkRegex(mkSeqUnit(mkInt(99)))
    check smtValid(containsRe(s, present))
    check smtValid(not containsRe(s, absent))

suite "containsRe — completeness over a symbolic s":
  test "free string var, no length bound: containsRe is satisfiable and the model actually contains the pattern":
    let ctx = newContext()
    let s = mkStringVar("s")
    let re = mkRegex(mkString("needle"))
    let solver = newSolver()
    # No bound on s's length anywhere — the property a bounded
    # `indexOfRe` unroll cannot offer.
    solver.add containsRe(s, re)
    check solver.check() == zsSat
    let m = solver.model()
    check m.evalStr(m[s]).contains("needle")

suite "substr — seq.extract boundary formula (load-bearing for §4.1/§4.2)":
  test "offset == len(s), positive length ⇒ empty sequence":
    let ctx = newContext()
    let s = mkString("abc")
    check smtValid(substr(s, s.len, mkInt(5)) == mkSeqEmpty[Z3Char](ctx))

  test "negative length, in-range offset ⇒ empty sequence":
    let ctx = newContext()
    let s = mkString("abc")
    check smtValid(substr(s, mkInt(1), mkInt(-1)) == mkSeqEmpty[Z3Char](ctx))

# ============================================================================
# indexOfRe / boundHolds — bounded-unroll `find` convenience (§4.2, slice 2)
# ============================================================================

suite "indexOfRe — bounded-unroll find convenience":
  test "leftmost among multiple matches: returns the first, not a later one":
    let ctx = newContext()
    let s = mkString("xxabcxxabcxx")
    let re = mkRegex(mkString("abc"))
    check smtValid(indexOfRe(s, re, matchBound(20)) == mkInt(2))

  test "start offset skips an earlier match, returns the next":
    let ctx = newContext()
    let s = mkString("xxabcxxabcxx")
    let re = mkRegex(mkString("abc"))
    check smtValid(indexOfRe(s, re, 3, matchBound(20)) == mkInt(7))

  test "-1 when the only match is beyond bound (documented incompleteness)":
    let ctx = newContext()
    let s = mkString("xxxxxxxxxxabc")  # match at index 10, len 13
    let re = mkRegex(mkString("abc"))
    check smtValid(indexOfRe(s, re, matchBound(5)) == mkInt(-1))

  test "symbolic start: free mkIntVar constrained, checkSat, read index back from model":
    let ctx = newContext()
    let s = mkString("xxabcxxabcxx")
    let re = mkRegex(mkString("abc"))
    let startVar = mkIntVar("start")
    let solver = newSolver()
    solver.add startVar == mkInt(3)
    let idx = indexOfRe(s, re, startVar, matchBound(20))
    check solver.check() == zsSat
    let m = solver.model()
    check m.evalInt(idx) == 7

  test "epsilon (nullable re) yields max(0, start) when reachable":
    let ctx = newContext()
    let s = mkString("abcdef")
    let re = mkRegex(mkString(""))
    check smtValid(matches(mkSeqEmpty[Z3Char](ctx), re))
    check smtValid(indexOfRe(s, re, matchBound(20)) == mkInt(0))
    check smtValid(indexOfRe(s, re, 3, matchBound(20)) == mkInt(3))

  test "epsilon with start > bound yields -1":
    let ctx = newContext()
    let s = mkString("abcdef")
    let re = mkRegex(mkString(""))
    check smtValid(indexOfRe(s, re, 10, matchBound(5)) == mkInt(-1))

  test "soundness under asserted len(s) <= bound: containsRe true implies indexOfRe finds a real position":
    let ctx = newContext()
    let s = mkStringVar("s")
    let re = mkRegex(mkString("abc"))
    let solver = newSolver()
    solver.add s.boundHolds(matchBound(10))
    solver.add containsRe(s, re)
    check solver.check() == zsSat
    let m = solver.model()
    let idx = indexOfRe(s, re, matchBound(10))
    check m.evalInt(idx) >= 0

  test "MatchBound misuse: transposed (bound, start) and negative literal both fail to compile":
    let ctx = newContext()
    let s = mkString("abc")
    let re = mkRegex(mkString("abc"))
    let myBound = matchBound(5)
    let myStart = 0
    check(not compiles(indexOfRe(s, re, myBound, myStart)))
    # `compiles(matchBound(-1))` alone is unreliable here: Nim's range check
    # on a literal-to-`Natural` conversion is enforced during constant
    # folding, a pass `compiles()` does not sandbox for a plain call
    # expression — verified `matchBound(-1)` used directly (outside
    # `compiles()`) is a hard compile error, but `compiles(matchBound(-1))`
    # itself spuriously reports `true`. Forcing the literal through a
    # `const` binding routes the conversion through compile-time evaluation,
    # which `compiles()` *does* sandbox, giving a reliable reject test.
    check(not compiles((const negBound = matchBound(-1))))
    check(compiles((const okBound = matchBound(5))))

  test "REGRESSION: nullable re with start > len(s) never returns a spurious positive index":
    let ctx = newContext()
    let s = mkString("abc")  # len 3
    let re = mkRegex(mkString(""))  # nullable
    check smtValid(matches(mkSeqEmpty[Z3Char](ctx), re))
    check smtValid(indexOfRe(s, re, 5, matchBound(20)) == mkInt(-1))

  test "symbolic string AND symbolic start: read the returned index back from the model":
    let ctx = newContext()
    let s = mkStringVar("s")
    let re = mkRegex(mkString("abc"))
    let startVar = mkIntVar("start")
    let solver = newSolver()
    solver.add s == mkString("xxabcxx")
    solver.add startVar == mkInt(0)
    let idx = indexOfRe(s, re, startVar, matchBound(10))
    check solver.check() == zsSat
    let m = solver.model()
    check m.evalInt(idx) == 2

  test "large bound (200) stays linear and returns promptly":
    let ctx = newContext()
    let s = mkString("a".repeat(50) & "abc" & "a".repeat(50))
    let re = mkRegex(mkString("abc"))
    check smtValid(indexOfRe(s, re, matchBound(200)) == mkInt(50))

  test "matchBound(0): chain degenerates to ite(g(0), 0, -1)":
    let ctx = newContext()
    let sMatch = mkString("abc")
    let sNoMatch = mkString("xabc")
    let re = mkRegex(mkString("abc"))
    check smtValid(indexOfRe(sMatch, re, matchBound(0)) == mkInt(0))
    check smtValid(indexOfRe(sNoMatch, re, matchBound(0)) == mkInt(-1))

  test "boundHolds standalone: len(s) == N exactly holds; len(s) == N+1 negates it":
    let ctx = newContext()
    let s = mkString("abcde")   # len 5
    check smtValid(s.boundHolds(matchBound(5)))
    let s2 = mkString("abcdef") # len 6
    check smtValid(not s2.boundHolds(matchBound(5)))

  test "hoisting cross-consistency: indexOfRe's leftmost hit agrees with matchStartsAt":
    let ctx = newContext()
    let s = mkString("xxabcxx")
    let re = mkRegex(mkString("abc"))
    let bound = matchBound(10)
    check smtValid(indexOfRe(s, re, bound) == mkInt(2))
    check smtValid(matchStartsAt(s, re, 2))
    for j in 0 ..< 2:
      check smtValid(not matchStartsAt(s, re, j))

  test "cross-primitive consistency: indexOfRe >= 0 implies containsRe; not containsRe implies indexOfRe == -1":
    let ctx = newContext()
    let re = mkRegex(mkString("abc"))
    let bound = matchBound(10)

    let sPresent = mkString("xxabcxx")  # len 7 <= bound
    check smtValid(not (indexOfRe(sPresent, re, bound) >= 0) or containsRe(sPresent, re))

    let sAbsent = mkString("xxxxxxx")   # len 7 <= bound
    check smtValid(not containsRe(sAbsent, re))
    check smtValid(indexOfRe(sAbsent, re, bound) == mkInt(-1))

  test "M5: start == len(s) exactly with a nullable re finds the zero-width match at len(s) (the <= vs < case)":
    let ctx = newContext()
    let s = mkString("abc")           # len 3
    let re = mkRegex(mkString(""))    # nullable
    check smtValid(matches(mkSeqEmpty[Z3Char](ctx), re))
    check smtValid(indexOfRe(s, re, 3, matchBound(10)) == mkInt(3))

# ============================================================================
# indexOfReChecked — bundled result ties completeIf to the same s (H1)
# ============================================================================

suite "indexOfReChecked — bundled index + completeIf obligation from the same s":
  test "returns the same leftmost index as indexOfRe":
    let ctx = newContext()
    let s = mkString("xxabcxxabcxx")
    let re = mkRegex(mkString("abc"))
    let r = indexOfReChecked(s, re, matchBound(20))
    check smtValid(r.index == mkInt(2))
    check smtValid(r.index == indexOfRe(s, re, matchBound(20)))

  test "start-offset overload agrees with indexOfRe's start-offset overload":
    let ctx = newContext()
    let s = mkString("xxabcxxabcxx")
    let re = mkRegex(mkString("abc"))
    let r = indexOfReChecked(s, re, 3, matchBound(20))
    check smtValid(r.index == mkInt(7))

  test "discharging completeIf makes 'index == -1' provably mean no match anywhere":
    let ctx = newContext()
    let s = mkStringVar("s")
    let re = mkRegex(mkString("abc"))
    let solver = newSolver()
    let r = indexOfReChecked(s, re, matchBound(10))
    # Constrain s to be within the bound so completeIf is dischargeable,
    # and assert the -1 answer plus containsRe: if completeIf really does
    # make -1 sound-and-complete, this combination must be UNSAT.
    solver.add r.completeIf
    solver.add r.index == mkInt(-1)
    solver.add containsRe(s, re)
    check solver.check() == zsUnsat

  test "without discharging completeIf, -1 does NOT preclude containsRe (the trap indexOfReChecked lets you avoid)":
    let ctx = newContext()
    let s = mkStringVar("s")
    let re = mkRegex(mkString("abc"))
    let solver = newSolver()
    let r = indexOfReChecked(s, re, matchBound(2))  # too small to see "needle...abc"
    # completeIf intentionally NOT asserted here.
    solver.add r.index == mkInt(-1)
    solver.add containsRe(s, re)
    check solver.check() == zsSat

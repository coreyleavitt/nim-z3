## String + regex example — finds a five-character "username"
## satisfying multiple regex-shaped constraints simultaneously.
##
## Constraints (the typical "valid identifier" shape):
##
##   1. Length is exactly 5.
##   2. Every character is in `[a-zA-Z0-9]` (alphanumeric only).
##   3. The first character is a letter `[a-zA-Z]`.
##   4. The string contains at least one digit `[0-9]`.
##
## Z3's string + regex theories together let us express each
## constraint as a regex membership claim and conjoin them. The
## solver returns a concrete string satisfying every clause.
##
## Demonstrated:
##
## - `Z3String` typed string family + `mkStringVar` / `mkString`
## - `Z3Regex[Z3String]` parameterised over the string basis
## - Building character classes via `union` over single-codepoint
##   `mkRegex(mkString("c"))` regexes
## - The `range(lo, hi)` regex constructor for character ranges
## - `s.len`, `s.matches(r)`, regex `star`, regex `concat`
## - Extracting a concrete model string via `evalStr`
##
## Run with:
##
## ```
## nim c -r examples/string_constraints.nim
## ```

import std/[strformat, strutils, sequtils]
import z3

proc main() =
  let ctx = newContext()
  echo "libz3 ", z3FullVersion()

  # Character classes via `range(lo, hi)` — a regex matching any
  # single-character string in the inclusive codepoint range.
  let lower = range("a", "z")              # [a-z]
  let upper = range("A", "Z")              # [A-Z]
  let digit = range("0", "9")              # [0-9]
  let letter = union(lower, upper)         # [a-zA-Z]
  let alnum = union(letter, digit)         # [a-zA-Z0-9]

  # Build the symbolic string variable and the regexes that
  # constrain it.
  let username = mkStringVar("username")

  # 1. Length 5
  let len5 = (username.len == mkInt(5))

  # 2. Every character is alphanumeric: matches (alnum)*
  let allAlnum = username.matches(star(alnum))

  # 3. First character is a letter: matches (letter)(alnum)*
  let firstLetter = username.matches(concat(letter, star(alnum)))

  # 4. Contains a digit: matches .*[0-9].*
  # Anything character is `range("\x00", "\xFF")` — but the
  # SMT-LIB `re.all` regex matches any string, which is more
  # idiomatic for "contains" patterns.
  let any = mkRegexFull[Z3String]()
  let containsDigit = username.matches(concat(any, concat(digit, any)))

  # Solve.
  let s = newSolver()
  s.add len5
  s.add allAlnum
  s.add firstLetter
  s.add containsDigit
  doAssert s.check() == zsSat,
    "the constraint set should have a satisfying username"

  let value = s.model().evalStr(username)
  echo &"username = \"{value}\""

  # Verify the invariants the example promises (cheap re-check via
  # plain Nim — pulls double-duty as a smoke test of `evalStr`).
  doAssert value.len == 5, "length mismatch"
  doAssert value.allCharsInSet({'a'..'z', 'A'..'Z', '0'..'9'}),
    "non-alphanumeric character present"
  doAssert value[0].isAlphaAscii, "first character is not a letter"
  doAssert value.anyIt(it.isDigit), "no digit found"

when isMainModule:
  main()

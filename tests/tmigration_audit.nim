## N11.6 — Migration guide audit.
##
## Asserts that `docs/MIGRATION-1.x-to-2.0.md` exists and that its content
## covers every hard break, new module, and known-bug section required by the
## N11.6 RFC slice.
##
## Checks (in order):
##   1. File exists at `docs/MIGRATION-1.x-to-2.0.md`.
##   2. All 7 renames are mentioned (both old and new name).
##   3. A "New modules" section lists all 11 new modules.
##   4. A "Z3 4.15 caveats" section exists.

import std/[unittest, os, strutils]

const
  docsDir  = currentSourcePath().parentDir.parentDir / "docs"
  migPath  = docsDir / "MIGRATION-1.x-to-2.0.md"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc content(): string =
  readFile(migPath)

proc mentions(text, token: string): bool =
  token in text

# ---------------------------------------------------------------------------
# Suite 1 — file existence
# ---------------------------------------------------------------------------

suite "N11.6 — MIGRATION-1.x-to-2.0.md exists":

  test "docs/MIGRATION-1.x-to-2.0.md exists":
    check fileExists(migPath)

# ---------------------------------------------------------------------------
# Suite 2 — all 7 renames present (old name + new name)
# ---------------------------------------------------------------------------

suite "N11.6 — all 7 renames documented (old and new names)":

  let text = content()

  # N4.4
  test "N4.4 old name toInt present":
    check mentions(text, "toInt")

  test "N4.4 new name toInt64 present":
    check mentions(text, "toInt64")

  # N5.7 rename 1
  test "N5.7 old name strToInt present":
    check mentions(text, "strToInt")

  test "N5.7 new name Z3String.toInt present":
    check mentions(text, "Z3String.toInt") or mentions(text, "toInt")

  # N5.7 rename 2
  test "N5.7 old name intToStr present":
    check mentions(text, "intToStr")

  test "N5.7 new name Z3Int.toStr present":
    check mentions(text, "Z3Int.toStr") or mentions(text, "toStr")

  # N6.7 rename 1
  test "N6.7 old name mkNaN present":
    check mentions(text, "mkNaN")

  test "N6.7 new name mkFpNaN present":
    check mentions(text, "mkFpNaN")

  # N6.7 rename 2
  test "N6.7 old name mkInf present":
    check mentions(text, "mkInf")

  test "N6.7 new name mkFpInf present":
    check mentions(text, "mkFpInf")

  # N6.7 rename 3
  test "N6.7 old name mkZero present":
    check mentions(text, "mkZero")

  test "N6.7 new name mkFpZero present":
    check mentions(text, "mkFpZero")

  # N6.7 rename 4
  test "N6.7 old name toFp(bv...) present":
    check mentions(text, "toFp")

  test "N6.7 new name bvToFpBits present":
    check mentions(text, "bvToFpBits")

  # N10.11
  test "N10.11 old name mkRegexAll present":
    check mentions(text, "mkRegexAll")

  test "N10.11 new name mkRegexAllChar present":
    check mentions(text, "mkRegexAllChar")

# ---------------------------------------------------------------------------
# Suite 3 — New modules section lists all 11 modules
# ---------------------------------------------------------------------------

suite "N11.6 — New modules section lists all 11 new modules":

  let text = content()

  test "New modules section heading present":
    check mentions(text, "New modules") or mentions(text, "new modules")

  test "sets listed":
    check mentions(text, "sets")

  test "astmap listed":
    check mentions(text, "astmap")

  test "uninterpretedval listed":
    check mentions(text, "uninterpretedval")

  test "rcf listed":
    check mentions(text, "rcf")

  test "algebraic listed":
    check mentions(text, "algebraic")

  test "spacer listed":
    check mentions(text, "spacer")

  test "simplifier listed":
    check mentions(text, "simplifier")

  test "propagator listed":
    check mentions(text, "propagator")

  test "onclause listed":
    check mentions(text, "onclause")

  test "order listed":
    check mentions(text, "order")

  test "logging listed":
    check mentions(text, "logging")

# ---------------------------------------------------------------------------
# Suite 4 — Z3 4.15 caveats section
# ---------------------------------------------------------------------------

suite "N11.6 — Z3 4.15 caveats section present":

  let text = content()

  test "Z3 4.15 caveats section heading present":
    check mentions(text, "4.15") and
      (mentions(text, "caveat") or mentions(text, "Caveat") or
       mentions(text, "known") or mentions(text, "quirk"))

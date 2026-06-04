## N11.3 — Per-new-module test file coverage audit.
##
## Confirms that each new module introduced in the N1.x RFC slices has a
## dedicated test file in `tests/` with at least 5 individual `test` blocks.
##
## Modules under audit:
##   sets.nim          → tsets.nim
##   astmap.nim        → tastmap.nim
##   uninterpretedval.nim → tuninterpretedval.nim
##   rcf.nim           → trcf.nim
##   spacer.nim        → tspacer.nim
##   algebraic.nim     → talgebraic.nim

import std/[unittest, strutils, os, sequtils]

const testsDir = currentSourcePath().parentDir

# ---------------------------------------------------------------------------
# Helper: count `test "` blocks in a file
# ---------------------------------------------------------------------------

proc countTestBlocks(path: string): int =
  ## Count lines that start a unittest `test "…"` block (any leading whitespace).
  let lines = readFile(path).splitLines()
  result = lines.filterIt(it.strip().startsWith("test \"")).len

# ---------------------------------------------------------------------------
# The six modules required by the RFC
# ---------------------------------------------------------------------------

const auditModules = [
  ("sets",           "tsets"),
  ("astmap",         "tastmap"),
  ("uninterpretedval", "tuninterpretedval"),
  ("rcf",            "trcf"),
  ("spacer",         "tspacer"),
  ("algebraic",      "talgebraic"),
]

const minTests = 5

suite "N11.3 — each RFC new-module has a dedicated test file":

  for (srcMod, testStem) in auditModules:
    let testFile = testsDir / testStem & ".nim"

    test testStem & ".nim exists in tests/":
      check fileExists(testFile)

suite "N11.3 — each RFC test file has >= 5 test blocks":

  for (srcMod, testStem) in auditModules:
    let testFile = testsDir / testStem & ".nim"

    test testStem & ".nim has >= " & $minTests & " test blocks":
      let count = countTestBlocks(testFile)
      checkpoint testStem & ".nim: " & $count & " test blocks found"
      check count >= minTests

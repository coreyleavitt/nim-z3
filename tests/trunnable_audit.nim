## N10.10 — `runnableExamples` adoption audit.
##
## Verifies that each target module from this RFC carries at least the
## minimum number of `runnableExamples` blocks specified below.  The test
## also imports each module (or the umbrella `z3`) to confirm the modules
## compile cleanly with the examples present.
##
## Target modules and minimum block counts:
##
##   sets.nim          — 3 (mkEmptySet, add/member, union)
##   astmap.nim        — 2 (newAstMap, insert/find)
##   uninterpretedval  — 2 (declareUninterpretedSort, mkUninterpretedVar)
##   rcf.nim           — 3 (mkRational, mkPi, arithmetic/ordering)
##   algebraic.nim     — 2 (algebraicRoot, algebraicRoots)
##   spacer.nim        — 1 (queryFromLevel — gated on !z3WithoutSpacer)
##   order.nim         — 2 (mkLinearOrder, mkTransitiveClosure — gated)
##   simplifier.nim    — 2 (mkSimplifier, addSimplifier — gated)
##
## Total minimum: 17 blocks across 8 modules.

import std/[unittest, strutils, os]
import z3

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

proc countRunnableExamples(path: string): int =
  ## Count the number of `runnableExamples` keyword occurrences in `path`.
  let src = readFile(path)
  result = 0
  var pos = 0
  let needle = "runnableExamples"
  while true:
    let idx = src.find(needle, pos)
    if idx < 0: break
    inc result
    pos = idx + needle.len

const srcDir = currentSourcePath().parentDir / ".." / "src" / "z3"

# ---------------------------------------------------------------------------
suite "N10.10 — runnableExamples counts":

  test "sets.nim has >= 3 runnableExamples blocks":
    let n = countRunnableExamples(srcDir / "sets.nim")
    checkpoint "sets.nim runnableExamples count: " & $n
    check n >= 3

  test "astmap.nim has >= 2 runnableExamples blocks":
    let n = countRunnableExamples(srcDir / "astmap.nim")
    checkpoint "astmap.nim runnableExamples count: " & $n
    check n >= 2

  test "uninterpretedval.nim has >= 2 runnableExamples blocks":
    let n = countRunnableExamples(srcDir / "uninterpretedval.nim")
    checkpoint "uninterpretedval.nim runnableExamples count: " & $n
    check n >= 2

  test "rcf.nim has >= 3 runnableExamples blocks":
    let n = countRunnableExamples(srcDir / "rcf.nim")
    checkpoint "rcf.nim runnableExamples count: " & $n
    check n >= 3

  test "algebraic.nim has >= 2 runnableExamples blocks":
    let n = countRunnableExamples(srcDir / "algebraic.nim")
    checkpoint "algebraic.nim runnableExamples count: " & $n
    check n >= 2

  test "spacer.nim has >= 1 runnableExamples block":
    let n = countRunnableExamples(srcDir / "spacer.nim")
    checkpoint "spacer.nim runnableExamples count: " & $n
    check n >= 1

  test "order.nim has >= 2 runnableExamples blocks":
    let n = countRunnableExamples(srcDir / "order.nim")
    checkpoint "order.nim runnableExamples count: " & $n
    check n >= 2

  test "simplifier.nim has >= 2 runnableExamples blocks":
    let n = countRunnableExamples(srcDir / "simplifier.nim")
    checkpoint "simplifier.nim runnableExamples count: " & $n
    check n >= 2

  test "total runnableExamples across all target modules >= 17":
    let modules = [
      "sets.nim", "astmap.nim", "uninterpretedval.nim",
      "rcf.nim", "algebraic.nim", "spacer.nim",
      "order.nim", "simplifier.nim"
    ]
    var total = 0
    for m in modules:
      total += countRunnableExamples(srcDir / m)
    checkpoint "total runnableExamples: " & $total
    check total >= 17

# ---------------------------------------------------------------------------
suite "N10.10 — compile smoke (import z3 covers all target modules)":

  test "z3 umbrella import compiles (includes sets, astmap, uninterpretedval, rcf, algebraic, spacer, order, simplifier)":
    ## The `import z3` at the top of this file already triggered compilation
    ## of all target modules. If we reached this point they compiled cleanly.
    ## Use a z3 symbol to suppress the UnusedImport warning.
    let ctx = newContext()
    check ctx != nil

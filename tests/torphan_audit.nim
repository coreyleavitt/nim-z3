## N11.1 — Orphan test binary / artifact cleanup audit.
##
## Verifies the hygiene of the `tests/` directory and `.gitignore`:
##
##   1. Count of tracked `t*.nim` test files is >= 80.
##   2. No debug/spike file patterns exist (`tdebug*.nim`, `tspike*.nim`,
##      `traw*.nim`, `tdbg*.nim`).
##   3. `.gitignore` contains the `nimcache_` pattern so local build
##      artifacts are excluded from version control.
##   4. Every `tests/t*.nim` file (except the deliberately excluded
##      `tminimal.nim`, which has its own `testMinimal` nimble task) is
##      listed in z3.nimble's `test` task.
##
## Category 4 is the primary gap caught by this RFC slice: Phase N8–N10
## added 72 test files that were committed but never wired into the `test`
## task, making them invisible to `nimble test` and easy to break silently.

import std/[unittest, strutils, os, sequtils, algorithm]

# ---------------------------------------------------------------------------
# Paths (resolved relative to this source file at compile time)
# ---------------------------------------------------------------------------

const testsDir  = currentSourcePath().parentDir
const repoRoot  = testsDir / ".."
const gitignore = repoRoot / ".gitignore"
const nimble    = repoRoot / "z3.nimble"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc collectTestStems(): seq[string] =
  ## Return sorted stems (no path, no .nim) of all `t*.nim` files in testsDir.
  result = @[]
  for kind, path in walkDir(testsDir):
    if kind != pcFile: continue
    let base = path.extractFilename
    if base.startsWith("t") and base.endsWith(".nim"):
      result.add(base[0 ..< base.len - 4])
  result.sort()

proc nimbleTestStems(): seq[string] =
  ## Return sorted unique stems extracted from z3.nimble's `test` task.
  ## Scans the entire file for all occurrences of `"tests/tXxx.nim"`.
  let src = readFile(nimble)
  var stems: seq[string] = @[]
  let marker = "\"tests/"
  var pos = 0
  while true:
    let idx = src.find(marker, pos)
    if idx < 0: break
    pos = idx + marker.len
    # find the closing quote
    let endQ = src.find('"', pos)
    if endQ < 0: break
    let fname = src[pos ..< endQ]
    if fname.endsWith(".nim") and fname.startsWith("t"):
      stems.add(fname[0 ..< fname.len - 4])
    pos = endQ + 1
  stems = stems.deduplicate()
  stems.sort()
  result = stems

# ---------------------------------------------------------------------------
suite "N11.1 — orphan audit":

  test "tests/ has >= 80 tracked t*.nim files":
    let stems = collectTestStems()
    checkpoint "actual count: " & $stems.len
    check stems.len >= 80

  test "no debug/spike .nim patterns in tests/":
    let bad = collectTestStems().filterIt(
      it.startsWith("tdebug") or
      it.startsWith("tspike") or
      it.startsWith("traw")   or
      it.startsWith("tdbg")
    )
    checkpoint "bad stems: " & $bad
    check bad.len == 0

  test ".gitignore contains nimcache_ pattern":
    let gi = readFile(gitignore)
    check "nimcache_" in gi

  test "every t*.nim (except tminimal) is in z3.nimble test task":
    ## tminimal is intentionally excluded: it requires compile-time flags
    ## and has its own `testMinimal` nimble task (documented in z3.nimble).
    let fileStems   = collectTestStems()
    let nimbleStems = nimbleTestStems()
    let excluded    = ["tminimal"]
    var missing: seq[string] = @[]
    for stem in fileStems:
      if stem in excluded: continue
      if stem notin nimbleStems:
        missing.add(stem)
    for m in missing:
      checkpoint "NOT in nimble test task: tests/" & m & ".nim"
    check missing.len == 0

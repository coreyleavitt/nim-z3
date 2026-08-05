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
##      `tminimal.nim`, which has its own `run-tests.sh minimal` subcommand)
##      is listed in run-tests.sh's `TESTS=( … )` array.
##
## Category 4 is the primary gap caught by this RFC slice: Phase N8–N10
## added 72 test files that were committed but never wired into the test
## list, making them invisible to the suite and easy to break silently.

import std/[unittest, strutils, os, sequtils, algorithm]

# ---------------------------------------------------------------------------
# Paths (resolved relative to this source file at compile time)
# ---------------------------------------------------------------------------

const testsDir  = currentSourcePath().parentDir
const repoRoot  = testsDir / ".."
const gitignore = repoRoot / ".gitignore"
const runner    = repoRoot / "run-tests.sh"

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

proc runnerTestStems(): seq[string] =
  ## Return sorted unique stems from run-tests.sh's `TESTS=( … )` array — the
  ## curated suite the `test` subcommand runs (milpa is the resolver; there is
  ## no nimble). Scans only the TESTS array, not EXAMPLES / VALGRIND / minimal.
  let src = readFile(runner)
  let startIdx = src.find("TESTS=(")
  doAssert startIdx >= 0, "run-tests.sh has no TESTS=( … ) array"
  let closeIdx = src.find("\n)", startIdx)
  let blk = src[startIdx ..< (if closeIdx < 0: src.len else: closeIdx)]
  var stems: seq[string] = @[]
  let marker = "tests/"
  var pos = 0
  while true:
    let idx = blk.find(marker, pos)
    if idx < 0: break
    pos = idx + marker.len
    var e = pos
    while e < blk.len and blk[e] notin {' ', '\n', '\t', ')', '"'}:
      inc e
    let fname = blk[pos ..< e]
    if fname.endsWith(".nim") and fname.startsWith("t"):
      stems.add(fname[0 ..< fname.len - 4])
    pos = e
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

  test "every t*.nim (except tminimal) is in run-tests.sh test list":
    ## tminimal is intentionally excluded: it requires compile-time flags
    ## and has its own `run-tests.sh minimal` subcommand.
    let fileStems   = collectTestStems()
    let runnerStems = runnerTestStems()
    let excluded    = ["tminimal"]
    var missing: seq[string] = @[]
    for stem in fileStems:
      if stem in excluded: continue
      if stem notin runnerStems:
        missing.add(stem)
    for m in missing:
      checkpoint "NOT in run-tests.sh test list: tests/" & m & ".nim"
    check missing.len == 0

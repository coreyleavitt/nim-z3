## N11.7 — Documentation sweep audit.
##
## Verifies that the four documentation deliverables required by the N11.7 RFC
## slice are present and contain the expected content:
##
##   1. docs/THREADING.md exists with content > 500 chars.
##   2. z3.nimble version is "2.2.0".
##   3. README.md mentions "2.0.0" and "MIGRATION".
##   4. CHANGELOG.md has a "2.0.0" section.

import std/[unittest, os, strutils]

const
  repoRoot    = currentSourcePath().parentDir.parentDir
  threadingMd = repoRoot / "docs" / "THREADING.md"
  nimblePath  = repoRoot / "z3.nimble"
  readmePath  = repoRoot / "README.md"
  changelogPath = repoRoot / "CHANGELOG.md"

# ---------------------------------------------------------------------------
# Suite 1 — docs/THREADING.md exists and is substantial
# ---------------------------------------------------------------------------

suite "N11.7 — docs/THREADING.md exists and is non-trivial":

  test "docs/THREADING.md exists":
    check fileExists(threadingMd)

  test "docs/THREADING.md has content > 500 chars":
    let content = readFile(threadingMd)
    check content.len > 500

# ---------------------------------------------------------------------------
# Suite 2 — z3.nimble version is 2.2.0
# ---------------------------------------------------------------------------

suite "N11.7 — z3.nimble version is 2.2.0":

  test "z3.nimble contains version = \"2.2.0\"":
    let content = readFile(nimblePath)
    check "\"2.2.0\"" in content

# ---------------------------------------------------------------------------
# Suite 3 — README.md mentions 2.0.0 and MIGRATION
# ---------------------------------------------------------------------------

suite "N11.7 — README.md mentions 2.0.0 and MIGRATION":

  let readmeContent = readFile(readmePath)

  test "README.md mentions 2.0.0":
    check "2.0.0" in readmeContent

  test "README.md mentions MIGRATION":
    check "MIGRATION" in readmeContent

# ---------------------------------------------------------------------------
# Suite 4 — CHANGELOG.md has a 2.0.0 section
# ---------------------------------------------------------------------------

suite "N11.7 — CHANGELOG.md has a 2.0.0 section":

  let changelogContent = readFile(changelogPath)

  test "CHANGELOG.md contains [2.0.0] section header":
    check "[2.0.0]" in changelogContent

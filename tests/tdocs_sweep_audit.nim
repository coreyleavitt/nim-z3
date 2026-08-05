## N11.7 — Documentation sweep audit.
##
## Verifies that the four documentation deliverables required by the N11.7 RFC
## slice are present and contain the expected content:
##
##   1. docs/THREADING.md exists with content > 500 chars.
##   2. README.md mentions "2.0.0" and "MIGRATION".
##   3. CHANGELOG.md has a "2.0.0" section.
##
## (The former "z3.nimble version" check was dropped: milpa is the dependency
## resolver, the nimble file is gone, and the package version is the git tag.)

import std/[unittest, os, strutils]

const
  repoRoot    = currentSourcePath().parentDir.parentDir
  threadingMd = repoRoot / "docs" / "THREADING.md"
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
# Suite 2 — README.md mentions 2.0.0 and MIGRATION
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

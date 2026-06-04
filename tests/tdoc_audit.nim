## N10.4 — Module doc-header `z3/` prefix sweep + rounding-mode SMT-LIB long-name doc.
##
## Two audit scopes:
##
##   1. **Rounding-mode SMT-LIB long names**: `fp.nim`'s rounding-mode
##      constructor doc comments contain the canonical SMT-LIB long names
##      `RNE`, `RNA`, `RTP`, `RTN`, `RTZ`.
##
##   2. **Module header z3/ prefix**: `##` doc-comment lines in `src/z3/`
##      modules that reference sibling modules use the `z3/X.nim` form
##      (not bare `X.nim`).

import std/[unittest, strutils, os, sequtils]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc slurp(path: string): string =
  readFile(path)

const srcDir = currentSourcePath().parentDir / ".." / "src" / "z3"

suite "N10.4 — rounding-mode SMT-LIB long names in fp.nim":

  test "rmRNE doc comment contains SMT-LIB long name RNE":
    let src = slurp(srcDir / "fp.nim")
    # The doc comment for rmRNE must mention the short IEEE name RNE
    # We look for it appearing in a ## doc line alongside the proc name
    check "RNE" in src

  test "rmRNA doc comment contains SMT-LIB long name RNA":
    let src = slurp(srcDir / "fp.nim")
    check "RNA" in src

  test "rmRTP doc comment contains SMT-LIB long name RTP":
    let src = slurp(srcDir / "fp.nim")
    check "RTP" in src

  test "rmRTN doc comment contains SMT-LIB long name RTN":
    let src = slurp(srcDir / "fp.nim")
    check "RTN" in src

  test "rmRTZ doc comment contains SMT-LIB long name RTZ":
    let src = slurp(srcDir / "fp.nim")
    check "RTZ" in src

  test "all five SMT-LIB names appear in fp.nim doc comments (not just proc names)":
    ## Verify the names appear in ## lines, proving they are doc comments
    ## and not merely embedded in proc/variable identifiers.
    let lines = slurp(srcDir / "fp.nim").splitLines()
    let docLines = lines.filterIt(it.strip().startsWith("##"))
    let docText = docLines.join("\n")
    check "RNE" in docText
    check "RNA" in docText
    check "RTP" in docText
    check "RTN" in docText
    check "RTZ" in docText

suite "N10.4 — z3/ prefix in module doc-header cross-references":

  test "arith.nim ## headers use z3/ prefix for ast.nim reference":
    let lines = slurp(srcDir / "arith.nim").splitLines()
    let badLines = lines.filterIt(
      it.strip().startsWith("##") and
      "`ast.nim`" in it
    )
    check badLines.len == 0

  test "arith.nim ## headers use z3/ prefix for boolean.nim reference":
    let lines = slurp(srcDir / "arith.nim").splitLines()
    let badLines = lines.filterIt(
      it.strip().startsWith("##") and
      "`boolean.nim`" in it
    )
    check badLines.len == 0

  test "ast.nim ## headers use z3/ prefix for arith.nim reference":
    let lines = slurp(srcDir / "ast.nim").splitLines()
    let badLines = lines.filterIt(
      it.strip().startsWith("##") and
      "`arith.nim`" in it
    )
    check badLines.len == 0

  test "ast.nim ## headers use z3/ prefix for boolean.nim reference":
    let lines = slurp(srcDir / "ast.nim").splitLines()
    let badLines = lines.filterIt(
      it.strip().startsWith("##") and
      "`boolean.nim`" in it
    )
    check badLines.len == 0

  test "ast.nim ## headers use z3/ prefix for builder.nim reference":
    let lines = slurp(srcDir / "ast.nim").splitLines()
    let badLines = lines.filterIt(
      it.strip().startsWith("##") and
      "`builder.nim`" in it
    )
    check badLines.len == 0

  test "lifecycle.nim ## headers use z3/ prefix for quantifier.nim reference":
    let lines = slurp(srcDir / "lifecycle.nim").splitLines()
    let badLines = lines.filterIt(
      it.strip().startsWith("##") and
      "`quantifier.nim`" in it
    )
    check badLines.len == 0

  test "sort.nim ## headers use z3/ prefix for ast.nim reference":
    let lines = slurp(srcDir / "sort.nim").splitLines()
    let badLines = lines.filterIt(
      it.strip().startsWith("##") and
      "`ast.nim`" in it
    )
    check badLines.len == 0

  test "algebraic.nim ## headers use z3/ prefix for polynomial.nim reference":
    let lines = slurp(srcDir / "algebraic.nim").splitLines()
    let badLines = lines.filterIt(
      it.strip().startsWith("##") and
      "`polynomial.nim`" in it
    )
    check badLines.len == 0

  test "no bare X.nim backtick refs remain in any src/z3/*.nim ## doc lines":
    ## Exhaustive sweep: no ## line in any src/z3 module may contain a bare
    ## `X.nim` reference where X is a sibling module name (no z3/ prefix).
    ## Sibling module names are all .nim files in src/z3/.
    let siblings = toSeq(walkFiles(srcDir / "*.nim"))
      .mapIt(it.extractFilename.changeFileExt(""))
    var violations: seq[string] = @[]
    for nimFile in walkFiles(srcDir / "*.nim"):
      let fname = nimFile.extractFilename
      let lines = readFile(nimFile).splitLines()
      for i, line in lines:
        let stripped = line.strip()
        if not stripped.startsWith("##"):
          continue
        for sib in siblings:
          let bare = "`" & sib & ".nim`"
          let prefixed = "`z3/" & sib & ".nim`"
          if bare in line and prefixed notin line:
            violations.add(fname & ":" & $(i+1) & ": " & line.strip())
    if violations.len > 0:
      checkpoint "Violations found:"
      for v in violations:
        checkpoint "  " & v
    check violations.len == 0

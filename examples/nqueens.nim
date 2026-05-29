## N-queens via SMT — place N queens on an N×N board with no two
## attacking. Demonstrates phantom-typed Int variables, `mkDistinct`,
## and the usual "constraint, propagate, witness" flow.
##
## The encoding: one `cols[i]: Z3Int` per row, with `cols[i] = j`
## meaning the queen in row `i` sits in column `j`. Constraints:
##
## - each `cols[i] ∈ [0, N-1]`
## - all `cols[i]` distinct (no two queens share a column)
## - all `cols[i] + i` distinct (no two share an anti-diagonal)
## - all `cols[i] - i` distinct (no two share a diagonal)
##
## Default N = 8. Override on the command line: `nim c -r -d:nQueens=12 …`.
## (Z3 solves to about N=20 in a couple seconds; beyond that wants
## a real combinatorial solver.)

import std/[strformat]
import z3

const nQueens {.intdefine.} = 8

proc main() =
  let ctx = newContext()
  let n = nQueens

  # One queen per row; `cols[i]` is the column of the queen in row i.
  var cols = newSeq[Z3Int](n)
  for i in 0 ..< n:
    cols[i] = mkIntVar(&"c{i}")

  let s = newSolver()

  # Each queen sits in [0, N-1].
  for c in cols:
    s.add c >= 0
    s.add c < n

  # All distinct columns.
  s.add mkDistinct(cols)

  # All distinct anti-diagonals (cols[i] + i).
  var anti = newSeq[Z3Int](n)
  for i in 0 ..< n:
    anti[i] = cols[i] + mkInt(i)
  s.add mkDistinct(anti)

  # All distinct diagonals (cols[i] - i).
  var diag = newSeq[Z3Int](n)
  for i in 0 ..< n:
    diag[i] = cols[i] - mkInt(i)
  s.add mkDistinct(diag)

  case s.check()
  of zsSat:
    let m = s.model()
    echo &"Solution for {n}-queens:"
    for i in 0 ..< n:
      let c = m.evalInt(cols[i])
      var row = ""
      for j in 0 ..< n:
        row.add(if j == c: "Q " else: ". ")
      echo "  ", row

    # Verify by independently checking the placement.
    var seen = newSeq[bool](n)
    for i in 0 ..< n:
      let c = m.evalInt(cols[i])
      doAssert 0 <= c and c < n
      doAssert not seen[c], "duplicate column"
      seen[c] = true
    # Diagonal check.
    for i in 0 ..< n:
      for j in i+1 ..< n:
        let ci = m.evalInt(cols[i])
        let cj = m.evalInt(cols[j])
        doAssert ci - cj != i - j, "shared diagonal"
        doAssert ci - cj != j - i, "shared anti-diagonal"
  of zsUnsat:
    quit &"unexpected: {n}-queens should always have a solution for n >= 4"
  of zsUnknown:
    quit &"z3 returned unknown: {s.reasonUnknown()}"

when isMainModule:
  main()

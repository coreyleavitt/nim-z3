## `z3/stats` + Z3Solver.getStatistics / getConsequences (v0.4 step 8).

import std/[unittest]
import z3

template withSolvedStats(body: untyped) =
  let ctx {.inject.} = newContext()
  let s {.inject.} = newSolver()
  let x {.inject.} = mkIntVar("x")
  s.add x > mkInt(0)
  s.add x < mkInt(100)
  check s.check() == zsSat
  let stats {.inject.} = s.getStatistics()
  body

suite "Z3Stats — solver getStatistics tracer":
  test "solving a trivial problem produces non-empty statistics":
    withSolvedStats:
      check stats.len > 0

suite "Z3Stats — key + value surface":
  test "keys() returns a string sequence covering every entry":
    withSolvedStats:
      let ks = stats.keys()
      check ks.len == stats.len
      for k in ks:
        check k.len > 0

  test "[key] lookup returns a finite float for present keys":
    withSolvedStats:
      let ks = stats.keys()
      check ks.len > 0
      let firstKey = ks[0]
      check stats.contains(firstKey)
      let v = stats[firstKey]
      check not (v != v)  # not NaN

  test "[key] on a missing key raises KeyError":
    withSolvedStats:
      expect KeyError:
        discard stats["this-key-does-not-exist"]

  test "pairs iterator yields every entry":
    withSolvedStats:
      var count = 0
      for k, v in stats.pairs:
        check k.len > 0
        inc count
      check count == stats.len

  test "isInt discriminates int vs double entries":
    withSolvedStats:
      # Z3 stats typically include both kinds; at least one entry
      # should be uint-typed (counter-like).
      var seenInt = false
      for k, _ in stats.pairs:
        if stats.isInt(k):
          seenInt = true
          # getInt round-trips for uint-typed entries.
          let asInt = stats.getInt(k)
          check asInt >= 0
          break
      check seenInt

  test "dollar-stats renders a non-empty multiline string":
    withSolvedStats:
      let rendered = $stats
      check rendered.len > 0

suite "Z3Fixedpoint.getStatistics — parity with solver":
  test "fixedpoint stats are accessible after a query":
    let ctx = newContext()
    let fp = newFixedpoint()
    let isTrue = mkFuncDecl[(Z3Int,), Z3Bool]("isTrue")
    fp.registerRelation(isTrue)
    fp.addRule(isTrue(mkInt(1)))
    discard fp.query(isTrue(mkInt(1)))
    let stats = fp.getStatistics()
    # Fixedpoint stats may be empty depending on engine; just verify
    # the call doesn't fail and len is non-negative.
    check stats.len >= 0

suite "Z3Solver.getConsequences — tracer":
  test "asserted variable is implied":
    let ctx = newContext()
    let s = newSolver()
    let p = mkBoolVar("p")
    s.add p
    let (status, conseq) = s.getConsequences(@[], @[p])
    check status == zsSat
    # The consequences include an implication where p is implied.
    check conseq.len > 0
    # Each entry is a Z3Bool of the form (=> (and ...) lit).
    for c in conseq:
      check ($c).len > 0

  test "unasserted variable is not implied":
    let ctx = newContext()
    let s = newSolver()
    let p = mkBoolVar("p")
    let q = mkBoolVar("q")
    s.add p
    # Ask for consequences over q, which the solver knows nothing about.
    let (status, conseq) = s.getConsequences(@[], @[q])
    check status == zsSat
    # No literal over q is implied by p alone.
    check conseq.len == 0

  test "non-empty assumptions drive conditional consequences":
    # v0.5.0 medium-audit C4: the assumptions-vec build branch
    # (solver.nim:219-220) had no test prior to this. Assert `p => q`,
    # then under assumption `p` we expect `q` to come back as a
    # consequence.
    let ctx = newContext()
    let s = newSolver()
    let p = mkBoolVar("p")
    let q = mkBoolVar("q")
    s.add (not p) or q          # p => q
    let (status, conseq) = s.getConsequences(@[p], @[q])
    check status == zsSat
    # At least one consequence over q must come back.
    check conseq.len >= 1

suite "Z3Stats — getFloat + getInt error path (medium C1/C2)":
  test "getFloat returns the float value for any entry":
    withSolvedStats:
      let ks = stats.keys()
      check ks.len > 0
      # Pick the first non-int entry if one exists; else the first.
      var chosen = ks[0]
      for k in ks:
        if not stats.isInt(k):
          chosen = k
          break
      let viaIndex = stats[chosen]
      let viaFloat = stats.getFloat(chosen)
      check viaIndex == viaFloat

  test "getInt on a double-typed entry raises Z3InvalidUsageError":
    withSolvedStats:
      var doubleKey = ""
      for k, _ in stats.pairs:
        if not stats.isInt(k):
          doubleKey = k
          break
      # Z3 stats for a non-trivial solve include both int + double
      # entries; if Z3 ever changes that we want to know.
      check doubleKey.len > 0
      expect Z3InvalidUsageError:
        discard stats.getInt(doubleKey)

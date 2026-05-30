## `z3/fixedpoint` tests — Horn-clause / CHC solver.

import std/[unittest, strutils]
import z3

suite "Z3Fixedpoint — tracer":
  test "newFixedpoint + simple relation: asserted fact is reachable":
    let ctx = newContext()
    let fp = newFixedpoint()
    let isTrue = mkFuncDecl[(Z3Int,), Z3Bool]("isTrue")
    fp.registerRelation(isTrue)
    fp.addRule(isTrue(mkInt(1)))
    check fp.query(isTrue(mkInt(1))) == zsSat

suite "Z3Fixedpoint — basic CHC":
  test "unreachable query returns zsUnsat":
    let ctx = newContext()
    let fp = newFixedpoint()
    let isTrue = mkFuncDecl[(Z3Int,), Z3Bool]("isTrue")
    fp.registerRelation(isTrue)
    fp.addRule(isTrue(mkInt(1)))
    # Only isTrue(1) was asserted; isTrue(99) is unreachable.
    check fp.query(isTrue(mkInt(99))) == zsUnsat

  test "graph reachability — transitive path via Horn rules":
    let ctx = newContext()
    let fp = newFixedpoint()
    # Use Z3's default engine — the datalog engine wants finite-domain
    # sorts (not arbitrary Z3Int), and bmc/spacer are smarter at
    # general Horn reasoning.

    let edge = mkFuncDecl[(Z3Int, Z3Int), Z3Bool]("edge")
    let path = mkFuncDecl[(Z3Int, Z3Int), Z3Bool]("path")
    fp.registerRelation(edge)
    fp.registerRelation(path)

    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let z = mkIntVar("z")
    # Base case: an edge is a path.
    fp.addRule(forall(x, y, edge(x, y).implies(path(x, y))))
    # Transitive step: edge composed with path is a path.
    fp.addRule(forall(x, y, z,
      (edge(x, y) and path(y, z)).implies(path(x, z))))
    # Facts: 1 → 2 → 3 → 4
    fp.addRule(edge(mkInt(1), mkInt(2)))
    fp.addRule(edge(mkInt(2), mkInt(3)))
    fp.addRule(edge(mkInt(3), mkInt(4)))

    # Reachable: there's a path 1 → 4.
    check fp.query(path(mkInt(1), mkInt(4))) == zsSat
    # Unreachable (reverse direction).
    check fp.query(path(mkInt(4), mkInt(1))) == zsUnsat

suite "Z3Fixedpoint — answers and introspection":
  test "getAnswer returns a Z3Bool formula after a query":
    let ctx = newContext()
    let fp = newFixedpoint()
    let isTrue = mkFuncDecl[(Z3Int,), Z3Bool]("isTrue")
    fp.registerRelation(isTrue)
    fp.addRule(isTrue(mkInt(7)))
    discard fp.query(isTrue(mkInt(7)))
    let ans = fp.getAnswer()
    # The answer formula exists (typed-Z3Bool); SMT string is non-empty.
    check ($ans).len > 0

  test "getRules + getAssertions return introspectable AST vectors":
    let ctx = newContext()
    let fp = newFixedpoint()
    let rel = mkFuncDecl[(Z3Int,), Z3Bool]("rel")
    fp.registerRelation(rel)
    fp.addRule(rel(mkInt(1)))
    fp.addRule(rel(mkInt(2)))
    fp.assertConstraint(mkBool(true))

    check fp.getRules().len >= 2
    check fp.getAssertions().len >= 1

  test "getReasonUnknown returns a string":
    let ctx = newContext()
    let fp = newFixedpoint()
    # Even after a sat result the call must be safe and return a
    # string (usually empty).
    let isTrue = mkFuncDecl[(Z3Int,), Z3Bool]("isTrue")
    fp.registerRelation(isTrue)
    fp.addRule(isTrue(mkInt(1)))
    discard fp.query(isTrue(mkInt(1)))
    discard fp.getReasonUnknown()
    check true

  test "getHelp returns a multiline parameter list":
    let ctx = newContext()
    let fp = newFixedpoint()
    let help = fp.getHelp()
    check help.len > 0

suite "Z3Fixedpoint — parameter configuration":
  test "setParams accepts a typed params bag without error":
    # The wrapper's contract is to pass the bag through cleanly; whether
    # Z3 honours a given param key is Z3's contract. Test just verifies
    # the call doesn't break the fixedpoint solver.
    let ctx = newContext()
    let fp = newFixedpoint()
    let p = newParams()
    p.set("timeout", 60_000'u)
    p.set("fp.engine", "spacer")
    fp.setParams(p)
    let isTrue = mkFuncDecl[(Z3Int,), Z3Bool]("isTrue")
    fp.registerRelation(isTrue)
    fp.addRule(isTrue(mkInt(1)))
    check fp.query(isTrue(mkInt(1))) == zsSat

suite "Z3Fixedpoint — pretty":
  test "dollar-fp renders an SMT-LIB-shaped string":
    let ctx = newContext()
    let fp = newFixedpoint()
    let rel = mkFuncDecl[(Z3Int,), Z3Bool]("myrel")
    fp.registerRelation(rel)
    fp.addRule(rel(mkInt(42)))
    let s = $fp
    check s.len > 0
    check "myrel" in s

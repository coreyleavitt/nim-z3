## N7.7 — Fixedpoint I/O + descrs + addFact

import std/[unittest, os, strutils]
import z3

suite "Z3Fixedpoint N7.7 — getParamDescrs":
  test "getParamDescrs returns a non-nil Z3ParamDescrs with size > 0":
    let ctx = newContext()
    let fp  = newFixedpoint()
    let d   = fp.getParamDescrs()
    check d != nil
    check d.len > 0

suite "Z3Fixedpoint N7.7 — fromString":
  test "fromString with a ground fact — subsequent query returns zsSat":
    ## Z3's fixedpoint SMT-LIB2 extension: `declare-rel`, `rule`, `query`.
    let ctx = newContext()
    let fp  = newFixedpoint()
    # The input string declares a unary relation `P` over integers,
    # adds the ground fact P(1), and does NOT include a query directive
    # (queries are issued programmatically below).
    let smtlib = """
(declare-rel P (Int))
(declare-var x Int)
(rule (P 1))
"""
    discard fp.fromString(smtlib)
    let p = mkFuncDecl[(Z3Int,), Z3Bool]("P")
    check fp.query(p(mkInt(1))) == zsSat

  test "fromString returns a Z3AstVector (query list, possibly empty)":
    let ctx = newContext()
    let fp  = newFixedpoint()
    let smtlib = """
(declare-rel Q (Int))
(rule (Q 42))
"""
    let queries = fp.fromString(smtlib)
    # No `(query ...)` directive → empty vector is valid.
    check queries != nil

suite "Z3Fixedpoint N7.7 — fromFile":
  test "fromFile with a temp SMT-LIB2 fixedpoint file — query returns zsSat":
    ## Write a trivial fixedpoint SMT-LIB2 file to a temp path, parse
    ## it with fromFile, then verify the declared fact is derivable.
    let path = getTempDir() / "z3fp_n77_test.smt2"
    writeFile(path,
      "(declare-rel R (Int))\n(declare-var x Int)\n(rule (R 99))\n")
    let ctx = newContext()
    let fp  = newFixedpoint()
    discard fp.fromFile(path)
    removeFile(path)
    let r = mkFuncDecl[(Z3Int,), Z3Bool]("R")
    check fp.query(r(mkInt(99))) == zsSat

suite "Z3Fixedpoint N7.7 — getHelp":
  test "getHelp returns a non-empty parameter documentation string":
    ## Already covered in tfixedpoint.nim but we confirm the new call-site
    ## here too, to make the N7.7 suite self-contained.
    let ctx = newContext()
    let fp  = newFixedpoint()
    let h   = fp.getHelp()
    check h.len > 0
    # The help string mentions at least one known fixedpoint parameter key.
    check "engine" in h

suite "Z3Fixedpoint N7.7 — addFact":
  test "addFact with @[0u, 1u] — subsequent datalog query reports zsSat":
    ## `addFact` is the datalog-engine shortcut for ground facts on
    ## finite-domain relations. The sort must be an integral type:
    ## we use Z3BitVec[32] so the datalog engine is satisfied.
    let ctx = newContext()
    let fp  = newFixedpoint()
    let p = newParams()
    p.set("fp.engine", "datalog")
    fp.setParams(p)

    let edge = mkFuncDecl[(Z3BitVec[32], Z3BitVec[32]), Z3Bool]("edge")
    fp.registerRelation(edge)

    # Add the fact edge(0, 1) via the integer-encoding path.
    fp.addFact(edge, @[0u, 1u])

    # Query: is edge(0, 1) derivable?
    check fp.query(edge(mkBitVec[32](0), mkBitVec[32](1))) == zsSat

  test "addFact with empty args — zero-arity relation derivable":
    ## A 0-ary relation (a propositional constant) can be asserted via
    ## addFact with an empty args sequence.
    let ctx = newContext()
    let fp  = newFixedpoint()
    let p = newParams()
    p.set("fp.engine", "datalog")
    fp.setParams(p)

    let flag = mkFuncDecl[tuple[], Z3Bool]("flag")
    fp.registerRelation(flag)
    fp.addFact(flag, @[])
    check fp.query(flag()) == zsSat

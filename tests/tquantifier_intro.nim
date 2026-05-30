## `z3/quantifier` introspection tests — v0.4 step 11.

import std/[unittest, strutils]
import z3

suite "quantifier introspection — tracer":
  test "forall(x, p(x)) has one bound variable":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int,), Z3Bool]("p")
    let x = mkIntVar("x")
    let q = forall(x, p(x))
    check getQuantifierNumBoundVars(q) == 1

suite "quantifier introspection — bound variables":
  test "bound-var name matches the input free constant":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int,), Z3Bool]("p")
    let x = mkIntVar("xyz")
    let q = forall(x, p(x))
    check getQuantifierBoundVarName(q, 0) == "xyz"

  test "bound-var sort dispatches via getSortKind":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int,), Z3Bool]("p")
    let x = mkIntVar("x")
    let q = forall(x, p(x))
    let s = getQuantifierBoundVarSort(q, 0)
    check getSortKind(ctx, s) == skInt

  test "multi-bound-var: forall(x, y, body) reports count 2":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int, Z3Int), Z3Bool]("p")
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let q = forall(x, y, p(x, y))
    check getQuantifierNumBoundVars(q) == 2

suite "quantifier introspection — body":
  test "getQuantifierBody returns the body AST":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int,), Z3Bool]("p")
    let x = mkIntVar("x")
    let q = forall(x, p(x))
    let body = getQuantifierBody(q)
    # The body contains an application of p; semantically equal to
    # p(bound 0).
    check ($body).contains("p")

suite "quantifier introspection — kind discriminators":
  test "forall reports isForall=true and isExists=isLambda=false":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int,), Z3Bool]("p")
    let x = mkIntVar("x")
    let q = forall(x, p(x))
    check isForall(q)
    check not isExists(q)
    check not isLambda(q)

  test "exists reports isExists=true and isForall=isLambda=false":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int,), Z3Bool]("p")
    let x = mkIntVar("x")
    let q = exists(x, p(x))
    check isExists(q)
    check not isForall(q)
    check not isLambda(q)

suite "quantifier introspection — patterns and weight":
  test "default weight is 0":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int,), Z3Bool]("p")
    let x = mkIntVar("x")
    let q = forall(x, p(x))
    check getQuantifierWeight(q) == 0

  test "default no-patterns count is 0":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int,), Z3Bool]("p")
    let x = mkIntVar("x")
    let q = forall(x, p(x))
    check getQuantifierNumPatterns(q) == 0
    check getQuantifierNumNoPatterns(q) == 0

  test "explicit pattern attached to forall is introspectable":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int,), Z3Bool]("p")
    let x = mkIntVar("x")
    let pat = mkPattern(p(x))
    let q = forall(x, p(x), patterns = [pat])
    check getQuantifierNumPatterns(q) >= 1

suite "quantifier introspection — error cases":
  test "non-quantifier AST raises Z3Error":
    let ctx = newContext()
    let p = mkBoolVar("p")
    # Not a quantifier — just a plain bool variable.
    expect Z3Error:
      discard getQuantifierNumBoundVars(p)

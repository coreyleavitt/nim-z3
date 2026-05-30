## `z3/rewrite` tests — term rewriting (`substitute` + `substituteVars`).

import std/[unittest]
import z3

suite "substitute — tracer":
  test "substitute(x + y, x, mkInt(3)) is semantically equal to mkInt(3) + y":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let expr = x + y
    let result = substitute(expr, x, mkInt(3))
    check smtValid(result == mkInt(3) + y)

suite "substitute — multi-pair via openArray":
  test "rewriting two free constants at once":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let expr = x + y
    let result = substitute(expr,
      [(toAnyAst(x), toAnyAst(mkInt(3))),
       (toAnyAst(y), toAnyAst(mkInt(5)))])
    # Resulting expression simplifies to 8.
    check smtValid(result == mkInt(8))

  test "different-sort pairs in one call":
    # Z3's substitute dispatches by structural match, so a single
    # call can carry pairs of different sorts.
    let ctx = newContext()
    let x = mkIntVar("x")
    let p = mkBoolVar("p")
    let expr = (x > mkInt(0)) and p
    let result = substitute(expr,
      [(toAnyAst(x), toAnyAst(mkInt(5))),
       (toAnyAst(p), toAnyAst(mkBool(true)))])
    # (5 > 0) and true ≡ true
    check smtValid(result == mkBool(true))

suite "substitute — no-match identity":
  test "substituting a term that doesn't appear returns the input semantically":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let z = mkIntVar("z")  # never appears
    let expr = x + y
    let result = substitute(expr, z, mkInt(99))
    check smtValid(result == expr)

suite "substitute — typed return preservation":
  test "substitute on a Z3Bool returns a Z3Bool":
    let ctx = newContext()
    let p = mkBoolVar("p")
    let q = mkBoolVar("q")
    let expr = p and q
    let result: Z3Bool = substitute(expr, p, mkBool(true))
    # true and q ≡ q
    check smtValid(result == q)

suite "substituteVars — bound-variable substitution":
  test "single bound var replaced by a concrete term":
    # Manually build a body: P(bound 0) where bound 0 is an Int.
    let ctx = newContext()
    let pred = mkFuncDecl[(Z3Int,), Z3Bool]("P")
    let intSort = sortOf(Z3Int, ctx)
    let bound0 = mkBound(ctx, 0, intSort)
    # Use the bound var inside pred — needs an asZ3Int lift since
    # pred(...) takes a typed Z3Int.
    let bound0Int = asZ3Int(bound0)
    let body = pred(bound0Int)
    # substituteVars: replace bound var 0 with mkInt(5).
    let instantiated = substituteVars(body, [toAnyAst(mkInt(5))])
    # instantiated should be P(5) — semantically equal to direct
    # application.
    let expected = pred(mkInt(5))
    check smtValid(instantiated == expected)

  test "two bound vars replaced simultaneously":
    let ctx = newContext()
    let pred = mkFuncDecl[(Z3Int, Z3Int), Z3Bool]("Q")
    let intSort = sortOf(Z3Int, ctx)
    let bound0 = asZ3Int(mkBound(ctx, 0, intSort))
    let bound1 = asZ3Int(mkBound(ctx, 1, intSort))
    let body = pred(bound0, bound1)
    # replacements[0] -> bound 0, replacements[1] -> bound 1.
    let instantiated = substituteVars(body,
      [toAnyAst(mkInt(10)), toAnyAst(mkInt(20))])
    let expected = pred(mkInt(10), mkInt(20))
    check smtValid(instantiated == expected)

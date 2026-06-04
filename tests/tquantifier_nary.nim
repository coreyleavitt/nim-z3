## `z3/quantifier` N2.6 tests — forallN / existsN N-ary escape hatch.
##
## The per-arity `forall`/`exists` templates cover 1–5 bound variables.
## `forallN` / `existsN` take `openArray[Z3AnyAst]` and delegate to the
## same `quantifierImpl` core, providing an unbounded-arity path.

import std/[unittest]
import z3

suite "quantifier — forallN 6-variable":
  test "forallN with 6 Int vars: x1+x2+x3+x4+x5+x6 >= x1+x2+x3+x4+x5+x6 is valid":
    let ctx = newContext()
    let x1 = mkIntVar("x1")
    let x2 = mkIntVar("x2")
    let x3 = mkIntVar("x3")
    let x4 = mkIntVar("x4")
    let x5 = mkIntVar("x5")
    let x6 = mkIntVar("x6")
    # A tautological body: lhs == rhs implies lhs >= rhs
    let lhs = x1 + x2 + x3 + x4 + x5 + x6
    let body = lhs >= lhs
    let q = forallN(@[x1.toAnyAst, x2.toAnyAst, x3.toAnyAst,
                      x4.toAnyAst, x5.toAnyAst, x6.toAnyAst], body)
    check smtValid(q)

  test "forallN yields a forall quantifier with 6 bound vars":
    let ctx = newContext()
    let x1 = mkIntVar("x1")
    let x2 = mkIntVar("x2")
    let x3 = mkIntVar("x3")
    let x4 = mkIntVar("x4")
    let x5 = mkIntVar("x5")
    let x6 = mkIntVar("x6")
    let lhs = x1 + x2 + x3 + x4 + x5 + x6
    let q = forallN(@[x1.toAnyAst, x2.toAnyAst, x3.toAnyAst,
                      x4.toAnyAst, x5.toAnyAst, x6.toAnyAst], lhs >= lhs)
    check q.isForall
    check getQuantifierNumBoundVars(q) == 6

suite "quantifier — existsN 6-variable":
  test "existsN with 6 Int vars: exists x1..x6. x1+x2+x3+x4+x5+x6 == 21":
    let ctx = newContext()
    let x1 = mkIntVar("x1")
    let x2 = mkIntVar("x2")
    let x3 = mkIntVar("x3")
    let x4 = mkIntVar("x4")
    let x5 = mkIntVar("x5")
    let x6 = mkIntVar("x6")
    # Witnessed by x1=1, x2=2, x3=3, x4=4, x5=5, x6=6
    let sum = x1 + x2 + x3 + x4 + x5 + x6
    let q = existsN(@[x1.toAnyAst, x2.toAnyAst, x3.toAnyAst,
                      x4.toAnyAst, x5.toAnyAst, x6.toAnyAst],
                    sum == mkInt(21))
    check smtValid(q)

  test "existsN yields an exists quantifier with 6 bound vars":
    let ctx = newContext()
    let x1 = mkIntVar("x1")
    let x2 = mkIntVar("x2")
    let x3 = mkIntVar("x3")
    let x4 = mkIntVar("x4")
    let x5 = mkIntVar("x5")
    let x6 = mkIntVar("x6")
    let sum = x1 + x2 + x3 + x4 + x5 + x6
    let q = existsN(@[x1.toAnyAst, x2.toAnyAst, x3.toAnyAst,
                      x4.toAnyAst, x5.toAnyAst, x6.toAnyAst],
                    sum == mkInt(21))
    check q.isExists
    check getQuantifierNumBoundVars(q) == 6

suite "quantifier — forallN pattern threading":
  test "forallN with explicit pattern: pattern count == 1":
    let ctx = newContext()
    let x = mkIntVar("x")
    let body = x + mkInt(1) > x
    let p = mkPattern(x + mkInt(1))
    # Single-element bound array uses the N-ary path
    let q = forallN(@[x.toAnyAst], body, patterns = @[p])
    check getQuantifierNumPatterns(q) == 1

  test "forallN with two patterns: both reach the quantifier":
    let ctx = newContext()
    let x = mkIntVar("x")
    let body = x + mkInt(1) > x
    let p1 = mkPattern(x + mkInt(1))
    let p2 = mkPattern(x + mkInt(1) > x)
    let q = forallN(@[x.toAnyAst], body, patterns = @[p1, p2])
    check getQuantifierNumPatterns(q) == 2
    # Quantifier is still valid (patterns don't change semantics)
    check smtValid(q)

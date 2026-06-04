## N8.9 — AstVector + Goal translate parity tests.
##
## Verifies:
##   - translate(v: Z3AstVector, ctx2) — cross-context vector transfer
##   - Goal.translate survival check (N8.8 regression)
##   - Round-trip: v → ctx2 → ctx1 preserves element count and sort structure

import std/[unittest]
import z3

suite "translate parity — Z3AstVector.translate":
  test "translate Z3AstVector of 3 ASTs to another context preserves len":
    let ctx1 = newContext()
    let ctx2 = newContext()
    let x = mkIntVar(ctx1, "x")
    let y = mkIntVar(ctx1, "y")
    let z = mkIntVar(ctx1, "z")
    let v = newAstVector(ctx1)
    v.add x
    v.add y
    v.add z
    let v2 = v.translate(ctx2)
    check v2.len == 3

  test "translated Z3AstVector elements are sort-equivalent (Int sort preserved)":
    let ctx1 = newContext()
    let ctx2 = newContext()
    let x = mkIntVar(ctx1, "x")
    let y = mkIntVar(ctx1, "y")
    let v = newAstVector(ctx1)
    v.add x
    v.add y
    let v2 = v.translate(ctx2)
    # toSeq[Z3Int] succeeds iff every element is an Int-sort AST
    let elems = v2.toSeq(Z3Int)
    check elems.len == 2
    # SMT-LIB rendering of the variables should match by name
    check $elems[0] == "x"
    check $elems[1] == "y"

  test "translated Z3AstVector lives in target context (ctx2)":
    let ctx1 = newContext()
    let ctx2 = newContext()
    let p = mkBoolVar(ctx1, "p")
    let q = mkBoolVar(ctx1, "q")
    let v = newAstVector(ctx1)
    v.add p
    v.add q
    let v2 = v.translate(ctx2)
    check v2.ctx.raw == ctx2.raw

  test "round-trip Z3AstVector ctx1 → ctx2 → ctx1 preserves element count":
    let ctx1 = newContext()
    let ctx2 = newContext()
    let a = mkBoolVar(ctx1, "a")
    let b = mkBoolVar(ctx1, "b")
    let c = mkBoolVar(ctx1, "c")
    let v = newAstVector(ctx1)
    v.add a
    v.add b
    v.add c
    let v2 = v.translate(ctx2)
    let v3 = v2.translate(ctx1)
    check v3.len == v.len

suite "translate parity — Goal.translate regression (N8.8)":
  test "goal.translate preserves size across contexts":
    let src = newContext()
    let tgt = newContext()
    let x = mkIntVar(src, "x")
    let g = newGoal(src)
    g.add (x > mkInt(src, 0))
    g.add (x < mkInt(src, 10))
    let g2 = g.translate(tgt)
    check g2.size == 2

  test "translated goal usable by tactic in target context":
    let src = newContext()
    let tgt = newContext()
    let x = mkIntVar(src, "x")
    let g = newGoal(src)
    g.add (x > mkInt(src, 0))
    let g2 = g.translate(tgt)
    let r = mkTactic(tgt, "smt").apply(g2)
    check r.numSubgoals >= 1

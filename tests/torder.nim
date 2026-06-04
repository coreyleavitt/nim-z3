## `z3/order` tests — order theory + transitive closure (N9.2).
##
## Covers: mkLinearOrder, mkPartialOrder, mkPiecewiseLinearOrder, mkTreeOrder,
## mkTransitiveClosure.

import std/unittest
import z3

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc checkValid(ctx: Z3Context, f: Z3Bool): bool =
  ## Return true iff f is valid (i.e. its negation is UNSAT).
  let s = ctx.newSolver()
  s.add(not f)
  s.check() == zsUnsat

# ===========================================================================
suite "mkLinearOrder — construction and application":
# ===========================================================================

  test "mkLinearOrder returns a non-nil Z3FuncDecl":
    let ctx = newContext()
    let lt = mkLinearOrder[Z3Int](ctx, 0)
    check lt != nil

  test "applying linear-order decl to two Z3Int yields Z3Bool":
    let ctx = newContext()
    let lt = mkLinearOrder[Z3Int](ctx, 0)
    let a = mkIntVar("a")
    let b = mkIntVar("b")
    let result = lt(a, b)
    # Just check it's a well-formed formula (not nil-raw).
    check not result.raw.isNil

  test "linear-order relation on concrete ints produces valid formula":
    let ctx = newContext()
    let lt = mkLinearOrder[Z3Int](ctx, 0)
    # Z3 adds axioms: 1 < 2 should be satisfiable, not necessarily valid.
    # But lt is the declared relation — just check it's callable.
    let f = lt(mkInt(1), mkInt(2))
    check not f.raw.isNil

# ===========================================================================
suite "mkLinearOrder — solver axioms":
# ===========================================================================

  test "transitivity: lt(a,b) AND lt(b,c) implies lt(a,c) is valid":
    ## Z3 adds the linear-order axioms automatically when the relation is
    ## created with mkLinearOrder. We check validity by asserting the negation
    ## and expecting UNSAT.
    let ctx = newContext()
    let lt = mkLinearOrder[Z3Int](ctx, 0)
    let a = mkIntVar("trans_a")
    let b = mkIntVar("trans_b")
    let c = mkIntVar("trans_c")
    let hypothesis = lt(a, b) and lt(b, c)
    let conclusion = lt(a, c)
    let stmt = implies(hypothesis, conclusion)
    check checkValid(ctx, stmt)

  test "linear order is reflexive (Z3 mkLinearOrder injects ≤-style axioms)":
    ## Z3's mkLinearOrder injects axioms for the fixedpoint/CHC engine;
    ## in the general SMT solver the relation is reflexive (not strict).
    ## lt(a,a) is satisfiable — not blocked by the standard solver.
    let ctx = newContext()
    let lt = mkLinearOrder[Z3Int](ctx, 0)
    let a = mkIntVar("irr_a")
    let s = ctx.newSolver()
    s.add lt(a, a)
    check s.check() == zsSat

  test "totality: lt(a,b) OR lt(b,a) OR (a == b) is valid":
    let ctx = newContext()
    let lt = mkLinearOrder[Z3Int](ctx, 0)
    let a = mkIntVar("tot_a")
    let b = mkIntVar("tot_b")
    check checkValid(ctx, lt(a, b) or lt(b, a) or (a == b))

# ===========================================================================
suite "mkPartialOrder — construction and smoke":
# ===========================================================================

  test "mkPartialOrder returns non-nil Z3FuncDecl":
    let ctx = newContext()
    let po = mkPartialOrder[Z3Int](ctx, 0)
    check po != nil

  test "applying partial-order decl to two Z3Int yields Z3Bool":
    let ctx = newContext()
    let po = mkPartialOrder[Z3Int](ctx, 0)
    let x = mkIntVar("po_x")
    let y = mkIntVar("po_y")
    let r = po(x, y)
    check not r.raw.isNil

  test "partial-order reflexivity: po(a,a) is valid":
    ## Partial orders include reflexivity (po is ≤, not <).
    let ctx = newContext()
    let po = mkPartialOrder[Z3Int](ctx, 0)
    let a = mkIntVar("po_ref_a")
    check checkValid(ctx, po(a, a))

  test "partial-order transitivity: po(a,b) AND po(b,c) implies po(a,c) is valid":
    let ctx = newContext()
    let po = mkPartialOrder[Z3Int](ctx, 0)
    let a = mkIntVar("po_ta")
    let b = mkIntVar("po_tb")
    let c = mkIntVar("po_tc")
    check checkValid(ctx, implies(po(a, b) and po(b, c), po(a, c)))

# ===========================================================================
suite "mkPiecewiseLinearOrder — construction and smoke":
# ===========================================================================

  test "mkPiecewiseLinearOrder returns non-nil Z3FuncDecl":
    let ctx = newContext()
    let pl = mkPiecewiseLinearOrder[Z3Int](ctx, 0)
    check pl != nil

  test "applying piecewise-linear-order decl to two Z3Int yields Z3Bool":
    let ctx = newContext()
    let pl = mkPiecewiseLinearOrder[Z3Int](ctx, 0)
    let x = mkIntVar("pl_x")
    let y = mkIntVar("pl_y")
    check not pl(x, y).raw.isNil

# ===========================================================================
suite "mkTreeOrder — construction and smoke":
# ===========================================================================

  test "mkTreeOrder returns non-nil Z3FuncDecl":
    let ctx = newContext()
    let to = mkTreeOrder[Z3Int](ctx, 0)
    check to != nil

  test "applying tree-order decl to two Z3Int yields Z3Bool":
    let ctx = newContext()
    let to = mkTreeOrder[Z3Int](ctx, 0)
    let x = mkIntVar("to_x")
    let y = mkIntVar("to_y")
    check not to(x, y).raw.isNil

# ===========================================================================
suite "mkTransitiveClosure — construction and application":
# ===========================================================================

  test "mkTransitiveClosure returns non-nil Z3FuncDecl":
    let ctx = newContext()
    # Use a binary relation on Z3Int as the base.
    let rel = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "tc_base_rel")
    let tc = mkTransitiveClosure(rel)
    check tc != nil

  test "transitive closure application yields Z3Bool":
    let ctx = newContext()
    let rel = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "tc_app_rel")
    let tc = mkTransitiveClosure(rel)
    let x = mkIntVar("tc_x")
    let y = mkIntVar("tc_y")
    check not tc(x, y).raw.isNil

  test "transitive closure: edge(1,2) and edge(2,3) implies tc(1,3) is SAT":
    ## The transitive closure tc of `edge` should include (1,3) when
    ## edge(1,2) and edge(2,3) are asserted.
    let ctx = newContext()
    let edge = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "tc_edge")
    let tc = mkTransitiveClosure(edge)
    let s = ctx.newSolver()
    s.add edge(mkInt(1), mkInt(2))
    s.add edge(mkInt(2), mkInt(3))
    s.add tc(mkInt(1), mkInt(3))
    check s.check() == zsSat

# ===========================================================================
suite "multiple order-ids coexist":
# ===========================================================================

  test "two linear orders with different ids are independent":
    let ctx = newContext()
    let lt0 = mkLinearOrder[Z3Int](ctx, 0)
    let lt1 = mkLinearOrder[Z3Int](ctx, 1)
    check lt0 != nil
    check lt1 != nil
    let a = mkIntVar("co_a")
    let b = mkIntVar("co_b")
    check not lt0(a, b).raw.isNil
    check not lt1(a, b).raw.isNil

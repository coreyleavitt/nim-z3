## N8.2 — Solver cube + congruence introspection
##
## Tests for `cube`, `congruenceRoot`, and `congruenceNext` added by RFC N8.2.
##
## Notes:
## - `cube` works with both `newSolver` and `newSimpleSolver`; we use
##   `newSimpleSolver` for the congruence tests since they are most
##   meaningful after CDCL propagation.
## - `congruenceRoot` and `congruenceNext` return `RawZ3Ast` (not a typed
##   wrapper) to avoid the `solver → introspect → bitvec → model → solver`
##   circular import. Callers compare raw pointers for class membership.
## - The bar is "the procs are callable and return sensible shapes."

import std/unittest
import z3

# ---------------------------------------------------------------------------
# cube
# ---------------------------------------------------------------------------

suite "Z3Solver — cube (N8.2)":

  test "cube on a SAT solver returns a non-nil Z3AstVector":
    let ctx = newContext()
    let s   = newSimpleSolver()
    let x   = mkIntVar("x")
    s.add(x > mkInt(0))
    let vars = newAstVector(ctx)   # empty hint vector
    let c = s.cube(vars, 1)
    check not c.raw.isNil

  test "cube result is bound to the solver's context":
    let ctx = newContext()
    let s   = newSimpleSolver()
    let p   = mkBoolVar("p")
    s.add(p)
    let vars = newAstVector(ctx)
    let c = s.cube(vars, 1)
    check c.ctx == ctx

  test "cube on a trivially UNSAT solver returns a valid vector":
    ## Z3 documents that when the cube enumerator detects UNSAT it returns
    ## a single-element vector containing `false`.
    let ctx = newContext()
    let s   = newSimpleSolver()
    let p   = mkBoolVar("p")
    s.add(p)
    s.add(not p)
    let vars = newAstVector(ctx)
    let c = s.cube(vars, 1)
    check not c.raw.isNil

  test "cube with backtrack_level=0 is callable and returns a vector":
    let ctx = newContext()
    let s   = newSimpleSolver()
    let x   = mkBoolVar("x")
    let y   = mkBoolVar("y")
    s.add(x or y)
    let vars = newAstVector(ctx)
    let c = s.cube(vars, 0)
    check not c.raw.isNil

# ---------------------------------------------------------------------------
# congruenceRoot + congruenceNext
# ---------------------------------------------------------------------------

suite "Z3Solver — congruenceRoot / congruenceNext (N8.2)":

  test "congruenceRoot is callable and returns a non-nil raw":
    ## After asserting x == y and checking SAT, x and y are in the same
    ## congruence class.
    let ctx = newContext()
    let s   = newSimpleSolver()
    let x   = mkIntVar("x")
    let y   = mkIntVar("y")
    s.add(x == y)
    doAssert s.check() == zsSat
    let rx = s.congruenceRoot(x)
    check not rx.isNil

  test "congruenceRoot of x and y are equal after asserting x == y":
    let ctx = newContext()
    let s   = newSimpleSolver()
    let x   = mkIntVar("x")
    let y   = mkIntVar("y")
    s.add(x == y)
    doAssert s.check() == zsSat
    let rx = s.congruenceRoot(x)
    let ry = s.congruenceRoot(y)
    # Both roots must be the same raw pointer.
    check rx == ry

  test "congruenceNext is callable and returns a non-nil raw":
    let ctx = newContext()
    let s   = newSimpleSolver()
    let x   = mkIntVar("x")
    let y   = mkIntVar("y")
    s.add(x == y)
    doAssert s.check() == zsSat
    let nxt = s.congruenceNext(x)
    check not nxt.isNil

  test "congruenceNext on a singleton class returns the element itself":
    ## An AST not equated to anything else forms a singleton class;
    ## congruenceNext cycles back to itself.
    let ctx = newContext()
    let s   = newSimpleSolver()
    let x   = mkIntVar("x")
    s.add(x > mkInt(0))   # no equality; x is alone in its class
    doAssert s.check() == zsSat
    let nxt = s.congruenceNext(x)
    check nxt == x.raw

  test "congruence class of x == y: next(x) lands in {x.raw, y.raw}":
    ## x and y are equated. The cycle contains exactly x and y.
    ## congruenceNext(x) must be one of the two raw handles.
    let ctx = newContext()
    let s   = newSimpleSolver()
    let x   = mkIntVar("x")
    let y   = mkIntVar("y")
    s.add(x == y)
    doAssert s.check() == zsSat
    let step1 = s.congruenceNext(x)
    check (step1 == x.raw) or (step1 == y.raw)

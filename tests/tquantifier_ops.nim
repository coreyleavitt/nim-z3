## `z3/quantifier` ops tests — N2.5: quantifier symbol introspection +
## substituteVars de-Bruijn round-trip.

import std/[unittest]
import z3

suite "quantifier ops — quantifierId stability":
  test "quantifierId is non-nil and stable across two calls":
    let ctx = newContext()
    let x = mkIntVar("x")
    let q = forall(x, x > mkInt(0))
    let id1 = quantifierId(q)
    let id2 = quantifierId(q)
    # Result is a valid Nim string (not nil; empty string is also acceptable)
    check id1 == id2

  test "quantifierId returns the same string for structurally-equal quantifiers":
    let ctx = newContext()
    let x = mkIntVar("x")
    let q1 = forall(x, x > mkInt(0))
    let q2 = forall(x, x > mkInt(0))
    # Structurally equal ASTs are interned by Z3 — same raw pointer,
    # same id.
    check quantifierId(q1) == quantifierId(q2)

suite "quantifier ops — quantifierSkolemId stability":
  test "quantifierSkolemId is stable across two calls":
    let ctx = newContext()
    let x = mkIntVar("x")
    let q = forall(x, x > mkInt(0))
    let sid1 = quantifierSkolemId(q)
    let sid2 = quantifierSkolemId(q)
    check sid1 == sid2

  test "quantifierSkolemId returns a string (not crash)":
    let ctx = newContext()
    let x = mkIntVar("x")
    let q = exists(x, x == mkInt(42))
    # Just verify the call doesn't raise and returns a usable string.
    let sid = quantifierSkolemId(q)
    # A valid Nim string is always non-nil; the value may be "" or "0".
    check sid.len >= 0   # always true; guards against nil-pointer path

suite "quantifier ops — substituteVars de-Bruijn round-trip":
  test "substituteVars replaces bound var 0 with 5; 5 > 0 is SAT":
    let ctx = newContext()
    # Build the body using a de-Bruijn bound variable at index 0 of Int sort.
    let intS = mkIntSort(ctx).raw
    let bound0: Z3AnyAst = mkBound(ctx, 0, intS)
    # body: bound(0) > 0  — not yet a ground term
    let body = asZ3Int(bound0) > mkInt(0)
    # Substitute bound var 0 → concrete 5
    let instantiated = substituteVars(body, [mkInt(5).toAnyAst])
    # instantiated: 5 > 0 — ground, satisfiable (actually valid/tautology)
    let s = newSolver()
    s.add(instantiated)
    check s.check() == zsSat

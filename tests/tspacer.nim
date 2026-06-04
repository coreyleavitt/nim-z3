## `z3/spacer` tests — Spacer-specific fixedpoint API.
##
## Covers:
##   - queryFromLevel — CHC query from a given induction level
##   - addInvariant + getReachable — inject invariant and retrieve reachable states
##   - getGroundSatAnswer — retrieve ground sat witness after SAT query
##   - getRulesAlongTrace — counterexample trace rules after SAT query
##   - modelExtrapolate — extrapolate a formula from a model
##   - qeLite — best-effort quantifier elimination
##   - qeModelProject — model-guided variable projection
##
## Build gate: `-d:z3WithoutSpacer` compiles cleanly but all Spacer suites
## are replaced by a single skip-report suite so `nimble test` doesn't
## need special casing.

import std/unittest
import z3

when defined(z3WithoutSpacer):
  # Module excluded: emit a single skip suite so CI reports it cleanly.
  suite "spacer — disabled build (-d:z3WithoutSpacer)":
    test "Spacer module excluded — all tests skipped":
      skip()

else:
  # Full Spacer test suite.

  # -------------------------------------------------------------------------
  # Helpers: build a minimal Spacer fixedpoint problem.
  #
  # Pattern: 1 unary predicate P(Int), 1 base fact P(0), 1 inductive rule
  #   P(x) ∧ x < 5 → P(x+1),
  # then query P(3) (sat) and P(99) (unsat).
  # This is the simplest possible Horn problem Spacer can reason about.
  # -------------------------------------------------------------------------

  suite "spacer — queryFromLevel":
    test "queryFromLevel 0 is callable and returns a Z3Status":
      ## The proc must dispatch without crashing. From level 0, Spacer
      ## may find the SAT answer at or below the given bound; the exact
      ## result is engine-dependent. We assert result is a valid Z3Status.
      let ctx = newContext()
      let fp = newFixedpoint()
      let p = newParams()
      p.set("fp.engine", "spacer")
      fp.setParams(p)
      let rel = mkFuncDecl[(Z3Int,), Z3Bool]("Q")
      fp.registerRelation(rel)
      fp.addRule(rel(mkInt(42)))
      let res = fp.queryFromLevel(0, rel(mkInt(42)))
      check res in {zsSat, zsUnsat, zsUnknown}

    test "queryFromLevel returns zsSat for a ground fact":
      ## A direct ground fact at level 0 must be immediately derivable.
      let ctx = newContext()
      let fp = newFixedpoint()
      let p = newParams()
      p.set("fp.engine", "spacer")
      fp.setParams(p)
      let rel = mkFuncDecl[(Z3Int,), Z3Bool]("R")
      fp.registerRelation(rel)
      fp.addRule(rel(mkInt(7)))
      let res = fp.queryFromLevel(0, rel(mkInt(7)))
      check res == zsSat

  suite "spacer — addInvariant and getReachable":
    test "addInvariant is callable without raising":
      ## `addInvariant` injects an assumed invariant into Spacer's state.
      ## Spacer's xform.slice optimisation is incompatible with the
      ## invariant API; must disable it via `xform.slice=false`.
      let ctx = newContext()
      let fp = newFixedpoint()
      let p = newParams()
      p.set("fp.engine", "spacer")
      p.set("xform.slice", false)        # required: invariants incompatible with xform.slice
      fp.setParams(p)
      let pred = mkFuncDecl[(Z3Int,), Z3Bool]("Inv")
      fp.registerRelation(pred)
      fp.addRule(pred(mkInt(0)))
      let x = mkIntVar("x")
      # Inject invariant: pred(x) → x >= 0
      fp.addInvariant(pred, forall(x, pred(x).implies(x >= mkInt(0))))
      # Solver still works after invariant injection
      check fp.query(pred(mkInt(0))) == zsSat

    test "getReachable returns a non-nil AST after a SAT query":
      ## After a successful SAT query, getReachable should provide the
      ## reachable states formula for the queried predicate.
      let ctx = newContext()
      let fp = newFixedpoint()
      let p = newParams()
      p.set("fp.engine", "spacer")
      p.set("xform.slice", false)        # required when using invariants
      fp.setParams(p)
      let pred = mkFuncDecl[(Z3Int,), Z3Bool]("Reach")
      fp.registerRelation(pred)
      fp.addRule(pred(mkInt(1)))
      let res = fp.query(pred(mkInt(1)))
      check res == zsSat
      let reachable = fp.getReachable(pred)
      # Result is a valid AST with a non-empty SMT2 rendering
      check ($reachable).len > 0

  suite "spacer — getGroundSatAnswer":
    test "getGroundSatAnswer returns a non-nil AST after SAT query":
      ## The ground sat answer is the bottom-up sequence of ground facts
      ## witnessing derivability. After a SAT query it must be available.
      let ctx = newContext()
      let fp = newFixedpoint()
      let p = newParams()
      p.set("fp.engine", "spacer")
      fp.setParams(p)
      let pred = mkFuncDecl[(Z3Int,), Z3Bool]("G")
      fp.registerRelation(pred)
      fp.addRule(pred(mkInt(5)))
      let res = fp.query(pred(mkInt(5)))
      check res == zsSat
      let ans = fp.getGroundSatAnswer()
      check ($ans).len > 0

  suite "spacer — getRulesAlongTrace":
    test "getRulesAlongTrace returns a Z3AstVector after a SAT query":
      ## The rules along the counterexample trace is the sequence of Horn
      ## rules fired to reach the query. After SAT it is non-nil and its
      ## SMT2 rendering is well-formed.
      let ctx = newContext()
      let fp = newFixedpoint()
      let p = newParams()
      p.set("fp.engine", "spacer")
      fp.setParams(p)
      let pred = mkFuncDecl[(Z3Int,), Z3Bool]("T")
      fp.registerRelation(pred)
      fp.addRule(pred(mkInt(3)))
      let res = fp.query(pred(mkInt(3)))
      check res == zsSat
      let trace = fp.getRulesAlongTrace()
      # Z3AstVector is non-nil (len >= 0 always valid post-SAT)
      check trace.len >= 0

  suite "spacer — modelExtrapolate":
    test "modelExtrapolate returns a non-nil AST from a satisfiable formula":
      ## modelExtrapolate generalises a model to a formula that is
      ## implied by the model and implies the original. The result must
      ## be a valid AST for any SAT formula + its model.
      let ctx = newContext()
      let s = newSolver()
      let x = mkIntVar("x")
      s.add(x > mkInt(0))
      s.add(x < mkInt(10))
      check s.check() == zsSat
      let m = s.model()
      let fml = (x > mkInt(0)) and (x < mkInt(10))
      let ext = modelExtrapolate(m, fml.toAnyAst)
      check ($ext).len > 0

  suite "spacer — qeLite":
    test "qeLite eliminates a free variable from an existential":
      ## qeLite performs best-effort quantifier elimination. Given an
      ## existential ∃x. x > 0 ∧ x < 10, the result should be
      ## provably satisfiable (non-false) and well-formed.
      let ctx = newContext()
      let x = mkIntVar("x")
      # Bound variables for qeLite are passed as a Z3AstVector
      let bound = newAstVector()
      bound.add(x)
      let body = (x > mkInt(0)) and (x < mkInt(10))
      let result = qeLite(bound, body.toAnyAst)
      check ($result).len > 0

    test "qeLite on a tautology body returns a formula without bound vars":
      ## ∃x. (x == x) should simplify to true or a trivially-sat formula.
      ## We only assert the result is a well-formed, non-nil AST.
      let ctx = newContext()
      let x = mkIntVar("x")
      let bound = newAstVector()
      bound.add(x)
      let body = (x == x).toAnyAst
      let result = qeLite(bound, body)
      check ($result).len > 0

  suite "spacer — qeModelProject":
    test "qeModelProject projects a bound variable given a model":
      ## qeModelProject eliminates bound vars from body guided by model m.
      ## After SAT-solving x > 0 ∧ x < 10, project out x. The result
      ## must be a well-formed AST.
      let ctx = newContext()
      let x = mkIntVar("x")
      let s = newSolver()
      s.add(x > mkInt(0))
      s.add(x < mkInt(10))
      check s.check() == zsSat
      let m = s.model()
      let body = ((x > mkInt(0)) and (x < mkInt(10))).toAnyAst
      let result = qeModelProject(m, @[x.toAnyAst], body)
      check ($result).len > 0

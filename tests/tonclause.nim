## N8.4d — Z3_solver_register_on_clause typed surface.
##
## Tests verify:
##  1. registerOnClause accepts a closure and check() completes.
##  2. The callback fires at least once during a UNSAT check.
##  3. The callback receives a non-nil lits vector on each invocation.
##  4. deps is a valid seq[uint] (may be empty for input clauses).
##  5. proofHint is delivered without crashing (may be nil).
##  6. Gate: module compiles under -d:z3WithoutOnClause (not directly testable
##     here; verified by building with that flag — see Deliverable note).
##
## IMPORTANT: Z3_solver_register_on_clause only fires when the context is
## created with proof=true. Without it Z3's CDCL(T) does not emit clause
## notifications. All tests in this file use newContext(("proof", "true")).

import std/unittest
import z3
import z3/onclause

suite "N8.4d — registerOnClause: callback fires on UNSAT":

  test "callback fires at least once when check() is UNSAT":
    ## Build p and not p — forced UNSAT. Z3 derives clause notifications;
    ## the handler must fire at least once. Requires proof=true context.
    let ctx = newContext(("proof", "true"))
    let s   = newSolver()
    let p   = mkBoolVar("p")
    s.add(p)
    s.add(not p)

    var callCount = 0
    s.registerOnClause(proc(proofHint: Z3AnyAst, deps: seq[uint],
                             lits: Z3AstVector) {.closure.} =
      inc callCount
    )

    let status = s.check()
    check status == zsUnsat
    check callCount > 0

  test "lits vector is non-nil on each callback invocation":
    ## Same contradiction; verify lits is never nil inside the callback.
    let ctx = newContext(("proof", "true"))
    let s   = newSolver()
    let q   = mkBoolVar("q")
    s.add(q)
    s.add(not q)

    var allLitsNonNil = true
    s.registerOnClause(proc(proofHint: Z3AnyAst, deps: seq[uint],
                             lits: Z3AstVector) {.closure.} =
      if lits == nil:
        allLitsNonNil = false
    )

    let status = s.check()
    check status == zsUnsat
    check allLitsNonNil

  test "deps is a valid seq[uint] on each callback invocation":
    ## The deps seq may be empty for input-preprocessing clauses.
    ## Iteration must not crash.
    let ctx = newContext(("proof", "true"))
    let s   = newSolver()
    let r   = mkBoolVar("r")
    s.add(r)
    s.add(not r)

    var iterOk = true
    s.registerOnClause(proc(proofHint: Z3AnyAst, deps: seq[uint],
                             lits: Z3AstVector) {.closure.} =
      for _ in deps:
        discard
    )

    let status = s.check()
    check status == zsUnsat
    check iterOk

  test "proofHint parameter is delivered without crashing (smoke)":
    ## proofHint may be nil (Z3 passes null for most derived clauses).
    ## Verify no crash and the closure fires.
    let ctx = newContext(("proof", "true"))
    let s   = newSolver()
    let t   = mkBoolVar("t")
    s.add(t)
    s.add(not t)

    var fired = false
    s.registerOnClause(proc(proofHint: Z3AnyAst, deps: seq[uint],
                             lits: Z3AstVector) {.closure.} =
      fired = true
      discard proofHint.raw.isNil   # must not crash even if nil
    )

    discard s.check()
    check fired

## N8.4d / N11.4b — Z3_solver_register_on_clause typed surface.
##
## Tests verify:
##  1. registerOnClause accepts a closure and check() completes.
##  2. The callback fires at least once during a UNSAT check.
##  3. The callback receives a non-nil lits vector on each invocation.
##  4. deps is a valid seq[uint] (may be empty for input clauses).
##  5. proofHint is delivered without crashing (may be nil).
##  6. Closure with accumulator (seq) captures state across invocations.
##  7. Second registerOnClause replaces first (Z3 replacement semantics).
##  8. Gate: -d:z3WithoutOnClause excludes registerOnClause from scope
##     (verified here via `compiles()` inside a gated suite; also
##     enforced at the module-import level by the `when` block below).
##
## IMPORTANT: Z3_solver_register_on_clause only fires when the context is
## created with proof=true. Without it Z3's CDCL(T) does not emit clause
## notifications. All functional tests use newContext(("proof", "true")).

import std/unittest
import z3

when not defined(z3WithoutOnClause):
  import z3/onclause

  # ---------------------------------------------------------------------------
  # Functional test suite (requires the module to be compiled in)
  # ---------------------------------------------------------------------------

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

      s.registerOnClause(proc(proofHint: Z3AnyAst, deps: seq[uint],
                               lits: Z3AstVector) {.closure.} =
        for _ in deps:
          discard
      )

      let status = s.check()
      check status == zsUnsat

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

    test "closure with accumulator captures lits.len across invocations":
      ## Verifies that a closure with heap-allocated mutable state (a seq)
      ## correctly accumulates across multiple callback invocations. This
      ## exercises both Nim's GC-safe closure-capture path and the boxing
      ## machinery that keeps the callback alive across the full check().
      let ctx = newContext(("proof", "true"))
      let s   = newSolver()
      let u   = mkBoolVar("u")
      s.add(u)
      s.add(not u)

      var litSizes: seq[int] = @[]
      s.registerOnClause(proc(proofHint: Z3AnyAst, deps: seq[uint],
                               lits: Z3AstVector) {.closure.} =
        litSizes.add(lits.len)
      )

      let status = s.check()
      check status == zsUnsat
      check litSizes.len > 0
      for sz in litSizes:
        check sz >= 0   # every lits.len must be a non-negative int

    test "second registerOnClause replaces first (Z3 replacement semantics)":
      ## Registering a second callback must replace the first. Only the
      ## second counter should increment; the first must remain zero.
      ## This validates the documented Z3 single-registration semantics.
      let ctx = newContext(("proof", "true"))
      let s   = newSolver()
      let v   = mkBoolVar("v")
      s.add(v)
      s.add(not v)

      var firstCount  = 0
      var secondCount = 0

      s.registerOnClause(proc(proofHint: Z3AnyAst, deps: seq[uint],
                               lits: Z3AstVector) {.closure.} =
        inc firstCount
      )
      s.registerOnClause(proc(proofHint: Z3AnyAst, deps: seq[uint],
                               lits: Z3AstVector) {.closure.} =
        inc secondCount
      )

      let status = s.check()
      check status == zsUnsat
      check secondCount > 0
      check firstCount  == 0   # replaced — must never have fired

else:
  # ---------------------------------------------------------------------------
  # Gate suite: -d:z3WithoutOnClause — module excluded
  # ---------------------------------------------------------------------------

  suite "onclause — disabled build (-d:z3WithoutOnClause)":
    test "registerOnClause not in scope when gate is set":
      ## Compile-time gate check: when -d:z3WithoutOnClause is set,
      ## the onclause module body is empty and registerOnClause must not
      ## be available. `compiles()` evaluates at compile time; the check
      ## itself runs at runtime to integrate with the test runner.
      ##
      ## Note: the `import z3/onclause` below is intentional — we re-import
      ## the (now empty) module to confirm the proc is absent post-import.
      ## The {.used.} suppressor is unavailable on imports; Nim's
      ## UnusedImport warning here is a false positive (import is inside
      ## compiles() and never surfaces to the outer scope).
      {.push warning[UnusedImport]: off.}
      check not compiles(block:
        import z3/onclause
        let s {.used.} = newSolver()
        s.registerOnClause(proc(proofHint: Z3AnyAst, deps: seq[uint],
                                 lits: Z3AstVector) {.closure.} = discard)
      )
      {.pop.}

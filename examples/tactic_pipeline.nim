## Tactic pipeline example — drives a constraint set through a
## composed solver strategy instead of the default `newSolver()`.
##
## The pattern `simplify.andThen(smt).toSolver()` builds:
##
##   1. `simplify` — Z3's pre-processing pass (constant folding,
##      common-subexpression elimination, rewriting).
##   2. `andThen` — composes two tactics so the second runs on the
##      simplified goal the first produced.
##   3. `smt` — the general-purpose decision procedure.
##   4. `toSolver()` — wraps the pipeline as a `Z3Solver` so the
##      familiar `add` / `check` / `model` surface applies.
##
## Why bother? For non-trivial constraint sets, running `simplify`
## first can fold redundant clauses, shrink the goal, and let the
## SMT solver decide faster (or at all). The pipeline is also a
## clean substrate for goal-property-driven tactic dispatch — see
## `examples/properties.nim` and the `z3/probe` module.
##
## Run with:
##
## ```
## nim c -r examples/tactic_pipeline.nim
## ```

import std/[strformat]
import z3

proc main() =
  let ctx = newContext()
  echo "libz3 ", z3FullVersion()

  # Constraint: find four distinct positive integers summing to 100,
  # with one of them at least 30. Small enough that simplify can fold
  # the sum-equation cleanly before SMT sees the problem.
  let a = mkIntVar("a")
  let b = mkIntVar("b")
  let c = mkIntVar("c")
  let d = mkIntVar("d")

  # Build the tactic pipeline. Each `mkTactic` lookup is by name —
  # the same names Z3 exposes via `(get-tactic-names)` in SMT-LIB.
  let pipeline = mkTactic("simplify").andThen(mkTactic("smt"))
  let s = pipeline.toSolver()

  s.add mkAnd(a > mkInt(0), b > mkInt(0), c > mkInt(0), d > mkInt(0))
  s.add a + b + c + d == mkInt(100)
  s.add mkDistinct(a, b, c, d)
  s.add mkOr(a >= mkInt(30),
             mkOr(b >= mkInt(30),
                  mkOr(c >= mkInt(30), d >= mkInt(30))))

  doAssert s.check() == zsSat,
    "pipeline failed to find a model for a sat problem"

  let m = s.model()
  let av = m.evalInt(a)
  let bv = m.evalInt(b)
  let cv = m.evalInt(c)
  let dv = m.evalInt(d)
  echo &"a={av}, b={bv}, c={cv}, d={dv}"
  echo &"sum = {av + bv + cv + dv}"
  echo &"max = {max(max(av, bv), max(cv, dv))}"

  # Invariants the example promises.
  doAssert av + bv + cv + dv == 100
  doAssert av != bv and av != cv and av != dv
  doAssert bv != cv and bv != dv
  doAssert cv != dv
  doAssert max(max(av, bv), max(cv, dv)) >= 30

when isMainModule:
  main()

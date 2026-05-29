## Pretty-printing and SMT2 workflow — shows how to inspect a
## constraint set, emit a runnable SMT2 script, and round-trip back
## through the parser. This is the "I need to debug this query" loop.
##
## Demonstrated:
##
## - `pretty(solver, indent, width)` — indented multi-line view that
##   stays readable for nested terms (vs. Z3's flat `$solver`).
## - `smt2Script(solver)` — self-contained file with declarations,
##   assertions, and `(check-sat)`. Pipe to the `z3` CLI for ablation
##   or feed to another solver.
## - `parseSmt2(ctx, source)` — read a script back into ASTs. Round-
##   trips with `smt2Script`.

import std/[strformat, strutils]
import z3

proc main() =
  let ctx = newContext()

  # Build a moderately complex constraint set.
  let x = mkIntVar("x")
  let y = mkIntVar("y")
  let z = mkIntVar("z")

  let s1 = newSolver()
  s1.add (x > 0) and (y > 0) and (z > 0)
  s1.add x + y + z == 30
  s1.add (x * x) + (y * y) < (z * z) + mkInt(100)

  echo "=== flat $ (Z3's own output) ==="
  echo $s1
  echo ""

  echo "=== pretty(s, width=40) ==="
  echo pretty(s1, width = 40)
  echo ""

  echo "=== smt2Script(s) — runnable input for the z3 CLI ==="
  let script = smt2Script(s1)
  echo script.indent(2)

  # Round-trip: parse the script back into a fresh solver under the
  # same context. Solver state after parseSmt2 is equivalent to s1.
  let asserts = parseSmt2(ctx, script)
  let s2 = newSolver()
  for a in asserts:
    s2.add a

  doAssert s2.check() == s1.check()
  echo &"round-trip preserved sat status: {s1.check()}"

when isMainModule:
  main()

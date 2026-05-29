## The headline example — finds integers `x, y` with `x + y == 10` and
## `x > 3`. If you only read one example, read this one.
##
## Run with:
##
## ```
## nim c -r examples/basic_solve.nim
## ```

import std/strformat
import z3

proc main() =
  # A Z3Context is the top-level handle every solver and AST is bound
  # to. Creating one also installs it as this thread's *current
  # context*, so subsequent builders (mkIntVar, mkInt, etc.) pick it
  # up without an explicit argument.
  let ctx = newContext()
  echo "libz3 ", z3FullVersion()

  # Free integer variables. Z3 hash-conses names, so two
  # `mkIntVar("x")` calls in the same context return the same AST.
  let x = mkIntVar("x")
  let y = mkIntVar("y")

  # A solver carries the working constraint set. `add` is the
  # primary surface; `assertConstraint` is an explicit alias.
  let s = newSolver()
  s.add (x + y == 10) and (x > 3)

  case s.check()
  of zsSat:
    let m = s.model()
    echo &"x = {m.evalInt(x)}, y = {m.evalInt(y)}"
    doAssert m.evalInt(x) + m.evalInt(y) == 10
    doAssert m.evalInt(x) > 3
  of zsUnsat:
    quit "unexpected: constraint should be satisfiable"
  of zsUnknown:
    quit &"z3 returned unknown: {s.reasonUnknown()}"

when isMainModule:
  main()

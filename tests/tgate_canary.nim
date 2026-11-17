## Canary for the memory gates: a planted bad release they must catch.
##
## A gate that only greps a leak summary passes on a use-after-free. Built
## with `-d:z3GateCanary`, this file plants one extra release of a
## wrapper-held reference: a `GC_unref` on a `Z3Context`, the reference
## every hook in `src/z3` releases with `` `=destroy`(v.ctx) ``. The
## context object is freed while a solver still holds it, and the solver's
## destroy then reads it (and, finding the count at zero again, frees the
## Z3 context a second time). `run-tests.sh asan-canary` and
## `valgrind-canary` build it that way and pass only when the tool fails
## the run AND names the invalid access (a heap-use-after-free from ASan,
## an `Invalid read` from valgrind): a crash alone does not count, since
## that is not the gate catching it. The CI asan job runs the former. Without the define the suite is skipped, so
## the file is harmless under `run-tests.sh test`.
##
## Why not a planted Z3-side dec_ref: on Z3 5.1 an extra
## `Z3_solver_dec_ref` is not visible at release time (a dec_ref at zero is
## ignored), and a premature one makes the next use of the object crash
## outright, which needs no gate to see. AST nodes live in Z3's own
## small-object pools, which neither tool sees into.

import std/unittest
import z3

when not defined(z3GateCanary):
  suite "gate canary":
    test "needs -d:z3GateCanary":
      skip()
else:
  proc plant() =
    var s: Z3Solver
    block:
      let ctx = newContext()
      s = newSolver(ctx)
      setCurrentContext(nil)
      # The planted defect: one release too many. `ctx` and `s` hold the
      # context's two references; after this and `ctx`'s own release at
      # block exit, the context is freed while `s` still points at it.
      GC_unref(ctx)
    # `s`'s destroy reads `s.ctx.raw` from the freed context.

  suite "gate canary":
    test "planted extra release of a Z3Context reference":
      plant()
      check true

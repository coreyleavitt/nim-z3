## `newScratchContext` tests — N10.12.
##
## `newScratchContext()` is a convenience constructor that allocates a
## fresh Z3 context and immediately enables concurrent dec_ref on it,
## making it ready to use as a worker-thread scratch space without a
## separate `enableConcurrentDecRef` call.

import std/[unittest]
import z3

suite "newScratchContext — tracer":
  test "newScratchContext() returns a non-nil context":
    let ctx = newScratchContext()
    check ctx != nil

suite "newScratchContext — basic operations":
  test "scratch context supports mkInt":
    let ctx = newScratchContext()
    withContext(ctx):
      let x = mkIntVar("x")
      check $x == "x"

  test "scratch context supports mkBool":
    let ctx = newScratchContext()
    withContext(ctx):
      let p = mkBoolVar("p")
      check $p == "p"

  test "scratch context supports solving a trivial constraint":
    let ctx = newScratchContext()
    withContext(ctx):
      let x = mkIntVar("x")
      let s = newSolver()
      s.add x == mkInt(42)
      check s.check() == zsSat
      check s.model().eval(x).toInt64 == 42

suite "newScratchContext — concurrent dec_ref idempotence":
  test "calling enableConcurrentDecRef on a scratch context is a no-op":
    ## The flag is already set by newScratchContext; a second call must
    ## not raise, crash, or corrupt the context.
    let ctx = newScratchContext()
    enableConcurrentDecRef(ctx)   # second call — must be idempotent
    withContext(ctx):
      let x = mkIntVar("x")
      let s = newSolver()
      s.add x > mkInt(0)
      check s.check() == zsSat

suite "newScratchContext — current context":
  test "newScratchContext() sets the calling thread's current context":
    ## Mirrors newContext() convention: after construction the new context
    ## is the current context for this thread.
    let ctx = newScratchContext()
    check currentContext() == ctx

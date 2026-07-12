## Slice A1 (RFC-fixedpoint-callbacks.md, ADR-FC-0005/0006/0008) —
## `Z3FixedpointHandlers` type + `setHandlers`/`handlers`/`hasHandlers`/
## `clearHandlers` + the in-query guard.
##
## Callbacks do **not** fire yet (A2/A3 wire the C-side shims). This
## slice only proves: the handlers record can be installed and read
## back, `hasHandlers` reflects it, `clearHandlers` resets the handler
## set WITHOUT dropping the box (ADR-FC-0008's sticky-box invariant),
## and `setHandlers` refuses to run while a query is on the stack
## (ADR-FC-0005).

import std/unittest
import z3
import z3/fixedpoint_callbacks

when defined(z3WithoutFixedpointCallbacks):
  # Module excluded: emit a single skip suite so CI reports it cleanly.
  suite "fixedpoint_callbacks — disabled build (-d:z3WithoutFixedpointCallbacks)":
    test "fixedpoint typed callbacks are compiled out":
      skip()

else:
  const N = 25
    ## Fixture iteration count; see `td3_ctx_release.nim` /
    ## `tfixedpoint_ctxbox.nim` for why a loop (not a single drop) makes
    ## a valgrind leak signal unambiguous.

  suite "A1 — Z3FixedpointHandlers storage + read-back":
    test "setHandlers with an empty (all-nil) handler set runs without raising; hasHandlers is false":
      let ctx = newContext()
      let fp = newFixedpoint(ctx)
      fp.setHandlers(Z3FixedpointHandlers())
      check not fp.hasHandlers()

    test "setHandlers with a non-nil newLemma closure is reflected by hasHandlers/handlers":
      let ctx = newContext()
      let fp = newFixedpoint(ctx)
      var lemmaCount = 0
      fp.setHandlers(Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc lemmaCount))
      check fp.hasHandlers()
      check fp.handlers.newLemma != nil
      check fp.handlers.predecessor == nil
      check fp.handlers.unfold == nil

    test "clearHandlers resets to all-nil but keeps the box alive (ADR-FC-0008 invariant)":
      let ctx = newContext()
      let fp = newFixedpoint(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        predecessor: proc() {.closure, raises: [].} = discard))
      check fp.hasHandlers()

      fp.clearHandlers()
      check not fp.hasHandlers()
      check fp.cbBoxRef != nil

    test "M1: handlersActive() is false before the first query, true after activation succeeds":
      ## `hasHandlers` reports installed intent; `handlersActive` reports
      ## whether the engine actually accepted the callbacks (the
      ## `exportActivated` latch). Before any query runs, activation
      ## hasn't happened yet even though a handler is installed.
      let ctx = newContext()
      let fp = newFixedpoint(ctx)
      let p = newParams(ctx)
      p.set("fp.engine", "spacer")
      fp.setParams(p)
      let pred = mkFuncDecl[(Z3Int,), Z3Bool](ctx, "P")
      fp.registerRelation(pred)
      let x = mkIntVar(ctx, "x")
      fp.addRule(pred(mkInt(ctx, 0)))
      fp.addRule(forall(x, pred(x).implies(pred(x + mkInt(ctx, 1)))))

      fp.setHandlers(Z3FixedpointHandlers(
        predecessor: proc() {.closure, raises: [].} = discard))
      check fp.hasHandlers()
      check not fp.handlersActive()  # not yet activated -- no query has run

      discard fp.query(pred(mkInt(-1)))
      check fp.handlersActive()  # engine accepted the callbacks

    test "M1: handlersActive() is false when no box exists at all":
      let ctx = newContext()
      let fp = newFixedpoint(ctx)
      check not fp.handlersActive()

    test "setHandlers trips the in-query guard (ADR-FC-0005)":
      let ctx = newContext()
      let fp = newFixedpoint(ctx)
      let p = newParams(ctx)
      p.set("fp.engine", "spacer")
      fp.setParams(p)
      let pred = mkFuncDecl[(Z3Int,), Z3Bool](ctx, "P")
      fp.registerRelation(pred)
      fp.addRule(pred(mkInt(ctx, 0)), "base")

      expect AssertionDefect:
        fp.withInQuery:
          fp.setHandlers(Z3FixedpointHandlers())

  suite "A1 — setHandlers/clearHandlers install cycle (valgrind leak proof)":
    test "fp + rooted box + non-nil closure env drop cleanly across N inner scopes":
      ## Each iteration's `newLemma` closure captures a fresh heap
      ## allocation (`newSeq[int](64)`) so the box AND the closure's
      ## captured environment must both be released for this to be
      ## leak-free — not just the box itself (already proven by
      ## `tfixedpoint_ctxbox.nim`).
      for i in 0 ..< N:
        block:
          let ctx = newContext()
          let fp = newFixedpoint(ctx)
          var captured = newSeq[int](64)
          captured[0] = i
          fp.setHandlers(Z3FixedpointHandlers(
            newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
              captured[0] = int(level)))
          fp.clearHandlers()
          # fp (and the box + closure env it roots) fall out of scope
          # when this block exits, below.
      check true

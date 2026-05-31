## `z3/concurrency` tests — per-thread isolation (v0.5 step 5).
##
## Exercises the wrapper's thread-safety contract documented in
## `docs/THREADING.md`:
##
##   1. Each thread gets its own `currentContext` slot via Nim's
##      `{.threadvar.}`. Calling `newContext()` in two threads
##      yields two distinct contexts.
##   2. A solver / model / AST is bound to the context of the
##      thread that created it. Multiple threads, each with its
##      own context, solve independently without interference.
##   3. `withContext(ctx): body` swaps the current-context slot
##      *for that thread only*; another thread's slot is untouched.
##   4. The per-context `datatypeRegistry` (v0.4 step 3) is isolated
##      per context — declaring a datatype in one thread's context
##      doesn't make it lookup-able from another thread's context.
##
## Documented UB (sharing handles across threads) is **not** tested
## here — that would crash the test runner rather than surface a
## clean `Z3Error`. See `docs/THREADING.md` "What's not safe".

import std/[unittest]
import z3

# Marker datatype for behaviour #4 — distinct from any other test
# file's markers to keep the registry namespace independent.
type
  ConcurrencyColor = object

suite "concurrency — tracer":
  test "two threads each get a distinct currentContext":
    var ctxAPtr, ctxBPtr: pointer
    var ready: array[2, bool]
    var threads: array[2, Thread[int]]

    proc body(idx: int) {.thread, gcsafe.} =
      # `{.gcsafe.}` asserted manually — every Z3 FFI call we make
      # is `{.cdecl.}` and doesn't touch Nim's heap. The softlink
      # layer indirects through a function pointer; Nim's safety
      # analysis can't see through it, so we vouch.
      {.cast(gcsafe).}:
        let ctx = newContext()
        if idx == 0:
          ctxAPtr = cast[pointer](ctx)
        else:
          ctxBPtr = cast[pointer](ctx)
        ready[idx] = true

    createThread(threads[0], body, 0)
    createThread(threads[1], body, 1)
    joinThreads(threads)

    check ready[0] and ready[1]
    check ctxAPtr != nil
    check ctxBPtr != nil
    check ctxAPtr != ctxBPtr

suite "concurrency — solver isolation":
  test "N threads each solve their own constraint independently":
    const N = 4
    var results: array[N, int]
    var threads: array[N, Thread[int]]

    proc body(idx: int) {.thread, gcsafe.} =
      {.cast(gcsafe).}:
        # Each thread's task: find an x such that x == idx + 100.
        # Trivial constraint; the goal is concurrency isolation, not
        # solving difficulty.
        let ctx = newContext()
        let x = mkIntVar("x")
        let s = newSolver()
        s.add x == mkInt(idx + 100)
        if s.check() == zsSat:
          results[idx] = s.model().eval(x).toInt
        else:
          results[idx] = -1  # sentinel for "didn't solve"

    for i in 0 ..< N:
      createThread(threads[i], body, i)
    joinThreads(threads)

    for i in 0 ..< N:
      check results[i] == i + 100

suite "concurrency — withContext is per-thread":
  test "thread A's withContext doesn't affect thread B's currentContext":
    # Both threads create their own context, then simultaneously enter
    # a `withContext` block. After the block, each thread's
    # currentContext should equal its own original — no cross-talk.
    var ctxAReady, ctxBReady: bool
    var ctxAPtr, ctxBPtr: pointer
    var insideAPtr, insideBPtr: pointer
    var afterAPtr, afterBPtr: pointer
    var threads: array[2, Thread[int]]

    proc body(idx: int) {.thread, gcsafe.} =
      {.cast(gcsafe).}:
        let myCtx = newContext()
        let scratch = newContext()
        # `newContext()` auto-sets `currentZ3Ctx` to the new ctx, so
        # creating `scratch` clobbered `myCtx`. Restore explicitly
        # before the `withContext` test — this is the documented
        # pattern for "create a context but keep current as before."
        setCurrentContext(myCtx)
        if idx == 0:
          ctxAPtr = cast[pointer](myCtx)
          ctxAReady = true
        else:
          ctxBPtr = cast[pointer](myCtx)
          ctxBReady = true
        # Wait until both threads have published their original ctx.
        # Bounded: if a thread panics before flagging, we want the
        # test runner to fail rather than hang indefinitely.
        var spinGuard = 0
        while not (ctxAReady and ctxBReady):
          inc spinGuard
          if spinGuard > 10_000_000: break
        doAssert ctxAReady and ctxBReady,
          "tconcurrency spin-wait timed out — a peer thread may have panicked"
        withContext(scratch):
          let inside = cast[pointer](currentContext())
          if idx == 0:
            insideAPtr = inside
          else:
            insideBPtr = inside
        let after = cast[pointer](currentContext())
        if idx == 0:
          afterAPtr = after
        else:
          afterBPtr = after

    createThread(threads[0], body, 0)
    createThread(threads[1], body, 1)
    joinThreads(threads)

    # Each thread's `withContext` saw its own `scratch`, not the other's.
    check insideAPtr != ctxAPtr
    check insideBPtr != ctxBPtr
    check insideAPtr != insideBPtr
    # After exiting `withContext`, each thread is back to its original.
    check afterAPtr == ctxAPtr
    check afterBPtr == ctxBPtr

suite "concurrency — datatypeRegistry is per-context":
  test "datatype declared in thread A's ctx isn't visible in thread B's ctx":
    # v0.4 step 3 introduced a per-context `datatypeRegistry` keyed by
    # marker-type name. Each `Z3Context` carries its own table, so
    # two threads with two contexts each running their own
    # `declareDatatype[ConcurrencyColor]` get independent registrations.
    # If the registry were process-global, the second call would
    # collide with the first; per-context isolation lets both succeed.
    var thrAOK, thrBOK: bool
    var threads: array[2, Thread[int]]

    proc body(idx: int) {.thread, gcsafe.} =
      {.cast(gcsafe).}:
        let ctx = newContext()
        # Declare a singleton datatype with one nullary constructor.
        # If isolation fails, the second thread to run would see a
        # populated registry for "ConcurrencyColor" and error.
        let dt = declareDatatype[ConcurrencyColor](
          [constructor("MkRed")])
        let s = newSolver()
        let c = mkDatatypeVar[ConcurrencyColor](dt, "c")
        # Trivial assertion to confirm the sort is wired up.
        s.add c == c
        let r = (s.check() == zsSat)
        if idx == 0:
          thrAOK = r
        else:
          thrBOK = r

    createThread(threads[0], body, 0)
    createThread(threads[1], body, 1)
    joinThreads(threads)

    check thrAOK
    check thrBOK

## The thread-exit handler that clears the current-context slot must
## not outlive its use.
##
## `newContext()` registers a handler with `onThreadDestruction` so the
## slot is cleared when a Nim thread ends. Nim keeps those handlers in a
## per-thread seq that it never frees, so whoever empties it must free
## it: nim-z3 removes its own entry when the handler runs or when the
## slot is cleared with `setCurrentContext(nil)`, and frees the list
## when it is left empty. Without that, every thread that makes a
## context leaks the list. A foreign thread (a raw pthread, where Nim's
## thread-exit handlers never run) has only `setCurrentContext(nil)`.
##
## The leaks are caught by LeakSanitizer (`run-tests.sh asan`); the
## handler counts below are observable without it. The raw-pthread case
## needs `-d:useMalloc` and is skipped without it (see the case).

import std/[posix, unittest]
import z3

proc handlerCount(): int =
  {.cast(gcsafe).}:
    nimThreadDestructionHandlers.len

# A second library's handler, written the way nelli writes its own: it
# removes itself and frees the list only when it leaves it empty.
var otherRanOnWorker: bool

proc otherHandler() {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    otherRanOnWorker = true
    for i in countdown(nimThreadDestructionHandlers.len - 1, 0):
      if rawProc(nimThreadDestructionHandlers[i]) ==
         cast[pointer](otherHandler):
        nimThreadDestructionHandlers.delete(i)
        break
    if nimThreadDestructionHandlers.len == 0:
      nimThreadDestructionHandlers = @[]

var
  armedAfterNew, afterClear, afterRearm, afterSecondClear: int
  otherAfterClear: int

proc nimWorker() {.thread.} =
  {.cast(gcsafe).}:
    let ctx = newContext()
    doAssert not ctx.raw.isNil

proc rearmWorker() {.thread.} =
  {.cast(gcsafe).}:
    discard newContext()
    armedAfterNew = handlerCount()
    setCurrentContext(nil)
    afterClear = handlerCount()
    setCurrentContext(nil)            # a second clear must not double-free
    afterSecondClear = handlerCount()
    discard newContext()              # re-arms; the exit handler frees
    afterRearm = handlerCount()

proc sharedWorker() {.thread.} =
  {.cast(gcsafe).}:
    discard newContext()              # nim-z3 registers first ...
    onThreadDestruction(otherHandler) # ... then another library

proc sharedClearWorker() {.thread.} =
  {.cast(gcsafe).}:
    onThreadDestruction(otherHandler)
    discard newContext()
    setCurrentContext(nil)
    otherAfterClear = handlerCount()  # only the other library's entry

var foreignAfterClear = -1

proc foreignWorker(arg: pointer): pointer {.noconv.} =
  {.cast(gcsafe).}:
    discard newContext()
    setCurrentContext(nil)
    foreignAfterClear = handlerCount()
  nil

suite "the thread-exit handler is removed and its list freed":
  test "a Nim thread that makes a context":
    var th: Thread[void]
    createThread(th, nimWorker)
    joinThread(th)

  test "clearing the slot disarms; a later context re-arms":
    var th: Thread[void]
    createThread(th, rearmWorker)
    joinThread(th)
    check armedAfterNew == 1
    check afterClear == 0
    check afterSecondClear == 0
    check afterRearm == 1

  test "another library's handler registered after nim-z3's still runs":
    otherRanOnWorker = false
    var th: Thread[void]
    createThread(th, sharedWorker)
    joinThread(th)
    check otherRanOnWorker

  test "clearing the slot leaves another library's handler in place":
    otherRanOnWorker = false
    var th: Thread[void]
    createThread(th, sharedClearWorker)
    joinThread(th)
    check otherAfterClear == 1
    check otherRanOnWorker

  test "a raw pthread that clears the slot before it ends":
    # Nim's own allocator keeps each thread's heap header in
    # thread-local storage and does no setup for a thread Nim did not
    # create, so a raw pthread allocating from it can crash in
    # `rawAlloc` (it does on the ubuntu-24.04 runners, with or without
    # this module's handler). Foreign threads need `-d:useMalloc`, which
    # is how `run-tests.sh asan` builds, so the case runs there.
    when not defined(useMalloc):
      skip()
    else:
      var t: Pthread
      check pthread_create(addr t, nil, foreignWorker, nil) == 0
      check pthread_join(t, nil) == 0
      check foreignAfterClear == 0

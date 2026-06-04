# Threading contract

> **Audience: users and contributors.** The wrapper's thread-safety
> story is small but precise. This file is the canonical statement of
> what's guaranteed and what isn't. See also:
> [GOTCHAS.md](GOTCHAS.md) (user-facing pitfalls),
> [PARITY.md](PARITY.md) (cross-family parity contract for new
> typed-family contributors),
> [INTERNAL_API.md](INTERNAL_API.md) (cross-module-internal seam).
> Tests covering this contract: `tests/tconcurrency.nim`.

## What's safe — per-thread `Z3Context`

**Each thread gets its own `Z3Context` via `newContext()`.** ASTs,
solvers, models, and any other handles you build from that context
belong to that thread. There's no global state shared between
threads except the library's load state (managed once on first
`newContext` per process via `ensureLoaded()`).

The mechanism: `currentContext` is a Nim `{.threadvar.}` (per-thread
storage). `newContext()` writes it; `currentContext()` reads it;
`setCurrentContext(ctx)` overrides it; `withContext(ctx): body`
scopes it for the duration of `body` and restores it via `finally`.
Each thread's slot is independent — thread A's `withContext` block
doesn't affect thread B's `currentContext()`.

The per-context `datatypeRegistry` (v0.4 step 3 — runtime
declarations of `Z3DatatypeValue[T]` sorts) is per-context, so
declaring a datatype in one thread doesn't pollute another thread's
context registry.

## What's not safe — sharing handles across threads

**Passing a handle (AST / solver / model / goal / tactic / etc.)
between threads is undefined behaviour.** Z3's own thread-safety
docs are explicit: a single `Z3_context` is not thread-safe; FFI
operations on one context from multiple threads simultaneously can
corrupt internal state. The wrapper inherits this contract — there
is no per-context lock, no copy-on-share, and no runtime check that
catches a cross-thread handle pass.

Common cases that are UB:
- Pinning a `Z3Solver` in a worker pool and submitting `add` /
  `check` from multiple threads.
- Building a `Z3Bool` in thread A and reading it in thread B's
  `withContext` block (the context is wrong).
- Sharing a `Z3Model` between the thread that called `check()` and
  another thread's analysis pass.

If you need cross-context AST transfer (for example, "the worker
returned a satisfying model; let me query it from the main thread"),
use the `z3/translate` module (v0.4 step 10):

```nim
let translated = translate(workerAst, mainCtx)
```

`translate[T: Z3Term]` is type-preserving and validated by Z3
internally — it's the only supported cross-context route.

## The one documented exception — `interrupt`

`Z3Context.interrupt()` is safe to call from **any** thread, even
while the owning thread is mid-`check()` / `optimize.check()` /
`fixedpoint.query()`. It sets Z3's internal cancellation flag,
which the decision procedures poll at safe points; the in-flight
call then returns `zsUnknown` (and `reasonUnknown()` reads
`"interrupted"`).

This is the only cross-thread operation on a `Z3Context` the
wrapper explicitly supports. Every other rule in this document
still applies — `interrupt` does not let you share solvers, models,
or ASTs; it just lets a watchdog thread cancel a long-running
operation owned by another thread.

```nim
# Watchdog pattern: spawn a thread that cancels after a deadline.
proc workerProc(ctx: Z3Context) {.thread, gcsafe.} =
  sleep(5_000)             # 5-second budget
  ctx.interrupt()           # signal the owner thread

var watchdog: Thread[Z3Context]
createThread(watchdog, workerProc, ctx)
let res = s.check()         # returns zsUnknown if the watchdog fired
joinThread(watchdog)
```

See [GOTCHAS.md §15](GOTCHAS.md#15-interruptctx-is-a-cross-thread-signal--same-thread-calls-are-no-ops)
for the full cross-thread semantics, the same-thread no-op caveat,
and the contrast with the in-thread `timeout` param.

## Pattern: parallel solving

The canonical "many independent SMT goals on a thread pool" shape
is one `Z3Context` per worker thread, created at thread start, used
exclusively by that thread, and dropped when the worker exits.
`docs/PARITY.md` §2 covers the ref-handle lifecycle; in particular,
`Z3Solver` carries a strong reference to its `Z3Context`, so the
context stays alive for the lifetime of the solver — workers don't
need to manage the context's refcount manually.

A subtle point worth noting: `newContext()` **auto-sets**
`currentContext` to the new context, so a worker creating multiple
contexts in sequence will see the last one as `currentContext()`
unless it explicitly restores. If a worker needs a "scratch"
context but wants to keep its primary current, the canonical
pattern is:

```nim
let primary = newContext()           # currentContext() == primary
let scratch = newContext()           # currentContext() == scratch
setCurrentContext(primary)           # restored
# ...do work with `primary` as current...
withContext(scratch):                # temporary swap
  # ...scratch is current here...
# ...primary is current again here...
```

`tests/tconcurrency.nim` ("withContext is per-thread" test)
exercises exactly this pattern.

## `newScratchContext` — a context that doesn't pollute `currentContext`

A common need in multi-context workflows is to spin up a short-lived
"scratch" context for a temporary computation (e.g., validity-check a
simplified form, test an interpolant) without overwriting the current
thread's active context. Because `newContext()` auto-sets
`currentContext` to the new context (so that `mkIntVar("x")` works
immediately without an explicit `ctx.mkIntVar("x")` call), naively
calling `newContext()` in the middle of a workflow disturbs the
threadvar.

The canonical pattern (and the backing of `newScratchContext()`) is:

```nim
proc newScratchContext*(): Z3Context =
  ## Creates a fresh Z3Context without side-effecting `currentContext`.
  let saved = currentContext()
  result = newContext()         # sets currentContext to result
  setCurrentContext(saved)      # restore the caller's context
```

`newScratchContext()` is a first-class export in `z3/context` since
v2.0.0. Prefer it over the manual save/restore pattern when the caller
wants a throwaway context and doesn't want `currentContext()` to change.

## `translate` — the only supported cross-context route

`translate[T: Z3Term](t, targetCtx): T` (in `z3/translate`) is the
one operation explicitly blessed for moving data across contexts. It
calls `Z3_translate` under the hood, which Z3 internally validates —
the operation is sound and the result is a fully independent handle in
`targetCtx`.

All other cross-context operations are **undefined behaviour**. In
particular:

- Passing a raw handle from context A to a proc that calls FFI functions
  with context B's raw handle is UB.
- Reading a `Z3Model` extracted from solver S in context A while context
  B's solver is mid-`check()` is UB even if the model's handles are
  not aliased.
- Storing a `Z3Bool` from thread A in a shared variable and calling
  `pretty(sharedBool)` from thread B is UB.

The wrapper does not currently insert runtime checks for cross-context
aliasing. The contract is advisory; violations corrupt Z3's internal
state silently.

## `global_param_*` — process-wide scope, not per-context

`setGlobalParam`, `getGlobalParam`, and `resetGlobalParams` (in
`z3/globalparams`) operate on Z3's **process-wide** parameter table, not
on any individual context. They are safe to call from any thread before
or after contexts exist — `ensureLoaded()` is called internally so no
context is required. However:

- `setGlobalParam` from thread A races with `setGlobalParam` from
  thread B unless the caller serialises them externally (e.g., set all
  global params at program start, before spawning workers).
- `resetGlobalParams()` reverts **all** params, including those set by
  other threads. Call it only when no other thread is actively
  reading global params.
- Per-context params (`Z3Params` passed to `setParams(solver, p)`) are
  strictly per-context and follow the one-context-one-thread rule. They
  do not interact with the process-wide global table.

The most common safe pattern: set all global params in `main()` before
spawning worker threads; never call `resetGlobalParams()` after
worker threads are running.

## `enableConcurrentDecRef` — experimental concurrent-refcount mode

Z3 4.12+ exposes an experimental concurrent-decrement-reference mode
that relaxes the strict one-context-one-thread rule for handle
destruction. When enabled, `Z3_dec_ref` on handles belonging to context
C becomes safe to call from any thread, not just C's owner thread.

The wrapper does **not** currently expose `enableConcurrentDecRef` as a
first-class API. The standard lifecycle hooks (`=destroy`) call
`Z3_dec_ref` on the thread that owns the handle, which is always the
owner thread under the one-context-one-thread contract. Enabling
concurrent decref is therefore a no-op under normal wrapper usage.

The mode becomes relevant if you manually `translate` a handle into a
second context (transferring ownership) and then have the first thread's
`=destroy` fire on the pre-translate handle after the second thread has
already driven the context forward. This corner case is only reachable
in unusual two-context ownership patterns; the safer alternative is to
ensure the owning thread drives all `=destroy` calls by structuring
lifetimes with `withContext` / explicit `reset`.

If you do need concurrent decref (e.g., a handle pool shared across
threads with explicit reference counting at the application layer),
call `Z3_enable_concurrent_dec_ref(ctx.raw)` via the raw FFI handle
before sharing any handles. The concurrent-decref mode applies
**per-context** — enabling it for context A does not affect context B.

## Memory-safety verification

The memory side of "safety" is covered by the `nimble valgrind`
task (v0.5 step 5B). It runs a representative subset of tests under
valgrind and gates on `definitely lost: 0 bytes`. Z3's program-
lifetime allocations show as "still reachable" (not a leak); Nim's
GC arena shows as "possibly lost" (not a leak); libz3 itself
triggers thousands of non-leak "Invalid read" warnings from its
hash-cons internals (benign in single-threaded use). The audit
runs ~3 minutes locally; full-suite coverage takes ~15 minutes and
is deferred to CI (currently blocked behind issue #1).

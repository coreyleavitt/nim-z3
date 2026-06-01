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

## Slice D3 (ADR-FC-0012, scope-corrected in Stage 3) — regression test for
## the missing `ctx: Z3Context` release in the two lifecycle-hook generators
## in `src/z3/lifecycle.nim`:
##
## 1. `emitRefcountLifecycle` — the `=destroy` for every ref-typed handle
##    (`Z3Solver`, `Z3Model`, `Z3Optimize`, ...). It dec_refs the raw
##    handle but never released the `ctx: Z3Context` field it holds.
## 2. `termDestroy` — the `=destroy` *body* shared by every value-typed
##    family (`Z3Ast`, `Z3BitVec`, `Z3Fp`, ...). Same omission.
##
## Under `--mm:orc` a custom `=destroy` REPLACES Nim's field-wise
## destruction entirely (ADR-FC-0011) — so an un-released `ctx` field
## leaks one strong reference to the owning `Z3Context` (and everything
## it owns: the Z3 context handle, its config, its two registry tables)
## every time a handle or value is destroyed.
##
## ## The threadvar-swap fixture idiom
##
## Both suites below follow `tests/tcontext_registry.nim`'s idiom (see its
## module doc for the full rationale): `newContext()` installs itself as
## this thread's `{.threadvar.}` current context, so a context that's
## merely let fall out of scope is still kept alive by that threadvar —
## valgrind reports it "still reachable", not "definitely lost", which
## would hide the very leak this test exists to catch. Swapping the
## threadvar to a fresh throwaway context INSIDE the same inner `block`,
## right before the block closes, leaves the local `ctx` binding (and
## everything that holds a `ctx` ref: the solver, model, or value handle
## under test) as the sole owner. When the block then exits, ORC drops
## that sole reference deterministically, in-process, where valgrind can
## observe the underlying `Z3ContextOwn` as genuinely unreachable — IF the
## fix under test is in place. Before the fix, the leaked `ctx` ref keeps
## `Z3ContextOwn` (and its `Z3_del_context`-backed native context) alive
## forever, with no live binding anywhere — a crisp "definitely lost"
## signal, not "still reachable".

import std/unittest
import z3

const N = 25
  ## Fixture iteration count. Large enough that a per-iteration leaked
  ## `Z3ContextOwn` produces a valgrind "definitely lost" total that
  ## can't be confused with an incidental few-byte leak elsewhere.

suite "D3 — ref-handle (Z3Solver/Z3Model) ctx release":
  test "fresh context + solver + model dropped in an inner scope, no outer ref":
    for i in 0 ..< N:
      block:
        let ctx = newContext()
        let s = newSolver(ctx)
        let x = mkIntVar(ctx, "x")
        s.add(x == mkInt(ctx, i))
        check s.check() == zsSat
        let m = s.model()
        check m != nil
        # Drop the threadvar's reference so `ctx` (and everything that
        # holds a ctx ref — s, x, m) is the sole owner of `ctx`; ORC
        # runs `=destroy` when this `block` exits below, in-process,
        # not at process exit. See module doc.
        discard newContext()
    check true

suite "D3 — value-type (Z3BitVec/Z3Int) ctx release":
  test "fresh context + bitvec/int values dropped in an inner scope, no outer ref":
    for i in 0 ..< N:
      block:
        let ctx = newContext()
        let bv = mkBitVecVar[32](ctx, "b")
        let lit = mkBitVec[32](ctx, i.uint64)
        let sum = bv + lit
        let iv = mkIntVar(ctx, "x")
        let ilit = mkInt(ctx, i)
        check (sum.ctx == ctx)
        check (iv + ilit).ctx == ctx
        # Drop the threadvar's reference so `ctx` (and every value that
        # holds a ctx ref — bv, lit, sum, iv, ilit) is the sole owner
        # of `ctx`; ORC runs `=destroy` when this `block` exits below.
        # See module doc.
        discard newContext()
    check true

when defined(z3CtxDestroyCount):
  # Second, more precise instrument (slice D3 report item (c)):
  # directly observe `Z3ContextOwn.=destroy` firing, rather than
  # inferring it from valgrind's aggregate leaked-bytes total. Compile
  # with `-d:z3CtxDestroyCount` to include this suite; the counter
  # lives in `z3/context` behind the same `when defined(...)` guard.
  suite "D3 — counting-hook: Z3ContextOwn.=destroy fires exactly 2N times":
    test "context-destroy counter rises by exactly 2N after N inner-scope drops":
      # Each iteration's `discard newContext()` (mid-block) creates a
      # one-off "dummy" context whose only purpose is to evict the
      # threadvar's reference to `ctx`; nothing else ever references
      # the dummy. It does NOT get destroyed immediately — it sits in
      # the threadvar until the NEXT iteration's `newContext()` call
      # evicts *it* in turn. So each iteration triggers exactly two
      # `=destroy` firings: the real `ctx` (once every local binding
      # that holds a ref to it — `ctx`, `s`, the `mkIntVar`/`mkInt`
      # temporaries — drops at block exit) and the PRIOR iteration's
      # dummy (evicted by this iteration's `newContext()` call, at the
      # top of the loop). The very first iteration's `newContext()`
      # evicts whatever dummy the prior suites left behind (counted,
      # since `before` was already captured); the very last iteration's
      # dummy is left hanging in the threadvar at test end (by design —
      # see module doc) and is NOT counted. Net: exactly 2*N firings.
      let before = z3CtxDestroyCounter
      for i in 0 ..< N:
        block:
          let ctx = newContext()
          let s = newSolver(ctx)
          s.add(mkIntVar(ctx, "x") == mkInt(ctx, i))
          check s.check() == zsSat
          discard newContext()
      check z3CtxDestroyCounter - before == 2 * N

## Slice C1a/C1b (RFC-fixedpoint-callbacks.md, ADR-FC-0008/0009) — the
## RFC's canonical integration-test file for the typed
## fixedpoint-callback surface (`docs/RFC-fixedpoint-callbacks.md:1099`).
## C1a covers behaviors (a) and (c); C1b (this revision) adds
## `collectLemmas`/`Z3LemmaLog` accumulation-and-compose tests (b) and
## an abort-from-handler test (d) to this same file. C2 added a
## `when defined(z3WithoutFixedpointCallbacks): suite ... skip()`
## same-file gate suite (`tspacer.nim`'s pattern) — see just below the
## imports.
##
## ## (a) — stable-box re-install (ADR-FC-0008)
##
## `setHandlers` used to allocate a **fresh** `FixedpointCtxBox` and
## re-root it on every call (`fp.cbBoxRef = cast[RootRef](newBox)`).
## Because Z3 has no callback-deregister call, `activateExportCallbacks`
## registers the box's raw pointer with Z3 as an opaque `state` at the
## *first* query, and Z3 keeps invoking the `{.cdecl.}` shims with that
## exact pointer for the rest of the `Z3Fixedpoint`'s life. A second
## `setHandlers` call under the old allocate-new scheme dropped the
## first box's only GC root (ORC frees it), while Z3 still held — and
## would still fire — that freed pointer as `state`: use-after-free. The
## fix makes `setHandlers` **reuse the existing box** (mutate
## `box.handlers` in place) once one has been allocated, so the Z3-side
## `state` pointer stays valid for `fp`'s whole lifetime and a
## previously-installed, now-nil'd-out handler simply goes **dormant**
## (the sticky shim reads `box.handlers` live and no-ops on a nil
## field) rather than being deregistered or dangling.
##
## The suite below proves: (1) the box pointer is identical across
## re-installs (stable-box, not reallocated), (2) nil'ing a handler via
## re-install makes it stop firing without a crash (dormancy, not a
## UAF — this is the case that crashed/used freed memory under the old
## allocate-new code), (3) swapping to a *different* non-nil handler on
## re-install fires the new one and not the old one (proves a real
## swap, not just dormancy).
##
## ## (c) — mixing hazard debug guard (ADR-FC-0009)
##
## The raw §N7.8 procs (`fp.init`, `fp.setReduceAssignCallback`,
## `fp.setReduceAppCallback`, `fp.addCallback`, in `z3/fixedpoint`) and
## the typed `setHandlers` surface (this module) both write the same
## Z3-side `state` slot / callback registration. Mixing them on the
## same `fp` — e.g. `setHandlers` then a raw `fp.init` — silently
## overwrites what the other surface depends on, producing
## type-confusion or a UAF on the next callback fire. A debug-only
## assert (`when not defined(release)`, the `inQuery`-guard idiom) on
## each surface's entry points makes the hazard loud instead of silent:
## the raw procs check `fp.cbBoxRef == nil` (the typed-surface tell —
## no separate flag needed for that half); `setHandlers` checks a new
## `fp.rawCbUsed` flag the raw procs set. Both checks are `assert`, so
## they trip `AssertionDefect` and are compiled out entirely (zero
## runtime cost) under `-d:release`/`-d:danger`.
##
## ## (b) — `collectLemmas`/`Z3LemmaLog` accumulation + compose (RFC §5)
##
## `collectLemmas(fp, base)` installs a `newLemma` closure that appends
## every `(lemma, level)` to a fresh, caller-owned `Z3LemmaLog`, chained
## AFTER `base.newLemma` (if any) so "collect AND run my own newLemma"
## is one call; `base.predecessor`/`base.unfold` pass through
## unchanged. The suite below proves: accumulation (N-entries,
## survives `clearHandlers`), compose-with-predecessor (both the log
## fills and the base handler fires), and compose-with-newLemma (both
## fire, same count, base-first ordering).
##
## ## (d) — abort-from-handler via `ctx.interrupt()` (RFC lines 1108-1113)
##
## A `newLemma` handler that calls the captured `Z3Context`'s
## `interrupt()` (never `fp` itself — capturing `fp` in a closure
## rooted on `fp`'s own box would be a reference cycle) makes the
## in-flight `query`/`queryFromLevel` return `zsUnknown` with
## `getReasonUnknown() == "interrupted"`, within a small, bounded
## number of further handler fires (proving Z3 polls the interrupt
## flag between callback firings within one query, not just between
## queries).

import std/[unittest, strutils]
import z3
import z3/fixedpoint_callbacks
import z3/spacer

when defined(z3WithoutFixedpointCallbacks):
  # Module excluded: emit a single skip suite so CI reports it cleanly.
  suite "fixedpoint_callbacks — disabled build (-d:z3WithoutFixedpointCallbacks)":
    test "fixedpoint typed callbacks are compiled out":
      skip()

else:
  proc mkChainFixture(ctx: Z3Context, suffix: string = ""):
      (Z3Fixedpoint, Z3FuncDecl[(Z3Int,), Z3Bool]) =
    ## Copied from `tests/tfixedpoint_newlemma.nim` (the Stage-0 firing
    ## fixture, `scratchpad/spike_q1c_p3share.nim`): engine=spacer, `P(0)`
    ## + `∀x. P(x) ⇒ P(x+1)`. `suffix` disambiguates relation/bound-var
    ## names when several fixtures share one `ctx`.
    let fp = newFixedpoint(ctx)
    let p = newParams(ctx)
    p.set("fp.engine", "spacer")
    fp.setParams(p)
    let pred = mkFuncDecl[(Z3Int,), Z3Bool](ctx, "P" & suffix)
    fp.registerRelation(pred)
    let x = mkIntVar(ctx, "x" & suffix)
    fp.addRule(pred(mkInt(ctx, 0)))
    fp.addRule(forall(x, pred(x).implies(pred(x + mkInt(ctx, 1)))))
    (fp, pred)

  suite "C1a(a) — stable-box re-install (ADR-FC-0008)":
    test "setHandlers reuses the SAME box across re-installs (stable-box proof)":
      let ctx = newContext()
      let (fp, _) = mkChainFixture(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          discard))
      let box1 = fp.cbBoxRef
      check box1 != nil

      fp.setHandlers(Z3FixedpointHandlers())  # re-install, all-nil
      let box2 = fp.cbBoxRef
      check box2 != nil
      check cast[pointer](box1) == cast[pointer](box2)

      fp.setHandlers(Z3FixedpointHandlers(
        predecessor: proc() {.closure, raises: [].} = discard))
      let box3 = fp.cbBoxRef
      check cast[pointer](box1) == cast[pointer](box3)

    test "dormant-not-deregistered: re-install with newLemma=nil stops it firing, no crash/UAF":
      ## RED under the old allocate-new `setHandlers`: Z3 still holds
      ## box1's (freed) pointer as `state` and fires the shim against it
      ## at the second query — a use-after-free, not just a wrong count.
      ## Run this test under `nimz3.sh valgrind` to see the "Invalid
      ## read"s that prove it, pre-fix.
      let ctx = newContext()
      var count = 0
      let (fp, pred) = mkChainFixture(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc count))

      let status1 = fp.query(pred(mkInt(-1)))
      check status1 == zsUnsat
      check count >= 1
      let firstCount = count

      fp.setHandlers(Z3FixedpointHandlers())  # newLemma -> nil: dormant
      check fp.cbBoxRef != nil  # box is still alive/rooted (sticky, ADR-FC-0008)

      let status2 = fp.query(pred(mkInt(-2)))
      check status2 == zsUnsat
      check count == firstCount  # dormant handler did not fire again

    test "re-install swap: a DIFFERENT non-nil handler fires after swap, the old one does not":
      let ctx = newContext()
      var countA = 0
      var countB = 0
      let (fp, pred) = mkChainFixture(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc countA))

      let status1 = fp.query(pred(mkInt(-1)))
      check status1 == zsUnsat
      check countA >= 1
      let countAAfterFirst = countA

      fp.setHandlers(Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc countB))

      let status2 = fp.query(pred(mkInt(-2)))
      check status2 == zsUnsat
      check countB >= 1
      check countA == countAAfterFirst  # the swapped-out handler never fires again

  suite "C1a(c) — mixing hazard debug guard (ADR-FC-0009)":
    test "(i) setHandlers then a raw §N7.8 proc (fp.init) trips AssertionDefect":
      let ctx = newContext()
      let fp = newFixedpoint(ctx)
      fp.setHandlers(Z3FixedpointHandlers())
      expect AssertionDefect:
        fp.init(nil)

    test "(ii) a raw §N7.8 proc (fp.addCallback) then setHandlers trips AssertionDefect":
      let ctx = newContext()
      let fp = newFixedpoint(ctx)
      fp.addCallback(nil, Z3FixedpointNewLemmaEh(nil),
                     Z3FixedpointPredecessorEh(nil), Z3FixedpointUnfoldEh(nil))
      expect AssertionDefect:
        fp.setHandlers(Z3FixedpointHandlers())

    test "(iii) a clean typed-only fp works without tripping (no false positive)":
      let ctx = newContext()
      let fp = newFixedpoint(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        predecessor: proc() {.closure, raises: [].} = discard))
      check fp.hasHandlers()
      fp.clearHandlers()
      check not fp.hasHandlers()

    test "(iii) a clean raw-only fp works without tripping (no false positive)":
      let ctx = newContext()
      let fp = newFixedpoint(ctx)
      fp.init(nil)
      fp.addCallback(nil, Z3FixedpointNewLemmaEh(nil),
                     Z3FixedpointPredecessorEh(nil), Z3FixedpointUnfoldEh(nil))
      check true

  suite "C1b(b) — collectLemmas/Z3LemmaLog accumulation":
    test "log accumulates N correctly-typed entries (cross-checked against a plain counter); survives clearHandlers":
      let ctx = newContext()
      var plainCount = 0
      let (fp, pred) = mkChainFixture(ctx)
      # Cross-check the exact fire count against a plain counter composed
      # in as `base.newLemma` -- collectLemmas' own appender fires once
      # per base call (see the "compose with base.newLemma" test below
      # for the general proof), so `log.len == plainCount` here pins down
      # the exact N for *this* fixture/query.
      let log = collectLemmas(fp, base = Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc plainCount))

      GC_fullCollect()
      let status = fp.query(pred(mkInt(-1)))
      GC_fullCollect()
      check status == zsUnsat
      check log.len > 1  # RFC: N>1 fires on the UNSAT counter-chain
      check log.len == plainCount
      for entry in log:
        check ($entry.lemma).len > 0
        check entry.level != high(uint)

      fp.clearHandlers()
      GC_fullCollect()
      # Entries must still be valid (independent inc_ref'd copies) after
      # the box's handler set (and thus the shim's own reference) is
      # cleared.
      check log.len > 1
      for entry in log:
        check ($entry.lemma).len > 0

  suite "C1b(b) — collectLemmas compose":
    test "compose with base.predecessor: both the log fills and the base handler fires":
      let ctx = newContext()
      var predecessorCount = 0
      let (fp, pred) = mkChainFixture(ctx)
      let log = collectLemmas(fp, base = Z3FixedpointHandlers(
        predecessor: proc() {.closure, raises: [].} =
          inc predecessorCount))

      let status = fp.query(pred(mkInt(-1)))
      check status == zsUnsat
      check log.len > 0
      check predecessorCount > 0

    test "compose with base.newLemma: both fire the same number of times, base-first ordering (falsifies a swap)":
      ## M4: the prior version of this test only asserted
      ## `order.len == baseNewLemmaCount` -- a pure COUNT, which cannot
      ## detect an ordering SWAP (if the log's own append ran BEFORE
      ## `base.newLemma` for a given event, `order.len` would still end
      ## up equal to `baseNewLemmaCount`, since `order` only ever records
      ## "base" once per event either way).
      ##
      ## Falsification technique: have `base` record `log.len` at the
      ## instant it runs, for every fire. Base-first composition
      ## (`combine(base, appender)` — `base` is `a`, the log-appending
      ## closure is `b`) means: at the i-th `base` call (0-indexed), the
      ## log must have EXACTLY `i` entries so far, because THIS event's
      ## append hasn't happened yet -- `base` always observes the log
      ## one append behind. A swap (appender-first) would make `base`
      ## observe `i + 1` at each call instead (the append for the
      ## CURRENT event would already be in the log). So
      ## `observedLenAtBase == @[0, 1, 2, ...]` proves base-first;
      ## anything else falsifies it.
      ##
      ## Verified against the real `collectLemmas`
      ## (`scratchpad/probe_m4_real.nim`: `observedLenAtBase=@[0, 1, 2]`
      ## on this exact fixture) and confirmed the technique itself is
      ## sound by hand-replicating both orderings via raw `setHandlers`
      ## (`scratchpad/probe_m4_swap.nim`): base-first yields
      ## `@[0, 1, 2]` (assertion holds), a manually swapped
      ## append-then-base composition yields `@[1, 2, 3]` (assertion
      ## trips) -- i.e. this test WOULD fail if `collectLemmas`/`combine`
      ## ever reversed the composition order.
      let ctx = newContext()
      var baseNewLemmaCount = 0
      var observedLenAtBase: seq[int] = @[]
      let (fp, pred) = mkChainFixture(ctx)
      var log: Z3LemmaLog  # forward-declared: the base closure below
                            # reads `log.len`, so `log` must already be
                            # in scope before `collectLemmas` (which
                            # constructs that closure) is called.
      log = collectLemmas(fp, base = Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          observedLenAtBase.add log.len
          inc baseNewLemmaCount))

      let status = fp.query(pred(mkInt(-1)))
      check status == zsUnsat
      check log.len > 0
      check log.len == baseNewLemmaCount
      check observedLenAtBase.len == baseNewLemmaCount
      for i, observedLen in observedLenAtBase:
        check observedLen == i  # base-first: the log hasn't grown for
                                 # THIS event yet when base observes it

  suite "M9 — combine() composition":
    ## `combine` extracts the base-first chaining logic `collectLemmas`
    ## hand-inlined (RFC §5, C1b) into a standalone, directly-testable
    ## combinator: `a`'s handler runs before `b`'s handler, per event
    ## field, for a caller who wants to install two independent handler
    ## sets on the same `fp` without writing the wrapper closures by
    ## hand.
    test "combine(a, b): both closures fire per newLemma event, a strictly before b (order proof)":
      let ctx = newContext()
      var order: seq[string] = @[]
      var countA = 0
      var countB = 0
      let (fp, pred) = mkChainFixture(ctx)
      let a = Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc countA
          order.add "a")
      let b = Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc countB
          order.add "b")
      fp.setHandlers(combine(a, b))

      let status = fp.query(pred(mkInt(-1)))
      check status == zsUnsat
      check countA > 0
      check countA == countB  # both fire once per event
      check order.len == countA + countB
      # a-before-b per event: pair up consecutive entries and check each
      # pair is exactly ("a", "b").
      for i in 0 ..< countA:
        check order[2 * i] == "a"
        check order[2 * i + 1] == "b"

    test "combine(a, b): predecessor and unfold also compose, a before b, independent of newLemma":
      let ctx = newContext()
      var predOrder: seq[string] = @[]
      var unfoldOrder: seq[string] = @[]
      let (fp, pred) = mkChainFixture(ctx)
      let a = Z3FixedpointHandlers(
        predecessor: (proc() {.closure, raises: [].} = predOrder.add "a"),
        unfold: (proc() {.closure, raises: [].} = unfoldOrder.add "a"))
      let b = Z3FixedpointHandlers(
        predecessor: (proc() {.closure, raises: [].} = predOrder.add "b"),
        unfold: (proc() {.closure, raises: [].} = unfoldOrder.add "b"))
      fp.setHandlers(combine(a, b))

      let status = fp.query(pred(mkInt(-1)))
      check status == zsUnsat
      check predOrder.len > 0
      check unfoldOrder.len > 0
      check predOrder.len mod 2 == 0
      check unfoldOrder.len mod 2 == 0
      for i in 0 ..< predOrder.len div 2:
        check predOrder[2 * i] == "a"
        check predOrder[2 * i + 1] == "b"
      for i in 0 ..< unfoldOrder.len div 2:
        check unfoldOrder[2 * i] == "a"
        check unfoldOrder[2 * i + 1] == "b"

    test "combine(a, b): a field set on only one side passes through unmolested (the other side stays nil)":
      let ctx = newContext()
      var predecessorCount = 0
      let (fp, pred) = mkChainFixture(ctx)
      let a = Z3FixedpointHandlers(
        predecessor: proc() {.closure, raises: [].} = inc predecessorCount)
      let b = Z3FixedpointHandlers()  # all-nil
      let combined = combine(a, b)
      check combined.newLemma == nil
      check combined.unfold == nil
      fp.setHandlers(combined)

      let status = fp.query(pred(mkInt(-1)))
      check status == zsUnsat
      check predecessorCount > 0

    test "collectLemmas uses combine internally: base-first ordering still holds (regression, no behavior change from the extraction)":
      let ctx = newContext()
      var baseCount = 0
      let (fp, pred) = mkChainFixture(ctx)
      let log = collectLemmas(fp, base = Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc baseCount))

      let status = fp.query(pred(mkInt(-1)))
      check status == zsUnsat
      check log.len > 0
      check log.len == baseCount

  suite "C1b(d) — abort-from-handler via ctx.interrupt()":
    ## Ground truth (established empirically,
    ## `scratchpad/spike_c1_step0_reason.nim`): `Z3Solver.reasonUnknown()`
    ## reads `"interrupted"` after `Z3Context.interrupt()` cancels an
    ## in-flight `check()` — matching `context.nim`'s existing
    ## `interrupt()` docstring and the RFC verbatim, so no correction was
    ## needed. `z3/fixedpoint`'s `runCancelableFixedpointQuery` (the
    ## always-on translation helper `query`/`queryRelations`/
    ## `queryFromLevel` now share) reports that same string via
    ## `getReasonUnknown` on a cancelled fixedpoint query, per the RFC's
    ## uniformity requirement — even though Spacer/Datalog's C-level
    ## cancellation mechanism (a thrown `Z3_EXCEPTION`, message
    ## `"canceled"`) is completely different from Solver's graceful
    ## `Z3_L_UNDEF` return.
    ##
    ## `mkChainFixture`'s counter-chain query (`pred(mkInt(-1))`, UNSAT)
    ## fires `newLemma` exactly 3 times to natural completion (verified:
    ## `scratchpad/probe_naturalcount2.nim`, stable across several
    ## unreachable targets). Interrupting on the very first fire must
    ## therefore stop the query well short of that — `fireCount < 3` is
    ## the natural-completion bound with headroom below it, not an
    ## arbitrary guess.

    test "abort a query from a newLemma handler: returns zsUnknown, reasonUnknown is Solver-consistent, fires bounded":
      let ctx = newContext()
      var fireCount = 0
      let (fp, pred) = mkChainFixture(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc fireCount
          if fireCount == 1:
            ctx.interrupt()))  # captures ctx, NOT fp -- see module doc (d)

      GC_fullCollect()
      let status = fp.query(pred(mkInt(-1)))
      GC_fullCollect()
      check status == zsUnknown
      check fp.getReasonUnknown() == "interrupted"
      check fireCount >= 1
      check fireCount < 3  # natural completion is 3 fires; this proves early stop

    test "abort a queryFromLevel from a newLemma handler: same contract":
      let ctx = newContext()
      var fireCount = 0
      let (fp, pred) = mkChainFixture(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc fireCount
          if fireCount == 1:
            ctx.interrupt()))

      GC_fullCollect()
      let status = fp.queryFromLevel(0, pred(mkInt(-1)))
      GC_fullCollect()
      check status == zsUnknown
      check fp.getReasonUnknown() == "interrupted"
      check fireCount >= 1
      check fireCount < 3

    test "non-cancellation regression: an uninterrupted query still returns its correct status, unflagged":
      ## Critical regression coverage: `query`/`queryFromLevel` now run
      ## through `runCancelableFixedpointQuery` for EVERY call, not just
      ## interrupted ones -- this proves the happy path is untouched by
      ## the new try/except wrapper (no accidental `zsUnknown`
      ## misdecoding, no `getReasonUnknown` false positive).
      let ctx = newContext()
      var fireCount = 0
      let (fp, pred) = mkChainFixture(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc fireCount))  # never calls ctx.interrupt()

      let status = fp.query(pred(mkInt(-1)))
      check status == zsUnsat            # correct status, not zsUnknown
      check fireCount == 3               # ran to natural completion
      check fp.getReasonUnknown() != "interrupted"

      # A second fp on the same ctx, queried via queryFromLevel, same check.
      let (fp2, pred2) = mkChainFixture(ctx, suffix = "2")
      let status2 = fp2.queryFromLevel(0, pred2(mkInt(-1)))
      check status2 == zsUnsat
      check fp2.getReasonUnknown() != "interrupted"

    test "a genuine (non-cancellation) Z3OperationError still propagates, not swallowed":
      ## `runCancelableFixedpointQuery`'s catch is narrowly discriminated
      ## on `.code == Z3_EXCEPTION and "canceled" in .msg` so it does NOT
      ## mask unrelated Z3-side faults as `zsUnknown`. Querying a
      ## relation that was never `registerRelation`-ed is a cheap,
      ## reliable way to force exactly this case: empirically
      ## (`scratchpad/probe_unregistered.nim`) it raises `Z3OperationError`
      ## (code `Z3_EXCEPTION`) with message
      ## `"Uninterpreted 'Unregistered' in <null>: ..."` -- a genuine
      ## `Z3_EXCEPTION` that does NOT contain "canceled", so the
      ## discriminator must (and does) let it propagate rather than
      ## decoding it as a cancelled/unknown query.
      let ctx = newContext()
      let fp = newFixedpoint(ctx)
      let p = newParams(ctx)
      p.set("fp.engine", "spacer")
      fp.setParams(p)
      let unregistered = mkFuncDecl[(Z3Int,), Z3Bool](ctx, "Unregistered")
      var caught = false
      try:
        discard fp.query(unregistered(mkInt(ctx, 0)))
      except Z3OperationError as e:
        caught = true
        check e.code == Z3_EXCEPTION
        check "canceled" notin e.msg
      check caught  # must propagate, not be swallowed as zsUnknown

  suite "M7 — clearHandlers / nil-box / no-handlers paths":
    ## Rounds out coverage of `clearHandlers` itself (as opposed to
    ## `setHandlers`-with-all-nil, already covered by C1a(a)'s
    ## "dormant-not-deregistered" test) and the "nothing was ever
    ## installed" paths through `handlers`/`hasHandlers`/`handlersActive`
    ## and `activateExportCallbacks`' `boxRef.isNil` early return.

    test "(a) clearHandlers trips the in-query guard (ADR-FC-0005), mirroring setHandlers's guard":
      ## Mirrors `tfixedpoint_handlers.nim`'s "setHandlers trips the
      ## in-query guard" test, for `clearHandlers`'s own `assert not
      ## fp.inQuery` (same guard, same rationale: resetting the handler
      ## set while Z3 holds a raw `state` pointer into the box mid-query
      ## is a use-after-free hazard class, even though `clearHandlers`
      ## doesn't reallocate the box -- the *handlers* it points at could
      ## still be mid-fire).
      let ctx = newContext()
      let fp = newFixedpoint(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        predecessor: proc() {.closure, raises: [].} = discard))
      expect AssertionDefect:
        fp.withInQuery:
          fp.clearHandlers()

    test "(b) clearHandlers on a fresh fp that never had setHandlers is a no-op, no crash":
      let ctx = newContext()
      let fp = newFixedpoint(ctx)
      check fp.cbBoxRef == nil
      fp.clearHandlers()
      check fp.cbBoxRef == nil  # still no box -- nothing was allocated
      check not fp.hasHandlers()

    test "(c) clearHandlers called twice in a row is idempotent":
      let ctx = newContext()
      let fp = newFixedpoint(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        predecessor: proc() {.closure, raises: [].} = discard))
      check fp.hasHandlers()

      fp.clearHandlers()
      check not fp.hasHandlers()
      let boxAfterFirst = fp.cbBoxRef
      fp.clearHandlers()  # second call on an already-cleared fp
      check not fp.hasHandlers()
      check fp.cbBoxRef == boxAfterFirst  # still the same sticky box (ADR-FC-0008)

    test "(d) a bare clearHandlers() (not a setHandlers all-nil re-install) actually stops a previously-firing handler":
      ## C1a(a)'s "dormant-not-deregistered" test proves dormancy through
      ## a `setHandlers(Z3FixedpointHandlers())` re-install. This proves
      ## the SAME dormancy property through the `clearHandlers` entry
      ## point specifically -- install a counting handler, query (count
      ## rises to the canonical fixture's exact count), `clearHandlers()`,
      ## query again, and confirm the count does NOT rise further.
      let ctx = newContext()
      var count = 0
      let (fp, pred) = mkChainFixture(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc count))

      let status1 = fp.query(pred(mkInt(-1)))
      check status1 == zsUnsat
      check count == 3  # canonical UNSAT fixture, same exact count as
                         # `tfixedpoint_newlemma.nim`'s M3-pinned tests
      let firstCount = count

      fp.clearHandlers()
      check not fp.hasHandlers()
      check fp.cbBoxRef != nil  # sticky box invariant still holds (ADR-FC-0008)

      let status2 = fp.query(pred(mkInt(-2)))
      check status2 == zsUnsat
      check count == firstCount  # dormant through clearHandlers: no further fires

    test "(e) handlers()/hasHandlers()/handlersActive() on a fp that never had setHandlers: safe defaults, no crash":
      let ctx = newContext()
      let fp = newFixedpoint(ctx)
      let h = fp.handlers
      check h.newLemma == nil
      check h.predecessor == nil
      check h.unfold == nil
      check not fp.hasHandlers()
      check not fp.handlersActive()

    test "(f) a query on an fp with no handlers ever installed: correct result, no crash (boxRef.isNil early return)":
      ## Exercises `activateExportCallbacks`' very first check
      ## (`if boxRef.isNil: return`) -- `withInQuery` still fires
      ## `exportActivateHook` on every query regardless of whether any
      ## handler was ever installed, so this is the only way to reach
      ## that early-return path at all.
      let ctx = newContext()
      let (fp, pred) = mkChainFixture(ctx)
      check fp.cbBoxRef == nil
      let status = fp.query(pred(mkInt(-1)))
      check status == zsUnsat
      check fp.cbBoxRef == nil  # still no box -- setHandlers was never called

  suite "L10(1) — empty Z3LemmaLog":
    ## Review finding L10 #1: a `Z3LemmaLog` that has never observed a
    ## `newLemma` fire -- here, a log installed via `collectLemmas` but
    ## read BEFORE any query runs -- must report `len == 0` and iterate
    ## as a genuinely empty sequence (the `items` iterator over
    ## `l.entries: seq[...]` is `for e in l.entries: yield e`, which is
    ## already safe over an empty seq by construction, but this pins it
    ## as an observed behavior of the public type rather than an
    ## un-exercised implementation detail).
    test "a fresh Z3LemmaLog (before any query) has len == 0; iterating items yields nothing, no crash":
      let ctx = newContext()
      let (fp, _) = mkChainFixture(ctx)
      let log = collectLemmas(fp)
      check log.len == 0
      var seen = 0
      for entry in log:
        inc seen
      check seen == 0

  suite "L10(2) — re-entrant read-only fp access from inside a handler":
    ## Review finding L10 #2: a handler that calls back into a
    ## read-only accessor on its OWN `fp` -- e.g. `hasHandlers()` /
    ## `handlersActive()`, which only read `box.handlers` /
    ## `box.exportActivated` and mutate nothing -- is a *re-entrancy*
    ## question, not a *concurrency* one (docs/THREADING.md's "Callback
    ## threading" section: callbacks run synchronously on the thread
    ## already inside `query()`). This is explicitly NOT a nested
    ## `fp.query()` call (unsupported, see the module's own C1b(d)
    ## abort-from-handler notes) -- just a read-only accessor call,
    ## proven safe here.
    ##
    ## This test intentionally captures `fp` itself in the handler
    ## closure, unlike C1b(d)'s `ctx.interrupt()` test (which
    ## deliberately captures `ctx`, NOT `fp`, to avoid a reference
    ## cycle -- see this file's module doc, section (d)). Capturing
    ## `fp` here is unavoidable (the accessors live on `fp`), which
    ## does create an `fp -> box -> handler-closure -> fp` reference
    ## cycle; `GC_fullCollect()` below forces ORC's cycle collector to
    ## run and confirms this is a memory-shape caveat, not a crash.
    test "a predecessor handler calling fp.hasHandlers()/fp.handlersActive() read-only does not crash; outer query completes normally":
      let ctx = newContext()
      var fires = 0
      var sawHasHandlers = false
      var sawActive = false
      let (fp, pred) = mkChainFixture(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        predecessor: proc() {.closure, raises: [].} =
          inc fires
          sawHasHandlers = fp.hasHandlers()
          sawActive = fp.handlersActive()))

      let status = fp.query(pred(mkInt(-1)))
      GC_fullCollect()
      check status == zsUnsat
      check fires > 0
      check sawHasHandlers
      check sawActive

  suite "L10(3) — exception-wall behavior inside a shim (CatchableError vs. Defect)":
    ## Review finding L10 #3. Ground truth established empirically
    ## (`scratchpad/probe_raises_l10.nim`, `probe_l10_catchable.nim`,
    ## `probe_l10_defect_compiles.nim`, `probe_l10_defect_abort.nim` --
    ## not part of this suite, kept as investigation artifacts):
    ##
    ## - Every handler field (`newLemma`/`predecessor`/`unfold`) is
    ##   typed `proc(...) {.closure, raises: [].}` (THREADING.md's
    ##   "compile-time backstop"). Nim's `raises` effect system tracks
    ##   `CatchableError` only, so a handler literal that directly
    ##   `raise`s a `CatchableError` subtype (e.g. `ValueError`) FAILS
    ##   TO COMPILE against that field type -- confirmed empirically:
    ##   `Error: ... can raise an unlisted exception: ref ValueError`.
    ##   The only way to get a genuine `CatchableError` to actually
    ##   reach a shim at runtime is to smuggle it past the type system
    ##   (e.g. an explicit `cast` from an untyped-raises proc, as the
    ##   test below does) -- a stand-in for a bug that defeats the
    ##   compile-time check by some other route (an FFI callback, an
    ##   effect-system gap, etc.). When that happens, each shim's
    ##   `try: ... except CatchableError: discard` (ADR-FC-0001) DOES
    ##   catch it: the query is not aborted, is not decoded as
    ##   `zsUnknown`, and later fires of the SAME handler still run --
    ##   pinned by the test below.
    ## - `Defect` (e.g. `raise newException(Defect, ...)`, or
    ##   `assert false` producing `AssertionDefect`) is NOT tracked by
    ##   `raises` at all, so it compiles into a handler literal with no
    ##   resistance, and `except CatchableError` does NOT catch it
    ##   (`Defect` is not a `CatchableError` subtype). Empirically
    ##   (`scratchpad/probe_l10_defect_abort.nim`, run manually against
    ##   the real `newLemmaShim`/`fp.query` path): the Defect unwinds
    ##   straight out of the `{.cdecl.}` shim frame -- exactly the
    ##   "undefined behavior" case ADR-FC-0001's module doc warns
    ##   about -- and the process terminates via Nim's unhandled-
    ##   exception path (`Error: unhandled exception: ... [Defect]`,
    ##   nonzero exit) before the query call can return at all. This is
    ##   intentional, not a bug to fix: Defects signal corrupted
    ##   process state, and swallowing one to keep a query "working"
    ##   would be unsound. Because there is no way to observe a
    ##   post-condition after that abort, a Defect-raising handler is
    ##   deliberately NOT exercised as an in-suite test here -- doing
    ##   so would abort this entire test binary (and, transitively, the
    ##   CI job) rather than reporting a clean pass/fail. The compile-
    ##   and runtime evidence above is pinned in this comment plus the
    ##   scratchpad probes instead.
    test "a genuine CatchableError that reaches a shim (smuggled past the raises:[] field type via cast) is swallowed; the query completes with the expected status and later fires still run":
      type RawNewLemma = proc(lemma: Z3AnyAst, level: uint) {.closure.}
      let ctx = newContext()
      var fires = 0
      var raisedOnFirst = false
      let (fp, pred) = mkChainFixture(ctx)
      let reallyRaises: RawNewLemma = proc(lemma: Z3AnyAst, level: uint) =
        inc fires
        if fires == 1:
          raisedOnFirst = true
          raise newException(ValueError, "boom (CatchableError, must be swallowed)")
      let unsafeHandler = cast[proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].}](reallyRaises)
      fp.setHandlers(Z3FixedpointHandlers(newLemma: unsafeHandler))

      let status = fp.query(pred(mkInt(-1)))
      check status == zsUnsat            # not zsUnknown -- the throw did not
                                          # get decoded as a cancellation
      check raisedOnFirst
      check fires == 3                   # canonical UNSAT fixture count -- the
                                          # throw on fire #1 did not stop
                                          # fires #2/#3 from happening

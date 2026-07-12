## Slice A2 (RFC-fixedpoint-callbacks.md, ADR-FC-0001/0007/0008) —
## `newLemma` fires for real: the `{.cdecl.}` shim + the
## `Z3_fixedpoint_add_callback` registration, gated behind the Spacer
## param pair `fp.spacer.p3.share_lemmas` / `fp.spacer.p3.share_invariants`
## that `setHandlers` sets automatically when a `newLemma` handler is
## installed (RFC lines 1029-1043; `context::new_lemma_eh`,
## `spacer_context.cpp:4286-4304`, gates dispatch behind those two
## params — see `scratchpad/spike_q1c_p3share.nim`, the Stage-0 proof).
##
## Fixture: a linear counter chain — `P(0)` plus the inductive rule
## `∀x. P(x) ⇒ P(x+1)` — under `engine=spacer`. Querying `P(target)`
## for a large negative `target` is UNSAT (never reachable by the
## chain); a small positive `target` is SAT. Both cases drive Spacer
## through enough induction levels to discover lemmas.
##
## The A2-time open note ("does the param pair change *solving*
## behavior, not just gate the callback?") was probed separately
## (`scratchpad/spike_a2_p3share_perturb.nim`, no callback registered
## either way): status and every SPACER-*/conflicts/decisions/
## propagations/arith-* stat were bit-identical between the params on
## and off; only memory-bookkeeping counters (`num-allocs`,
## `max-memory`, `memory`) differed, plus two near-zero timer keys that
## appear/disappear from the stats table (threshold-rounding noise, not
## a decision-count change). Conclusion: **callback-gate-only** — the
## `setHandlers` auto-set is safe and does not perturb the caller's
## solve. Kept as built (see `fixedpoint_callbacks.nim`'s `setHandlers`
## doc for the recorded finding).
##
## Also covers an A2-discovered **RFC-vs-Z3 divergence**: the RFC
## claims installing an export handler under a non-Spacer engine is "a
## silent no-op at the Z3 level" — false for `newLemma` specifically, Z3
## raises `Z3_EXCEPTION` from `Z3_fixedpoint_add_callback` itself when
## the engine isn't `spacer` at registration time. `setHandlers` catches
## that one error and restores the documented no-op contract at the
## wrapper boundary; the "engine=datalog" and "unset engine" suites
## below are the regression proof (see `fixedpoint_callbacks.nim`'s
## `setHandlers` doc for the full account).

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
    ## Fixture iteration count for the leak/teardown pass — see
    ## `tfixedpoint_handlers.nim` for why a loop (not a single drop)
    ## makes a valgrind leak signal unambiguous.

  proc mkChainFixture(ctx: Z3Context, suffix: string = ""):
      (Z3Fixedpoint, Z3FuncDecl[(Z3Int,), Z3Bool]) =
    ## The Stage-0 firing fixture (`spike_q1c_p3share.nim`): engine=spacer,
    ## `P(0)` + `∀x. P(x) ⇒ P(x+1)`. `suffix` disambiguates the relation/
    ## bound-variable names when several fixtures share one `ctx` (the
    ## leak-proof loop below).
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

  suite "A2 — newLemma fires via setHandlers (Spacer engine)":
    test "newLemma fires exactly 3 times on an UNSAT counter-chain query; lemma renders, level is plausible":
      ## M3: `mkChainFixture` / `pred(mkInt(-1))` is the canonical UNSAT
      ## fixture shared with `tfixedpoint_typed_callbacks.nim` (whose
      ## non-cancellation regression test independently pins the same
      ## `newLemma`-alone count to 3 on this fixture). Empirically
      ## confirmed exact and stable — 5 consecutive runs, both `c` and
      ## `cpp` backends, zero variance — before hardcoding; a
      ## latch/double-registration regression that fired 1x or more/
      ## fewer than 3x would silently pass a weaker `>= 1` bound.
      let ctx = newContext()
      var count = 0
      var lastRender = ""
      var lastLevel = high(uint)
      let (fp, pred) = mkChainFixture(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc count
          lastLevel = level
          try:
            lastRender = $lemma
          except CatchableError:
            discard))

      let status = fp.query(pred(mkInt(-1)))  # unreachable by the chain -> UNSAT
      check status == zsUnsat
      check count == 3
      check lastRender.len > 0
      check lastLevel != high(uint)  # a real level was observed (uint, so always >= 0)

    test "newLemma fires >=1 time on a SAT counter-chain query":
      let ctx = newContext()
      var count = 0
      var lastRender = ""
      let (fp, pred) = mkChainFixture(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc count
          try:
            lastRender = $lemma
          except CatchableError:
            discard))

      let status = fp.query(pred(mkInt(3)))  # reachable in 3 steps -> SAT
      check status == zsSat
      check count >= 1
      check lastRender.len > 0

    test "negative control: setHandlers with no newLemma handler never fires, does not crash":
      let ctx = newContext()
      let (fp, pred) = mkChainFixture(ctx)
      fp.setHandlers(Z3FixedpointHandlers())  # all-nil

      let status = fp.query(pred(mkInt(-1)))
      check status == zsUnsat
      check not fp.hasHandlers()

    test "engine=datalog (non-Spacer): setHandlers(newLemma: ...) installs without raising, and the handler never fires (RFC's documented silent-no-op contract, restored at the wrapper boundary -- see setHandlers doc)":
      ## Z3 itself raises `Z3_EXCEPTION` from `Z3_fixedpoint_add_callback`
      ## when a non-nil `newLemmaEh` is registered under a non-Spacer
      ## engine (empirically found at A2 -- see `setHandlers`' doc
      ## comment) rather than the RFC-promised silent no-op.
      ## `setHandlers` catches that specific error so install order never
      ## matters and this regression can never resurface unnoticed.
      let ctx = newContext()
      let fp = newFixedpoint(ctx)
      let p = newParams(ctx)
      p.set("fp.engine", "datalog")
      fp.setParams(p)
      var count = 0
      fp.setHandlers(Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc count))
      check fp.hasHandlers()

      let rel = mkFuncDecl[(Z3BitVec[8],), Z3Bool]("DL")
      fp.registerRelation(rel)
      fp.addFact(rel, @[1u])
      let status = fp.query(rel(mkBitVec[8](1)))
      check status == zsSat
      check count == 0  # Spacer-only callback: never fires under datalog.

    test "unset engine (auto-config default): setHandlers(newLemma: ...) installs without raising":
      ## Companion to the explicit `engine=datalog` case above: the
      ## default `auto-config` engine (no `setParams` call at all --
      ## matches `tfixedpoint_handlers.nim`'s A1 install-cycle tests)
      ## already resolves to a concrete non-Spacer engine internally by
      ## the time `setHandlers` registers the callback, so this exercises
      ## the same catch path without the caller ever mentioning an engine.
      let ctx = newContext()
      let fp = newFixedpoint(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          discard))
      check fp.hasHandlers()

  suite "A2-redesign — lazy activation at the query choke point":
    test "order-independence: setHandlers BEFORE engine=spacer still fires (the RED bug -- dead handler under eager registration)":
      ## Eager (install-time) registration is order-dependent: at
      ## `setHandlers` time the engine is still the default `auto-config`
      ## (non-Spacer by the time registration would run), so
      ## `Z3_fixedpoint_add_callback` would raise and be swallowed, and
      ## `newLemma` would never fire even though the caller correctly
      ## selects Spacer *afterward*, before ever querying. Lazy
      ## activation at the query choke point defers the engine-support
      ## decision to query time, when the engine is final, so this order
      ## must fire.
      ## `mkChainFixture` sets `engine=spacer` itself, so this test builds
      ## the chain fixture manually to control ordering: `setHandlers`
      ## strictly before `setParams(engine=spacer)`, both strictly before
      ## `query`.
      let ctx = newContext()
      var count = 0
      let fp = newFixedpoint(ctx)
      let pred = mkFuncDecl[(Z3Int,), Z3Bool](ctx, "P")
      fp.registerRelation(pred)
      let x = mkIntVar(ctx, "x")
      fp.addRule(pred(mkInt(ctx, 0)))
      fp.addRule(forall(x, pred(x).implies(pred(x + mkInt(ctx, 1)))))

      fp.setHandlers(Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc count))
      let p = newParams(ctx)
      p.set("fp.engine", "spacer")
      fp.setParams(p)  # engine chosen AFTER setHandlers

      let status = fp.query(pred(mkInt(-1)))
      check status == zsUnsat
      check count == 3  # M3: same canonical UNSAT fixture -- exact count confirmed above

    test "idempotency: activation latches after the first successful query -- a second query on the same fp/box neither re-registers nor breaks":
      ## Complements the order-independence test: proves the OTHER half
      ## of the `exportActivated` design ("register at most once
      ## successfully per box") without depending on a mid-lifetime
      ## engine change. A genuine "retry across an engine CHANGE" test
      ## (setHandlers -> query(datalog) -> setParams(spacer) -> query
      ## fires) is **not constructible against real Z3** on a single
      ## `Z3Fixedpoint` -- once any engine-touching operation runs
      ## (including the activation hook's own `add_callback` call, which
      ## itself triggers Z3's `ensure_engine()`), Z3 permanently locks in
      ## whichever engine was resolved at that moment; a later
      ## `Z3_fixedpoint_set_params(engine=...)` is empirically a no-op
      ## for that instance's remaining lifetime -- see
      ## `scratchpad/spike_a2redesign_engine_lock.nim` for the source
      ## citation (`dl_context.cpp`'s `context::ensure_engine`'s
      ## `if (!m_engine.get())` one-shot guard) and the direct empirical
      ## confirmation (post-switch statistics contain no `SPACER-*` keys
      ## at all). Flagged as a blocker in the task handoff rather than
      ## silently dropped or faked.
      let ctx = newContext()
      var count = 0
      let (fp, pred) = mkChainFixture(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc count))

      let status1 = fp.query(pred(mkInt(-1)))
      check status1 == zsUnsat
      let firstCount = count
      check firstCount == 3  # M3: same canonical UNSAT fixture -- exact count confirmed above

      # Same fp, same box, same (already-activated) handler set: query
      # again. Must not crash, must not double-register (a second
      # `add_callback` on the same shim would be redundant, not a
      # crash risk here, but the guard existing at all is what this
      # proves indirectly -- no assertion failure, no raised error, and
      # firing continues normally).
      let status2 = fp.query(pred(mkInt(-2)))
      check status2 == zsUnsat
      # M3: `pred(mkInt(-2))` on this same fixture also fires newLemma
      # exactly 3 times (empirically confirmed, 5 runs x 2 backends, zero
      # variance) -- pin the total, not just "more than before", so a
      # regression that fires e.g. 1 or 12 extra times on the second
      # query cannot slip past a weaker `>` bound.
      check count == firstCount + 3

    test "H1: a handler field that goes nil->non-nil via a LATER setHandlers call fires after activation already latched (latent-registration bug)":
      ## H1 bug: `activateExportCallbacks` used to register a real shim
      ## pointer ONLY for handler fields that were non-nil AT THE MOMENT
      ## of the first successful activation, then latched
      ## `exportActivated = true` forever. Since Z3 has no re-register
      ## API, a field that was nil at first activation and set non-nil
      ## by a LATER `setHandlers` call on the same `fp` could never fire
      ## -- `activateExportCallbacks` early-returns on
      ## `box.exportActivated` before it ever looks at the new field.
      ##
      ## Fixture: install a predecessor-only handler, query (predecessor
      ## must fire -- this is what latches `exportActivated`), THEN
      ## `setHandlers` a newLemma handler, query again on the SAME fp.
      ## Pre-fix, `newLemmaCount` stays 0 forever even though
      ## `fp.handlers.newLemma != nil`. Post-fix (always registering all
      ## three shims unconditionally at first activation -- each shim
      ## already nil-guards on the LIVE `box.handlers` field at fire
      ## time), the revival fires with zero re-registration.
      let ctx = newContext()
      var predecessorCount = 0
      var newLemmaCount = 0
      let (fp, pred) = mkChainFixture(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        predecessor: proc() {.closure, raises: [].} =
          inc predecessorCount))

      let status1 = fp.query(pred(mkInt(-1)))
      check status1 == zsUnsat
      check predecessorCount >= 1  # activation latched here

      fp.setHandlers(Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc newLemmaCount))
      check fp.handlers.newLemma != nil

      let status2 = fp.query(pred(mkInt(-2)))
      check status2 == zsUnsat
      check newLemmaCount > 0  # RED pre-fix: stays 0 forever

  suite "A3 — predecessor + unfold fire via the same lazy activation path":
    test "predecessor fires exactly 4 times on a counter-chain query, no newLemma installed":
      ## RED proof: the pre-A3 activation gate is `box.exportActivated or
      ## box.handlers.newLemma == nil` -- a predecessor-only install has
      ## `newLemma == nil`, so activation is skipped entirely and
      ## `predecessorShim` never gets registered, even though Z3's Spacer
      ## engine would happily fire it. This must fail (count == 0) before
      ## the gate is generalized to "no export handler at all".
      ##
      ## M3: exact count empirically confirmed (5 runs x 2 backends, zero
      ## variance) on the canonical UNSAT fixture -- see the A2 UNSAT
      ## test above for the general note on why exact beats `>= 1` here.
      let ctx = newContext()
      var count = 0
      let (fp, pred) = mkChainFixture(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        predecessor: proc() {.closure, raises: [].} =
          inc count))

      let status = fp.query(pred(mkInt(-1)))
      check status == zsUnsat
      check count == 4

    test "unfold fires exactly 1 time on a counter-chain query, no newLemma installed":
      ## M3: exact count empirically confirmed (5 runs x 2 backends, zero
      ## variance) on the canonical UNSAT fixture.
      let ctx = newContext()
      var count = 0
      let (fp, pred) = mkChainFixture(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        unfold: proc() {.closure, raises: [].} =
          inc count))

      let status = fp.query(pred(mkInt(-1)))
      check status == zsUnsat
      check count == 1

    test "all three (newLemma + predecessor + unfold) fire on one query, exact counts":
      ## M3: exact counts empirically confirmed (5 runs x 2 backends,
      ## zero variance) on the canonical UNSAT fixture -- matches each
      ## handler's individually-pinned count above (3/4/1), proving the
      ## three don't perturb each other's fire count when installed
      ## together.
      let ctx = newContext()
      var newLemmaCount = 0
      var predecessorCount = 0
      var unfoldCount = 0
      let (fp, pred) = mkChainFixture(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        newLemma: (proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc newLemmaCount),
        predecessor: (proc() {.closure, raises: [].} =
          inc predecessorCount),
        unfold: (proc() {.closure, raises: [].} =
          inc unfoldCount)))

      let status = fp.query(pred(mkInt(-1)))
      check status == zsUnsat
      check newLemmaCount == 3
      check predecessorCount == 4
      check unfoldCount == 1

    test "selective nil: newLemma-only install leaves predecessor/unfold counters at 0, no crash":
      ## Proves nil fptrs are actually passed for the absent handlers
      ## (not, say, a stale non-nil shim left registered from a prior
      ## install on the same box).
      ##
      ## M3: `newLemmaCount`'s exact value (3) is empirically confirmed,
      ## matching the standalone newLemma-only test above; `predecessorCount`/
      ## `unfoldCount` were already exact (`== 0`) and are left as-is.
      let ctx = newContext()
      var newLemmaCount = 0
      var predecessorCount = 0
      var unfoldCount = 0
      let (fp, pred) = mkChainFixture(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          inc newLemmaCount))

      let status = fp.query(pred(mkInt(-1)))
      check status == zsUnsat
      check newLemmaCount == 3
      check predecessorCount == 0
      check unfoldCount == 0

    test "selective nil, symmetric: predecessor-only install leaves newLemma counter at 0, no crash":
      ## M3: `predecessorCount`'s exact value (4) is empirically confirmed,
      ## matching the standalone predecessor-only test above; `newLemmaCount`
      ## was already exact (`== 0`) and is left as-is.
      let ctx = newContext()
      var newLemmaCount = 0
      var predecessorCount = 0
      let (fp, pred) = mkChainFixture(ctx)
      fp.setHandlers(Z3FixedpointHandlers(
        predecessor: proc() {.closure, raises: [].} =
          inc predecessorCount))

      let status = fp.query(pred(mkInt(-1)))
      check status == zsUnsat
      check predecessorCount == 4
      check newLemmaCount == 0

  suite "A2 — newLemma install/fire/teardown cycle (valgrind leak proof)":
    test "fp + box + firing closure capture drop cleanly across N inner scopes":
      ## Each iteration's `newLemma` closure captures a fresh heap
      ## allocation so the box AND the closure's captured environment
      ## (plus every `Z3AnyAst` the shim wraps and hands to it) must all
      ## be released for this to be leak-free.
      ##
      ## One `Z3Context` shared across all `N` iterations (not fresh per
      ## iteration, unlike the sibling suites above) -- deliberate.
      ## Bisection (`scratchpad/spike_a2_newctx_leak.nim`) isolated a
      ## small **pre-existing, A2-unrelated** "definitely lost" leak that
      ## appears whenever `Z3Fixedpoint.registerRelation` runs against
      ## repeated *fresh* `Z3Context`s in a tight loop -- reproduces
      ## identically with the datalog engine, zero quantifiers, and zero
      ## callback code, so it is not this slice's shim/registration path.
      ## It doesn't reproduce here because `ctx` is reused; that isolates
      ## *this* proof to what A2 actually adds (box + closure capture +
      ## the shim's `wrap[Z3AnyAst]` per fire) while leaving the
      ## unrelated finding written up for a follow-on ticket rather than
      ## silently laundered through a weaker test.
      let ctx = newContext()
      for i in 0 ..< N:
        block:
          var captured = newSeq[int](64)
          captured[0] = i
          let (fp, pred) = mkChainFixture(ctx, $i)
          fp.setHandlers(Z3FixedpointHandlers(
            newLemma: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
              captured[0] = int(level)))
          discard fp.query(pred(mkInt(ctx, -1)))
          # fp (and the box + closure env it roots) fall out of scope
          # when this block exits, below.
      check true

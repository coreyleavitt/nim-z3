## `z3/fixedpoint_callbacks` — typed-callback surface for
## `Z3Fixedpoint` (RFC-fixedpoint-callbacks.md, Stage A).
##
## Slice A0 built the box scaffolding (`FixedpointCtxBox`, rooted via
## `Z3FixedpointOwn.cbBox`). Slice A1 added the typed handler record and
## the install/read-back/clear surface. Slice A2 made `newLemma`
## actually fire and re-architected activation timing — see "Lazy
## activation" below; it supersedes ADR-FC-0008's install-time
## `Z3_fixedpoint_add_callback` call while keeping that ADR's
## sticky-box invariant intact. Slice A3 adds `predecessor` and
## `unfold` through the same lazy path. Slice C1b adds
## `collectLemmas`/`Z3LemmaLog` — the lemma-accumulation convenience
## built on top of the same `setHandlers` surface (RFC §5).
##
## - `Z3FixedpointHandlers` — three Spacer-engine export closures
##   (`newLemma`, `predecessor`, `unfold`; reduce fields are cut from
##   v2.1.0 — see the raw §N7.8 procs in `z3/fixedpoint` for reduce).
## - `setHandlers`/`handlers`/`hasHandlers`/`clearHandlers` — install,
##   read back, test, and reset the handler set on a `Z3Fixedpoint`.
##   `setHandlers` is **pure intent-recording** — it never touches Z3's
##   engine-gated registration call, so it never raises on engine
##   grounds and install order relative to `setParams(engine=...)`
##   never matters.
## - `Z3LemmaLog`/`collectLemmas` — a `newLemma` convenience that
##   accumulates every fired `(lemma, level)` into a caller-owned,
##   iterable log, and **composes** with a caller-supplied `base`
##   handler set (`base.newLemma` runs first, `base.predecessor`/
##   `base.unfold` pass through unchanged) rather than replacing it —
##   see `collectLemmas`' doc comment.
##
## **All three export handlers fire (A2/A3), activated lazily at query
## time.** Intent (`setHandlers`) and Z3-side activation are separated:
## `setHandlers` only records the handler set on the box;
## `activateExportCallbacks` (below) — reached via the
## `z3/fixedpoint.exportActivateHook` seam fired from the single
## `withInQuery` choke point — registers all three of
## `newLemmaShim`/`predecessorShim`/`unfoldShim` **unconditionally**
## (each a `{.cdecl.}` thunk behind the mandatory exception wall,
## ADR-FC-0001; never `nil`, regardless of which handler fields are
## non-nil at that moment — H1 fix, see below) via a single
## `Z3_fixedpoint_add_callback` call, and unconditionally auto-sets the
## Spacer param gate (`fp.spacer.p3.share_lemmas`/`share_invariants`)
## that Z3 requires for `new_lemma_eh` dispatch — the first time (and
## only the first successful time) any query runs with at least one
## non-nil export handler installed. Each shim nil-guards on the LIVE
## `box.handlers.X` field at fire time, so an unset field simply does
## nothing until a later `setHandlers` call sets it — **H1 fix**: the
## original design registered a real shim pointer only for fields
## non-nil at that first-activation moment, which meant a field set
## non-nil by a *later* `setHandlers` call could never fire (Z3 has no
## re-register API, and `exportActivated` had already latched); always
## registering all three up front makes that nil->non-nil revival work
## for every field, for free. See `activateExportCallbacks`'s doc
## comment for the source citation, the empirical no-perturbation
## proof, the engine-detection investigation, and the idempotency/retry
## design.
##
## ## Build gate (ADR-FC-0006)
##
## The entire module body is guarded by
## `when not defined(z3WithoutFixedpointCallbacks):` — **undefined by
## default**, so this typed surface **ships by default**; defining the
## flag strips it (mirrors the `z3WithoutPropagator` convention). When
## built with the flag, this file imports cleanly but exports nothing.
##
## ## Rooting (ADR-FC-0002)
##
## `Z3FixedpointOwn` (in the always-on `z3/fixedpoint`) holds a
## **type-erased** `cbBox: RootRef` field so the always-on module need
## not import this gated one (which would form a circular import: this
## module imports `z3/fixedpoint` for `Z3Context`/`Z3Fixedpoint`). This
## module casts through `RootRef` at the boundary — see `fp.cbBoxRef =`
## in `setHandlers` and the collection proof in
## `tests/tfixedpoint_ctxbox.nim`.
##
## `RootRef`, not `pointer`: ORC traces `RootRef` (a real GC-managed
## ref), so the box is both **rooted** by `fp` while `fp` is alive and
## **collected** when `fp`'s own `=destroy` drops `cbBox` — a plain
## `pointer` would give neither property.
##
## ## Lazy activation seam
##
## `cbBoxRef`/`cbBoxRef=` (above) are the **data** seam bridging the
## always-on/gated boundary; `z3/fixedpoint.exportActivateHook` is its
## **behavioral** twin — a `nil`-by-default proc-var in the always-on
## module that this module points at `activateExportCallbacks` on
## import. `withInQuery` (the always-on module's single query choke
## point) fires the hook, if non-nil, on every `query`/
## `queryRelations`/`queryFromLevel` call, giving this gated module a
## way to run Spacer-specific registration logic exactly at the point
## the always-on module can't name it directly. Both seams exist for
## the identical reason: `z3/fixedpoint` cannot import
## `z3/fixedpoint_callbacks` (circular import), so it exposes a typed
## slot the gated module fills in instead.
##
## ## In-query guard (ADR-FC-0005)
##
## `setHandlers`/`clearHandlers` assert `not fp.inQuery` — swapping (or
## resetting) the callback box while Z3 holds a raw `state` pointer
## into the current one, mid-query, is a use-after-free hazard. The
## guard is set/cleared by the single `withInQuery` choke point in
## `z3/fixedpoint`, routed through all three query entry points
## (`query`, `queryRelations`, `z3/spacer.queryFromLevel`) — so no call
## site can forget it. `when not defined(release)`-gated (deviates
## from the RFC's literal `when defined(debug)` — Nim never
## auto-defines `debug`, so that phrasing would be permanently dead
## code under this project's actual build commands; see
## `z3/fixedpoint`'s `inQuery` field doc for the verification); a
## no-op check in release builds.
##
## ## Sticky box invariant (ADR-FC-0008)
##
## `clearHandlers` resets the installed handler set to all-nil but
## does **not** drop `fp`'s box — the box (and the Z3-side `state`
## pointer into it) stays live for `fp`'s whole lifetime, because Z3
## has no deregister call and the C-side registration is sticky.
##
## ## Threading contract
##
## Callbacks fire **synchronously on the thread that calls**
## `query`/`queryRelations`/`z3/spacer.queryFromLevel` — Z3's Spacer
## engine does not dispatch across threads (Stage-0 spike, empirically
## verified: caller tid == callback tid). There is no cross-thread
## delivery to guard against, and — unlike `z3/propagator`, which
## needs a `{.threadvar.}` `currentBox` seam so `consequence`/
## `nextSplit` can recover their context — no threadvar is needed
## here either: each `{.cdecl.}` shim recovers its box directly from
## the `state` pointer Z3 passes back on every invocation (ADR-FC-0007).
## `Z3FixedpointHandlers`' closure fields deliberately omit `gcsafe`,
## mirroring `z3/propagator.Z3PropagatorHandlers`' identical stance,
## for the identical reason. The mandatory exception wall
## (ADR-FC-0001) is the orthogonal, load-bearing safety property: a
## Nim exception must never unwind out of a `{.cdecl.}` shim into
## Z3's C++ call stack, regardless of threading.

when not defined(z3WithoutFixedpointCallbacks):
  import ./context, ./ffi, ./error, ./ast, ./fixedpoint, ./params

  type
    Z3FixedpointHandlers* = object
      ## Typed Spacer-engine export closures dispatched from `fp`'s
      ## callback box (RFC §5). All three are optional (`nil` = not
      ## installed); `reduceApp`/`reduceAssign` are cut from v2.1.0 —
      ## use the raw §N7.8 `setReduceAssignCallback`/
      ## `setReduceAppCallback` for reduce until the v2.2 RFC.
      ##
      ## Every handler runs behind the exception wall (ADR-FC-0001,
      ## A2/A3): a handler must not `raise`. To abort an in-flight
      ## query from a handler, call `fp.ctx.interrupt()` instead.
      newLemma*: proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].}
        ## Spacer engine only. Fired on each newly discovered lemma at
        ## induction `level`. `level` is `uint` (Z3 gives `cuint`; a
        ## signed `int` would truncate to negative above
        ## `int32.high` on 32-bit) — matches `propagator.nim`'s `uint`
        ## for cuint-sourced counters.
      predecessor*: proc() {.closure, raises: [].}
        ## Spacer engine only. Fired on predecessor-frame exploration.
      unfold*: proc() {.closure, raises: [].}
        ## Spacer engine only. Fired on each unfolding step.

    FixedpointCtxBoxObj* = object of RootObj
      ## Root of the per-`Z3Fixedpoint` callback state. `ref object of
      ## RootObj` (not a plain `ref object`) so `FixedpointCtxBox` can be
      ## stored, type-erased, in `Z3FixedpointOwn.cbBox: RootRef` and
      ## recovered via `cast[FixedpointCtxBox](...)` at each call site
      ## that needs it back (`fp.cbBoxRef`, the A2/A3 callback shims).
      ctx*: Z3Context
        ## The fixedpoint's owning context.
      handlers*: Z3FixedpointHandlers
        ## The currently-installed typed closures. `setHandlers`
        ## replaces this wholesale; `clearHandlers` resets it to
        ## `default(Z3FixedpointHandlers)` in place (the box itself
        ## stays live — ADR-FC-0008).
      exportActivated*: bool
        ## Lazy-activation latch (A2-redesign). `false` on a fresh box
        ## (the *first* `setHandlers` call on an `fp` allocates one —
        ## see `setHandlers`); every *subsequent* `setHandlers` call on
        ## that same `fp` reuses the box in place (ADR-FC-0008
        ## stable-box invariant) and deliberately leaves this field
        ## untouched, since the underlying `Z3_fixedpoint_add_callback`
        ## registration it tracks stays valid across a handler swap.
        ## Set to `true` **only** on a successful
        ## `Z3_fixedpoint_add_callback` registration inside
        ## `activateExportCallbacks`, never on the skipped/failed path
        ## — that asymmetry is what makes activation retry correctly:
        ## a query under a non-Spacer engine leaves this `false`, so a
        ## *later* query under a corrected engine still attempts (and
        ## can succeed at) registration, while a query that already
        ## succeeded never re-registers (which would double-fire the
        ## same callback on every subsequent query).
    FixedpointCtxBox* = ref FixedpointCtxBoxObj

  # --- =destroy hook on the underlying object type ---------------------------
  #
  # Nim 2's hook signatures require the underlying object type, not the
  # ref alias. {.raises: [].} + try/except CatchableError: discard because
  # softlink-wrapped procs can raise SoftlinkError (e.g. if libz3 was
  # unloaded mid-program); =destroy can't propagate exceptions. Mirrors
  # `Z3ContextOwn.=destroy` in `src/z3/context.nim`.

  when defined(z3FpBoxDestroyCount):
    var z3FpBoxDestroyCounter*: int
      ## Test-only instrument (slice A0, ADR-FC-0002). Compiled in only
      ## under `-d:z3FpBoxDestroyCount`; incremented once per
      ## `FixedpointCtxBoxObj.=destroy` invocation. Gives
      ## `tests/tfixedpoint_ctxbox.nim` a direct way to observe the box
      ## being collected exactly once when the last `Z3Fixedpoint`
      ## reference that roots it drops (probe FACT B: a `ref object of
      ## RootObj` is reclaimed deterministically on scope exit under
      ## `--mm:orc`).

  proc `=destroy`(b: var FixedpointCtxBoxObj) {.raises: [].} =
    when defined(z3FpBoxDestroyCount):
      inc z3FpBoxDestroyCounter
    # Release both GC-managed fields this box holds — a custom
    # `=destroy` replaces field-wise destruction under ORC
    # (ADR-FC-0011), so `ctx` and `handlers` would otherwise each leak
    # one strong ref (the closures' captured environments, for
    # `handlers`). `handlers` is a plain closure-record value (no
    # `Z3Context` involved), so its destroy can't raise bare
    # `Exception` — narrow `CatchableError`, matching
    # `datatypes.nim`'s treatment of its non-ctx fields (`accessorsFD`/
    # `cname`). `except Exception` (not `CatchableError`) is kept ONLY
    # for the `ctx` release below, matching `lifecycle.nim`'s
    # `emitRefcountLifecycle` ctx-release block — releasing a
    # `Z3Context` ref triggers an unlisted-`Exception` effect warning
    # under `{.raises: [].}` that the narrower `CatchableError` catch
    # doesn't silence.
    try:
      `=destroy`(b.handlers)
    except CatchableError:
      discard
    try:
      `=destroy`(b.ctx)
    except Exception:
      discard

  # ==========================================================================
  # newLemma — C-ABI shim (ADR-FC-0001 exception wall, ADR-FC-0007)
  # ==========================================================================

  proc newLemmaShim(state: pointer, lemma: RawZ3Ast,
                     level: cuint) {.cdecl.} =
    ## Recovers the box from `state`, wraps the raw lemma AST into a
    ## typed `Z3AnyAst` (via the box's `ctx` — ADR-FC-0007: no
    ## `currentBox` threadvar needed, `wrap` gives the closure a
    ## self-contained typed value), and dispatches to the installed
    ## `newLemma` closure.
    ##
    ## `level: uint` (not `int`) — matches `Z3FixedpointHandlers.newLemma`
    ## (RFC §5): a signed `int` would truncate to negative above
    ## `int32.high` on 32-bit.
    ##
    ## Mandatory exception wall (ADR-FC-0001, CRITICAL): a Nim exception
    ## unwinding out of this `{.cdecl.}` frame into Z3's C++ call stack
    ## is undefined behavior. `box.handlers.newLemma` is declared
    ## `{.raises: [].}` (compile-time defense); the `try/except` here is
    ## the runtime wall — both ship, mirroring `propagator.nim`'s shims.
    let box = cast[FixedpointCtxBox](state)
    if box != nil and box.handlers.newLemma != nil:
      try:
        let anyAst = wrap[Z3AnyAst](box.ctx, lemma)
        box.handlers.newLemma(anyAst, uint(level))
      except CatchableError:
        discard

  proc predecessorShim(state: pointer) {.cdecl.} =
    ## Payload-free counterpart to `newLemmaShim` — the Spacer engine
    ## passes only `state`; there is no argument to unwrap (ADR-FC-0007:
    ## these are pure observers, they build nothing). Same nil-guard +
    ## exception-wall idiom (ADR-FC-0001).
    let box = cast[FixedpointCtxBox](state)
    if box != nil and box.handlers.predecessor != nil:
      try:
        box.handlers.predecessor()
      except CatchableError:
        discard

  proc unfoldShim(state: pointer) {.cdecl.} =
    ## Payload-free counterpart to `newLemmaShim`, see `predecessorShim`.
    let box = cast[FixedpointCtxBox](state)
    if box != nil and box.handlers.unfold != nil:
      try:
        box.handlers.unfold()
      except CatchableError:
        discard

  # ==========================================================================
  # setHandlers / handlers / hasHandlers / clearHandlers (RFC §5;
  # ADR-FC-0005, ADR-FC-0008)
  # ==========================================================================

  proc setHandlers*(fp: Z3Fixedpoint, handlers: Z3FixedpointHandlers) =
    ## Install typed closures on `fp`, **replacing** any previously
    ## installed set wholesale (not merged).
    ##
    ## **Stable box across `fp`'s lifetime (ADR-FC-0008).** The
    ## *first* call allocates a fresh GC-rooted `FixedpointCtxBox`
    ## holding `handlers` (`exportActivated` starting `false`), roots
    ## it on `fp` (`fp.cbBoxRef =`), and pins the Z3-side `state`
    ## pointer to it via `Z3_fixedpoint_init`. **Every subsequent
    ## call reuses that same box** — it recovers it via `fp.cbBoxRef`
    ## and mutates `box.handlers = handlers` **in place**; it does
    ## **not** allocate a new box, does not re-root, does not re-run
    ## `Z3_fixedpoint_init`, and does not reset `box.exportActivated`.
    ##
    ## This is load-bearing, not cosmetic: `activateExportCallbacks`
    ## (below) registers this box's raw pointer with Z3 as an opaque
    ## `state` via a single `Z3_fixedpoint_add_callback` call at the
    ## *first* query, and Z3 has no deregister call — it keeps
    ## invoking the `{.cdecl.}` shims with that exact pointer for the
    ## rest of `fp`'s life. If a later `setHandlers` allocated a
    ## *different* box and re-rooted `fp.cbBoxRef` onto it (the old
    ## behavior), the first box would lose its only GC root and ORC
    ## would free it — while Z3 kept firing the shims against that now-
    ## dangling pointer: a use-after-free on the very next query. Since
    ## the shims read `box.handlers` live on every fire, re-installing
    ## a handler as `nil` on the *stable* box simply makes it go
    ## **dormant** (the shim's nil-check short-circuits) rather than
    ## deregistered or dangling — see `tests/tfixedpoint_typed_callbacks.nim`,
    ## suite "C1a(a)", for the RED-before/GREEN-after proof (including a
    ## valgrind 0-invalid-reads run against the old allocate-new code).
    ##
    ## **Pure intent-recording — engine-agnostic, never raises on
    ## engine grounds (A2-redesign, supersedes ADR-FC-0008's
    ## install-time registration).** This call does **not** touch
    ## `Z3_fixedpoint_add_callback` or the Spacer param gate at all —
    ## see "Lazy activation" below for where and why that moved.
    ## `setHandlers` therefore never depends on, or cares about, `fp`'s
    ## currently-configured engine; install order relative to
    ## `setParams(engine=...)` is never observable.
    ##
    ## Must be called **outside** an active query (ADR-FC-0005) —
    ## swapping the box while Z3 holds a raw `state` pointer into the
    ## old one, mid-query, dangles. Non-release builds assert this;
    ## `-d:release`/`-d:danger` builds do not check (the guard is
    ## `when not defined(release)`-gated in `z3/fixedpoint`).
    ##
    ## Do not mix with the raw §N7.8 procs (`fp.init`,
    ## `fp.setReduceAssignCallback`, `fp.addCallback`, …) on the same
    ## `fp` (ADR-FC-0009) — both surfaces write the same Z3-side
    ## `state` slot.
    ##
    ## ## Lazy activation (A2-redesign)
    ##
    ## Export-callback registration (`Z3_fixedpoint_add_callback` +
    ## the `fp.spacer.p3.share_lemmas`/`share_invariants` param gate,
    ## see `activateExportCallbacks`' doc comment for the full
    ## mechanism and the engine-detection investigation) happens
    ## **lazily, at the query choke point** (`z3/fixedpoint.withInQuery`
    ## → `exportActivateHook` → `activateExportCallbacks`), not here.
    ##
    ## Rationale: `setHandlers` runs whenever the caller decides to
    ## wire up handlers, which may be *before* they've chosen an engine
    ## (`setParams(engine=spacer)` is often a separate, later call —
    ## and the un-set `auto-config` default resolves to a concrete
    ## engine that isn't necessarily Spacer even earlier than that).
    ## Deciding "is this Spacer" at `setHandlers` time makes correctness
    ## order-dependent on a call this proc has no visibility into.
    ## Deferring the decision to query time — when Z3's resolved engine
    ## is truly final relative to *this* `setHandlers`/`setParams`/
    ## `query` sequence — makes that sequence's ordering irrelevant. See
    ## `tests/tfixedpoint_newlemma.nim`'s "A2-redesign" suite,
    ## "order-independence" test, for the proof (`setHandlers` strictly
    ## before `setParams(engine=spacer)`, both strictly before the
    ## first `query`, still fires).
    ##
    ## **Scope note (does not extend to a mid-lifetime engine change
    ## across two separate queries):** Z3 itself permanently locks a
    ## `Z3Fixedpoint`'s engine at the first engine-touching operation —
    ## source-verified `dl_context.cpp`'s `context::ensure_engine()`
    ## (`if (!m_engine.get()) { … }`, a one-shot construction guard) and
    ## `context::updt_params()` (never resets `m_engine`) — so a
    ## `setParams(engine=...)` call issued *after* a query has already
    ## run on that `fp` cannot change what engine subsequent queries on
    ## that same `fp` use; see
    ## `scratchpad/spike_a2redesign_engine_lock.nim` for the empirical
    ## confirmation. `exportActivated`'s "leave `false` on failure so a
    ## later query retries" design is still correct and load-bearing —
    ## it is what makes the *first* query's activation attempt
    ## order-independent from a same-lifetime-but-earlier `setParams`
    ## call, and what makes a second query on an *already-Spacer*, already-
    ## activated `fp` cheap (skip, don't re-register) — but it cannot
    ## rescue a callback across a real engine change, because Z3 does
    ## not support real engine changes on a live `Z3Fixedpoint` at all.
    assert not fp.inQuery,
      "Z3Fixedpoint.setHandlers: cannot install handlers while a " &
      "query (query/queryRelations/queryFromLevel) is in progress " &
      "(ADR-FC-0005)"
    assert not fp.rawCbUsed,
      "Z3Fixedpoint.setHandlers: the raw §N7.8 callback surface " &
      "(fp.init/setReduceAssignCallback/setReduceAppCallback/" &
      "addCallback) has already been used on this fp — the raw and " &
      "typed callback surfaces are mutually exclusive per fp " &
      "(ADR-FC-0009 mixing hazard: both write the same Z3-side " &
      "`state` slot)"
    let existing = fp.cbBoxRef
    if existing.isNil:
      let box = FixedpointCtxBox(ctx: fp.ctx, handlers: handlers)
      fp.cbBoxRef = cast[RootRef](box)
      fp.ctx.checkErrVoid Z3_fixedpoint_init(
        fp.ctx.raw, fp.raw, cast[pointer](box))
    else:
      cast[FixedpointCtxBox](existing).handlers = handlers

  # ==========================================================================
  # Lazy export-callback activation (A2-redesign) — the
  # `exportActivateHook` seam target
  # ==========================================================================

  proc activateExportCallbacks(fp: Z3Fixedpoint) {.nimcall, raises: [].} =
    ## Assigned to `z3/fixedpoint.exportActivateHook` at this module's
    ## init time (below) — the dependency-inversion seam that lets the
    ## always-on `withInQuery` (in `z3/fixedpoint`) trigger GATED,
    ## Spacer-specific activation logic without importing this gated
    ## module (which would be circular — see the module doc's
    ## "Rooting" section). Called once per query, from `withInQuery`,
    ## just before the FFI query call, for all three query entry points
    ## (`query`, `queryRelations`, `z3/spacer.queryFromLevel`).
    ##
    ## ## What it does
    ##
    ## No-ops immediately (cheap: two field reads, three pointer
    ## compares) unless there is a box with at least one non-nil export
    ## handler (`newLemma`, `predecessor`, or `unfold` — all three are
    ## export handlers, RFC §5) that hasn't yet been successfully
    ## activated. Otherwise:
    ## 1. **Unconditionally**, sets the Spacer param gate
    ##    (`fp.spacer.p3.share_lemmas`/`share_invariants`, RFC lines
    ##    1029-1043; source-verified `spacer_context.cpp:4286-4304`,
    ##    `context::new_lemma_eh` — both default `false`, so a
    ##    registered `newLemma` callback silently never fires without
    ##    them), whether or not `newLemma` happens to be the field that's
    ##    non-nil right now. `predecessor`/`unfold` have **no such param
    ##    gate** (A3 Finding 1, source-verified alongside `new_lemma_eh`
    ##    — Spacer dispatches `predecessor_eh`/`unfold_eh`
    ##    unconditionally once registered), so setting the gate for a
    ##    predecessor-only or unfold-only install is inert, not
    ##    incorrect. Proven not to perturb solving under any engine
    ##    (either way, on any engine) —
    ##    `scratchpad/spike_a2_p3share_perturb.nim`; see the historical
    ##    account in git history / `docs/SPIKE_FINDINGS-fixedpoint.md`.
    ##    **H1 fix, deliberate deviation from the original "minimal
    ##    blast radius" design:** the original code only touched this
    ##    gate, and only registered a real shim pointer (vs. `nil`) for a
    ##    field that was non-nil AT THE MOMENT of this call — cheaper,
    ##    but wrong: since `exportActivated` latches after the first
    ##    successful call and Z3 has no re-register API, a field that was
    ##    nil at first activation and set non-nil by a LATER
    ##    `setHandlers` call on the same `fp` could never fire (proof:
    ##    `tests/tfixedpoint_newlemma.nim`'s "H1" test). Blast-radius
    ##    minimization is sacrificed here for correctness.
    ## 2. Attempts `Z3_fixedpoint_add_callback`, passing
    ##    `newLemmaShim`/`predecessorShim`/`unfoldShim` **unconditionally
    ##    — never `nil`**, regardless of which handler fields are non-nil
    ##    right now. Each shim already nil-guards on the LIVE
    ##    `box.handlers.X` field at fire time (see the shims above), so
    ##    registering all three costs nothing when a field stays nil
    ##    forever, and makes a nil->non-nil revival via a later
    ##    `setHandlers` call fire correctly with zero re-registration —
    ##    `Z3_fixedpoint_add_callback` is still called exactly once per
    ##    `fp` (inside this success path), so there is no
    ##    double-registration or leak risk from ever calling it twice. On
    ##    success, latches `box.exportActivated = true` so later queries
    ##    skip straight past step 1 (no double-registration) — the latch
    ##    now means "the engine accepted my callbacks," not "the engine
    ##    accepted the callbacks I had at the time." On the specific
    ##    "engine doesn't support this" failure (see below), leaves
    ##    `exportActivated = false` so a *later* query — e.g. after the
    ##    caller corrects the engine via `setParams(engine=spacer)` —
    ##    retries.
    ##
    ## ## Engine-detection investigation (this task's §3)
    ##
    ## The ideal design reads `fp`'s currently-resolved engine and only
    ## calls `add_callback` when it's `spacer`, with no exception
    ## involved at all. **No such read exists in Z3's C API**:
    ## `Z3_params`/`Z3_fixedpoint_set_params` are write-only (no
    ## `Z3_fixedpoint_get_param` / "get current value" call exists —
    ## only `Z3_fixedpoint_get_param_descrs`, which is the parameter
    ## *schema* — names/kinds/docs — not the caller's chosen values,
    ## and no schema entry reports what `auto-config` resolved to for
    ## THIS `fp`). Confirmed against the actual header
    ## (`z3_fixedpoint.h`, Z3 4.15.0) and by direct inspection of Z3's
    ## engine-resolution path (`muz/base/dl_context.h`'s
    ## `context::add_callback` calls `ensure_engine()` — which runs
    ## `auto-config` heuristics over the ruleset the *first* time any
    ## engine-touching call is made — before delegating to
    ## `m_engine->add_callback`; there is no public accessor for the
    ## engine `ensure_engine()` picked). Reimplementing Z3's
    ## `auto-config` heuristic in this wrapper to predict the engine
    ## ahead of the call would be both unsound (liable to drift from
    ## Z3's actual logic across versions) and against the grain of a
    ## thin wrapper.
    ##
    ## **Chosen path: narrow `except Z3OperationError`, and it is
    ## sound.** Source-verified (`muz/base/dl_engine_base.h`, Z3
    ## 4.15.0): the *default* `engine_base::add_callback` — inherited
    ## by every engine that doesn't override it (datalog, bmc, …) — is
    ## exactly:
    ## ```cpp
    ## virtual void add_callback(...) {
    ##     throw default_exception(std::string(
    ##         "add_lemma_exchange_callbacks is not supported for ") + m_name);
    ## }
    ## ```
    ## — no partial registration, no other side effect: either the
    ## call throws (nothing happened) or it doesn't (Spacer's override
    ## actually stores the callbacks and returns normally). So catching
    ## exactly `Z3OperationError` around exactly this one call masks no
    ## other failure mode — there is no other failure mode for this
    ## call to have. This is the same reasoning A2 originally used at
    ## install time; the redesign only *moves* the catch to query time
    ## (where the engine is actually final) rather than removing it.
    ## (The implementation also has a second, broader
    ## `except CatchableError` below the `Z3OperationError` one —
    ## project-wide defensive convention, same as `registerCb` in
    ## `propagator.nim`: the softlink-generated FFI proc's declared
    ## type includes `SoftlinkError`, unrelated to engine support.)
    ##
    ## ## Idempotency / retry
    ##
    ## `exportActivated` is the guard: read (skip if already `true`),
    ## written to `true` **only** in the success path. A query that
    ## finds the engine unsupported leaves it `false` — safe to retry
    ## on the next query, and cheap to skip-check on every query in
    ## between (`hasHandlers`-shaped short-circuit above). This is what
    ## makes install-order-independence hold (`setHandlers` before or
    ## after the engine is chosen, as long as it's chosen before the
    ## first query — see `setHandlers`' doc "scope note" for why a
    ## retry *across a genuine engine change on the same live `fp`*
    ## isn't achievable, independent of this guard: Z3 locks the engine
    ## at first use.)
    let boxRef = fp.cbBoxRef
    if boxRef.isNil:
      return
    let box = cast[FixedpointCtxBox](boxRef)
    if box.exportActivated or
        (box.handlers.newLemma == nil and box.handlers.predecessor == nil and
         box.handlers.unfold == nil):
      return
    # H1 fix: always set the `share_lemmas`/`share_invariants` gate and
    # always register ALL THREE shims unconditionally — never `nil` for
    # an unset field — regardless of which handler field is non-nil AT
    # THIS MOMENT. The old code passed a real shim pointer only for
    # fields non-nil at the moment of the FIRST successful activation,
    # then latched `exportActivated = true` forever; since Z3 has no
    # re-register API, a field that was nil at first activation and set
    # non-nil by a LATER `setHandlers` call could never fire (the latch
    # makes every subsequent query early-return before it ever looks at
    # the new field) — proven by `tests/tfixedpoint_newlemma.nim`'s "H1"
    # test. The three shims already nil-guard on the LIVE
    # `box.handlers.X` field at fire time (see `newLemmaShim`/
    # `predecessorShim`/`unfoldShim` above), so registering all three up
    # front costs nothing when a field stays nil forever, and makes a
    # nil->non-nil revival via a later `setHandlers` work for free — no
    # second `Z3_fixedpoint_add_callback` call, so no double-registration
    # or leak risk from calling it twice. Same reasoning for the param
    # gate: `scratchpad/spike_a2_p3share_perturb.nim` (see
    # `docs/SPIKE_FINDINGS-fixedpoint.md`) proved `share_lemmas`/
    # `share_invariants` do not perturb solving under any engine, so
    # setting them unconditionally — even when `newLemma` isn't
    # (yet) installed — is safe. This sacrifices the old "minimal blast
    # radius" rationale (only touch what's currently requested) for
    # correctness (a later `setHandlers` must be able to revive a
    # dormant field); `exportActivated` remains the one-shot latch, now
    # meaning "the engine accepted my callbacks" rather than "the engine
    # accepted the callbacks I had at the time."
    try:
      let p = newParams(fp.ctx)
      p.set("fp.spacer.p3.share_lemmas", true)
      p.set("fp.spacer.p3.share_invariants", true)
      fp.setParams(p)
    except CatchableError:
      # Defensive only — `fp.spacer.p3.*` are always-valid schema
      # params (proven safe under every engine by the A2 regression
      # suite; setting a Spacer-specific param while a different
      # engine is active is not itself an error), so this branch is
      # not expected to trigger in practice. Kept so the narrow catch
      # below stays scoped to exactly its documented, sound case. If
      # param-setting failed, don't attempt registration this round —
      # `exportActivated` stays `false`, so a later query retries.
      return
    try:
      fp.ctx.checkErrVoid Z3_fixedpoint_add_callback(
        fp.ctx.raw, fp.raw, cast[pointer](box),
        newLemmaShim, predecessorShim, unfoldShim)
      box.exportActivated = true
    except Z3OperationError:
      # See doc comment above ("Chosen path") — the engine doesn't
      # support export callbacks. `exportActivated` stays `false`.
      discard
    except CatchableError:
      # Defensive-only, project-wide convention (see `registerCb` in
      # `propagator.nim`): the softlink-generated FFI proc's type is
      # `raises: [SoftlinkError]` (symbol-resolution failure, e.g. libz3
      # unloaded mid-program) in addition to `checkErrVoid`'s
      # `Z3Error`. Unrelated to engine support; `exportActivated` stays
      # `false` either way, so a later query retries.
      discard

  exportActivateHook = activateExportCallbacks

  proc handlers*(fp: Z3Fixedpoint): Z3FixedpointHandlers =
    ## The currently-installed handler set — `default(Z3FixedpointHandlers)`
    ## (all-nil) if `setHandlers` has never been called. The box already
    ## holds this value to dispatch through, so exposing it is free.
    let box = fp.cbBoxRef
    if box.isNil:
      default(Z3FixedpointHandlers)
    else:
      cast[FixedpointCtxBox](box).handlers

  proc hasHandlers*(fp: Z3Fixedpoint): bool =
    ## True if any handler field is currently non-nil. Sugar over
    ## `handlers()`. Reports installed *intent* only — it does **not**
    ## mean the engine accepted the callbacks or that they will fire; see
    ## `handlersActive` for that (it stays `false` until the first query
    ## activates them under a Spacer engine).
    let h = fp.handlers
    h.newLemma != nil or h.predecessor != nil or h.unfold != nil

  proc handlersActive*(fp: Z3Fixedpoint): bool =
    ## True if handlers are installed AND the engine accepted them —
    ## they will fire when their field is non-nil; contrast
    ## `hasHandlers` (merely installed). Reads `box.exportActivated`,
    ## the same latch `activateExportCallbacks` sets on the first
    ## successful `Z3_fixedpoint_add_callback` registration (`false` if
    ## no box exists yet, i.e. `setHandlers` has never been called).
    ##
    ## Since activation runs lazily at the first `query`/
    ## `queryRelations`/`queryFromLevel` call (see the module doc's
    ## "Lazy activation seam"), this is `false` right after `setHandlers`
    ## and stays `false` under a non-Spacer engine — even though
    ## `hasHandlers` is already `true` in both cases. Use this instead of
    ## hand-rolling a fire-counter to check "will my callbacks actually
    ## run" (`docs/GOTCHAS.md` #21).
    let box = fp.cbBoxRef
    if box.isNil:
      false
    else:
      cast[FixedpointCtxBox](box).exportActivated

  proc clearHandlers*(fp: Z3Fixedpoint) =
    ## Reset `fp`'s installed handler set to all-nil.
    ##
    ## **Invariant (ADR-FC-0008):** does **not** drop `fp`'s box — the
    ## box (and the Z3-side `state` pointer into it) stays live for
    ## `fp`'s whole lifetime, because Z3 has no deregister call and the
    ## C-side callback registration is sticky. Implemented by mutating
    ## the existing box's handler set in place. A no-op if `setHandlers`
    ## has never been called (no box to mutate).
    ##
    ## Safe outside a query only (ADR-FC-0005), same as `setHandlers`.
    assert not fp.inQuery,
      "Z3Fixedpoint.clearHandlers: cannot clear handlers while a " &
      "query (query/queryRelations/queryFromLevel) is in progress " &
      "(ADR-FC-0005)"
    let box = fp.cbBoxRef
    if box.isNil:
      return
    cast[FixedpointCtxBox](box).handlers = default(Z3FixedpointHandlers)

  # ==========================================================================
  # Z3LemmaLog / collectLemmas (RFC §5, C1b)
  # ==========================================================================

  type
    Z3LemmaLog* = ref object
      ## Growing log of discovered lemmas, returned by `collectLemmas`.
      ## Named/iterable rather than a bare `ref seq[...]` — the
      ## codebase returns plain `seq[T]` everywhere else; this is the
      ## one place a `ref` is warranted (a rooted handle that keeps
      ## growing across callback fires the caller doesn't otherwise
      ## touch), so it gets a name that documents itself and can gain
      ## fields later without a breaking change.
      ##
      ## **M2 caveat — silent detach.** A log **stops growing** if
      ## `setHandlers`/`clearHandlers` is called again on the `fp` it was
      ## created against — both replace the box's installed handler set
      ## wholesale, dropping the accumulator closure this log's entries
      ## come from. No error is raised; entries already collected stay
      ## valid and readable (each is an independent, inc_ref'd copy), but
      ## nothing new gets appended. Use `combine` to fold additional
      ## handlers into `fp.handlers` in place, instead of calling
      ## `setHandlers`/`collectLemmas` fresh, if you need the log to keep
      ## growing while adding more behavior.
      entries*: seq[tuple[lemma: Z3AnyAst, level: uint]]

  iterator items*(l: Z3LemmaLog): tuple[lemma: Z3AnyAst, level: uint] =
    for e in l.entries: yield e

  proc len*(l: Z3LemmaLog): int = l.entries.len

  proc combine*(base, extra: Z3FixedpointHandlers): Z3FixedpointHandlers =
    ## Compose two handler sets field-by-field: for each event
    ## (`newLemma`, `predecessor`, `unfold`), if BOTH `base` and `extra`
    ## have a non-nil handler for that field, the result fires `base`'s
    ## handler FIRST, then `extra`'s (base-first ordering — the parameter
    ## names make the order explicit, matching `collectLemmas`' own
    ## `base` vocabulary). If only one side has a handler for a field, the
    ## result **is** that handler, unmodified — no wrapper closure, no
    ## overhead, and no behavior change from installing it directly via
    ## `setHandlers`. If neither side has one, the result field is `nil`.
    ##
    ## Extracted from `collectLemmas` (below), which used to hand-inline
    ## this exact base-first chaining logic for `newLemma` alone; this is
    ## the general form, usable directly on any two `Z3FixedpointHandlers`
    ## values (see `tests/tfixedpoint_typed_callbacks.nim`, suite "M9",
    ## for the order + both-fire proof).
    ##
    ## Each per-field composed closure calls `base`'s handler then
    ## `extra`'s handler unconditionally when both exist; both fields are already
    ## typed `{.closure, raises: [].}`, so neither call can raise — no
    ## defensive `try/except` needed here (the C-boundary shim's own
    ## exception wall, ADR-FC-0001, is still the second line of defense).
    ##
    ## **M2 caveat:** `combine`'s result is a plain value — installing it
    ## via `setHandlers` still *replaces* whatever was on `fp` before
    ## wholesale (`setHandlers` never merges with what's already
    ## installed). To ADD a handler to what's already on `fp` without
    ## detaching anything the current handlers close over (e.g. a
    ## `Z3LemmaLog` from an earlier `collectLemmas` call), pass
    ## `fp.handlers` as one side: `fp.setHandlers(combine(fp.handlers,
    ## newHandlers))`.
    let baseNewLemma = base.newLemma
    let extraNewLemma = extra.newLemma
    result.newLemma =
      if baseNewLemma == nil: extraNewLemma
      elif extraNewLemma == nil: baseNewLemma
      else:
        (proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
          baseNewLemma(lemma, level)
          extraNewLemma(lemma, level))

    let basePredecessor = base.predecessor
    let extraPredecessor = extra.predecessor
    result.predecessor =
      if basePredecessor == nil: extraPredecessor
      elif extraPredecessor == nil: basePredecessor
      else:
        (proc() {.closure, raises: [].} =
          basePredecessor()
          extraPredecessor())

    let baseUnfold = base.unfold
    let extraUnfold = extra.unfold
    result.unfold =
      if baseUnfold == nil: extraUnfold
      elif extraUnfold == nil: baseUnfold
      else:
        (proc() {.closure, raises: [].} =
          baseUnfold()
          extraUnfold())

  proc collectLemmas*(fp: Z3Fixedpoint,
                       base = default(Z3FixedpointHandlers)): Z3LemmaLog =
    ## Convenience: installs (via `setHandlers`) a `newLemma` closure
    ## that appends every discovered `(lemma, level)` to the returned
    ## `Z3LemmaLog` — read after `query`/`queryRelations`/
    ## `queryFromLevel` returns.
    ##
    ## **Composes** with `base`, rather than replacing it wholesale
    ## (RFC §5), via `combine` (above): if `base.newLemma` is non-nil, it
    ## runs FIRST on every fire, then the log gets its append — so
    ## "collect lemmas AND run my own newLemma" is one call, not a
    ## hand-rolled record. `base.predecessor`/`base.unfold` pass through
    ## unchanged, so "collect lemmas AND run a predecessor/unfold
    ## handler" is also one call.
    ##
    ## The returned log is rooted by both the composed closure's
    ## capture (kept alive by `fp`'s sticky box, ADR-FC-0008) and the
    ## caller's own binding — so it stays valid, and its `Z3AnyAst`
    ## entries stay renderable, even after `clearHandlers(fp)` drops
    ## the closure back to nil (each entry is an independent,
    ## inc_ref'd `Z3AnyAst` copy — `emitTermLifecycle`'s value-type
    ## `=copy`/`=dup`, `z3/ast.nim`).
    ##
    ## **M2 caveat — silent detach.** The returned `Z3LemmaLog` stops
    ## growing if `setHandlers` or `clearHandlers` is called again on
    ## `fp` afterward: both **replace** the box's handler set wholesale
    ## (per-field, not merged — see `setHandlers`' doc comment), which
    ## drops this call's accumulator closure. This is silent — no error,
    ## no crash, the log simply freezes at whatever it already
    ## collected (already-collected entries stay valid and readable, per
    ## the paragraph above — only *future* growth stops). To add a
    ## handler without detaching the log, use `combine` to fold the new
    ## handlers into `fp`'s *current* set instead of calling
    ## `setHandlers`/`collectLemmas` with a fresh one:
    ## `fp.setHandlers(combine(fp.handlers, moreHandlers))`.
    let log = Z3LemmaLog(entries: @[])
    proc appendToLog(lemma: Z3AnyAst, level: uint) {.closure, raises: [].} =
      log.entries.add (lemma, level)
    setHandlers(fp, combine(base, Z3FixedpointHandlers(newLemma: appendToLog)))
    log

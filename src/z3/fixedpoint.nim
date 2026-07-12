## `z3/fixedpoint` — Horn-clause / Constrained Horn Clause (CHC) solver.
##
## `Z3Fixedpoint` is Z3's specialised decision procedure for CHC
## verification, datalog, and Spacer-style model checking. Use it
## when your problem fits the Horn shape:
##
## - **Relations**: predicate symbols (`Z3FuncDecl[..., Z3Bool]`)
##   registered with `registerRelation`.
## - **Rules**: universally-quantified Horn clauses
##   (`forall x. premise ⇒ conclusion`) added via `addRule`.
## - **Facts**: ground assertions added via `addRule` (with no
##   quantifier) or `addFact` (for the datalog engine's
##   finite-domain shortcut).
## - **Queries**: `query` runs the CHC decision procedure;
##   returns `zsSat` (the query is reachable / derivable),
##   `zsUnsat` (provably unreachable), or `zsUnknown`.
##
## ## Engine selection
##
## Z3 ships three CHC engines:
##
## - **`spacer`** (default in modern Z3) — IC3/PDR-style model checker
##   for software verification.
## - **`bmc`** — bounded model checking; good for finite-state
##   reachability questions.
## - **`datalog`** — finite-domain bottom-up evaluation; the
##   classical relational-algebra engine.
##
## Switch engines via `setParams`:
##
## ```nim
## let p = newParams()
## p.set("engine", "datalog")
## fp.setParams(p)
## ```
##
## ## Canonical example — graph reachability
##
## ```nim
## let ctx = newContext()
## let fp = newFixedpoint()
## let p = newParams(); p.set("engine", "datalog"); fp.setParams(p)
##
## let edge = mkFuncDecl[(Z3Int, Z3Int), Z3Bool]("edge")
## let path = mkFuncDecl[(Z3Int, Z3Int), Z3Bool]("path")
## fp.registerRelation(edge); fp.registerRelation(path)
##
## let x = mkIntVar("x"); let y = mkIntVar("y"); let z = mkIntVar("z")
##
## # Rules
## fp.addRule(forall(x, y, edge(x, y).implies(path(x, y))))
## fp.addRule(forall(x, y, z,
##   (edge(x, y) and path(y, z)).implies(path(x, z))))
##
## # Facts
## fp.addRule(edge(mkInt(1), mkInt(2)))
## fp.addRule(edge(mkInt(2), mkInt(3)))
##
## # Query
## doAssert fp.query(path(mkInt(1), mkInt(3))) == zsSat
## ```

import std/strutils
import ./ffi, ./context, ./error, ./ast, ./builder, ./solver, ./params,
       ./funcdecl, ./astvector, ./stats

# ============================================================================
# Z3Fixedpoint — ref-typed handle
# ============================================================================

type
  Z3FixedpointOwn = object
    raw: RawZ3Fixedpoint
    ctx: Z3Context
    cbBox: RootRef
      ## Type-erased root of the callback state (ADR-FC-0002). `nil`
      ## until `setHandlers` (A1); ORC-traced, so assigning it roots
      ## the `FixedpointCtxBox` for `fp`'s lifetime and releasing it
      ## (below) lets ORC collect the box. `RootRef`, not the concrete
      ## box type, to avoid a circular import with the gated
      ## `z3/fixedpoint_callbacks` module — see that module's doc
      ## comment.
    lastQueryCanceled: bool
      ## RFC C1(d): true iff the most recently *completed* `query` /
      ## `queryRelations` / `queryFromLevel` (`z3/spacer`) call was
      ## cancelled — via `Z3Context.interrupt()`, or a resource/timeout
      ## limit — and `runCancelableFixedpointQuery` (below) translated
      ## Z3's thrown cancellation exception into a graceful `zsUnknown`,
      ## uniform with `Z3Solver.check()`'s graceful `L_UNDEF` on
      ## interrupt. Always-on (NOT `not defined(release)`-gated, unlike
      ## `inQuery`/`rawCbUsed` below) because `getReasonUnknown` reads
      ## it in every build, including `-d:release`. Reset to `false` at
      ## the start of every query and set `true` only inside
      ## `runCancelableFixedpointQuery`'s cancellation catch — see that
      ## template's doc comment for the full mechanism.
    when not defined(release):
      inQuery: bool
        ## ADR-FC-0005 guard: true while a `query`/`queryRelations`/
        ## `queryFromLevel` call is on the stack. `setHandlers`
        ## (z3/fixedpoint_callbacks, gated) asserts this is false —
        ## swapping the callback box while Z3 holds a raw `state`
        ## pointer into the old one is a use-after-free hazard.
        ##
        ## Gated on `not defined(release)`, not the RFC's literal
        ## `when defined(debug)`: verified empirically that Nim does
        ## **not** auto-define `debug` for a plain `nim c` — it must be
        ## passed explicitly via `-d:debug`, which nothing in this
        ## project's build (`nim.cfg`, `z3.nimble`'s `task test`) does.
        ## A literal `when defined(debug)` would make this whole guard
        ## permanently dead code under every build this project
        ## actually runs. `not defined(release)` is the Nim idiom that
        ## matches the RFC's *stated intent* — "release builds pay
        ## nothing" — since `-d:danger` implies `-d:release` (verified
        ## empirically too), one check covers both.
      rawCbUsed: bool
        ## ADR-FC-0009 mixing-hazard guard: true once any raw §N7.8
        ## callback-registration proc (`init`, `setReduceAssignCallback`,
        ## `setReduceAppCallback`, `addCallback`, below) has been called
        ## on this `fp`. The raw surface and the typed
        ## `z3/fixedpoint_callbacks.setHandlers` surface both write the
        ## same Z3-side `state` slot / callback registration on `fp`;
        ## mixing them silently overwrites what the other surface's
        ## `{.cdecl.}` shims depend on, producing type-confusion or a
        ## use-after-free on the next callback fire. Each raw proc
        ## below asserts `fp.cbBoxRef.isNil` (the typed-surface tell —
        ## no separate flag needed for that half) before setting this;
        ## `setHandlers` asserts `not fp.rawCbUsed` before installing.
        ## Same `not defined(release)` gate as `inQuery` — zero cost in
        ## release builds (the field doesn't exist; `rawCbUsed()` below
        ## folds to a compile-time `false`).
  Z3Fixedpoint* = ref Z3FixedpointOwn

proc cbBoxRef*(fp: Z3Fixedpoint): RootRef {.inline.} = fp.cbBox
  ## INTERNAL_API — recover the type-erased callback box. Used by
  ## `z3/fixedpoint_callbacks` (A1+) to read back what `setHandlers`
  ## stored; casts through `RootRef` at the call site.
proc `cbBoxRef=`*(fp: Z3Fixedpoint, r: RootRef) {.inline.} = fp.cbBox = r
  ## INTERNAL_API — root `r` on `fp`. Used by `setHandlers` (A1) to
  ## install a freshly allocated `FixedpointCtxBox`.

proc inQuery*(fp: Z3Fixedpoint): bool {.inline.} =
  ## INTERNAL_API — true while `fp` has a `query`/`queryRelations`/
  ## `queryFromLevel` call on the stack (ADR-FC-0005). Always `false`
  ## in release builds (the guard is `when not defined(release)`-gated,
  ## so there is no field to read — see the field's doc comment for why
  ## this isn't the RFC's literal `when defined(debug)`); `setHandlers`
  ## (`z3/fixedpoint_callbacks`) asserts `not fp.inQuery`.
  when not defined(release):
    fp.inQuery
  else:
    false

proc rawCbUsed*(fp: Z3Fixedpoint): bool {.inline.} =
  ## INTERNAL_API — true once any raw §N7.8 callback-registration proc
  ## has run on `fp` (ADR-FC-0009). Always `false` in release builds
  ## (no field to read — see the `rawCbUsed` field's doc comment);
  ## `setHandlers` (`z3/fixedpoint_callbacks`) asserts `not
  ## fp.rawCbUsed` before installing the typed surface.
  when not defined(release):
    fp.rawCbUsed
  else:
    false

var exportActivateHook*: proc(fp: Z3Fixedpoint) {.nimcall, raises: [].}
  ## INTERNAL_API — dependency-inversion seam (the behavioral twin of
  ## `cbBox: RootRef` above) bridging this always-on module to the
  ## GATED `z3/fixedpoint_callbacks`, which cannot be imported here
  ## (circular import — see `cbBoxRef`'s doc comment). `nil` unless the
  ## gated module is compiled in, in which case it assigns itself here
  ## at module-init time (`exportActivateHook = activateExportCallbacks`
  ## in `fixedpoint_callbacks.nim`).
  ##
  ## Called from `withInQuery` (the single choke point shared by
  ## `query`, `queryRelations`, and `z3/spacer.queryFromLevel`) just
  ## before each query's FFI call — this is the **lazy activation**
  ## point for Spacer export callbacks (supersedes ADR-FC-0008's
  ## install-time `Z3_fixedpoint_add_callback` call): the engine
  ## Z3 actually resolves (including its `auto-config` heuristics) is
  ## only final at query time, so that is the only point at which
  ## "is this Spacer" can be soundly decided — deciding it any earlier
  ## (e.g. at `setHandlers`) makes correctness depend on call order
  ## between `setHandlers` and a later `setParams(engine=spacer)`.
  ##
  ## Under `-d:z3WithoutFixedpointCallbacks` the gated module (and this
  ## assignment) is stripped, so this stays `nil` forever and the
  ## `if exportActivateHook != nil` check in `withInQuery` costs one
  ## always-false pointer compare — zero behavioral cost.

template withInQuery*(fp: Z3Fixedpoint, body: untyped) =
  ## INTERNAL_API choke point (ADR-FC-0005) — the *only* place that
  ## sets/clears `inQuery`, and the *only* place that fires
  ## `exportActivateHook` (lazy Spacer export-callback activation, see
  ## that var's doc comment). Every query entry point (`query`,
  ## `queryRelations` below, and `z3/spacer.queryFromLevel`) wraps its
  ## FFI-call body in this so no call site can forget either guard.
  ## `finally`-protected so `inQuery` clears even if `body` raises
  ## (e.g. a `Z3Error` from `checkErr`). `when not defined(release)`-
  ## gated — in release builds this is just the hook call then `body`,
  ## no flag, no try/finally (see the `inQuery` field's doc comment for
  ## why this isn't the RFC's literal `when defined(debug)`).
  ##
  ## The hook fires with `fp.inQuery == true` (non-release builds) —
  ## that's fine: it's an internal activation call, not a user-facing
  ## `setHandlers`/`clearHandlers` call, so ADR-FC-0005's "no box swap
  ## mid-query" guard doesn't apply to it.
  when not defined(release):
    fp.inQuery = true
    try:
      if exportActivateHook != nil: exportActivateHook(fp)
      body
    finally:
      fp.inQuery = false
  else:
    if exportActivateHook != nil: exportActivateHook(fp)
    body

proc `=destroy`(v: var Z3FixedpointOwn) {.raises: [].} =
  ## Hand-written (ADR-FC-0002): a custom `=destroy` replaces
  ## `emitRefcountLifecycle`'s field-wise destruction, so it must
  ## explicitly release `cbBox` too or it leaks. Order matters —
  ## mirrors `Z3ContextOwn.=destroy` (context.nim) and the body
  ## `emitRefcountLifecycle` generates (lifecycle.nim):
  ## 1. `Z3_fixedpoint_dec_ref` first — needs `v.ctx.raw` live.
  ## 2. Drop `cbBox` — releases the `RootRef`; ORC collects the box.
  ## 3. Release the `ctx` ARC ref — only after both of the above are
  ##    done with it.
  try:
    if not v.raw.isNil and v.ctx != nil and not v.ctx.raw.isNil:
      Z3_fixedpoint_dec_ref(v.ctx.raw, v.raw)
  except CatchableError:
    discard
  try:
    `=destroy`(v.cbBox)
  except CatchableError:
    discard
  try:
    if v.ctx != nil:
      `=destroy`(v.ctx)
  except Exception:
    discard

proc newFixedpoint*(ctx: Z3Context): Z3Fixedpoint =
  ## Fresh CHC solver bound to `ctx`.
  let raw = ctx.checkErr Z3_mk_fixedpoint(ctx.raw)
  Z3_fixedpoint_inc_ref(ctx.raw, raw)
  Z3Fixedpoint(raw: raw, ctx: ctx)

proc newFixedpoint*(): Z3Fixedpoint =
  ## Fresh CHC solver bound to the current context.
  newFixedpoint(requireCurrentContext())

proc raw*(fp: Z3Fixedpoint): RawZ3Fixedpoint {.inline.} = fp.raw
proc ctx*(fp: Z3Fixedpoint): Z3Context {.inline.} = fp.ctx

# ============================================================================
# Relation / rule / fact registration
# ============================================================================

proc registerRelation*[ArgsTup: tuple, Ret](
    fp: Z3Fixedpoint,
    decl: Z3FuncDecl[ArgsTup, Ret]) =
  ## Tell the fixedpoint solver that `decl` is a predicate it will
  ## reason about. Required before adding rules / facts that mention
  ## `decl`.
  fp.ctx.checkErrVoid Z3_fixedpoint_register_relation(
    fp.ctx.raw, fp.raw, decl.raw)

proc addRule*(fp: Z3Fixedpoint, rule: Z3Bool, name: string = "") =
  ## Add a Horn rule to the solver. `rule` is typically
  ## `forall ...vars. premise ⇒ conclusion` for the universal form,
  ## or a ground predicate application for a fact.
  let sym = if name.len == 0:
    fp.ctx.checkErr Z3_mk_string_symbol(fp.ctx.raw, cstring(""))
  else:
    fp.ctx.checkErr Z3_mk_string_symbol(fp.ctx.raw, name.cstring)
  fp.ctx.checkErrVoid Z3_fixedpoint_add_rule(
    fp.ctx.raw, fp.raw, rule.raw, sym)

proc updateRule*(fp: Z3Fixedpoint, rule: Z3Bool, name: string) =
  ## Replace an existing named rule. Names must match.
  let sym = fp.ctx.checkErr Z3_mk_string_symbol(fp.ctx.raw, name.cstring)
  fp.ctx.checkErrVoid Z3_fixedpoint_update_rule(
    fp.ctx.raw, fp.raw, rule.raw, sym)

proc assertConstraint*(fp: Z3Fixedpoint, axiom: Z3Bool) =
  ## Add a background axiom (non-rule constraint). Useful for
  ## constraining the universe of discourse.
  fp.ctx.checkErrVoid Z3_fixedpoint_assert(fp.ctx.raw, fp.raw, axiom.raw)

proc addConstraint*(fp: Z3Fixedpoint, e: Z3Bool, level: int) =
  ## Spacer-engine extension: add a constraint at a specific
  ## inductive level.
  doAssert level >= 0
  fp.ctx.checkErrVoid Z3_fixedpoint_add_constraint(
    fp.ctx.raw, fp.raw, e.raw, cuint(level))

# ============================================================================
# Query
# ============================================================================

const z3QueryCancellationMarker = "canceled"
  ## The message substring Z3 4.15.0's C++ exception implementation
  ## uses when Spacer/Datalog's query loop observes a cancellation
  ## (`Z3_interrupt` or a resource/timeout limit) mid-query. This is
  ## NOT part of Z3's stable public API — it is textual sniffing of a
  ## diagnostic string, pinned to Z3 4.15.0 (this project's pinned
  ## version). Empirically captured via `scratchpad/spike_c1b_abort.nim`
  ## / `spike_c1b_abort2.nim`, which raised
  ## `Z3OperationError(code: Z3_EXCEPTION, msg: "Z3 Z3_EXCEPTION: canceled")`.
  ## If a future Z3 version reraises the wording of this diagnostic,
  ## `runCancelableFixedpointQuery` below must be re-verified against
  ## it (the failure mode of a stale marker is safe-by-default: a
  ## genuine cancellation would simply propagate as an uncaught
  ## `Z3OperationError` again, rather than being silently misdecoded
  ## as some other status).

const z3SolverConsistentCancelReason = "interrupted"
  ## The exact string `Z3Solver.reasonUnknown()` reports after
  ## `Z3Context.interrupt()` cancels an in-flight `Z3Solver.check()`
  ## — verified empirically (`scratchpad/spike_c1_step0_reason.nim`)
  ## against `context.nim`'s existing `interrupt()` docstring, which
  ## already documents this exact word. `getReasonUnknown` below
  ## reports the same string on a cancelled fixedpoint query, per the
  ## RFC C1(d) uniformity requirement — Solver and Fixedpoint agree on
  ## what "the operator hit cancel" looks like from the caller's side,
  ## even though the two engines implement cancellation completely
  ## differently at the Z3 C level (see
  ## `runCancelableFixedpointQuery`'s doc comment).

proc isZ3QueryCancellation(e: ref Z3OperationError): bool {.inline.} =
  ## Narrow discriminator used by `runCancelableFixedpointQuery` below.
  ## A plain (non-template) proc so `strutils.contains` resolves
  ## against *this* module's imports regardless of which module
  ## instantiates the template (`z3/spacer`, notably, does not import
  ## `std/strutils` itself) — templates resolve open symbols like
  ## `contains` at the instantiation site, which would otherwise leak
  ## an import requirement onto every caller module.
  e.code == Z3_EXCEPTION and z3QueryCancellationMarker in e.msg

template runCancelableFixedpointQuery*(fp: Z3Fixedpoint,
                                        callExpr: untyped): Z3Status =
  ## Shared FFI-call + cancellation-translation choke point (RFC
  ## C1(d)) for `query`, `queryRelations` (below), and
  ## `z3/spacer.queryFromLevel` — the three `Z3_fixedpoint_query*`
  ## entry points. `callExpr` is the raw `Z3_fixedpoint_query*(...)`
  ## FFI call (untyped, so each of the three differently-shaped calls
  ## plugs straight in); this template supplies the `fp.ctx.checkErr`
  ## wrap, the `decodeLBool` decode, and the cancellation catch around
  ## both. `*`-exported so `z3/spacer` (which imports this module
  ## one-directionally) can call it too, rather than duplicating the
  ## catch a third time.
  ##
  ## ## The asymmetry this compensates for
  ##
  ## `Z3_solver_check` reports interrupt/timeout gracefully: it
  ## returns `Z3_L_UNDEF` and leaves `Z3_solver_get_reason_unknown`
  ## reading `"interrupted"` (verified:
  ## `scratchpad/spike_c1_step0_reason.nim`). Spacer/Datalog's query
  ## loop does NOT use that path: Z3 4.15.0 throws a C++ exception
  ## surfaced through the C API as error code `Z3_EXCEPTION` with
  ## message `"canceled"` (verified:
  ## `scratchpad/spike_c1b_abort{,2}.nim`). That means `fp.ctx.checkErr`
  ## raises `Z3OperationError` *before* `decodeLBool` ever runs, and
  ## the query never reaches Z3's own reason-unknown machinery
  ## (unhandled, `Z3_fixedpoint_get_reason_unknown` would keep reading
  ## `"ok"` forever). This template closes that gap so callers of
  ## `query`/`queryRelations`/`queryFromLevel` see the same graceful
  ## `zsUnknown` contract Solver already promises.
  ##
  ## ## Discriminator — narrow on purpose
  ##
  ## Catches `Z3OperationError`; treats it as a cancellation ONLY when
  ## BOTH `.code == Z3_EXCEPTION` AND the message contains the
  ## substring `z3QueryCancellationMarker` ("canceled"). Any other
  ## `Z3Error` (including a genuine `Z3OperationError`/`Z3_EXCEPTION`
  ## with a different message — some other internal Z3 fault) is NOT
  ## swallowed: it re-raises unchanged, exactly as `query` behaved
  ## before this fix. Silently downgrading an unrelated internal
  ## error to `zsUnknown` would be a correctness regression far worse
  ## than the bug this template fixes.
  ##
  ## ## Effect on cancellation
  ##
  ## Resets `fp.lastQueryCanceled = false` at the start of every call
  ## (so a prior cancellation doesn't leak into an unrelated later
  ## query's `getReasonUnknown`), then sets it `true` and yields
  ## `zsUnknown` if the cancellation discriminator matches.
  block:
    fp.lastQueryCanceled = false
    var qres: Z3Status
    try:
      qres = decodeLBool(fp.ctx.checkErr callExpr)
    except Z3OperationError as qexc:
      if isZ3QueryCancellation(qexc):
        fp.lastQueryCanceled = true
        qres = zsUnknown
      else:
        raise
    qres

proc query*(fp: Z3Fixedpoint, q: Z3Bool): Z3Status =
  ## Run the CHC decision procedure on the query formula. Returns
  ## `zsSat` if the query is reachable / derivable, `zsUnsat` if
  ## provably unreachable, `zsUnknown` otherwise — including when the
  ## query is cancelled mid-flight via `Z3Context.interrupt()` (RFC
  ## C1(d); `getReasonUnknown()` then reads `"interrupted"`, uniform
  ## with `Z3Solver.check()`'s interrupt contract).
  ##
  ## Raises `Z3Error` (typed subclass via `checkErr`) if Z3 sets an
  ## error code during the query — e.g. ill-typed formula, sort
  ## mismatch with a registered relation, or use after
  ## context-destruction. Pre-v0.5.0 this raw-cast the FFI return
  ## with no error check, silently turning Z3 errors into garbage
  ## `Z3Status` values; v0.5.0 audit closed that gap.
  fp.withInQuery:
    result = fp.runCancelableFixedpointQuery(
      Z3_fixedpoint_query(fp.ctx.raw, fp.raw, q.raw))

proc queryRelations*[ArgsTup: tuple, Ret](
    fp: Z3Fixedpoint,
    relations: openArray[Z3FuncDecl[ArgsTup, Ret]]): Z3Status =
  ## Multi-relation query — checks reachability of any of the listed
  ## predicates. Raises `Z3Error` on Z3-side failure; see `query`.
  ## Cancellation (`Z3Context.interrupt()`) is translated to
  ## `zsUnknown` the same way `query` does.
  doAssert relations.len > 0
  var raws = newSeq[RawZ3FuncDecl](relations.len)
  for i, r in relations:
    raws[i] = r.raw
  fp.withInQuery:
    result = fp.runCancelableFixedpointQuery(
      Z3_fixedpoint_query_relations(
        fp.ctx.raw, fp.raw, cuint(raws.len),
        cast[ptr UncheckedArray[RawZ3FuncDecl]](addr raws[0])))

proc getAnswer*(fp: Z3Fixedpoint): Z3Bool =
  ## Retrieve the answer formula after a `query` call. For sat
  ## queries this is a witness; for unsat queries it's a derivation
  ## (with `proof=true` set on the context, a proof object).
  let raw = fp.ctx.checkErr Z3_fixedpoint_get_answer(fp.ctx.raw, fp.raw)
  if raw.isNil:
    var e = newException(Z3InvalidUsageError,
      "Z3Fixedpoint.getAnswer: nil answer returned. Most likely cause: " &
      "query() hasn't been called, or returned zsUnknown.")
    e.code = Z3_INVALID_USAGE
    raise e
  wrap[Z3Bool](fp.ctx, raw)

proc getReasonUnknown*(fp: Z3Fixedpoint): string =
  ## Human-readable diagnostic for a `zsUnknown` query result. When
  ## the most recent query was cancelled via `Z3Context.interrupt()`
  ## (RFC C1(d)), returns `"interrupted"` — the same string
  ## `Z3Solver.reasonUnknown()` reports after an interrupted
  ## `check()` — rather than deferring to
  ## `Z3_fixedpoint_get_reason_unknown`, which Spacer/Datalog's
  ## cancellation path never populates (it stays `"ok"`; see
  ## `runCancelableFixedpointQuery`'s doc comment for why).
  if fp.lastQueryCanceled:
    z3SolverConsistentCancelReason
  else:
    $Z3_fixedpoint_get_reason_unknown(fp.ctx.raw, fp.raw)

# Note: `Z3_fixedpoint_get_ground_sat_answer` doesn't exist in
# z3_fixedpoint.h (spec correction — see §8). `getAnswer` is the
# canonical witness extractor.

# ============================================================================
# Spacer / cover / level surface
# ============================================================================

proc getNumLevels*[ArgsTup: tuple, Ret](
    fp: Z3Fixedpoint,
    pred: Z3FuncDecl[ArgsTup, Ret]): int =
  ## Number of induction levels Z3 has discovered for `pred` in its
  ## Spacer state. Useful for understanding the verification
  ## progress.
  int(Z3_fixedpoint_get_num_levels(fp.ctx.raw, fp.raw, pred.raw))

proc getCoverDelta*[ArgsTup: tuple, Ret](
    fp: Z3Fixedpoint, level: int,
    pred: Z3FuncDecl[ArgsTup, Ret]): Z3Bool =
  ## Retrieve the predicate's inductive cover at the given level
  ## (the over-approximation Spacer is maintaining).
  let raw = fp.ctx.checkErr Z3_fixedpoint_get_cover_delta(
    fp.ctx.raw, fp.raw, cint(level), pred.raw)
  wrap[Z3Bool](fp.ctx, raw)

proc addCover*[ArgsTup: tuple, Ret](
    fp: Z3Fixedpoint, level: int,
    pred: Z3FuncDecl[ArgsTup, Ret], property: Z3Bool) =
  ## Inject a hand-provided invariant at the given induction level.
  fp.ctx.checkErrVoid Z3_fixedpoint_add_cover(
    fp.ctx.raw, fp.raw, cint(level), pred.raw, property.raw)

# ============================================================================
# Introspection
# ============================================================================

proc getRules*(fp: Z3Fixedpoint): Z3AstVector =
  ## All rules currently asserted, as an `Z3AstVector` of Z3Bool ASTs.
  wrapAstVector(fp.ctx,
    fp.ctx.checkErr Z3_fixedpoint_get_rules(fp.ctx.raw, fp.raw))

proc getAssertions*(fp: Z3Fixedpoint): Z3AstVector =
  ## All background axioms currently asserted via `assertConstraint`.
  wrapAstVector(fp.ctx,
    fp.ctx.checkErr Z3_fixedpoint_get_assertions(fp.ctx.raw, fp.raw))

proc getHelp*(fp: Z3Fixedpoint): string =
  ## Z3's documentation for fixedpoint parameters. Returns a
  ## multiline string with each parameter + its meaning.
  $Z3_fixedpoint_get_help(fp.ctx.raw, fp.raw)

proc getParamDescrs*(fp: Z3Fixedpoint): Z3ParamDescrs =
  ## Parameter schema for the fixedpoint solver. Parity with
  ## `Z3Solver.getParamDescrs` / `Z3Optimize.getParamDescrs`; N7.7.
  wrapParamDescrs(fp.ctx,
    fp.ctx.checkErr Z3_fixedpoint_get_param_descrs(fp.ctx.raw, fp.raw))

proc fromString*(fp: Z3Fixedpoint, s: string): Z3AstVector =
  ## Parse SMT-LIB2 fixedpoint declarations from `s`. Adds rules and
  ## facts to `fp` in place; returns the set of query formulas found
  ## in the string (may be empty). N7.7.
  wrapAstVector(fp.ctx,
    fp.ctx.checkErr Z3_fixedpoint_from_string(fp.ctx.raw, fp.raw, s.cstring))

proc fromFile*(fp: Z3Fixedpoint, path: string): Z3AstVector =
  ## Parse an SMT-LIB2 fixedpoint file at `path`. Adds rules and facts
  ## to `fp` in place; returns the set of query formulas found in the
  ## file. File-input twin of `fromString`. N7.7.
  wrapAstVector(fp.ctx,
    fp.ctx.checkErr Z3_fixedpoint_from_file(fp.ctx.raw, fp.raw, path.cstring))

proc addFact*[ArgsTup: tuple](
    fp: Z3Fixedpoint,
    pred: Z3FuncDecl[ArgsTup, Z3Bool],
    args: openArray[uint]) =
  ## Assert a positive ground fact for `pred` in the datalog engine.
  ## Each element of `args` is the integer encoding of one column
  ## argument (the sort must be a finite-domain / bit-vector / Boolean
  ## sort as required by the datalog engine). N7.7.
  ##
  ## Equivalent to `addRule(pred(mkInt(args[0]), mkInt(args[1]), ...))`
  ## but avoids constructing AST nodes and is the idiomatic datalog
  ## interface for ground-fact bulk loading.
  var buf = newSeq[cuint](args.len)
  for i, v in args: buf[i] = cuint(v)
  fp.ctx.checkErrVoid Z3_fixedpoint_add_fact(
    fp.ctx.raw, fp.raw, pred.raw, cuint(buf.len),
    if buf.len == 0: nil
    else: cast[ptr UncheckedArray[cuint]](addr buf[0]))

# Note: `Z3_fixedpoint_push` / `_pop` don't exist in z3_fixedpoint.h
# (spec correction — see §8). The fixedpoint engine doesn't have
# user-controlled scoping; rules + facts accumulate for the lifetime
# of the handle. Users who want fresh state allocate a new
# `Z3Fixedpoint`.

# ============================================================================
# Params
# ============================================================================

proc getStatistics*(fp: Z3Fixedpoint): Z3Stats =
  ## Snapshot of the fixedpoint solver's runtime statistics.
  wrapStats(fp.ctx,
    fp.ctx.checkErr Z3_fixedpoint_get_statistics(fp.ctx.raw, fp.raw))

proc setParams*(fp: Z3Fixedpoint, p: Z3Params) =
  ## Configure the fixedpoint solver. The most user-visible knob is
  ## `engine` — one of `"spacer"` (default), `"bmc"`, `"datalog"`.
  ## Other params include `fp.engine.spacer.*`,
  ## `fp.datalog.*`, etc. — `getHelp(fp)` prints the full list.
  fp.ctx.checkErrVoid Z3_fixedpoint_set_params(fp.ctx.raw, fp.raw, p.raw)

# ============================================================================
# Pretty
# ============================================================================

proc `$`*(fp: Z3Fixedpoint): string =
  ## SMT-LIB rendering of the fixedpoint solver state — rules,
  ## assertions, registered relations.
  $Z3_fixedpoint_to_string(fp.ctx.raw, fp.raw, 0, nil)

# ============================================================================
# N7.8 — Callback registration (raw pointer / cdecl surface)
#
# These procs expose the four Z3 callback-registration functions with
# raw `pointer` state and `{.cdecl.}` function pointers. Typed-closure
# wrappers (boxing a Nim closure into a stable C-ABI thunk) are
# deferred to a follow-on RFC per the complete-lib-not-consumer directive.
# ============================================================================

template assertRawCbSurfaceOk(fp: Z3Fixedpoint, procName: string) =
  ## ADR-FC-0009 mixing-hazard guard shared by all four raw §N7.8
  ## procs below: refuses to run if the typed `setHandlers` surface
  ## (`z3/fixedpoint_callbacks`, gated) is already in use on `fp` —
  ## both surfaces write the same Z3-side `state` slot / callback
  ## registration, so mixing them produces type-confusion or a
  ## use-after-free on the next fire. `fp.cbBoxRef` is the typed
  ## surface's tell (non-nil once `setHandlers` has run); no separate
  ## flag is needed for that half. `when not defined(release)`-gated,
  ## same idiom as `inQuery` — compiles to nothing in release builds.
  when not defined(release):
    assert fp.cbBoxRef.isNil,
      "Z3Fixedpoint." & procName & ": the typed setHandlers surface " &
      "(z3/fixedpoint_callbacks) has already been used on this fp — " &
      "the raw and typed callback surfaces are mutually exclusive " &
      "per fp (ADR-FC-0009 mixing hazard: both write the same " &
      "Z3-side `state` slot)"
    fp.rawCbUsed = true

proc initRawState(fp: Z3Fixedpoint, state: pointer) =
  ## Internal, already-checked fast path for the `Z3_fixedpoint_init`
  ## FFI call — no `assertRawCbSurfaceOk` of its own. `init*` and the
  ## two `setReduce*Callback*` procs below each call
  ## `assertRawCbSurfaceOk` exactly once (with their own correct
  ## `procName`) and then this helper, instead of `init*` calling
  ## `assertRawCbSurfaceOk` a second time under the caller's name (L3
  ## fix: the old code had `setReduceAssignCallback`/
  ## `setReduceAppCallback` call `fp.init(state)`, which re-ran the
  ## assert — firing the mixing-hazard check and the `rawCbUsed = true`
  ## write twice per call, with the second firing misreporting
  ## `procName` as `"init"`). The guard's behavior is unchanged: each
  ## public entry point still asserts exactly once before touching Z3.
  Z3_fixedpoint_init(fp.ctx.raw, fp.raw, state)

proc init*(fp: Z3Fixedpoint, state: pointer) =
  ## Bind a user-defined `state` pointer to `fp`. This must be called
  ## before `setReduceAssignCallback` or `setReduceAppCallback` so that
  ## Z3 knows which state to thread through each callback invocation.
  ## Pass `nil` when no per-callback state is needed.
  ##
  ## Must not be mixed with the typed `setHandlers` surface on the
  ## same `fp` (ADR-FC-0009) — debug builds assert this.
  fp.assertRawCbSurfaceOk("init")
  fp.initRawState(state)

proc setReduceAssignCallback*(fp: Z3Fixedpoint, state: pointer,
    cb: Z3FixedpointReduceAssignCallbackFptr) =
  ## Register a destructive-update callback on `fp`. Z3 calls `cb`
  ## (with the `state` pointer) whenever the fixedpoint engine performs
  ## a register-assign step. Pass `nil` for both `state` and `cb` to
  ## deregister. Binds `state` internally (`initRawState`, the same
  ## `Z3_fixedpoint_init` call `init` makes) without re-asserting the
  ## mixing-hazard guard `init` would (L3 fix).
  ##
  ## The FFI layer accepts `pointer` for the callback argument to avoid
  ## a softlink const-qualification mismatch (`Z3_ast * const*` in C).
  ##
  ## Must not be mixed with the typed `setHandlers` surface on the
  ## same `fp` (ADR-FC-0009) — debug builds assert this.
  fp.assertRawCbSurfaceOk("setReduceAssignCallback")
  fp.initRawState(state)
  Z3_fixedpoint_set_reduce_assign_callback(fp.ctx.raw, fp.raw,
    cast[pointer](cb))

proc setReduceAppCallback*(fp: Z3Fixedpoint, state: pointer,
    cb: Z3FixedpointReduceAppCallbackFptr) =
  ## Register a term-building callback on `fp`. Z3 calls `cb` when
  ## it needs to construct a term from a relational operator; the
  ## callback can replace the result via its out-param. Pass `nil`
  ## for both arguments to deregister. Binds `state` internally
  ## (`initRawState`, the same `Z3_fixedpoint_init` call `init` makes)
  ## without re-asserting the mixing-hazard guard `init` would (L3 fix).
  ##
  ## Must not be mixed with the typed `setHandlers` surface on the
  ## same `fp` (ADR-FC-0009) — debug builds assert this.
  fp.assertRawCbSurfaceOk("setReduceAppCallback")
  fp.initRawState(state)
  Z3_fixedpoint_set_reduce_app_callback(fp.ctx.raw, fp.raw,
    cast[pointer](cb))

proc addCallback*(fp: Z3Fixedpoint, state: pointer,
    newLemmaEh: Z3FixedpointNewLemmaEh,
    predecessorEh: Z3FixedpointPredecessorEh,
    unfoldEh: Z3FixedpointUnfoldEh) =
  ## Register Spacer-engine export callbacks. `newLemmaEh` is invoked
  ## on each new lemma discovery; `predecessorEh` on predecessor-frame
  ## exploration; `unfoldEh` on each unfolding step. Any callback
  ## may be `nil` to opt out of that event. The `state` pointer is
  ## threaded through all three callbacks unchanged.
  ##
  ## Must not be mixed with the typed `setHandlers` surface on the
  ## same `fp` (ADR-FC-0009) — debug builds assert this.
  fp.assertRawCbSurfaceOk("addCallback")
  Z3_fixedpoint_add_callback(fp.ctx.raw, fp.raw, state,
    newLemmaEh, predecessorEh, unfoldEh)

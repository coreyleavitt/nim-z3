## `Z3Optimize` — solver-shaped object for optimisation problems.
##
## Z3's optimisation API generalises the satisfiability solver with
## three additions: weighted soft constraints, optimisation
## objectives (`maximize` / `minimize`), and bound retrieval via
## `upper` / `lower`. The standard hard constraints + check + model
## flow carries over unchanged.
##
## ## Phantom-typed objective handles
##
## `maximize(t: Z3Int)` returns `Z3OptHandle[Z3Int]`; `maximize(t:
## Z3BitVec[8])` returns `Z3OptHandle[Z3BitVec[8]]`. `upper(h)` /
## `lower(h)` dispatch on the type parameter so the returned bound
## comes back as the right typed AST without casts. Same precedent
## as `datatypes.read[Ret]` and `array.select[Key, Val]`.
##
## `addSoft` returns `Z3OptHandle[Z3Int]` — Z3's soft-constraint
## objective is the (possibly weighted) count of unsatisfied soft
## constraints, which is integer-sorted.
##
## ## Multi-objective behaviour
##
## Z3's default for multiple objectives is **lex** (lexicographic):
## maximise the first objective, then maximise the second subject to
## the first's optimum, and so on. Pass `priority` via `Z3Params` to
## change mode:
##
## - `"lex"` (default) — lexicographic priority chain.
## - `"box"` — each objective independently; a single model whose
##   bounds report each per-objective optimum.
## - `"pareto"` — Pareto-front enumeration; repeated `check()` calls
##   yield successive frontier points until `zsUnsat`.
##
## See `setParams`'s docstring for the full param surface (v0.5 step
## 6B's `getParamDescrs` returns the schema at runtime), and
## `tests/toptimize.nim` for working examples of each mode.

import ./ffi, ./context, ./error, ./ast, ./bitvec, ./fp, ./model, ./solver, ./params, ./astvector, ./stats, ./introspect

# ============================================================================
# Z3Optimize — lifecycle
# ============================================================================

type
  Z3OptimizeOwn = object
    raw: RawZ3Optimize
    ctx: Z3Context

  Z3Optimize* = ref Z3OptimizeOwn
    ## Reference-counted handle. Like `Z3Solver`, the underlying Z3
    ## object is refcounted and the Nim wrapper's `=destroy` drops the
    ## ref when the last `Z3Optimize` reference goes out of scope.

  Z3OptHandle*[T] = object
    ## Phantom-typed handle for an objective index. `T` is the
    ## typedesc of the bound term (`Z3Int`, `Z3Real`, `Z3BitVec[W]`)
    ## or `Z3Int` for `addSoft`. Keep a strong ref to the parent so
    ## the optimize object outlives the handle (Z3 indices refer back
    ## into per-optimize state).
    idx: cuint
    parent: Z3Optimize

emitRefcountLifecycle(Z3OptimizeOwn, Z3_optimize_dec_ref)

proc newOptimize*(ctx: Z3Context): Z3Optimize =
  ## Fresh optimiser bound to `ctx`.
  let raw = ctx.checkErr Z3_mk_optimize(ctx.raw)
  Z3_optimize_inc_ref(ctx.raw, raw)
  Z3Optimize(raw: raw, ctx: ctx)

proc newOptimize*(): Z3Optimize =
  ## Fresh optimiser bound to `currentContext()`.
  newOptimize(requireCurrentContext())

proc setParams*(o: Z3Optimize, p: Z3Params) =
  ## Configure the optimiser. The most user-visible knob is
  ## `priority` — set it as a string param to one of:
  ##
  ## - `"lex"` (default) — lexicographic; first objective is
  ##   maximised, then second is maximised subject to the first's
  ##   optimum, and so on.
  ## - `"box"` — each objective optimised independently; `upper(h)`
  ##   gives that objective's true maximum, but no single model
  ##   simultaneously witnesses all of them.
  ## - `"pareto"` — Pareto-frontier enumeration; each `check()` call
  ##   returns one frontier point as `zsSat`; once the frontier is
  ##   exhausted `check()` returns `zsUnsat`.
  ##
  ## ```nim
  ## let p = newParams()
  ## p.set("priority", "box")
  ## o.setParams(p)
  ## ```
  o.ctx.checkErrVoid Z3_optimize_set_params(o.ctx.raw, o.raw, p.raw)

# ============================================================================
# Hard + soft constraints
# ============================================================================

proc add*(o: Z3Optimize, c: Z3Bool) =
  ## Add a hard constraint. The solver must satisfy it.
  o.ctx.checkErrVoid Z3_optimize_assert(o.ctx.raw, o.raw, c.raw)

proc addSoft*(o: Z3Optimize, c: Z3Bool,
              weight = 1.0, group = ""): Z3OptHandle[Z3Int] =
  ## Add a soft constraint with a weight. Z3 minimises the weighted
  ## sum of violated soft constraints. `group` names a sub-objective
  ## — soft constraints sharing a group are optimised together as one
  ## sum; the empty string means "default group". The returned handle
  ## indexes the corresponding objective.
  let weightStr = $weight
  let groupSym = o.ctx.checkErr Z3_mk_string_symbol(o.ctx.raw,
    group.cstring)
  let idx = o.ctx.checkErr Z3_optimize_assert_soft(o.ctx.raw, o.raw,
    c.raw, weightStr.cstring, groupSym)
  Z3OptHandle[Z3Int](idx: idx, parent: o)

# ============================================================================
# maximize / minimize
# ============================================================================

proc maximize*[T: Z3Int | Z3Real | Z3BitVec](
    o: Z3Optimize, t: T): Z3OptHandle[T] =
  ## Register `t` as a maximisation objective. Constrained at compile
  ## time to numeric / orderable families (`Z3Int`, `Z3Real`,
  ## `Z3BitVec[W]`) — passing a `Z3Bool`, `Z3Seq`, `Z3Char`, etc.
  ## was previously a runtime sort error from Z3 that the wrapper then
  ## stuffed into a malformed `wrapBound` result; the constraint now
  ## rejects them at compile time.
  let idx = o.ctx.checkErr Z3_optimize_maximize(o.ctx.raw, o.raw, t.raw)
  Z3OptHandle[T](idx: idx, parent: o)

proc maximize*[E, S: static int](
    o: Z3Optimize, t: Z3Fp[E, S]): Z3OptHandle[Z3Fp[E, S]] =
  ## Register a `Z3Fp[E, S]` FP expression as a maximisation objective.
  ## Z3's C `Z3_optimize_maximize` accepts any AST sort; this overload
  ## exposes the FP variant with correct phantom typing.
  let idx = o.ctx.checkErr Z3_optimize_maximize(o.ctx.raw, o.raw, t.raw)
  Z3OptHandle[Z3Fp[E, S]](idx: idx, parent: o)

proc minimize*[T: Z3Int | Z3Real | Z3BitVec](
    o: Z3Optimize, t: T): Z3OptHandle[T] =
  ## Register `t` as a minimisation objective. Same type constraints
  ## as `maximize`.
  let idx = o.ctx.checkErr Z3_optimize_minimize(o.ctx.raw, o.raw, t.raw)
  Z3OptHandle[T](idx: idx, parent: o)

proc minimize*[E, S: static int](
    o: Z3Optimize, t: Z3Fp[E, S]): Z3OptHandle[Z3Fp[E, S]] =
  ## Register a `Z3Fp[E, S]` FP expression as a minimisation objective.
  ## Z3's C `Z3_optimize_minimize` accepts any AST sort; this overload
  ## exposes the FP variant with correct phantom typing.
  let idx = o.ctx.checkErr Z3_optimize_minimize(o.ctx.raw, o.raw, t.raw)
  Z3OptHandle[Z3Fp[E, S]](idx: idx, parent: o)

# ============================================================================
# check / model / reasonUnknown
# ============================================================================

proc check*(o: Z3Optimize): Z3Status =
  ## Solve the current hard + soft + objective set. Mirrors
  ## `Z3Solver.check()`.
  decodeLBool(o.ctx.checkErr Z3_optimize_check(o.ctx.raw, o.raw, 0, nil))

proc model*(o: Z3Optimize): Z3Model =
  ## Witness model after a `zsSat` check.
  let raw = o.ctx.checkErr Z3_optimize_get_model(o.ctx.raw, o.raw)
  wrapModel(o.ctx, raw)

proc reasonUnknown*(o: Z3Optimize): string =
  ## Diagnostic for `zsUnknown` outcomes.
  $Z3_optimize_get_reason_unknown(o.ctx.raw, o.raw)

# ============================================================================
# upper / lower — bound retrieval
# ============================================================================

proc rawBound(h: Z3OptHandle, isUpper: bool): RawZ3Ast =
  let ctx = h.parent.ctx
  if isUpper:
    ctx.checkErr Z3_optimize_get_upper(ctx.raw, h.parent.raw, h.idx)
  else:
    ctx.checkErr Z3_optimize_get_lower(ctx.raw, h.parent.raw, h.idx)

proc wrapBound[T](ctx: Z3Context, raw: RawZ3Ast): T =
  ## Z3's `optimize_get_upper`/`lower` returns the bound typed by
  ## Z3's internal representation — `Int` for Int objectives, `Real`
  ## for Real objectives, and *also Int* for BV objectives (Z3
  ## internally maps BV to its unsigned-magnitude Int). For the BV
  ## branch we convert the Int back via `Z3_mk_int2bv` so the typed
  ## return promise holds. Everything else routes through the unified
  ## `wrap[T]` template from `z3/lifecycle`.
  when T is Z3BitVec:
    # `T.W` accesses the static-int generic parameter from the type
    # variable. This compiles cleanly in Nim 2.2 for parameterised
    # `Z3BitVec[W]` instantiations; the alternative `default(T).W` is
    # equivalent but allocates a throwaway value, which the optimiser
    # then has to elide. We use the typedesc form for clarity.
    let bvRaw = ctx.checkErr Z3_mk_int2bv(ctx.raw, cuint(T.W), raw)
    wrap[T](ctx, bvRaw)
  else:
    wrap[T](ctx, raw)

proc upper*[T](h: Z3OptHandle[T]): T =
  ## Upper bound for the objective. May be a literal, an
  ## infinitesimal-bound expression (`epsilon + N` for Reals), or
  ## an "oo"-like positive-infinity term if unbounded. Caller may
  ## `simplify` for canonical form. BV bounds are re-typed back to
  ## `Z3BitVec[W]` here (Z3 returns them as Int internally).
  wrapBound[T](h.parent.ctx, rawBound(h, isUpper = true))

proc lower*[T](h: Z3OptHandle[T]): T =
  ## Lower bound for the objective. Same conversion story as `upper`.
  wrapBound[T](h.parent.ctx, rawBound(h, isUpper = false))

# ============================================================================
# Scope frames
# ============================================================================

proc push*(o: Z3Optimize) =
  ## Open a scope frame. Subsequent `add` / `addSoft` / `maximize` /
  ## `minimize` calls accumulate against this frame; `pop` discards
  ## them.
  o.ctx.checkErrVoid Z3_optimize_push(o.ctx.raw, o.raw)

proc pop*(o: Z3Optimize) =
  ## Discard the most-recent `push` frame.
  o.ctx.checkErrVoid Z3_optimize_pop(o.ctx.raw, o.raw)

template withFrame*(o: Z3Optimize, body: untyped) =
  ## Run `body` inside a freshly-pushed optimiser frame; the frame is
  ## popped on every exit path (success, exception). Mirror of
  ## `Z3Solver.withFrame`; added in the v0.5.0 medium audit (B2).
  o.push()
  try: body
  finally: o.pop()

# ============================================================================
# Param-descrs introspection
# ============================================================================

proc getParamDescrs*(o: Z3Optimize): Z3ParamDescrs =
  ## Schema of tunable params accepted by `setParams` for this
  ## optimiser. Parity with `Z3Solver.getParamDescrs` /
  ## `Z3Tactic.getParamDescrs`; v0.5.0 medium audit (B3).
  wrapParamDescrs(o.ctx,
    o.ctx.checkErr Z3_optimize_get_param_descrs(o.ctx.raw, o.raw))

# ============================================================================
# assertAndTrack / getUnsatCore (N7.6a)
# ============================================================================

proc assertAndTrack*(o: Z3Optimize, p: Z3Bool, tracker: Z3Bool) {.discardable.} =
  ## Assert hard constraint `p` tagged by tracker proposition `tracker`
  ## (a fresh Boolean literal). After an unsat `check()`, `getUnsatCore`
  ## returns the subset of tracker propositions whose assertions
  ## participate in the contradiction. Mirrors
  ## `Z3Solver.assertConstraintAndTrack`.
  o.ctx.checkErrVoid Z3_optimize_assert_and_track(o.ctx.raw, o.raw, p.raw,
                                                   tracker.raw)

proc getUnsatCore*(o: Z3Optimize): seq[Z3Bool] =
  ## Extract the minimal unsatisfiable core after `check() == zsUnsat`.
  ## Returns the subset of tracker propositions (the second argument to
  ## `assertAndTrack`) whose assertions participate in the contradiction.
  ##
  ## Returns the empty sequence if no tracked assertions are in the core
  ## (e.g. if `check()` returned sat / unknown, or if no tracked
  ## assertions were added). Mirrors `Z3Solver.getUnsatCore`.
  let raw = o.ctx.checkErr Z3_optimize_get_unsat_core(o.ctx.raw, o.raw)
  let vec = wrapAstVector(o.ctx, raw)
  vec.toSeq(Z3Bool)

# ============================================================================
# fromString / fromFile (N7.6a)
# ============================================================================

proc fromString*(o: Z3Optimize, s: string) =
  ## Parse an SMT2 string (which may include `(maximize ...)` /
  ## `(minimize ...)` directives) and assert the constraints and
  ## objectives directly into `o`. Mirrors `Z3Solver.fromString` (v0.4
  ## step 14) for the optimiser API.
  o.ctx.checkErrVoid Z3_optimize_from_string(o.ctx.raw, o.raw, s.cstring)

proc fromFile*(o: Z3Optimize, path: string) =
  ## Load an SMT2 file and assert its contents into `o`. File-input twin
  ## of `fromString`. Mirrors `Z3_solver_from_file` for the optimiser API.
  o.ctx.checkErrVoid Z3_optimize_from_file(o.ctx.raw, o.raw, path.cstring)

# ============================================================================
# getHelp (N7.6a)
# ============================================================================

proc getHelp*(o: Z3Optimize): string =
  ## Z3's documentation for optimiser parameters. Returns a multiline
  ## string with each parameter name and its meaning. Mirrors
  ## `Z3Fixedpoint.getHelp` and `Z3_fixedpoint_get_help`.
  $Z3_optimize_get_help(o.ctx.raw, o.raw)

# ============================================================================
# N7.6b — getStatistics, getAssertions, getObjectives,
#          setInitialValue, getLowerAsVector, getUpperAsVector
# ============================================================================

proc getStatistics*(o: Z3Optimize): Z3Stats =
  ## Solver-style statistics for this optimiser. Returns a `Z3Stats`
  ## handle after any `check()` call; may hold zero entries on trivial
  ## problems. Mirrors `Z3Solver.getStatistics`.
  wrapStats(o.ctx,
    o.ctx.checkErr Z3_optimize_get_statistics(o.ctx.raw, o.raw))

proc getAssertions*(o: Z3Optimize): Z3AstVector =
  ## Returns the set of asserted hard constraints (added via `add` /
  ## `assertAndTrack`) as an `Z3AstVector`. Each element is a `Z3Bool`
  ## typed AST. The vector length equals the number of asserted hard
  ## constraints at the time of the call.
  wrapAstVector(o.ctx,
    o.ctx.checkErr Z3_optimize_get_assertions(o.ctx.raw, o.raw))

proc getObjectives*(o: Z3Optimize): Z3AstVector =
  ## Returns the current set of objectives (maximize / minimize targets
  ## and soft-constraint pseudo-objectives) as a `Z3AstVector`. Each
  ## element is the objective expression passed to `maximize` /
  ## `minimize`, or the internal expression produced by `addSoft`.
  wrapAstVector(o.ctx,
    o.ctx.checkErr Z3_optimize_get_objectives(o.ctx.raw, o.raw))

proc setInitialValue*(o: Z3Optimize, v: Z3AnyAst, value: Z3AnyAst) =
  ## Provide a warm-start hint: suggest that the variable `v` should
  ## start the search at `value`. Z3 treats this as a hint only — it
  ## is never added as a constraint and may be silently ignored.
  ## Useful for guiding the optimiser toward known good regions when
  ## a prior solution or domain insight is available.
  o.ctx.checkErrVoid Z3_optimize_set_initial_value(o.ctx.raw, o.raw,
                                                    v.raw, value.raw)

proc getLowerAsVector*(o: Z3Optimize, idx: int): Z3AstVector =
  ## Multi-precision lower-bound representation for objective `idx`.
  ## Returns a `Z3AstVector` whose elements encode the bound in Z3's
  ## internal extended-number representation — typically three ASTs:
  ## the rational part, the sign-of-infinity coefficient, and the
  ## infinitesimal (epsilon) coefficient. Prefer `lower(h)` for a
  ## single-AST scalar bound; use this proc when you need the full
  ## three-component representation (e.g. to distinguish a finite bound
  ## from a bound involving an infinitesimal). Must be called after a
  ## `check()` returning `zsSat`.
  wrapAstVector(o.ctx,
    o.ctx.checkErr Z3_optimize_get_lower_as_vector(o.ctx.raw, o.raw,
                                                    cuint(idx)))

proc getUpperAsVector*(o: Z3Optimize, idx: int): Z3AstVector =
  ## Multi-precision upper-bound representation for objective `idx`.
  ## Twin of `getLowerAsVector`. Must be called after a `check()`
  ## returning `zsSat`.
  wrapAstVector(o.ctx,
    o.ctx.checkErr Z3_optimize_get_upper_as_vector(o.ctx.raw, o.raw,
                                                    cuint(idx)))

# ============================================================================
# Pretty
# ============================================================================

proc `$`*(o: Z3Optimize): string =
  ## SMT-LIB-style rendering of the optimiser's current state.
  $Z3_optimize_to_string(o.ctx.raw, o.raw)

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
## By default, multiple objectives are optimised independently in
## *box* mode — each gets its own optimum, the solver returns a
## single model whose objective bounds are reported. *Lex* (priority
## lexicographic) and *Pareto* (Pareto front) modes are deferred
## (see plan §8) — they require setting `Z3_optimize_set_params` with
## a typed `Z3Params` object, which is the v0.2 step-1 deferral.

import ./ffi, ./context, ./sort, ./ast, ./bitvec, ./model, ./solver

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

proc `=destroy`(o: Z3OptimizeOwn) {.raises: [].} =
  try:
    if not o.raw.isNil and o.ctx != nil and not o.ctx.raw.isNil:
      Z3_optimize_dec_ref(o.ctx.raw, o.raw)
  except CatchableError:
    discard

proc newOptimize*(ctx: Z3Context): Z3Optimize =
  ## Fresh optimiser bound to `ctx`.
  let raw = ctx.checkErr Z3_mk_optimize(ctx.raw)
  Z3_optimize_inc_ref(ctx.raw, raw)
  Z3Optimize(raw: raw, ctx: ctx)

proc newOptimize*(): Z3Optimize =
  ## Fresh optimiser bound to `currentContext()`.
  newOptimize(requireCurrentContext())

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

proc maximize*[T](o: Z3Optimize, t: T): Z3OptHandle[T] =
  ## Register `t` as a maximisation objective. The bound term must be
  ## a numeric / orderable AST family — `Z3Int`, `Z3Real`, or
  ## `Z3BitVec[W]`. (Booleans aren't ordered; that would be a sort
  ## error at the FFI.)
  let idx = o.ctx.checkErr Z3_optimize_maximize(o.ctx.raw, o.raw, t.raw)
  Z3OptHandle[T](idx: idx, parent: o)

proc minimize*[T](o: Z3Optimize, t: T): Z3OptHandle[T] =
  ## Register `t` as a minimisation objective. Same type constraints
  ## as `maximize`.
  let idx = o.ctx.checkErr Z3_optimize_minimize(o.ctx.raw, o.raw, t.raw)
  Z3OptHandle[T](idx: idx, parent: o)

# ============================================================================
# check / model / reasonUnknown
# ============================================================================

proc check*(o: Z3Optimize): Z3Status =
  ## Solve the current hard + soft + objective set. Mirrors
  ## `Z3Solver.check()`.
  let r = o.ctx.checkErr Z3_optimize_check(o.ctx.raw, o.raw, 0, nil)
  case ord(r)
  of -1: zsUnsat
  of 0:  zsUnknown
  of 1:  zsSat
  else:  zsUnknown

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
  ## Dispatch: Z3's `optimize_get_upper`/`lower` returns the bound
  ## typed by Z3's internal representation — `Int` for Int objectives,
  ## `Real` for Real objectives, **also `Int`** for BV objectives
  ## (Z3 internally maps BV to its unsigned-magnitude Int). For the
  ## BV branch we convert the Int back via `Z3_mk_int2bv` so the
  ## return type matches the user-facing typed promise.
  when T is Z3Int:    wrap[stInt](ctx, raw)
  elif T is Z3Real:   wrap[stReal](ctx, raw)
  elif T is Z3Bool:   wrap[stBool](ctx, raw)
  elif T is Z3BitVec:
    let bvRaw = ctx.checkErr Z3_mk_int2bv(ctx.raw, cuint(T.W), raw)
    wrapBv[T.W](ctx, bvRaw)
  else:
    {.error: "Z3OptHandle: unsupported objective type.".}

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

# ============================================================================
# Pretty
# ============================================================================

proc `$`*(o: Z3Optimize): string =
  ## SMT-LIB-style rendering of the optimiser's current state.
  $Z3_optimize_to_string(o.ctx.raw, o.raw)

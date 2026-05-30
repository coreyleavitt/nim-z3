## `Z3Goal` + `Z3Tactic` + `Z3ApplyResult` — composable solving
## strategies.
##
## ## Conceptual model
##
## A **goal** is a conjunction of formulas the user wants resolved
## (satisfied / refuted / simplified). A **tactic** is a strategy that
## rewrites a goal into one or more *sub-goals* (each easier than the
## original). Applying a tactic yields a `Z3ApplyResult` — a list of
## subgoals plus the metadata Z3 needs to convert models/proofs back
## to the original goal's space.
##
## The standard usage pattern:
##
## ```nim
## let g = newGoal()
## g.add (x > 0)
## g.add ((x + 1) * (x - 1) == x * x - 1)
## let pipeline = mkTactic("simplify").andThen(mkTactic("smt"))
## let r = pipeline.apply(g)
## for i in 0 ..< r.numSubgoals:
##   echo r.subgoal(i)
## ```
##
## ## Combinator naming
##
## Z3's SMT-LIB tactic combinators are `and-then`, `or-else`, `repeat`,
## `try-for`, `using-params`. We expose them as `andThen`, `orElse`,
## `repeat`, `tryFor`, `withParams`. The v0.2 plan §2 sketched
## ``proc `then` `` and ``proc `or` `` — `or` would shadow the boolean
## `or` we use everywhere else, and `andThen`/`orElse` match the
## upstream names more cleanly.
##
## ## Built-in tactic names
##
## A non-exhaustive list of tactics Z3 ships:
##
## - `simplify` — applies rewrite rules
## - `solve-eqs` — eliminate linear equalities
## - `smt` — full SMT solver
## - `sat` — boolean SAT solver
## - `qfnia`, `qfbv`, `qflia`, `qflra`, … — quantifier-free theories
## - `skip` (or use `tacticSkip`), `fail`
##
## Run `(get-tactics)` in a Z3 CLI session for the full list.

import ./ffi, ./context, ./ast, ./params

# ============================================================================
# Z3Goal
# ============================================================================

type
  Z3GoalOwn = object
    raw: RawZ3Goal
    ctx: Z3Context
  Z3Goal* = ref Z3GoalOwn

emitRefcountLifecycle(Z3GoalOwn, Z3_goal_dec_ref)

proc newGoal*(ctx: Z3Context, models = true, unsatCores = false,
              proofs = false): Z3Goal =
  ## Fresh goal. `models`/`unsatCores`/`proofs` enable the corresponding
  ## conversion metadata; leave them at the defaults unless you plan to
  ## extract models or unsat cores from sub-goals.
  let raw = ctx.checkErr Z3_mk_goal(ctx.raw, models, unsatCores, proofs)
  Z3_goal_inc_ref(ctx.raw, raw)
  Z3Goal(raw: raw, ctx: ctx)

proc newGoal*(models = true, unsatCores = false, proofs = false): Z3Goal =
  newGoal(requireCurrentContext(), models, unsatCores, proofs)

proc add*(g: Z3Goal, c: Z3Bool) =
  ## Add a formula to the goal's conjunction.
  g.ctx.checkErrVoid Z3_goal_assert(g.ctx.raw, g.raw, c.raw)

proc size*(g: Z3Goal): int =
  ## Number of formulas currently asserted in the goal.
  int(Z3_goal_size(g.ctx.raw, g.raw))

proc formula*(g: Z3Goal, idx: int): Z3Bool =
  ## The `idx`-th formula in the goal. Useful for inspecting what
  ## tactics produced.
  wrap[Z3Bool](g.ctx, g.ctx.checkErr Z3_goal_formula(g.ctx.raw, g.raw, cuint(idx)))

proc inconsistent*(g: Z3Goal): bool =
  ## True iff the goal contains an obviously-`false` formula. Doesn't
  ## require running a full solver.
  Z3_goal_inconsistent(g.ctx.raw, g.raw)

proc isDecidedSat*(g: Z3Goal): bool =
  ## True iff the goal is trivially satisfiable (empty or contains
  ## only `true`).
  Z3_goal_is_decided_sat(g.ctx.raw, g.raw)

proc isDecidedUnsat*(g: Z3Goal): bool =
  ## True iff the goal is trivially unsatisfiable.
  Z3_goal_is_decided_unsat(g.ctx.raw, g.raw)

proc `$`*(g: Z3Goal): string =
  $Z3_goal_to_string(g.ctx.raw, g.raw)

# Internal: wrap a freshly-returned Z3_goal handle from FFI.
proc wrapGoal(ctx: Z3Context, raw: RawZ3Goal): Z3Goal =
  if raw.isNil:
    var e = newException(Z3Error,
      "Z3 returned a nil goal handle.")
    e.code = Z3_INVALID_USAGE
    raise e
  Z3_goal_inc_ref(ctx.raw, raw)
  Z3Goal(raw: raw, ctx: ctx)

# ============================================================================
# Z3Tactic — lifecycle + constructors + combinators
# ============================================================================

type
  Z3TacticOwn = object
    raw: RawZ3Tactic
    ctx: Z3Context
  Z3Tactic* = ref Z3TacticOwn

emitRefcountLifecycle(Z3TacticOwn, Z3_tactic_dec_ref)

proc wrapTactic(ctx: Z3Context, raw: RawZ3Tactic): Z3Tactic =
  if raw.isNil:
    var e = newException(Z3Error,
      "Z3 returned a nil tactic handle.")
    e.code = Z3_INVALID_USAGE
    raise e
  Z3_tactic_inc_ref(ctx.raw, raw)
  Z3Tactic(raw: raw, ctx: ctx)

proc mkTactic*(ctx: Z3Context, name: string): Z3Tactic =
  ## Look up a built-in tactic by name. Raises `Z3Error` for unknown
  ## names. See module docstring for common names.
  wrapTactic(ctx, ctx.checkErr Z3_mk_tactic(ctx.raw, name.cstring))

proc mkTactic*(name: string): Z3Tactic =
  mkTactic(requireCurrentContext(), name)

proc tacticSkip*(ctx: Z3Context): Z3Tactic =
  ## The no-op tactic — always succeeds and returns the goal unchanged.
  wrapTactic(ctx, ctx.checkErr Z3_tactic_skip(ctx.raw))
proc tacticSkip*(): Z3Tactic = tacticSkip(requireCurrentContext())

proc tacticFail*(ctx: Z3Context): Z3Tactic =
  ## The always-fail tactic — useful as the first argument to
  ## `orElse(tacticFail(), realTactic)` for testing fallback paths.
  wrapTactic(ctx, ctx.checkErr Z3_tactic_fail(ctx.raw))
proc tacticFail*(): Z3Tactic = tacticFail(requireCurrentContext())

# --- Combinators ------------------------------------------------------------

proc andThen*(t1, t2: Z3Tactic): Z3Tactic =
  ## Sequential composition: run `t1`, then `t2` on every subgoal.
  wrapTactic(t1.ctx,
    t1.ctx.checkErr Z3_tactic_and_then(t1.ctx.raw, t1.raw, t2.raw))

proc orElse*(t1, t2: Z3Tactic): Z3Tactic =
  ## Fallback: run `t1`; if it fails, run `t2`.
  wrapTactic(t1.ctx,
    t1.ctx.checkErr Z3_tactic_or_else(t1.ctx.raw, t1.raw, t2.raw))

proc repeat*(t: Z3Tactic, maxSteps = high(int32) div 2): Z3Tactic =
  ## Repeatedly apply `t` until it produces no further change or
  ## `maxSteps` iterations elapse.
  wrapTactic(t.ctx,
    t.ctx.checkErr Z3_tactic_repeat(t.ctx.raw, t.raw, cuint(maxSteps)))

proc tryFor*(t: Z3Tactic, msTimeout: int): Z3Tactic =
  ## Apply `t` with a millisecond timeout. If the time elapses the
  ## tactic fails (which can be caught with `orElse`).
  wrapTactic(t.ctx,
    t.ctx.checkErr Z3_tactic_try_for(t.ctx.raw, t.raw, cuint(msTimeout)))

proc withParams*(t: Z3Tactic, p: Z3Params): Z3Tactic =
  ## Apply `t` configured with the parameter bag `p`. Returns a new
  ## tactic; the original `t` is unchanged.
  wrapTactic(t.ctx,
    t.ctx.checkErr Z3_tactic_using_params(t.ctx.raw, t.raw, p.raw))

# ============================================================================
# Z3ApplyResult
# ============================================================================

type
  Z3ApplyResultOwn = object
    raw: RawZ3ApplyResult
    ctx: Z3Context
  Z3ApplyResult* = ref Z3ApplyResultOwn

emitRefcountLifecycle(Z3ApplyResultOwn, Z3_apply_result_dec_ref)

proc wrapApplyResult(ctx: Z3Context, raw: RawZ3ApplyResult): Z3ApplyResult =
  if raw.isNil:
    var e = newException(Z3Error,
      "Z3 returned a nil apply-result handle.")
    e.code = Z3_INVALID_USAGE
    raise e
  Z3_apply_result_inc_ref(ctx.raw, raw)
  Z3ApplyResult(raw: raw, ctx: ctx)

proc apply*(t: Z3Tactic, g: Z3Goal): Z3ApplyResult =
  ## Run `t` on `g`. Result is a list of subgoals plus model/proof
  ## conversion metadata.
  wrapApplyResult(t.ctx,
    t.ctx.checkErr Z3_tactic_apply(t.ctx.raw, t.raw, g.raw))

proc apply*(t: Z3Tactic, g: Z3Goal, p: Z3Params): Z3ApplyResult =
  ## Parameterised apply. Equivalent to `t.withParams(p).apply(g)`,
  ## one fewer intermediate object.
  wrapApplyResult(t.ctx,
    t.ctx.checkErr Z3_tactic_apply_ex(t.ctx.raw, t.raw, g.raw, p.raw))

proc numSubgoals*(r: Z3ApplyResult): int =
  int(Z3_apply_result_get_num_subgoals(r.ctx.raw, r.raw))

proc subgoal*(r: Z3ApplyResult, idx: int): Z3Goal =
  wrapGoal(r.ctx,
    r.ctx.checkErr Z3_apply_result_get_subgoal(r.ctx.raw, r.raw, cuint(idx)))

proc `$`*(r: Z3ApplyResult): string =
  $Z3_apply_result_to_string(r.ctx.raw, r.raw)

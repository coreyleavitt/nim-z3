## `Z3Solver` — assertion + satisfiability + model retrieval.
##
## A solver carries a set of asserted boolean constraints. `check()`
## runs Z3's decision procedures to decide whether the constraints
## are jointly satisfiable; on success you can retrieve a witness
## `Z3Model` via `model()`.
##
## ## Scope frames (push / pop)
##
## Solvers maintain a stack of scope frames. Constraints asserted
## within a `push()` / `pop(1)` pair are forgotten on pop. This is
## the standard SMT idiom for hypothesis testing:
##
## ```nim
## s.push()
## s.add(extraConstraint)
## case s.check()
## of zsSat: # extraConstraint is consistent with the rest
##   ...
## of zsUnsat: # extraConstraint contradicts the rest
##   ...
## of zsUnknown: ...
## s.pop()   # remove extraConstraint; original constraints intact
## ```
##
## ## Naming
##
## `add` is the canonical operation (Python z3 / Rust z3 convention),
## matching `Z3Goal.add` and `Z3Optimize.add` for cross-handle
## consistency. We *don't* call it `assert` because Nim has a
## built-in `assert` template; overloading would create distracting
## ambiguity in user code. The tracker-tagged variant
## (`assertConstraintAndTrack`) keeps its longer name because the
## semantics differ — that's not an `add`.

import ./ffi, ./context, ./error, ./ast, ./builder, ./boolean, ./lifecycle, ./params,
       ./astvector, ./stats
export builder, boolean

type
  Z3SolverOwn = object
    raw: RawZ3Solver
    ctx: Z3Context
  Z3Solver* = ref Z3SolverOwn

  Z3Status* = enum
    ## Outcome of `Z3Solver.check()`. Divergence from
    ## IMPLEMENTATION_PLAN.md §14 Q4 (the variant-with-reason form):
    ## a plain enum reads more cleanly at the call site
    ## (`case s.check() of zsSat:` instead of
    ## `case (let r = s.check(); r.kind) of zsSat:`), and the metadata
    ## (`reasonUnknown`, eventual `unsatCore`) belongs on the solver
    ## anyway since it's solver-owned state, not a property of the
    ## decision itself.
    zsUnsat = -1
    zsUnknown = 0
    zsSat = 1

proc decodeLBool*(r: Z3_lbool): Z3Status {.inline.} =
  ## Cross-module-internal helper. Z3's `Z3_lbool` is a C int and the
  ## API contract is values in `{-1, 0, 1}`; we decode safely rather
  ## than `cast[Z3Status]` (which silently produces an invalid enum
  ## value if Z3 ever returns something out of range). The `else`
  ## branch is defensive — Z3 doesn't define other values.
  ##
  ## Cross-module consumers: `z3/fixedpoint` (`query`,
  ## `queryRelations`), `z3/solver` (`getConsequences`). See
  ## docs/INTERNAL_API.md.
  case ord(r)
  of -1: zsUnsat
  of 0:  zsUnknown
  of 1:  zsSat
  else:  zsUnknown

# ============================================================================
# Lifecycle
# ============================================================================

emitRefcountLifecycle(Z3SolverOwn, Z3_solver_dec_ref)

proc wrapSolver*(ctx: Z3Context, raw: RawZ3Solver): Z3Solver =
  ## Take ownership of a freshly-returned raw solver handle. Public so
  ## sibling modules (`z3/tactic` for `newSolverFromTactic`, future
  ## extensions) can wrap solvers obtained from their own FFI paths.
  ## Raises `Z3Error` if `raw` is nil.
  if raw.isNil:
    var e = newException(Z3InvalidUsageError,
      "Z3 returned a nil solver handle.")
    e.code = Z3_INVALID_USAGE
    raise e
  Z3_solver_inc_ref(ctx.raw, raw)
  Z3Solver(raw: raw, ctx: ctx)

proc newSolver*(ctx: Z3Context): Z3Solver =
  ## Fresh solver bound to `ctx`. The solver retains a strong reference
  ## to the context (Z3 ASTs in its assertions are context-owned), so
  ## the context can't be finalised while the solver is alive.
  wrapSolver(ctx, ctx.checkErr Z3_mk_solver(ctx.raw))

proc newSolver*(): Z3Solver =
  ## Fresh solver bound to `currentContext()`. Raises `Z3Error` with
  ## `Z3_INVALID_USAGE` if no current context is set.
  newSolver(requireCurrentContext())

# ============================================================================
# Raw-handle accessor (for model.nim which needs it)
# ============================================================================

proc raw*(s: Z3Solver): RawZ3Solver {.inline.} = s.raw
proc ctx*(s: Z3Solver): Z3Context {.inline.} = s.ctx

# ============================================================================
# Parameter configuration (v0.3 step 8)
# ============================================================================

proc setParams*(s: Z3Solver, p: Z3Params) =
  ## Apply a typed param bag to the solver. Common knobs:
  ##
  ## - `timeout` (`uint`, milliseconds) — return `zsUnknown` if the
  ##   solver hasn't decided within the budget.
  ## - `model` (`bool`, default `true`) — enable / disable model
  ##   generation. With `model = false`, `s.model()` after a sat
  ##   `check()` raises `Z3Error` because Z3 didn't produce one.
  ## - `random_seed` (`uint`) — seeds the solver's nondeterminism.
  ## - `unsat_core` (`bool`) — enable unsat-core extraction (the
  ##   `Z3_solver_get_unsat_core` surface isn't wrapped yet).
  ##
  ## Z3 silently ignores keys the solver doesn't recognise; for the
  ## per-solver list of valid keys see `Z3_solver_get_param_descrs`
  ## (not surfaced — needs its own design pass).
  ##
  ## ```nim
  ## let p = newParams()
  ## p.set("timeout", 5000'u)
  ## p.set("random_seed", 42'u)
  ## s.setParams(p)
  ## ```
  ##
  ## Mirrors `setParams(o: Z3Optimize, p: Z3Params)`. **v0.3 step 8.**
  s.ctx.checkErrVoid Z3_solver_set_params(s.ctx.raw, s.raw, p.raw)

# ============================================================================
# Assertion
# ============================================================================

proc add*(s: Z3Solver, constraint: Z3Bool) =
  ## Add `constraint` to the solver's working set. Constraints are
  ## accumulated until `check()` runs Z3's decision procedures.
  ##
  ## Asserting from a different context than the solver was created
  ## under is undefined behavior in Z3; the wrapper makes no attempt
  ## to detect or prevent this at runtime (the FFI is silent on
  ## cross-context AST usage). Stick to one context per solver, OR
  ## use `withContext` for scoping if you must.
  s.ctx.checkErrVoid Z3_solver_assert(s.ctx.raw, s.raw, constraint.raw)

# `assertConstraint` alias deleted in v0.5 step 2B (goal 11) —
# `add` is the canonical name. The longer-named
# `assertConstraintAndTrack` below stays because its semantics
# differ (it adds a *tracked* assertion).

# ============================================================================
# Tracked assertions + unsat core (v0.4 step 6)
# ============================================================================

proc assertConstraintAndTrack*(s: Z3Solver, constraint: Z3Bool,
                               tracker: Z3Bool): Z3Bool {.discardable.} =
  ## Assert `constraint` tagged by `tracker` — a fresh Bool literal
  ## (typically built via `mkBoolVar`). After `check()` returns
  ## `zsUnsat`, `getUnsatCore` returns the subset of trackers whose
  ## assertions appear in the minimal unsatisfiable core.
  ##
  ## Returns `tracker` for fluent capture:
  ##
  ## ```nim
  ## let t1 = s.assertConstraintAndTrack(x > 5, mkBoolVar("t1"))
  ## let t2 = s.assertConstraintAndTrack(x < 3, mkBoolVar("t2"))
  ## doAssert s.check() == zsUnsat
  ## let core = s.getUnsatCore()  # @[t1, t2]
  ## ```
  s.ctx.checkErrVoid Z3_solver_assert_and_track(
    s.ctx.raw, s.raw, constraint.raw, tracker.raw)
  tracker

proc track*(s: Z3Solver, constraint: Z3Bool, name: string): Z3Bool
    {.discardable.} =
  ## Convenience: create a fresh `Z3Bool` tracker named `name` and
  ## assert `constraint` tracked by it. Returns the tracker.
  ##
  ## ```nim
  ## let t1 = s.track(x > 5, "x-too-big")
  ## let t2 = s.track(x < 3, "x-too-small")
  ## doAssert s.check() == zsUnsat
  ## for tr in s.getUnsatCore():
  ##   echo $tr   # "x-too-big" / "x-too-small"
  ## ```
  let tracker = mkBoolVar(s.ctx, name)
  s.assertConstraintAndTrack(constraint, tracker)
  tracker

proc getUnsatCore*(s: Z3Solver): seq[Z3Bool] =
  ## Extract the minimal unsatisfiable core after `check() == zsUnsat`.
  ## Returns the subset of tracker propositions (the second argument
  ## to `assertConstraintAndTrack` or the proposition returned by
  ## `track`) whose assertions participate in the contradiction.
  ##
  ## Returns the empty sequence if no tracked assertions are in the
  ## core (e.g. if `check()` returned sat / unknown, or if no
  ## tracked assertions were added).
  let raw = s.ctx.checkErr Z3_solver_get_unsat_core(s.ctx.raw, s.raw)
  let vec = wrapAstVector(s.ctx, raw)
  vec.toSeq(Z3Bool)

# ============================================================================
# Statistics + consequences (v0.4 step 8)
# ============================================================================

proc getStatistics*(s: Z3Solver): Z3Stats =
  ## Snapshot of the solver's runtime statistics. Key-value table
  ## (per-decision-procedure counters, time, memory) — see
  ## `z3/stats` for the access surface (`len`, `keys`, `[key]`,
  ## `pairs` iterator, `isInt` / `getInt` / `getFloat`).
  wrapStats(s.ctx, s.ctx.checkErr Z3_solver_get_statistics(s.ctx.raw, s.raw))

proc getConsequences*(s: Z3Solver,
                     assumptions: openArray[Z3Bool],
                     variables: openArray[Z3Bool]):
                     tuple[status: Z3Status, consequences: seq[Z3Bool]] =
  ## Compute the consequences of the solver's assertions + the given
  ## assumptions over the literals in `variables`. Returns the
  ## status (sat/unsat/unknown) plus the implied literals — each as a
  ## `Z3Bool` of shape `(=> (and a_1 ... a_n) lit)` where the `a_i`
  ## are a subset of the assumptions and `lit` is one of the
  ## variables.
  let assumptionsVec = newAstVector(s.ctx)
  for a in assumptions: assumptionsVec.add(a)
  let variablesVec = newAstVector(s.ctx)
  for v in variables: variablesVec.add(v)
  let consequencesVec = newAstVector(s.ctx)
  let lbool = Z3_solver_get_consequences(s.ctx.raw, s.raw,
    assumptionsVec.raw, variablesVec.raw, consequencesVec.raw)
  let errCode = Z3_get_error_code(s.ctx.raw)
  if errCode != Z3_OK:
    raiseZ3Error(s.ctx.raw, errCode)
  result.status = decodeLBool(lbool)
  result.consequences = consequencesVec.toSeq(Z3Bool)

# Convenience: assert several constraints at once.
proc add*(s: Z3Solver, constraints: varargs[Z3Bool]) =
  ## Add multiple constraints in one call:
  ##
  ## ```nim
  ## s.add(x > 0, y > 0, x + y < 100)
  ## ```
  ##
  ## Equivalent to calling `add` once per element.
  for c in constraints:
    s.add(c)

# ============================================================================
# Decision
# ============================================================================

proc check*(s: Z3Solver): Z3Status =
  ## Run Z3's decision procedures on the current assertion set.
  ## Returns one of:
  ##
  ## - `zsSat`: assertions are jointly satisfiable; `model()` returns
  ##   a witness.
  ## - `zsUnsat`: assertions are jointly unsatisfiable; calling
  ##   `model()` will raise `Z3Error`.
  ## - `zsUnknown`: Z3 couldn't decide (timeout, incomplete theory,
  ##   etc.). `reasonUnknown()` returns a human-readable explanation.
  decodeLBool(s.ctx.checkErr Z3_solver_check(s.ctx.raw, s.raw))

proc reasonUnknown*(s: Z3Solver): string =
  ## Human-readable explanation of why the last `check()` returned
  ## `zsUnknown`. Meaningful only after such a `check()`; otherwise
  ## the returned string is unspecified.
  $Z3_solver_get_reason_unknown(s.ctx.raw, s.raw)

# ============================================================================
# Scope frames
# ============================================================================

proc push*(s: Z3Solver) =
  ## Open a new scope frame. Subsequent `add()`
  ## calls register against this frame; `pop()` discards them.
  s.ctx.checkErrVoid Z3_solver_push(s.ctx.raw, s.raw)

proc pop*(s: Z3Solver, n: int = 1) =
  ## Pop `n` scope frames, discarding all constraints asserted within
  ## them. `n = 1` (the default) pops the most-recent push.
  if n <= 0: return
  s.ctx.checkErrVoid Z3_solver_pop(s.ctx.raw, s.raw, cuint(n))

template withFrame*(s: Z3Solver, body: untyped) =
  ## Push a scope before `body`, pop it after (even on exception).
  ## Convenient for hypothetical reasoning:
  ##
  ## ```nim
  ## s.withFrame:
  ##   s.add(x == mkInt(5))
  ##   if s.check() == zsSat:
  ##     # constraint x == 5 is consistent with the rest
  ##     ...
  ## # frame popped — x == 5 no longer asserted
  ## ```
  push(s)
  try:
    body
  finally:
    pop(s, 1)

proc reset*(s: Z3Solver) =
  ## Clear all assertions and pop all scope frames. The solver is
  ## reusable as if freshly constructed (no need to call `newSolver`
  ## again).
  s.ctx.checkErrVoid Z3_solver_reset(s.ctx.raw, s.raw)

# ============================================================================
# Pretty-print
# ============================================================================

# Validity / equivalence oracles (`smtValid` / `smtEquiv`) lived here
# up through v0.2; v0.3 step 2 relocated them to `z3/semantics`. See
# that module for the surface and the rationale.

proc `$`*(s: Z3Solver): string =
  ## SMT-LIB rendering of the solver's current assertion set. Useful
  ## for diagnostic output:
  ##
  ## ```nim
  ## s.add(x > 0)
  ## s.add(x < 100)
  ## echo $s
  ## # (declare-fun x () Int)
  ## # (assert (> x 0))
  ## # (assert (< x 100))
  ## ```
  $Z3_solver_to_string(s.ctx.raw, s.raw)

# ============================================================================
# Schema introspection (v0.5 step 6B)
# ============================================================================

proc getParamDescrs*(s: Z3Solver): Z3ParamDescrs =
  ## Return the schema of parameters this solver accepts. Each
  ## parameter has a name (queryable via `pd.keys`), a kind
  ## (`pd[name]` returns a `ParamKind`), and a documentation
  ## string (`pd.getDocumentation(name)`).
  ##
  ## Used by tooling that wants to enumerate legal params before
  ## constructing a `Z3Params` against this solver, and for
  ## human-readable `(help-solver)`-style output via `$pd`.
  let raw = s.ctx.checkErr Z3_solver_get_param_descrs(s.ctx.raw, s.raw)
  wrapParamDescrs(s.ctx, raw)

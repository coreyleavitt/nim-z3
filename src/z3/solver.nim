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
      "Z3 returned a nil solver handle. " &
      "Likely causes: (a) tactic-to-solver bridge " &
      "(`newSolverFromTactic`) called with a malformed tactic; " &
      "(b) `Z3_solver_translate` against a context that no longer " &
      "exists; (c) wrapper called before the dynlib was resolvable.")
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
  runnableExamples:
    import z3
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.add x > mkInt(0)
    doAssert s.check() == zsSat
  newSolver(requireCurrentContext())

proc newSimpleSolver*(ctx: Z3Context): Z3Solver =
  ## Fresh *simple* (CDCL/DPLL) solver bound to `ctx`. Unlike
  ## `newSolver`, this solver is **not** wrapped in a tactic layer, which
  ## makes it weaker on non-linear arithmetic but gives access to the
  ## SAT-engine introspection surface:
  ##
  ## - `trail()` — literals on the current trail
  ## - `units()` / `nonUnits()` — unit vs decided literals
  ## - `levels()` — decision level per literal
  ##
  ## Use `newSolver` for general SMT; use `newSimpleSolver` when you
  ## need trail/units/levels introspection. N8.1.
  wrapSolver(ctx, ctx.checkErr Z3_mk_simple_solver(ctx.raw))

proc newSimpleSolver*(): Z3Solver =
  ## Fresh simple solver bound to `currentContext()`. Raises `Z3Error`
  ## with `Z3_INVALID_USAGE` if no current context is set. N8.1.
  newSimpleSolver(requireCurrentContext())

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
  ## - `model` (`bool`, default `true`) — *nominally* enable/disable
  ##   model generation. **Z3 4.13 silently ignores `model = false`
  ##   and always produces a model** — see GOTCHAS #13 for the
  ##   workaround (just don't call `s.model()` if you don't want it).
  ## - `random_seed` (`uint`) — seeds the solver's nondeterminism.
  ## - `unsat_core` (`bool`) — enable unsat-core extraction. Surface
  ##   the result via `assertConstraintAndTrack` + `getUnsatCore` —
  ##   both shipped in v0.4 step 6.
  ##
  ## Z3 silently ignores keys the solver doesn't recognise. The
  ## per-solver schema of valid keys + types + defaults is reachable
  ## via `s.getParamDescrs()` (v0.5 step 6B).
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
  runnableExamples:
    import z3
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.add x > mkInt(0)
    s.add x < mkInt(10)
    doAssert s.check() == zsSat
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
  runnableExamples:
    import z3
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.add x * x == mkInt(4)
    s.add x > mkInt(0)
    doAssert s.check() == zsSat
    doAssert s.model().evalInt(x) == 2
  decodeLBool(s.ctx.checkErr Z3_solver_check(s.ctx.raw, s.raw))

proc checkWith*(s: Z3Solver, assumptions: openArray[Z3Bool]): Z3Status =
  ## Check satisfiability under a *temporary* assumption set. The
  ## `assumptions` are conjoined to the solver's persistent
  ## assertions for this one call only — the next `check()` /
  ## `checkWith()` sees the original state.
  ##
  ## Standard pattern for incremental solving when push/pop frames
  ## are too heavy: each `check_assumptions` call probes a different
  ## branch of the search without rebuilding solver state.
  ##
  ## Empty `assumptions` is equivalent to `check()`.
  ##
  ## v1.0 audit round 2, item #4.
  if assumptions.len == 0:
    return s.check()
  var raws = newSeq[RawZ3Ast](assumptions.len)
  for i, a in assumptions:
    raws[i] = a.raw
  decodeLBool(s.ctx.checkErr Z3_solver_check_assumptions(
    s.ctx.raw, s.raw, cuint(raws.len),
    cast[ptr UncheckedArray[RawZ3Ast]](addr raws[0])))

proc getAssertions*(s: Z3Solver): seq[Z3Bool] =
  ## Snapshot of the solver's current assertion set as a typed
  ## sequence. Each element is a `Z3Bool` — Z3 only accepts Boolean
  ## assertions, so the typed return saves the caller a downstream
  ## decode step.
  ##
  ## Useful for debugging (`for a in s.getAssertions(): echo $a`),
  ## for serialising solver state outside `$s`, and as a building
  ## block for solver-state transforms that compose with
  ## `s.translate(otherCtx)`.
  ##
  ## v1.0 audit round 2, item #5.
  let vec = wrapAstVector(s.ctx,
    s.ctx.checkErr Z3_solver_get_assertions(s.ctx.raw, s.raw))
  vec.toSeq(Z3Bool)

proc translate*(s: Z3Solver, target: Z3Context): Z3Solver =
  ## Translate `s` and its assertion stack into `target`. The result
  ## is a fresh solver bound to `target` whose assertions are
  ## sort-equivalent ASTs in the target context.
  ##
  ## Use case: migrate solver state across contexts when you want
  ## to enable a feature flag (`proof`, `unsat_core`) that the
  ## source context wasn't built with, or move analysis to a worker
  ## thread that owns a different context (the rest of the wrapper's
  ## one-context-one-thread discipline applies).
  ##
  ## v1.0 audit round 2, item #6.
  wrapSolver(target,
    s.ctx.checkErr Z3_solver_translate(s.ctx.raw, s.raw, target.raw))

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

# ============================================================================
# SAT-engine introspection — trail / units / nonUnits / levels /
# setInitialValue (N8.1)
# ============================================================================

proc trail*(s: Z3Solver): Z3AstVector =
  ## Return the current SAT-engine trail (the sequence of Boolean
  ## literals decided or unit-propagated since the last `check()`).
  ## Meaningful only after a `check()` call on a solver backed by
  ## CDCL/DPLL internals (the default Z3 solver). Returns a non-nil
  ## `Z3AstVector`; may be empty if no propagation occurred.
  wrapAstVector(s.ctx, s.ctx.checkErr Z3_solver_get_trail(s.ctx.raw, s.raw))

proc units*(s: Z3Solver): Z3AstVector =
  ## Return the unit literals from the most recent `check()`.
  ## Unit literals are those whose value was forced by unit propagation
  ## (i.e. they appear in clauses with all other literals false).
  wrapAstVector(s.ctx, s.ctx.checkErr Z3_solver_get_units(s.ctx.raw, s.raw))

proc nonUnits*(s: Z3Solver): Z3AstVector =
  ## Return the non-unit literals from the most recent `check()`.
  ## These are literals that were decided (not forced) by the solver.
  wrapAstVector(s.ctx,
    s.ctx.checkErr Z3_solver_get_non_units(s.ctx.raw, s.raw))

proc levels*(s: Z3Solver, lits: Z3AstVector): seq[uint] =
  ## Return the decision level at which each literal in `lits` was
  ## assigned. The result is a `seq[uint]` of the same length as `lits`;
  ## `result[i]` is the decision level of `lits[i]`.
  ##
  ## The output buffer is heap-allocated (Z3 4.15 disallows VLAs on the
  ## stack for this call). If `lits` is empty, returns an empty sequence.
  let sz = lits.len
  if sz == 0:
    return @[]
  # Allocate a seq of cuint (Z3 fills it with unsigned values).
  var buf = newSeq[cuint](sz)
  Z3_solver_get_levels(s.ctx.raw, s.raw, lits.raw, cuint(sz), addr buf[0])
  # Copy to seq[uint] (cuint is C's `unsigned int`; uint is Nim's native
  # unsigned — same width on all platforms z3 targets).
  result = newSeq[uint](sz)
  for i in 0 ..< sz:
    result[i] = uint(buf[i])

proc setInitialValue*[V: Z3Term, Val: Z3Term](s: Z3Solver, v: V, value: Val) =
  ## Suggest a warm-start assignment: hint that variable `v` should begin
  ## the search at `value`. Z3 treats this as a non-binding hint and may
  ## ignore it. Useful for guiding CDCL toward a known-good region.
  ##
  ## Generic over any `Z3Term` pair; no import of `z3/introspect` required
  ## (avoids the `solver → introspect → bitvec → model → solver` cycle).
  ## Both `v` and `value` must belong to the solver's context.
  s.ctx.checkErrVoid Z3_solver_set_initial_value(
    s.ctx.raw, s.raw, v.raw, value.raw)

# ============================================================================
# Cube + congruence introspection (N8.2)
# ============================================================================

proc cube*(s: Z3Solver, vars: Z3AstVector, backtrackLevel: int): Z3AstVector =
  ## Return a cube (conjunction of literals) that the solver is willing to
  ## branch on. `vars` is a hint vector of relevant variables (may be an
  ## empty `newAstVector`); `backtrackLevel` limits the search depth.
  ##
  ## Semantics of the returned vector:
  ## - length 0 — the search space is exhausted (no more cubes)
  ## - length 1, sole element is `false` — the constraint set is UNSAT
  ## - length ≥ 1, otherwise — a valid branching cube
  ##
  ## Backed by `Z3_solver_cube`. Works with both `newSolver` and
  ## `newSimpleSolver`; call `check()` first on the solver to warm up
  ## internal state. N8.2.
  var varsCopy = vars  # may not be needed but clarifies ownership intent
  let raw = s.ctx.checkErr Z3_solver_cube(
    s.ctx.raw, s.raw, varsCopy.raw, cuint(backtrackLevel))
  wrapAstVector(s.ctx, raw)

proc congruenceRoot*[T: Z3Term](s: Z3Solver, ast: T): RawZ3Ast =
  ## Return the raw congruence-closure root of `ast` in the solver's current
  ## state. All members of the same congruence class share the same root.
  ##
  ## Returns a `RawZ3Ast` (untyped) because the root's sort is identical to
  ## `ast`'s sort but the typed family isn't statically recoverable without
  ## importing `z3/introspect` (which creates a cycle through
  ## `bitvec → model → solver`). Callers may compare `.raw` values directly
  ## to test class membership.
  ##
  ## Valid after `check()` on a CDCL-backed solver. The congruences reflect
  ## current case-split state — true *under* the current search path, not
  ## global consequences. N8.2.
  s.ctx.checkErr Z3_solver_congruence_root(s.ctx.raw, s.raw, ast.raw)

proc congruenceNext*[T: Z3Term](s: Z3Solver, ast: T): RawZ3Ast =
  ## Return the raw next AST in `ast`'s congruence class. The class
  ## forms a cyclic linked list; iterating `congruenceNext` from any member
  ## eventually returns back to the starting AST.
  ##
  ## Returns `RawZ3Ast` for the same reason as `congruenceRoot` — avoids the
  ## `solver → introspect → bitvec → model → solver` import cycle. N8.2.
  s.ctx.checkErr Z3_solver_congruence_next(s.ctx.raw, s.raw, ast.raw)

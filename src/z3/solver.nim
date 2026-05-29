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
## We expose `add` (Python z3 / Rust z3 convention) as the primary
## name, with `assertConstraint` as an explicit alias for readers
## who prefer Z3's SMT-LIB-aligned terminology. We *don't* call it
## `assert` because Nim has a built-in `assert` template; overloading
## would create distracting ambiguity in user code.

import ./ffi, ./context, ./ast, ./builder, ./boolean
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

# ============================================================================
# Lifecycle
# ============================================================================

proc `=destroy`(s: Z3SolverOwn) {.raises: [].} =
  try:
    if not s.raw.isNil and s.ctx != nil and not s.ctx.raw.isNil:
      Z3_solver_dec_ref(s.ctx.raw, s.raw)
  except CatchableError:
    discard

proc newSolver*(ctx: Z3Context): Z3Solver =
  ## Fresh solver bound to `ctx`. The solver retains a strong reference
  ## to the context (Z3 ASTs in its assertions are context-owned), so
  ## the context can't be finalised while the solver is alive.
  let raw = ctx.checkErr Z3_mk_solver(ctx.raw)
  Z3_solver_inc_ref(ctx.raw, raw)
  Z3Solver(raw: raw, ctx: ctx)

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

proc assertConstraint*(s: Z3Solver, constraint: Z3Bool) {.inline.} =
  ## Alias for `add` — closer to Z3's SMT-LIB terminology. Use whichever
  ## reads better at the call site.
  s.add(constraint)

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
  let r = s.ctx.checkErr Z3_solver_check(s.ctx.raw, s.raw)
  case ord(r)
  of -1: zsUnsat
  of 0:  zsUnknown
  of 1:  zsSat
  else:  zsUnknown   # defensive; Z3 doesn't define other values

proc reasonUnknown*(s: Z3Solver): string =
  ## Human-readable explanation of why the last `check()` returned
  ## `zsUnknown`. Meaningful only after such a `check()`; otherwise
  ## the returned string is unspecified.
  $Z3_solver_get_reason_unknown(s.ctx.raw, s.raw)

# ============================================================================
# Scope frames
# ============================================================================

proc push*(s: Z3Solver) =
  ## Open a new scope frame. Subsequent `add()` / `assertConstraint()`
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

# ============================================================================
# Validity / equivalence oracles
# ============================================================================
#
# Top-level convenience for "is this proposition valid?" — every PBT
# property over Z3 expressions wants this. Implemented as a scratch
# solver against the proposition's context so the user's primary
# solver state stays untouched. We could in principle stash a
# per-context throwaway solver, but allocating one per call is cheap
# in the timeframes SMT queries run in (microseconds to seconds), and
# the API stays trivially composable: `smtValid(p)` reads at the
# call site exactly the way you'd read it on paper.

proc smtValid*(p: Z3Bool): bool =
  ## True iff `p` is valid — i.e. `(not p)` is unsatisfiable. Uses a
  ## fresh throwaway solver bound to `p`'s context.
  ##
  ## Returns `false` for both falsified and unknown — strict validity
  ## requires Z3 prove unsat. If you need to distinguish "definitely
  ## not valid" from "couldn't decide", use a solver manually and case
  ## on `Z3Status`.
  let s = newSolver(p.ctx)
  s.add wrap[stBool](p.ctx,
    p.ctx.checkErr Z3_mk_not(p.ctx.raw, p.raw))
  s.check() == zsUnsat

proc smtEquiv*[S: static SortTag](a, b: Z3Ast[S]): bool {.inline.} =
  ## True iff `a` and `b` are SMT-level equal under every interpretation.
  ## Sugar over `smtValid(a == b)`.
  smtValid(a == b)

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

## `z3/onclause` — typed `Z3Solver.registerOnClause` surface.
##
## Wraps `Z3_solver_register_on_clause` (available on Z3 4.12+).
##
## ## Gate flag
##
## The entire module is a no-op when compiled with `-d:z3WithoutOnClause`.
## That flag is the opt-out for users on Z3 builds older than 4.12 that
## lack the symbol. The default (flag absent) means the surface is available.
##
## ## Callback contract
##
## The closure receives:
##   - `proofHint: Z3AnyAst` — may be nil (Z3 passes null for most derived
##     clauses; check `proofHint.raw.isNil` before use).
##   - `deps: seq[uint]` — indices of antecedent clauses; empty for
##     input / preprocessing clauses.
##   - `lits: Z3AstVector` — the clause's literal vector.
##
## Z3 fires the callback on the `check()` thread. The closure must not call
## back into Z3 in a way that would re-enter the solver (same restriction as
## the propagator's final handler).
##
## ## Strong-reference ownership
##
## `registerOnClause` heap-allocates a `RawZ3OnClauseBox` and pins it with
## `GC_ref`. Z3 holds the raw pointer as `user_context`; the strong ref
## prevents the GC from collecting the box before `check()` returns.
## The box is released with `GC_unref` only when the `Z3Solver` itself is
## finalised — which guarantees lifetime coverage for any number of
## `check()` calls after registration.
##
## Only one on-clause callback can be active per solver at a time; calling
## `registerOnClause` a second time replaces the previous registration
## (Z3 semantics).

when not defined(z3WithoutOnClause):
  import ./ffi, ./context, ./ast, ./solver, ./astvector, ./introspect

  # --------------------------------------------------------------------------
  # RawZ3OnClauseBox — Nim-side closure storage, GC-pinned
  # --------------------------------------------------------------------------

  type
    RawZ3OnClauseBox = ref object
      ## Heap-allocated closure holder. Z3 receives a raw `pointer` to this
      ## object as `user_context`; we keep a strong ref on the `Z3Solver` so
      ## the box can safely be used across multiple `check()` calls.
      cb:  proc(proofHint: Z3AnyAst, deps: seq[uint],
                lits: Z3AstVector) {.closure.}
      ctx: Z3Context

  # --------------------------------------------------------------------------
  # C-side shim — must be a module-level {.cdecl.} proc (not a closure).
  # Recovers the box from user_context and dispatches to the Nim closure.
  # --------------------------------------------------------------------------

  proc onClauseShim(userCtx: pointer,
                    proofHintRaw: RawZ3Ast,
                    n: cuint,
                    depsRaw: ptr UncheckedArray[cuint],
                    litsRaw: RawZ3AstVector) {.cdecl.} =
    let box = cast[RawZ3OnClauseBox](userCtx)

    # --- proofHint: wrap as Z3AnyAst (may be nil)
    let hint = wrap[Z3AnyAst](box.ctx, proofHintRaw)

    # --- deps: materialise into seq[uint]
    let count = int(n)
    var depsSeq = newSeq[uint](count)
    if count > 0 and depsRaw != nil:
      for i in 0 ..< count:
        depsSeq[i] = uint(depsRaw[i])

    # --- lits: wrap as Z3AstVector
    let lits = wrapAstVector(box.ctx, litsRaw)

    box.cb(hint, depsSeq, lits)

  # --------------------------------------------------------------------------
  # registerOnClause — public surface
  # --------------------------------------------------------------------------

  proc registerOnClause*(s: Z3Solver,
                         cb: proc(proofHint: Z3AnyAst, deps: seq[uint],
                                  lits: Z3AstVector) {.closure.}) =
    ## Register a callback that receives every clause Z3 asserts, infers, or
    ## deletes during CDCL(T) search. The callback fires on the `check()`
    ## thread; do not call back into the solver from inside it.
    ##
    ## Registering a second callback replaces the first (Z3 semantics).
    ##
    ## Requires Z3 4.12+. Compile with `-d:z3WithoutOnClause` to disable
    ## this surface on older Z3 builds.
    let box = RawZ3OnClauseBox(cb: cb, ctx: s.ctx)
    GC_ref(box)  # pin: Z3 holds a raw pointer; GC must not collect it
    let rawCtx = cast[pointer](box)
    # Cast the shim to `pointer` because the FFI declares the callback param
    # as `pointer` to avoid a Nim-vs-C `const unsigned int *` mismatch;
    # see the comment in `z3/ffi` on `Z3_solver_register_on_clause`.
    Z3_solver_register_on_clause(s.ctx.raw, s.raw, rawCtx,
                                 cast[pointer](onClauseShim))

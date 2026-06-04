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
## ## Ownership design
##
## `registerOnClause` stores the heap-allocated `RawZ3OnClauseBox` ref in a
## thread-local `Table[uint, seq[ref RawZ3OnClauseBox]]` keyed on the raw
## solver pointer. ORC keeps the boxes alive as long as they're in the table.
## Entries accumulate across repeated `registerOnClause` calls on the same
## solver (Z3 replaces the active callback, but we retain the old box to avoid
## use-after-free if Z3 fires it after the replacement). Entries are not
## reclaimed until the thread exits or the table is reset — this is acceptable
## for v2.0 because (a) solvers are short-lived in practice, and (b) each box
## is small (a closure + context ref). A future `unregisterOnClause` proc can
## trim the seq when the solver is known dead.
##
## Only one on-clause callback can be active per solver at a time; calling
## `registerOnClause` a second time replaces the previous registration
## (Z3 semantics). The previous box is retained in the table (not freed)
## because Z3 may still hold the raw pointer transiently across the boundary.

when not defined(z3WithoutOnClause):
  import std/tables
  import ./ffi, ./context, ./ast, ./solver, ./astvector, ./introspect

  # --------------------------------------------------------------------------
  # RawZ3OnClauseBox — Nim-side closure storage
  # --------------------------------------------------------------------------

  type
    RawZ3OnClauseBox = ref object
      ## Heap-allocated closure holder. Z3 receives a raw `pointer` to this
      ## object as `user_context`. The box is kept alive by ORC through the
      ## thread-local `onClauseBoxes` registry below.
      cb:  proc(proofHint: Z3AnyAst, deps: seq[uint],
                lits: Z3AstVector) {.closure.}
      ctx: Z3Context

  # Thread-local registry: raw solver pointer → seq of boxes held for that
  # solver. ORC keeps boxes alive as long as they're in this table.
  # RawZ3OnClauseBox is already a ref object; seq[RawZ3OnClauseBox] holds refs.
  var onClauseBoxes {.threadvar.}: Table[uint, seq[RawZ3OnClauseBox]]

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
    # Root via thread-local table (ORC reachability path); no GC_ref needed.
    let key = cast[uint](s.raw)
    if key notin onClauseBoxes:
      onClauseBoxes[key] = @[]
    onClauseBoxes[key].add(box)
    let rawCtx = cast[pointer](box)
    # Cast the shim to `pointer` because the FFI declares the callback param
    # as `pointer` to avoid a Nim-vs-C `const unsigned int *` mismatch;
    # see the comment in `z3/ffi` on `Z3_solver_register_on_clause`.
    Z3_solver_register_on_clause(s.ctx.raw, s.raw, rawCtx,
                                 cast[pointer](onClauseShim))

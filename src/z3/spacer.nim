## `z3/spacer` — Spacer-engine extensions to `Z3Fixedpoint`.
##
## Spacer (IC3/PDR-style model checker) is Z3's primary engine for
## software verification via Constrained Horn Clauses. This module
## exposes the Spacer-specific C API from `z3_spacer.h` as idiomatic
## Nim procs on the existing `Z3Fixedpoint` handle.
##
## ## Build gate
##
## The entire module body is guarded by `when not defined(z3WithoutSpacer):`.
## When built with `-d:z3WithoutSpacer`, this file imports cleanly but
## exports nothing. This allows Z3 distros that strip Spacer (e.g.
## minimal solver-only builds) to compile the project without modification.
##
## ## Relationship to `z3/fixedpoint`
##
## Spacer is not a new handle type — it IS the fixedpoint engine. All
## procs here extend `Z3Fixedpoint` with capabilities that only exist
## in the Spacer engine (or are labelled "Spacer-only" in the C header).
##
## ## Key procs
##
## - `queryFromLevel(fp, level, query)` — run CHC query from a given
##   induction level; useful for iterative deepening in verification.
## - `addInvariant(fp, pred, property)` — inject an assumed invariant
##   (speeds up convergence when you have external knowledge).
## - `getReachable(fp, pred)` — extract reachable states formula for
##   a predicate after a query.
## - `getGroundSatAnswer(fp)` — bottom-up ground fact witness after SAT.
## - `getRulesAlongTrace(fp)` — Horn rules fired along the cex trace.
## - `modelExtrapolate(model, fml)` — generalise a model to a formula.
## - `qeLite(bound, body)` — best-effort quantifier elimination.
## - `qeModelProject(model, bound, body)` — model-guided projection.
##
## ## Example — query from level
##
## ```nim
## let ctx = newContext()
## let fp = newFixedpoint()
## let p = newParams(); p.set("fp.engine", "spacer"); fp.setParams(p)
## let pred = mkFuncDecl[(Z3Int,), Z3Bool]("P")
## fp.registerRelation(pred)
## fp.addRule(pred(mkInt(0)))
## let res = fp.queryFromLevel(0, pred(mkInt(0)))
## doAssert res == zsSat
## ```

when not defined(z3WithoutSpacer):
  import ./ffi, ./context, ./error, ./ast, ./builder, ./solver, ./model,
         ./astvector, ./fixedpoint, ./introspect, ./funcdecl

  # ==========================================================================
  # Query extensions
  # ==========================================================================

  proc queryFromLevel*(fp: Z3Fixedpoint, level: int,
                      query: Z3Bool): Z3Status =
    ## Run the CHC decision procedure from induction level `level`. Like
    ## `query`, but starts Spacer's IC3/PDR search from the given level
    ## rather than level 0. Useful for resuming or deepening a previous
    ## bounded query.
    ##
    ## Returns `zsSat`, `zsUnsat`, or `zsUnknown`.
    doAssert level >= 0
    let res = fp.ctx.checkErr Z3_fixedpoint_query_from_lvl(
      fp.ctx.raw, fp.raw, query.raw, cuint(level))
    decodeLBool(res)

  # ==========================================================================
  # Invariant + reachability
  # ==========================================================================

  proc addInvariant*[ArgsTup: tuple, Ret](
      fp: Z3Fixedpoint,
      pred: Z3FuncDecl[ArgsTup, Ret],
      property: Z3Bool) =
    ## Inject an assumed invariant for `pred` into Spacer's state.
    ## The `property` formula should describe a property that `pred`
    ## is assumed to satisfy at every reachable state.
    ##
    ## Note: this is an assumption, not a proof obligation. Spacer will
    ## use `property` to accelerate convergence. If the invariant is
    ## incorrect, soundness is not guaranteed.
    fp.ctx.checkErrVoid Z3_fixedpoint_add_invariant(
      fp.ctx.raw, fp.raw, pred.raw, property.raw)

  proc getReachable*[ArgsTup: tuple, Ret](
      fp: Z3Fixedpoint,
      pred: Z3FuncDecl[ArgsTup, Ret]): Z3AnyAst =
    ## Retrieve the reachable states formula for `pred` after a query.
    ## Spacer computes an over-approximation of the reachable states;
    ## this proc exposes that approximation as a Z3 formula.
    let raw = fp.ctx.checkErr Z3_fixedpoint_get_reachable(
      fp.ctx.raw, fp.raw, pred.raw)
    wrap[Z3AnyAst](fp.ctx, raw)

  # ==========================================================================
  # Ground sat answer + trace
  # ==========================================================================

  proc getGroundSatAnswer*(fp: Z3Fixedpoint): Z3AnyAst =
    ## Retrieve a bottom-up sequence of ground facts witnessing the last
    ## SAT query. Must be called after `query` (or `queryFromLevel`)
    ## returned `zsSat`.
    ##
    ## Raises `Z3InvalidUsageError` if no SAT answer is available
    ## (i.e. query was not called, or returned zsUnsat / zsUnknown).
    let raw = fp.ctx.checkErr Z3_fixedpoint_get_ground_sat_answer(
      fp.ctx.raw, fp.raw)
    if raw.isNil:
      var e = newException(Z3InvalidUsageError,
        "Z3Fixedpoint.getGroundSatAnswer: nil answer returned. " &
        "Most likely cause: query() hasn't returned zsSat.")
      e.code = Z3_INVALID_USAGE
      raise e
    wrap[Z3AnyAst](fp.ctx, raw)

  proc getRulesAlongTrace*(fp: Z3Fixedpoint): Z3AstVector =
    ## The list of Horn rules fired along the counterexample trace.
    ## Must be called after a SAT query. The vector may be empty if
    ## the engine didn't build a trace (e.g. trivial ground fact).
    wrapAstVector(fp.ctx,
      fp.ctx.checkErr Z3_fixedpoint_get_rules_along_trace(
        fp.ctx.raw, fp.raw))

  # ==========================================================================
  # Model extrapolation and quantifier elimination
  # ==========================================================================

  proc modelExtrapolate*(model: Z3Model, fml: Z3AnyAst): Z3AnyAst =
    ## Extrapolate a model of `fml` to a generalised formula.
    ## Z3 computes a formula `φ` such that:
    ##   1. `model ⊨ φ`  (model satisfies the result)
    ##   2. `φ ⊨ fml`    (result implies the original formula)
    ##
    ## This "cube generalisation" is the core step in IC3/PDR lifting.
    ## Useful for computing abstract predecessors in software verification.
    let raw = model.ctx.checkErr Z3_model_extrapolate(
      model.ctx.raw, model.raw, fml.raw)
    wrap[Z3AnyAst](model.ctx, raw)

  proc qeLite*(bound: Z3AstVector, body: Z3AnyAst): Z3AnyAst =
    ## Best-effort quantifier elimination. Eliminates the variables in
    ## `bound` from `body` using a lightweight (possibly incomplete)
    ## QE procedure.
    ##
    ## `bound` is a `Z3AstVector` of free constants to eliminate. The
    ## result is a formula with those variables projected out. When the
    ## procedure cannot fully eliminate a variable, it leaves quantifiers
    ## in place (hence "lite" / best-effort).
    let raw = body.ctx.checkErr Z3_qe_lite(
      body.ctx.raw, bound.raw, body.raw)
    wrap[Z3AnyAst](body.ctx, raw)

  proc qeModelProject*(model: Z3Model,
                       bound: openArray[Z3AnyAst],
                       body: Z3AnyAst): Z3AnyAst =
    ## Project `bound` variables out of `body` guided by `model`.
    ## Unlike `qeLite`, this uses the model to resolve which branch to
    ## keep, making it complete for the model-consistent projection.
    ##
    ## `bound` is a sequence of free constants (app ASTs). Each element
    ## is converted to `Z3_app` form via `Z3_to_app`. The result is a
    ## formula over the remaining variables that is implied by `body`
    ## and consistent with `model`.
    if bound.len == 0:
      # Nothing to project — return body unchanged via inc_ref/wrap
      return wrap[Z3AnyAst](body.ctx, body.raw)
    var apps = newSeq[RawZ3App](bound.len)
    for i, b in bound:
      apps[i] = Z3_to_app(body.ctx.raw, b.raw)
    let raw = body.ctx.checkErr Z3_qe_model_project(
      body.ctx.raw, model.raw,
      cuint(apps.len),
      cast[ptr UncheckedArray[RawZ3App]](addr apps[0]),
      body.raw)
    wrap[Z3AnyAst](body.ctx, raw)

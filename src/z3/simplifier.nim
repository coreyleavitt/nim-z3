## `Z3Simplifier` — named simplification strategies (N8.7).
##
## A simplifier is a named, composable rewriting strategy that can be
## attached to a solver via `addSimplifier`. Unlike tactics, simplifiers
## run incrementally as assertions are added — they pre-process each
## assertion before it enters the solver's internal data structures.
##
## ## Typical usage
##
## ```nim
## let ctx = newContext()
## let s = newSolver(ctx)
## let simp = mkSimplifier(ctx, "elim-and")
## addSimplifier(s, simp)
## s.add(x > 0)
## doAssert s.check() == zsSat
## ```
##
## ## Composition
##
## Two simplifiers can be composed sequentially with `andThen`:
##
## ```nim
## let composed = andThen(mkSimplifier(ctx, "elim-and"),
##                        mkSimplifier(ctx, "propagate-values"))
## addSimplifier(s, composed)
## ```
##
## ## Built-in simplifier names
##
## Run `allSimplifierNames(ctx)` for the full list. Common names:
## - `"elim-and"` — eliminate conjunctions
## - `"propagate-values"` — constant propagation
## - `"ctx-simplify"` — contextual simplification
## - `"bit-blast"` — bit-vector blasting
##
## ## Feature gate
##
## Gated on Z3 4.12+. Opt out entirely with `-d:z3WithoutSimplifierObject`.
## `allSimplifierNames` / enumeration surface in `z3/tactic` is always available.

import ./ffi, ./context, ./error, ./lifecycle, ./params, ./solver

when not defined(z3WithoutSimplifierObject):

  # ==========================================================================
  # Type declaration (ADR-N0006 v3: plain object + ref alias)
  # ==========================================================================

  type
    Z3SimplifierOwn* = object
      raw*: RawZ3Simplifier
      ctx*: Z3Context
    Z3Simplifier* = ref Z3SimplifierOwn

  emitRefcountLifecycle(Z3SimplifierOwn, Z3_simplifier_dec_ref)

  # ==========================================================================
  # Internal wrap helper
  # ==========================================================================

  proc wrapSimplifier*(ctx: Z3Context, raw: RawZ3Simplifier): Z3Simplifier =
    ## Take ownership of a freshly-returned raw simplifier handle.
    ## Raises `Z3Error` if `raw` is nil.
    if raw.isNil:
      var e = newException(Z3InvalidUsageError,
        "Z3 returned a nil simplifier handle. " &
        "Likely cause: unknown simplifier name passed to mkSimplifier. " &
        "Call allSimplifierNames(ctx) for the full list.")
      e.code = Z3_INVALID_USAGE
      raise e
    Z3_simplifier_inc_ref(ctx.raw, raw)
    Z3Simplifier(raw: raw, ctx: ctx)

  # ==========================================================================
  # Constructors
  # ==========================================================================

  proc mkSimplifier*(ctx: Z3Context, name: string): Z3Simplifier =
    ## Look up a built-in simplifier by name. Raises `Z3Error` for
    ## unknown names. See module docstring for common names; call
    ## `allSimplifierNames(ctx)` (from `z3/tactic`) for the full list.
    ##
    runnableExamples:
      import z3
      let ctx = newContext()
      let simp = mkSimplifier(ctx, "elim-and")
      doAssert simp != nil
    wrapSimplifier(ctx, ctx.checkErr Z3_mk_simplifier(ctx.raw, name.cstring))

  proc mkSimplifier*(name: string): Z3Simplifier =
    ## Look up a built-in simplifier in the current context.
    mkSimplifier(requireCurrentContext(), name)

  # ==========================================================================
  # Typed surface
  # ==========================================================================

  proc addSimplifier*(s: Z3Solver, simp: Z3Simplifier): Z3Solver =
    ## Return a new solver that is a copy of `s` with `simp` installed.
    ## The simplifier pre-processes each assertion as it is added via
    ## `add(...)`, rewriting it before it enters Z3's internal data
    ## structures.
    ##
    ## `Z3_solver_add_simplifier` returns a fresh solver handle; this
    ## wrapper ref-counts and returns it as a `Z3Solver`. The original
    ## `s` is unmodified. Typical usage:
    ##
    runnableExamples:
      import z3
      let ctx = newContext()
      let simp = mkSimplifier(ctx, "elim-and")
      let x = mkIntVar(ctx, "x")
      let s = newSolver(ctx).addSimplifier(simp)
      s.add(x > mkInt(ctx, 0))
      doAssert s.check() == zsSat
    ##
    ## ```nim
    ## let s = newSolver(ctx).addSimplifier(mkSimplifier(ctx, "elim-and"))
    ## ```
    wrapSolver(s.ctx,
      s.ctx.checkErr Z3_solver_add_simplifier(s.ctx.raw, s.raw, simp.raw))

  proc andThen*(s1, s2: Z3Simplifier): Z3Simplifier =
    ## Compose two simplifiers sequentially: `s1` runs first, then `s2`
    ## on the result. Both simplifiers must belong to the same context.
    wrapSimplifier(s1.ctx,
      s1.ctx.checkErr Z3_simplifier_and_then(s1.ctx.raw, s1.raw, s2.raw))

  proc usingParams*(s: Z3Simplifier, p: Z3Params): Z3Simplifier =
    ## Return a copy of `s` configured with the parameter bag `p`.
    ## The original `s` is unchanged.
    wrapSimplifier(s.ctx,
      s.ctx.checkErr Z3_simplifier_using_params(s.ctx.raw, s.raw, p.raw))

  proc getParamDescrs*(s: Z3Simplifier): Z3ParamDescrs =
    ## Return the schema of parameters this simplifier accepts.
    let raw = s.ctx.checkErr Z3_simplifier_get_param_descrs(s.ctx.raw, s.raw)
    wrapParamDescrs(s.ctx, raw)

  proc getHelp*(s: Z3Simplifier): string =
    ## Human-readable help string for this simplifier, listing its
    ## configurable parameters.
    $Z3_simplifier_get_help(s.ctx.raw, s.raw)

  # `$` is intentionally absent from Z3Simplifier. `getHelp(s)` returns
  # parameter documentation (not a value representation), which is
  # surprising as a `$` result. Call `s.getHelp()` explicitly when you
  # need the help text.

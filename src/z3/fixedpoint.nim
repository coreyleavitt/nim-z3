## `z3/fixedpoint` — Horn-clause / Constrained Horn Clause (CHC) solver.
##
## `Z3Fixedpoint` is Z3's specialised decision procedure for CHC
## verification, datalog, and Spacer-style model checking. Use it
## when your problem fits the Horn shape:
##
## - **Relations**: predicate symbols (`Z3FuncDecl[..., Z3Bool]`)
##   registered with `registerRelation`.
## - **Rules**: universally-quantified Horn clauses
##   (`forall x. premise ⇒ conclusion`) added via `addRule`.
## - **Facts**: ground assertions added via `addRule` (with no
##   quantifier) or `addFact` (for the datalog engine's
##   finite-domain shortcut).
## - **Queries**: `query` runs the CHC decision procedure;
##   returns `zsSat` (the query is reachable / derivable),
##   `zsUnsat` (provably unreachable), or `zsUnknown`.
##
## ## Engine selection
##
## Z3 ships three CHC engines:
##
## - **`spacer`** (default in modern Z3) — IC3/PDR-style model checker
##   for software verification.
## - **`bmc`** — bounded model checking; good for finite-state
##   reachability questions.
## - **`datalog`** — finite-domain bottom-up evaluation; the
##   classical relational-algebra engine.
##
## Switch engines via `setParams`:
##
## ```nim
## let p = newParams()
## p.set("engine", "datalog")
## fp.setParams(p)
## ```
##
## ## Canonical example — graph reachability
##
## ```nim
## let ctx = newContext()
## let fp = newFixedpoint()
## let p = newParams(); p.set("engine", "datalog"); fp.setParams(p)
##
## let edge = mkFuncDecl[(Z3Int, Z3Int), Z3Bool]("edge")
## let path = mkFuncDecl[(Z3Int, Z3Int), Z3Bool]("path")
## fp.registerRelation(edge); fp.registerRelation(path)
##
## let x = mkIntVar("x"); let y = mkIntVar("y"); let z = mkIntVar("z")
##
## # Rules
## fp.addRule(forall(x, y, edge(x, y).implies(path(x, y))))
## fp.addRule(forall(x, y, z,
##   (edge(x, y) and path(y, z)).implies(path(x, z))))
##
## # Facts
## fp.addRule(edge(mkInt(1), mkInt(2)))
## fp.addRule(edge(mkInt(2), mkInt(3)))
##
## # Query
## doAssert fp.query(path(mkInt(1), mkInt(3))) == zsSat
## ```

import ./ffi, ./context, ./error, ./ast, ./builder, ./solver, ./params,
       ./funcdecl, ./astvector, ./stats

# ============================================================================
# Z3Fixedpoint — ref-typed handle
# ============================================================================

type
  Z3FixedpointOwn = object
    raw: RawZ3Fixedpoint
    ctx: Z3Context
  Z3Fixedpoint* = ref Z3FixedpointOwn

emitRefcountLifecycle(Z3FixedpointOwn, Z3_fixedpoint_dec_ref)

proc newFixedpoint*(ctx: Z3Context): Z3Fixedpoint =
  ## Fresh CHC solver bound to `ctx`.
  let raw = ctx.checkErr Z3_mk_fixedpoint(ctx.raw)
  Z3_fixedpoint_inc_ref(ctx.raw, raw)
  Z3Fixedpoint(raw: raw, ctx: ctx)

proc newFixedpoint*(): Z3Fixedpoint =
  ## Fresh CHC solver bound to the current context.
  newFixedpoint(requireCurrentContext())

proc raw*(fp: Z3Fixedpoint): RawZ3Fixedpoint {.inline.} = fp.raw
proc ctx*(fp: Z3Fixedpoint): Z3Context {.inline.} = fp.ctx

# ============================================================================
# Relation / rule / fact registration
# ============================================================================

proc registerRelation*[ArgsTup: tuple, Ret](
    fp: Z3Fixedpoint,
    decl: Z3FuncDecl[ArgsTup, Ret]) =
  ## Tell the fixedpoint solver that `decl` is a predicate it will
  ## reason about. Required before adding rules / facts that mention
  ## `decl`.
  fp.ctx.checkErrVoid Z3_fixedpoint_register_relation(
    fp.ctx.raw, fp.raw, decl.raw)

proc addRule*(fp: Z3Fixedpoint, rule: Z3Bool, name: string = "") =
  ## Add a Horn rule to the solver. `rule` is typically
  ## `forall ...vars. premise ⇒ conclusion` for the universal form,
  ## or a ground predicate application for a fact.
  let sym = if name.len == 0:
    fp.ctx.checkErr Z3_mk_string_symbol(fp.ctx.raw, cstring(""))
  else:
    fp.ctx.checkErr Z3_mk_string_symbol(fp.ctx.raw, name.cstring)
  fp.ctx.checkErrVoid Z3_fixedpoint_add_rule(
    fp.ctx.raw, fp.raw, rule.raw, sym)

proc updateRule*(fp: Z3Fixedpoint, rule: Z3Bool, name: string) =
  ## Replace an existing named rule. Names must match.
  let sym = fp.ctx.checkErr Z3_mk_string_symbol(fp.ctx.raw, name.cstring)
  fp.ctx.checkErrVoid Z3_fixedpoint_update_rule(
    fp.ctx.raw, fp.raw, rule.raw, sym)

proc assertConstraint*(fp: Z3Fixedpoint, axiom: Z3Bool) =
  ## Add a background axiom (non-rule constraint). Useful for
  ## constraining the universe of discourse.
  fp.ctx.checkErrVoid Z3_fixedpoint_assert(fp.ctx.raw, fp.raw, axiom.raw)

proc addConstraint*(fp: Z3Fixedpoint, e: Z3Bool, level: int) =
  ## Spacer-engine extension: add a constraint at a specific
  ## inductive level.
  doAssert level >= 0
  fp.ctx.checkErrVoid Z3_fixedpoint_add_constraint(
    fp.ctx.raw, fp.raw, e.raw, cuint(level))

# ============================================================================
# Query
# ============================================================================

proc query*(fp: Z3Fixedpoint, q: Z3Bool): Z3Status =
  ## Run the CHC decision procedure on the query formula. Returns
  ## `zsSat` if the query is reachable / derivable, `zsUnsat` if
  ## provably unreachable, `zsUnknown` otherwise.
  ##
  ## Raises `Z3Error` (typed subclass via `checkErr`) if Z3 sets an
  ## error code during the query — e.g. ill-typed formula, sort
  ## mismatch with a registered relation, or use after
  ## context-destruction. Pre-v0.5.0 this raw-cast the FFI return
  ## with no error check, silently turning Z3 errors into garbage
  ## `Z3Status` values; v0.5.0 audit closed that gap.
  let res = fp.ctx.checkErr Z3_fixedpoint_query(fp.ctx.raw, fp.raw, q.raw)
  decodeLBool(res)

proc queryRelations*[ArgsTup: tuple, Ret](
    fp: Z3Fixedpoint,
    relations: openArray[Z3FuncDecl[ArgsTup, Ret]]): Z3Status =
  ## Multi-relation query — checks reachability of any of the listed
  ## predicates. Raises `Z3Error` on Z3-side failure; see `query`.
  doAssert relations.len > 0
  var raws = newSeq[RawZ3FuncDecl](relations.len)
  for i, r in relations:
    raws[i] = r.raw
  let res = fp.ctx.checkErr Z3_fixedpoint_query_relations(
    fp.ctx.raw, fp.raw, cuint(raws.len),
    cast[ptr UncheckedArray[RawZ3FuncDecl]](addr raws[0]))
  decodeLBool(res)

proc getAnswer*(fp: Z3Fixedpoint): Z3Bool =
  ## Retrieve the answer formula after a `query` call. For sat
  ## queries this is a witness; for unsat queries it's a derivation
  ## (with `proof=true` set on the context, a proof object).
  let raw = fp.ctx.checkErr Z3_fixedpoint_get_answer(fp.ctx.raw, fp.raw)
  if raw.isNil:
    var e = newException(Z3InvalidUsageError,
      "Z3Fixedpoint.getAnswer: nil answer returned. Most likely cause: " &
      "query() hasn't been called, or returned zsUnknown.")
    e.code = Z3_INVALID_USAGE
    raise e
  wrap[Z3Bool](fp.ctx, raw)

proc getReasonUnknown*(fp: Z3Fixedpoint): string =
  ## Human-readable diagnostic for a `zsUnknown` query result.
  $Z3_fixedpoint_get_reason_unknown(fp.ctx.raw, fp.raw)

# Note: `Z3_fixedpoint_get_ground_sat_answer` doesn't exist in
# z3_fixedpoint.h (spec correction — see §8). `getAnswer` is the
# canonical witness extractor.

# ============================================================================
# Spacer / cover / level surface
# ============================================================================

proc getNumLevels*[ArgsTup: tuple, Ret](
    fp: Z3Fixedpoint,
    pred: Z3FuncDecl[ArgsTup, Ret]): int =
  ## Number of induction levels Z3 has discovered for `pred` in its
  ## Spacer state. Useful for understanding the verification
  ## progress.
  int(Z3_fixedpoint_get_num_levels(fp.ctx.raw, fp.raw, pred.raw))

proc getCoverDelta*[ArgsTup: tuple, Ret](
    fp: Z3Fixedpoint, level: int,
    pred: Z3FuncDecl[ArgsTup, Ret]): Z3Bool =
  ## Retrieve the predicate's inductive cover at the given level
  ## (the over-approximation Spacer is maintaining).
  let raw = fp.ctx.checkErr Z3_fixedpoint_get_cover_delta(
    fp.ctx.raw, fp.raw, cint(level), pred.raw)
  wrap[Z3Bool](fp.ctx, raw)

proc addCover*[ArgsTup: tuple, Ret](
    fp: Z3Fixedpoint, level: int,
    pred: Z3FuncDecl[ArgsTup, Ret], property: Z3Bool) =
  ## Inject a hand-provided invariant at the given induction level.
  fp.ctx.checkErrVoid Z3_fixedpoint_add_cover(
    fp.ctx.raw, fp.raw, cint(level), pred.raw, property.raw)

# ============================================================================
# Introspection
# ============================================================================

proc getRules*(fp: Z3Fixedpoint): Z3AstVector =
  ## All rules currently asserted, as an `Z3AstVector` of Z3Bool ASTs.
  wrapAstVector(fp.ctx,
    fp.ctx.checkErr Z3_fixedpoint_get_rules(fp.ctx.raw, fp.raw))

proc getAssertions*(fp: Z3Fixedpoint): Z3AstVector =
  ## All background axioms currently asserted via `assertConstraint`.
  wrapAstVector(fp.ctx,
    fp.ctx.checkErr Z3_fixedpoint_get_assertions(fp.ctx.raw, fp.raw))

proc getHelp*(fp: Z3Fixedpoint): string =
  ## Z3's documentation for fixedpoint parameters. Returns a
  ## multiline string with each parameter + its meaning.
  $Z3_fixedpoint_get_help(fp.ctx.raw, fp.raw)

proc getParamDescrs*(fp: Z3Fixedpoint): Z3ParamDescrs =
  ## Parameter schema for the fixedpoint solver. Parity with
  ## `Z3Solver.getParamDescrs` / `Z3Optimize.getParamDescrs`; N7.7.
  wrapParamDescrs(fp.ctx,
    fp.ctx.checkErr Z3_fixedpoint_get_param_descrs(fp.ctx.raw, fp.raw))

proc fromString*(fp: Z3Fixedpoint, s: string): Z3AstVector =
  ## Parse SMT-LIB2 fixedpoint declarations from `s`. Adds rules and
  ## facts to `fp` in place; returns the set of query formulas found
  ## in the string (may be empty). N7.7.
  wrapAstVector(fp.ctx,
    fp.ctx.checkErr Z3_fixedpoint_from_string(fp.ctx.raw, fp.raw, s.cstring))

proc fromFile*(fp: Z3Fixedpoint, path: string): Z3AstVector =
  ## Parse an SMT-LIB2 fixedpoint file at `path`. Adds rules and facts
  ## to `fp` in place; returns the set of query formulas found in the
  ## file. File-input twin of `fromString`. N7.7.
  wrapAstVector(fp.ctx,
    fp.ctx.checkErr Z3_fixedpoint_from_file(fp.ctx.raw, fp.raw, path.cstring))

proc addFact*[ArgsTup: tuple](
    fp: Z3Fixedpoint,
    pred: Z3FuncDecl[ArgsTup, Z3Bool],
    args: openArray[uint]) =
  ## Assert a positive ground fact for `pred` in the datalog engine.
  ## Each element of `args` is the integer encoding of one column
  ## argument (the sort must be a finite-domain / bit-vector / Boolean
  ## sort as required by the datalog engine). N7.7.
  ##
  ## Equivalent to `addRule(pred(mkInt(args[0]), mkInt(args[1]), ...))`
  ## but avoids constructing AST nodes and is the idiomatic datalog
  ## interface for ground-fact bulk loading.
  var buf = newSeq[cuint](args.len)
  for i, v in args: buf[i] = cuint(v)
  fp.ctx.checkErrVoid Z3_fixedpoint_add_fact(
    fp.ctx.raw, fp.raw, pred.raw, cuint(buf.len),
    if buf.len == 0: nil
    else: cast[ptr UncheckedArray[cuint]](addr buf[0]))

# Note: `Z3_fixedpoint_push` / `_pop` don't exist in z3_fixedpoint.h
# (spec correction — see §8). The fixedpoint engine doesn't have
# user-controlled scoping; rules + facts accumulate for the lifetime
# of the handle. Users who want fresh state allocate a new
# `Z3Fixedpoint`.

# ============================================================================
# Params
# ============================================================================

proc getStatistics*(fp: Z3Fixedpoint): Z3Stats =
  ## Snapshot of the fixedpoint solver's runtime statistics.
  wrapStats(fp.ctx,
    fp.ctx.checkErr Z3_fixedpoint_get_statistics(fp.ctx.raw, fp.raw))

proc setParams*(fp: Z3Fixedpoint, p: Z3Params) =
  ## Configure the fixedpoint solver. The most user-visible knob is
  ## `engine` — one of `"spacer"` (default), `"bmc"`, `"datalog"`.
  ## Other params include `fp.engine.spacer.*`,
  ## `fp.datalog.*`, etc. — `getHelp(fp)` prints the full list.
  fp.ctx.checkErrVoid Z3_fixedpoint_set_params(fp.ctx.raw, fp.raw, p.raw)

# ============================================================================
# Pretty
# ============================================================================

proc `$`*(fp: Z3Fixedpoint): string =
  ## SMT-LIB rendering of the fixedpoint solver state — rules,
  ## assertions, registered relations.
  $Z3_fixedpoint_to_string(fp.ctx.raw, fp.raw, 0, nil)

# ============================================================================
# N7.8 — Callback registration (raw pointer / cdecl surface)
#
# These procs expose the four Z3 callback-registration functions with
# raw `pointer` state and `{.cdecl.}` function pointers. Typed-closure
# wrappers (boxing a Nim closure into a stable C-ABI thunk) are
# deferred to a follow-on RFC per the complete-lib-not-consumer directive.
# ============================================================================

proc init*(fp: Z3Fixedpoint, state: pointer) =
  ## Bind a user-defined `state` pointer to `fp`. This must be called
  ## before `setReduceAssignCallback` or `setReduceAppCallback` so that
  ## Z3 knows which state to thread through each callback invocation.
  ## Pass `nil` when no per-callback state is needed.
  Z3_fixedpoint_init(fp.ctx.raw, fp.raw, state)

proc setReduceAssignCallback*(fp: Z3Fixedpoint, state: pointer,
    cb: Z3FixedpointReduceAssignCallbackFptr) =
  ## Register a destructive-update callback on `fp`. Z3 calls `cb`
  ## (with the `state` pointer) whenever the fixedpoint engine performs
  ## a register-assign step. Pass `nil` for both `state` and `cb` to
  ## deregister. `init` is called internally to bind `state`.
  ##
  ## The FFI layer accepts `pointer` for the callback argument to avoid
  ## a softlink const-qualification mismatch (`Z3_ast * const*` in C).
  fp.init(state)
  Z3_fixedpoint_set_reduce_assign_callback(fp.ctx.raw, fp.raw,
    cast[pointer](cb))

proc setReduceAppCallback*(fp: Z3Fixedpoint, state: pointer,
    cb: Z3FixedpointReduceAppCallbackFptr) =
  ## Register a term-building callback on `fp`. Z3 calls `cb` when
  ## it needs to construct a term from a relational operator; the
  ## callback can replace the result via its out-param. Pass `nil`
  ## for both arguments to deregister. `init` is called internally.
  fp.init(state)
  Z3_fixedpoint_set_reduce_app_callback(fp.ctx.raw, fp.raw,
    cast[pointer](cb))

proc addCallback*(fp: Z3Fixedpoint, state: pointer,
    newLemmaEh: Z3FixedpointNewLemmaEh,
    predecessorEh: Z3FixedpointPredecessorEh,
    unfoldEh: Z3FixedpointUnfoldEh) =
  ## Register Spacer-engine export callbacks. `newLemmaEh` is invoked
  ## on each new lemma discovery; `predecessorEh` on predecessor-frame
  ## exploration; `unfoldEh` on each unfolding step. Any callback
  ## may be `nil` to opt out of that event. The `state` pointer is
  ## threaded through all three callbacks unchanged.
  Z3_fixedpoint_add_callback(fp.ctx.raw, fp.raw, state,
    newLemmaEh, predecessorEh, unfoldEh)

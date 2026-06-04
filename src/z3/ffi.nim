## Raw FFI layer — softlink `dynlib` block declaring Z3's C API.
##
## **Internal module.** Consumers should not import this directly; the
## idiomatic Nim layer (`z3/context`, `z3/sort`, `z3/ast`, `z3/solver`,
## `z3/model` — yet to land) exposes the public surface. For v0.0.2
## the top-level `z3` re-exports the FFI directly so smoke tests can
## exercise it.
##
## Two responsibilities:
##
## 1. Declare opaque type wrappers for Z3's C typedefs using the
##    `bycopy importc` idiom. Nim emits the proper Z3 type names
##    (`Z3_context`, `Z3_config`, etc.) in C output rather than
##    `void*`, which is what makes softlink's `_Static_assert` accept
##    them as compatible with `z3.h`.
##
## 2. Declare every Z3 C function we use via a softlink `dynlib` block
##    with `header: "z3.h"` for compile-time signature verification.
##
## Naming convention: raw FFI types are `RawZ3X`; the idiomatic Nim
## layer uses `Z3X` without the prefix. Nim's identifier matching
## ignores case and underscores, so `Z3_context` (the C typedef) and
## `Z3Context` (our idiomatic ref) would collide without the prefix.
##
## The dynlib's library pattern `libz3.so(.4|.4.13|.4.12|.4.11|.4.10|)`
## supports Z3 4.10 → 4.13.x. softlink resolves the first match in
## order; the bare `|)` at the end falls through to `libz3.so` for
## development setups without a versioned symlink.

import softlink

# ============================================================================
# Opaque Z3 types — `typedef struct _Z3_X * Z3_X;` in C
# ============================================================================

type
  RawZ3Config*    {.importc: "Z3_config",    header: "z3.h", bycopy.} = object
  RawZ3Context*   {.importc: "Z3_context",   header: "z3.h", bycopy.} = object
  RawZ3Sort*      {.importc: "Z3_sort",      header: "z3.h", bycopy.} = object
  RawZ3Ast*       {.importc: "Z3_ast",       header: "z3.h", bycopy.} = object
  RawZ3App*       {.importc: "Z3_app",       header: "z3.h", bycopy.} = object
  RawZ3Symbol*    {.importc: "Z3_symbol",    header: "z3.h", bycopy.} = object
  RawZ3Solver*    {.importc: "Z3_solver",    header: "z3.h", bycopy.} = object
  RawZ3Model*     {.importc: "Z3_model",     header: "z3.h", bycopy.} = object
  RawZ3FuncDecl*  {.importc: "Z3_func_decl", header: "z3.h", bycopy.} = object
  RawZ3AstVector* {.importc: "Z3_ast_vector", header: "z3.h", bycopy.} = object
  RawZ3Constructor* {.importc: "Z3_constructor", header: "z3.h", bycopy.} = object
    ## Opaque handle to a constructor descriptor, intermediate between
    ## a `ConstructorSpec` and the finalised `Z3_func_decl` that the
    ## datatype's `mk_datatype` call yields. Must be deleted with
    ## `Z3_del_constructor` after `Z3_query_constructor` has extracted
    ## the func_decls — Z3 doesn't refcount the descriptor itself.
  RawZ3ConstructorList* {.importc: "Z3_constructor_list", header: "z3.h", bycopy.} = object
    ## Bundle of constructors for one datatype, passed to
    ## `Z3_mk_datatypes` (plural) when finalising N mutually-recursive
    ## datatypes in a single call. Cleaned up with
    ## `Z3_del_constructor_list` after the datatype sorts have been
    ## extracted.
  RawZ3Pattern* {.importc: "Z3_pattern", header: "z3.h", bycopy.} = object
    ## Quantifier instantiation trigger. Z3 only instantiates a
    ## quantifier when ground terms in the context match one of its
    ## attached patterns. Refcounted through `Z3_pattern_to_ast` —
    ## same trick used for `Z3_func_decl` (Z3 doesn't expose a
    ## dedicated `Z3_pattern_inc_ref`).
  RawZ3Optimize* {.importc: "Z3_optimize", header: "z3.h", bycopy.} = object
    ## Solver-shaped object specialised for optimisation problems:
    ## hard + weighted-soft constraints, maximise / minimise
    ## objectives with upper / lower bounds. Refcounted via
    ## `Z3_optimize_inc_ref` / `Z3_optimize_dec_ref`.
  RawZ3Fixedpoint* {.importc: "Z3_fixedpoint", header: "z3.h", bycopy.} = object
    ## **v0.4 step 5.** Horn-clause / CHC solver. Refcounted via
    ## `Z3_fixedpoint_inc_ref` / `_dec_ref`.
  RawZ3Stats* {.importc: "Z3_stats", header: "z3.h", bycopy.} = object
    ## **v0.4 step 8.** Statistics handle (key-value table) returned
    ## by `Z3_solver_get_statistics` / `Z3_fixedpoint_get_statistics`.
    ## Refcounted via `Z3_stats_inc_ref` / `_dec_ref`.
  RawZ3Goal* {.importc: "Z3_goal", header: "z3.h", bycopy.} = object
    ## Conjunction of formulas a tactic operates on. Refcounted.
  RawZ3Tactic* {.importc: "Z3_tactic", header: "z3.h", bycopy.} = object
    ## Strategy combinator that rewrites goals.
  RawZ3Probe* {.importc: "Z3_probe", header: "z3.h", bycopy.} = object
    ## **v0.4 step 12.** Goal-property predicate. Numeric output;
    ## refcounted via `Z3_probe_inc_ref` / `_dec_ref`. Used with
    ## `Z3_tactic_cond` for conditional tactic dispatch.
  RawZ3ApplyResult* {.importc: "Z3_apply_result", header: "z3.h", bycopy.} = object
    ## Output of a tactic — N sub-goals plus model/proof conversion
    ## metadata.
  RawZ3Params* {.importc: "Z3_params", header: "z3.h", bycopy.} = object
    ## Typed parameter bag for tactics / solvers / optimisers.
  RawZ3ParserContext* {.importc: "Z3_parser_context", header: "z3.h",
                        bycopy.} = object
    ## **v0.4 step 14.** Stateful SMT-LIB2 parser. Holds incrementally-
    ## registered sorts and decls between successive parse calls;
    ## refcounted via `Z3_parser_context_inc_ref` / `_dec_ref`.
  RawZ3FuncInterp* {.importc: "Z3_func_interp", header: "z3.h",
                     bycopy.} = object
    ## **v0.5 step 6A.** Tabular interpretation of an uninterpreted
    ## function under a model — a sequence of `(args, value)` entries
    ## plus an else-value. Refcounted via `Z3_func_interp_inc_ref` /
    ## `_dec_ref`.
  RawZ3FuncEntry* {.importc: "Z3_func_entry", header: "z3.h",
                    bycopy.} = object
    ## **v0.5 step 6A.** A single `(args, value)` row of a
    ## `Z3_func_interp`. Refcounted via `Z3_func_entry_inc_ref` /
    ## `_dec_ref`.
  RawZ3ParamDescrs* {.importc: "Z3_param_descrs", header: "z3.h",
                      bycopy.} = object
    ## **v0.5 step 6B.** Schema description for the parameters a
    ## solver / tactic / simplifier accepts. Refcounted via
    ## `Z3_param_descrs_inc_ref` / `_dec_ref`.

  # --- N0.1 / N1.x reserved handles -----------------------------------------
  RawZ3AstMap* {.importc: "Z3_ast_map", header: "z3.h", bycopy.} = object
    ## Mutable mapping from `Z3_ast` keys to `Z3_ast` values. Used for
    ## term-substitution caches and model-evaluation memo tables.
    ## Refcounted via `Z3_ast_map_inc_ref` / `_dec_ref`.
  RawZ3RcfNum* {.importc: "Z3_rcf_num", header: "z3.h", bycopy.} = object
    ## Real closed field numeral — an exact algebraic number produced
    ## by the RCF (Real Closed Fields) solver. NOT a Z3_ast; lifecycle
    ## via `Z3_rcf_del` (no inc/dec_ref pair).
  RawZ3Simplifier* {.importc: "Z3_simplifier", header: "z3.h", bycopy.} = object
    ## Named simplification strategy. Refcounted via
    ## `Z3_simplifier_inc_ref` / `_dec_ref`.
  RawZ3PropagatorCtxBox* {.importc: "Z3_solver_callback",
                           header: "z3.h", bycopy.} = object
    ## Opaque callback context passed by Z3 into user-supplied propagator hooks.

import std/macros

## `emitOpaqueOps` macro — emit per-type `isNil`, `==`, `!=` overloads for
## every opaque RawZ3* handle type. Using per-type procs (instead of a generic
## typeclass union) avoids the ambiguity with `system.==` on `tuple or object`
## that the generic form triggers in Nim 2.x.
##
## Background: Nim's `bycopy` objects expose no fields to Nim, so the compiler
## falls back to `system.==` (field-by-field) which always returns `true` for
## zero-field objects. We need pointer-identity semantics. The generic
## `[T: A|B|...]` form is ambiguous with `system.==`; per-type overloads
## resolve unambiguously.
macro emitOpaqueOps*(types: varargs[untyped]): untyped =
  result = newStmtList()
  for t in types:
    let tn = t  # the type name node
    # proc isNil*(x: T): bool {.inline.} = cast[pointer](x) == nil
    let isNilProc = newProc(
      name = newTree(nnkPostfix, ident("*"), ident("isNil")),
      params = [ident("bool"), newIdentDefs(ident("x"), tn)],
      body = newTree(nnkInfix,
               ident("=="),
               newTree(nnkCast, ident("pointer"), ident("x")),
               newNilLit()),
      procType = nnkProcDef
    )
    isNilProc.addPragma(ident("inline"))
    result.add isNilProc

    # proc `==`*(a, b: T): bool {.inline.} = cast[pointer](a) == cast[pointer](b)
    let eqProc = newProc(
      name = newTree(nnkPostfix, ident("*"),
               newTree(nnkAccQuoted, ident("=="))),
      params = [ident("bool"),
                newIdentDefs(ident("a"), tn),
                newIdentDefs(ident("b"), tn)],
      body = newTree(nnkInfix,
               ident("=="),
               newTree(nnkCast, ident("pointer"), ident("a")),
               newTree(nnkCast, ident("pointer"), ident("b"))),
      procType = nnkProcDef
    )
    eqProc.addPragma(ident("inline"))
    result.add eqProc

    # proc `!=`*(a, b: T): bool {.inline.} = cast[pointer](a) != cast[pointer](b)
    let neqProc = newProc(
      name = newTree(nnkPostfix, ident("*"),
               newTree(nnkAccQuoted, ident("!="))),
      params = [ident("bool"),
                newIdentDefs(ident("a"), tn),
                newIdentDefs(ident("b"), tn)],
      body = newTree(nnkInfix,
               ident("!="),
               newTree(nnkCast, ident("pointer"), ident("a")),
               newTree(nnkCast, ident("pointer"), ident("b"))),
      procType = nnkProcDef
    )
    neqProc.addPragma(ident("inline"))
    result.add neqProc

# Identity ops for all opaque handle types.
# Without these, Nim's default `==` compares the empty-from-Nim's-POV `bycopy`
# structs field-by-field — and since they expose no fields, all instances
# compare equal regardless of the underlying C pointer. That breaks the `=copy`
# short-circuit (`if dst.raw != src.raw`) and was the cause of a real refcount
# bug surfaced by step 4-5 testing.
emitOpaqueOps(
  RawZ3Config, RawZ3Context, RawZ3Sort, RawZ3Ast, RawZ3App,
  RawZ3Symbol, RawZ3Solver, RawZ3Model, RawZ3FuncDecl,
  RawZ3AstVector, RawZ3Constructor, RawZ3ConstructorList,
  RawZ3Pattern, RawZ3Optimize, RawZ3Fixedpoint, RawZ3Stats,
  RawZ3Probe, RawZ3Goal, RawZ3Tactic, RawZ3ApplyResult,
  RawZ3Params, RawZ3ParserContext,
  RawZ3FuncInterp, RawZ3FuncEntry, RawZ3ParamDescrs,
  RawZ3AstMap, RawZ3RcfNum, RawZ3Simplifier, RawZ3PropagatorCtxBox
)

# ============================================================================
# Z3 enums — must be importc with `size: sizeof(cint)` for ABI compat
# ============================================================================

type
  Z3LBool* {.importc: "Z3_lbool", header: "z3.h", size: sizeof(cint).} = enum
    Z3_L_FALSE = -1
    Z3_L_UNDEF = 0
    Z3_L_TRUE = 1

  Z3ErrorCode* {.importc: "Z3_error_code", header: "z3.h",
                 size: sizeof(cint).} = enum
    Z3_OK = 0
    Z3_SORT_ERROR = 1
    Z3_IOB = 2
    Z3_INVALID_ARG = 3
    Z3_PARSER_ERROR = 4
    Z3_NO_PARSER = 5
    Z3_INVALID_PATTERN = 6
    Z3_MEMOUT_FAIL = 7
    Z3_FILE_ACCESS_ERROR = 8
    Z3_INTERNAL_FATAL = 9
    Z3_INVALID_USAGE = 10
    Z3_DEC_REF_ERROR = 11
    Z3_EXCEPTION = 12

  # --- AST kind + sort kind enums (v0.4 step 2) ----------------------------

  Z3AstKindFFI* {.importc: "Z3_ast_kind", header: "z3.h",
                  size: sizeof(cint).} = enum
    Z3_NUMERAL_AST = 0
    Z3_APP_AST = 1
    Z3_VAR_AST = 2
    Z3_QUANTIFIER_AST = 3
    Z3_SORT_AST = 4
    Z3_FUNC_DECL_AST = 5
    Z3_UNKNOWN_AST = 1000

  Z3DeclKindFFI* {.importc: "Z3_decl_kind", header: "z3.h",
                   size: sizeof(cint).} = enum
    ## Z3_decl_kind has ~250 entries in z3_api.h; we only declare the
    ## proof-rule subset because that's all the wrapper dispatches on
    ## (in `z3/proof`). Imported enums tolerate out-of-range runtime
    ## values; `z3/proof.toProofRule` uses an `else` branch to map
    ## anything else to `prUnknown`. C++ backend's static_assert is
    ## satisfied because Nim emits the type as `Z3_decl_kind`.
    Z3_OP_PR_UNDEF_E            = 0x500
    Z3_OP_PR_TRUE_E             = 0x501
    Z3_OP_PR_ASSERTED_E         = 0x502
    Z3_OP_PR_GOAL_E             = 0x503
    Z3_OP_PR_MODUS_PONENS_E     = 0x504
    Z3_OP_PR_REFLEXIVITY_E      = 0x505
    Z3_OP_PR_SYMMETRY_E         = 0x506
    Z3_OP_PR_TRANSITIVITY_E     = 0x507
    Z3_OP_PR_TRANSITIVITY_STAR_E = 0x508
    Z3_OP_PR_MONOTONICITY_E     = 0x509
    Z3_OP_PR_QUANT_INTRO_E      = 0x50A
    Z3_OP_PR_BIND_E             = 0x50B
    Z3_OP_PR_DISTRIBUTIVITY_E   = 0x50C
    Z3_OP_PR_AND_ELIM_E         = 0x50D
    Z3_OP_PR_NOT_OR_ELIM_E      = 0x50E
    Z3_OP_PR_REWRITE_E          = 0x50F
    Z3_OP_PR_REWRITE_STAR_E     = 0x510
    Z3_OP_PR_PULL_QUANT_E       = 0x511
    Z3_OP_PR_PUSH_QUANT_E       = 0x512
    Z3_OP_PR_ELIM_UNUSED_VARS_E = 0x513
    Z3_OP_PR_DER_E              = 0x514
    Z3_OP_PR_QUANT_INST_E       = 0x515
    Z3_OP_PR_HYPOTHESIS_E       = 0x516
    Z3_OP_PR_LEMMA_E            = 0x517
    Z3_OP_PR_UNIT_RESOLUTION_E  = 0x518
    Z3_OP_PR_IFF_TRUE_E         = 0x519
    Z3_OP_PR_IFF_FALSE_E        = 0x51A
    Z3_OP_PR_COMMUTATIVITY_E    = 0x51B
    Z3_OP_PR_DEF_AXIOM_E        = 0x51C
    Z3_OP_PR_ASSUMPTION_ADD_E   = 0x51D
    Z3_OP_PR_LEMMA_ADD_E        = 0x51E
    Z3_OP_PR_REDUNDANT_DEL_E    = 0x51F
    Z3_OP_PR_CLAUSE_TRAIL_E     = 0x520
    Z3_OP_PR_DEF_INTRO_E        = 0x521
    Z3_OP_PR_APPLY_DEF_E        = 0x522
    Z3_OP_PR_IFF_OEQ_E          = 0x523
    Z3_OP_PR_NNF_POS_E          = 0x524
    Z3_OP_PR_NNF_NEG_E          = 0x525
    Z3_OP_PR_SKOLEMIZE_E        = 0x526
    Z3_OP_PR_MODUS_PONENS_OEQ_E = 0x527
    Z3_OP_PR_TH_LEMMA_E         = 0x528
    Z3_OP_PR_HYPER_RESOLVE_E    = 0x529

  Z3SortKindFFI* {.importc: "Z3_sort_kind", header: "z3.h",
                   size: sizeof(cint).} = enum
    Z3_UNINTERPRETED_SORT = 0
    Z3_BOOL_SORT = 1
    Z3_INT_SORT = 2
    Z3_REAL_SORT = 3
    Z3_BV_SORT = 4
    Z3_ARRAY_SORT = 5
    Z3_DATATYPE_SORT = 6
    Z3_RELATION_SORT = 7
    Z3_FINITE_DOMAIN_SORT = 8
    Z3_FLOATING_POINT_SORT = 9
    Z3_ROUNDING_MODE_SORT = 10
    Z3_SEQ_SORT = 11
    Z3_RE_SORT = 12
    Z3_CHAR_SORT = 13
    Z3_TYPE_VAR = 14
    Z3_UNKNOWN_SORT = 1000

  Z3ParamKindFFI* {.importc: "Z3_param_kind", header: "z3.h",
                    size: sizeof(cint).} = enum
    ## **v0.5 step 6B.** Mirrors Z3's `Z3_param_kind`. Used by
    ## `Z3_param_descrs_get_kind` to classify each parameter the
    ## schema lists.
    Z3_PK_UINT    = 0
    Z3_PK_BOOL    = 1
    Z3_PK_DOUBLE  = 2
    Z3_PK_SYMBOL  = 3
    Z3_PK_STRING  = 4
    Z3_PK_OTHER   = 5
    Z3_PK_INVALID = 6

  Z3ParameterKindFFI* {.importc: "Z3_parameter_kind", header: "z3.h",
                        size: sizeof(cint).} = enum
    ## Mirrors `Z3_parameter_kind` from z3_api.h.  Describes the variant
    ## of a decl's sort/value parameter.  `Z3_PARAMETER_INTERNAL` cannot
    ## be read via any public API accessor; it is included for completeness.
    Z3_PARAMETER_INT        = 0
    Z3_PARAMETER_DOUBLE     = 1
    Z3_PARAMETER_RATIONAL   = 2
    Z3_PARAMETER_SYMBOL     = 3
    Z3_PARAMETER_SORT       = 4
    Z3_PARAMETER_AST        = 5
    Z3_PARAMETER_FUNC_DECL  = 6
    Z3_PARAMETER_INTERNAL   = 7

  Z3GoalPrec* {.importc: "Z3_goal_prec", header: "z3.h",
                size: sizeof(cint).} = enum
    ## Approximation status of a goal after tactic application.
    ##
    ## - `gpPrecise`   — no approximation; sat/unsat answers preserved.
    ## - `gpUnder`     — under-approximation; sat answers preserved.
    ## - `gpOver`      — over-approximation; unsat answers preserved.
    ## - `gpUnderOver` — both approximations applied; no guarantee.
    gpPrecise   = 0  ## Z3_GOAL_PRECISE
    gpUnder     = 1  ## Z3_GOAL_UNDER
    gpOver      = 2  ## Z3_GOAL_OVER
    gpUnderOver = 3  ## Z3_GOAL_UNDER_OVER

# ============================================================================
# Z3 callback types
# ============================================================================

type
  Z3ErrorHandler* = proc(c: RawZ3Context, e: Z3ErrorCode) {.cdecl.}
    ## C-ABI callback Z3 invokes when an API error occurs. The default
    ## handler aborts the program; we install a no-op handler at
    ## context creation (see `z3/context.nim`) so error codes remain
    ## accessible via `Z3_get_error_code` rather than terminating the
    ## process.

  # ---- N7.8 fixedpoint callback typedefs ------------------------------------

  Z3FixedpointReduceAssignCallbackFptr* =
    proc(state: pointer, decl: RawZ3FuncDecl,
         numIn: cuint, inArgs: pointer,
         numOut: cuint, outArgs: pointer) {.cdecl.}
    ## Callback invoked by Z3's fixedpoint engine for destructive updates
    ## (register-assign style). `decl` is the relation being updated;
    ## `inArgs`/`numIn` are the input column values (`Z3_ast const[]`),
    ## `outArgs`/`numOut` are the output columns. C declares the array
    ## params as `Z3_ast const[]` (const-qualified); Nim uses `pointer`
    ## to avoid a `-Wincompatible-pointer-types` mismatch — cast to
    ## `ptr UncheckedArray[RawZ3Ast]` inside the callback body.
    ## Matches `Z3_fixedpoint_reduce_assign_callback_fptr`.

  Z3FixedpointReduceAppCallbackFptr* =
    proc(state: pointer, decl: RawZ3FuncDecl,
         numArgs: cuint, args: pointer,
         res: ptr RawZ3Ast) {.cdecl.}
    ## Callback for building terms from relational operators. `args` is
    ## a `Z3_ast const[]` array (const-qualified in C; `pointer` here
    ## for the same reason as `Z3FixedpointReduceAssignCallbackFptr`).
    ## `res` is a non-const out-param the callback fills with a
    ## replacement AST (or leaves unchanged for no replacement). Matches
    ## `Z3_fixedpoint_reduce_app_callback_fptr`.

  Z3FixedpointNewLemmaEh* =
    proc(state: pointer, lemma: RawZ3Ast, level: cuint) {.cdecl.}
    ## Export callback fired by the Spacer engine when it discovers a
    ## new lemma at the given induction level. Matches
    ## `Z3_fixedpoint_new_lemma_eh`.

  Z3FixedpointPredecessorEh* =
    proc(state: pointer) {.cdecl.}
    ## Callback fired when the Spacer engine explores a predecessor
    ## frame. Matches `Z3_fixedpoint_predecessor_eh`.

  Z3FixedpointUnfoldEh* =
    proc(state: pointer) {.cdecl.}
    ## Callback fired on each unfolding step. Matches
    ## `Z3_fixedpoint_unfold_eh`.

  # ---- N8.4a propagator callback typedefs ------------------------------------
  # Each typedef maps to the corresponding Z3_DECLARE_CLOSURE in z3_api.h
  # (lines 1435–1442). The first parameter is always the user_context pointer
  # supplied to `Z3_solver_propagate_init`. `Z3_solver_callback` is the opaque
  # callback context — exposed in Nim as `RawZ3PropagatorCtxBox`.

  Z3PropagatorPushEh* =
    proc(ctx: pointer, cb: RawZ3PropagatorCtxBox) {.cdecl.}
    ## Called when Z3 pushes a scope. Matches `Z3_push_eh`.

  Z3PropagatorPopEh* =
    proc(ctx: pointer, cb: RawZ3PropagatorCtxBox, numScopes: cuint) {.cdecl.}
    ## Called when Z3 pops `numScopes` scopes. Matches `Z3_pop_eh`.

  Z3PropagatorFreshEh* =
    proc(ctx: pointer, newContext: RawZ3Context): pointer {.cdecl.}
    ## Called when Z3 spawns a fresh solver; must return a fresh user_context
    ## for the new solver. Matches `Z3_fresh_eh`.

  Z3PropagatorFixedEh* =
    proc(ctx: pointer, cb: RawZ3PropagatorCtxBox,
         t: RawZ3Ast, value: RawZ3Ast) {.cdecl.}
    ## Called when a registered expression `t` is fixed to `value`.
    ## Matches `Z3_fixed_eh`.

  Z3PropagatorEqEh* =
    proc(ctx: pointer, cb: RawZ3PropagatorCtxBox,
         s: RawZ3Ast, t: RawZ3Ast) {.cdecl.}
    ## Called for an equality (or disequality) between two registered
    ## expressions. Shared by both `Z3_solver_propagate_eq` and
    ## `Z3_solver_propagate_diseq` per ADR-N0004. Matches `Z3_eq_eh`.

  Z3PropagatorFinalEh* =
    proc(ctx: pointer, cb: RawZ3PropagatorCtxBox) {.cdecl.}
    ## Called at the final-check point (all decisions assigned). Matches
    ## `Z3_final_eh`.

  Z3PropagatorCreatedEh* =
    proc(ctx: pointer, cb: RawZ3PropagatorCtxBox, t: RawZ3Ast) {.cdecl.}
    ## Called when a new expression using a declared propagator function is
    ## created. Matches `Z3_created_eh`.

  Z3PropagatorDecideEh* =
    proc(ctx: pointer, cb: RawZ3PropagatorCtxBox,
         t: RawZ3Ast, idx: cuint, phase: bool) {.cdecl.}
    ## Called when Z3 decides to split on a registered expression.
    ## Matches `Z3_decide_eh`.

  # ---- N8.4d on-clause callback typedef ------------------------------------
  # Matches `Z3_on_clause_eh` from z3_api.h line 1443.
  # Signature: (ctx, proof_hint, n, deps, literals)
  # Note: the count `n` precedes the pointer `deps` in the actual C ABI —
  # this is the correct ordering per z3_api.h (not swapped).
  Z3OnClauseEh* =
    proc(ctx: pointer, proofHint: RawZ3Ast,
         n: cuint, deps: ptr UncheckedArray[cuint],
         lits: RawZ3AstVector) {.cdecl.}
    ## Called when Z3 asserts, infers, or deletes a clause during search.
    ## `proofHint` may be nil. `deps` is an array of `n` clause-index
    ## references. `lits` is the Z3_ast_vector of literals in the clause.

# ============================================================================
# Z3 FFI declarations
# ============================================================================
#
# v0.0.2 surface: enough to build the idiomatic layer through the
# v0.1 milestone (sorts: Int / Real / Bool; numerals + variables;
# boolean and arithmetic ops; solver push/pop/check/get-model;
# model value extraction for Int + Bool; pretty-print). BitVec
# theory is the next FFI expansion step.

dynlib "libz3.so(.4|.4.13|.4.12|.4.11|.4.10|)":

  # --- Version --------------------------------------------------------------

  proc Z3_get_full_version(): cstring {.cdecl, header: "z3.h".}
    ## Returns a libz3 version string like "4.13.3.0".

  proc Z3_get_version(major, minor, build, revision: ptr cuint)
    {.cdecl, header: "z3.h".}
    ## Component-wise version; lets callers compare numerically without
    ## parsing the string form.

  proc Z3_finalize_memory() {.cdecl, header: "z3.h".}
    ## Process-wide cleanup. Z3 keeps internal globals (hash-cons tables,
    ## allocator pools) that survive `Z3_del_context`; calling this at
    ## program shutdown lets sanitisers report a clean exit. Safe to
    ## call multiple times. After this returns, *no* further Z3 API may
    ## be invoked from this process.

  # --- Configuration --------------------------------------------------------

  proc Z3_mk_config(): RawZ3Config {.cdecl, header: "z3.h".}
  proc Z3_del_config(c: RawZ3Config) {.cdecl, header: "z3.h".}
  proc Z3_set_param_value(c: RawZ3Config, param_id, param_value: cstring)
    {.cdecl, header: "z3.h".}
    ## Configuration knob — e.g. `("model", "true")` or `("proof", "true")`
    ## before the context is created.

  # --- Context lifecycle ----------------------------------------------------
  #
  # Z3_mk_context_rc: reference-counted contexts. Every AST returned by
  # the API must be paired with Z3_inc_ref / Z3_dec_ref; objects are
  # *not* GC'd on context destruction unless their refcount hits zero
  # via dec_ref. This is the only context variant we use; the eagerly-
  # GC'd Z3_mk_context isn't appropriate for Nim's =destroy / =copy
  # discipline.

  proc Z3_mk_context_rc(c: RawZ3Config): RawZ3Context
    {.cdecl, header: "z3.h".}
  proc Z3_del_context(c: RawZ3Context) {.cdecl, header: "z3.h".}

  proc Z3_enable_concurrent_dec_ref(c: RawZ3Context) {.cdecl, header: "z3.h".}
    ## Notify Z3 that `Z3_dec_ref` may be called from threads other than
    ## the one that owns the context. After this call Z3 protects its
    ## internal reference-count updates with a lock, making cross-thread
    ## dec_ref safe. Calling it more than once on the same context is a
    ## no-op. Must be called before spawning any thread that will dec_ref
    ## objects belonging to this context.

  # --- Refcounting ---------------------------------------------------------

  proc Z3_inc_ref(c: RawZ3Context, a: RawZ3Ast) {.cdecl, header: "z3.h".}
  proc Z3_dec_ref(c: RawZ3Context, a: RawZ3Ast) {.cdecl, header: "z3.h".}
  proc Z3_solver_inc_ref(c: RawZ3Context, s: RawZ3Solver) {.cdecl, header: "z3.h".}
  proc Z3_solver_dec_ref(c: RawZ3Context, s: RawZ3Solver) {.cdecl, header: "z3.h".}
  proc Z3_model_inc_ref(c: RawZ3Context, m: RawZ3Model) {.cdecl, header: "z3.h".}
  proc Z3_model_dec_ref(c: RawZ3Context, m: RawZ3Model) {.cdecl, header: "z3.h".}

  # --- Sorts ---------------------------------------------------------------

  proc Z3_mk_int_sort(c: RawZ3Context): RawZ3Sort {.cdecl, header: "z3.h".}
  proc Z3_mk_real_sort(c: RawZ3Context): RawZ3Sort {.cdecl, header: "z3.h".}
  proc Z3_mk_bool_sort(c: RawZ3Context): RawZ3Sort {.cdecl, header: "z3.h".}
  proc Z3_sort_to_string(c: RawZ3Context, s: RawZ3Sort): cstring
    {.cdecl, header: "z3.h".}

  # --- Symbols (variable names) --------------------------------------------

  proc Z3_mk_uninterpreted_sort(c: RawZ3Context, name: RawZ3Symbol): RawZ3Sort
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 14.** Free / opaque sort identified only by its
    ## name — the SMT-LIB `(declare-sort Color)` primitive.

  proc Z3_mk_string_symbol(c: RawZ3Context, s: cstring): RawZ3Symbol
    {.cdecl, header: "z3.h".}
  proc Z3_mk_int_symbol(c: RawZ3Context, i: cint): RawZ3Symbol
    {.cdecl, header: "z3.h".}

  # --- Constants + numerals + variables ------------------------------------

  proc Z3_mk_const(c: RawZ3Context, s: RawZ3Symbol, ty: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## "Constant" in Z3-speak = a free variable bound to a sort.

  proc Z3_mk_fresh_const(c: RawZ3Context, prefix: cstring, ty: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Create a fresh constant of sort `ty` with a unique name derived from
    ## `prefix`. Unlike `Z3_mk_const`, this generates an internal unique id
    ## so the resulting AST is structurally distinct from any other constant
    ## — safe to use where `Z3_mk_const` with a plain symbol causes Z3 4.15
    ## sort-identity confusion in `Z3_mk_distinct` / `Z3_mk_eq`.

  proc Z3_mk_int(c: RawZ3Context, v: cint, ty: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Integer literal. Use Z3_mk_numeral for values outside int32 range.

  proc Z3_mk_real(c: RawZ3Context, num, den: cint): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Rational literal num/den.

  proc Z3_mk_numeral(c: RawZ3Context, numeral: cstring, ty: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## String-based literal; handles arbitrary-precision integers and rationals
    ## (`"123456789012345678901234567890"`, `"1/2"`).

  proc Z3_mk_true(c: RawZ3Context): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_false(c: RawZ3Context): RawZ3Ast {.cdecl, header: "z3.h".}

  # --- Boolean operations --------------------------------------------------
  #
  # Multi-arg operators (and, or, add, mul) take an array of args. From
  # Nim, use `cast[ptr UncheckedArray[RawZ3Ast]](addr arr[0])` and the
  # arg count; matches Z3's `unsigned num_args, Z3_ast const args[]`
  # convention.

  proc Z3_mk_and(c: RawZ3Context, num_args: cuint,
                 args: ptr UncheckedArray[RawZ3Ast]): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_or(c: RawZ3Context, num_args: cuint,
                args: ptr UncheckedArray[RawZ3Ast]): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_not(c: RawZ3Context, a: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_implies(c: RawZ3Context, t1, t2: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_xor(c: RawZ3Context, t1, t2: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_iff(c: RawZ3Context, t1, t2: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_ite(c: RawZ3Context, t1, t2, t3: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## `if t1 then t2 else t3` — `t1` must be Bool; `t2` and `t3` must
    ## have the same sort.

  # --- Pseudo-boolean / cardinality ----------------------------------------
  #
  # atmost/atleast take an *unsigned* k; pble/pbge/pbeq take *signed* k
  # and a coefficients array (also signed int).

  proc Z3_mk_atmost(c: RawZ3Context, num_args: cuint,
                    args: ptr UncheckedArray[RawZ3Ast],
                    k: cuint): RawZ3Ast
    {.cdecl, header: "z3.h".}

  proc Z3_mk_atleast(c: RawZ3Context, num_args: cuint,
                     args: ptr UncheckedArray[RawZ3Ast],
                     k: cuint): RawZ3Ast
    {.cdecl, header: "z3.h".}

  proc Z3_mk_pble(c: RawZ3Context, num_args: cuint,
                  args: ptr UncheckedArray[RawZ3Ast],
                  coeffs: ptr UncheckedArray[cint],
                  k: cint): RawZ3Ast
    {.cdecl, header: "z3.h".}

  proc Z3_mk_pbge(c: RawZ3Context, num_args: cuint,
                  args: ptr UncheckedArray[RawZ3Ast],
                  coeffs: ptr UncheckedArray[cint],
                  k: cint): RawZ3Ast
    {.cdecl, header: "z3.h".}

  proc Z3_mk_pbeq(c: RawZ3Context, num_args: cuint,
                  args: ptr UncheckedArray[RawZ3Ast],
                  coeffs: ptr UncheckedArray[cint],
                  k: cint): RawZ3Ast
    {.cdecl, header: "z3.h".}

  # --- Arithmetic + comparison ---------------------------------------------

  proc Z3_mk_add(c: RawZ3Context, num_args: cuint,
                 args: ptr UncheckedArray[RawZ3Ast]): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_sub(c: RawZ3Context, num_args: cuint,
                 args: ptr UncheckedArray[RawZ3Ast]): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_mul(c: RawZ3Context, num_args: cuint,
                 args: ptr UncheckedArray[RawZ3Ast]): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_unary_minus(c: RawZ3Context, t: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_div(c: RawZ3Context, t1, t2: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_mod(c: RawZ3Context, t1, t2: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_rem(c: RawZ3Context, t1, t2: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Truncated remainder (differs from Z3_mk_mod for negative operands).

  proc Z3_mk_abs(c: RawZ3Context, arg: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Absolute value of an integer or real term.

  proc Z3_mk_power(c: RawZ3Context, arg1, arg2: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## `arg1 ^ arg2` — both arguments must be of the same numeric sort.

  proc Z3_mk_divides(c: RawZ3Context, t1, t2: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Boolean predicate `t1 divides t2` (integer divisibility).

  proc Z3_mk_int2real(c: RawZ3Context, t1: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Coerce integer `t1` to its Real-sort equivalent.

  proc Z3_mk_real2int(c: RawZ3Context, t1: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Floor of real `t1` as an Int-sort term.

  proc Z3_mk_is_int(c: RawZ3Context, t1: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Boolean predicate: true iff the real `t1` is an integer value.

  proc Z3_mk_real_int64(c: RawZ3Context, num, den: int64): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Rational literal `num / den` using int64 precision.
    ## Analogue of `Z3_mk_real` but accepts 64-bit numerator / denominator.

  proc Z3_mk_eq(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_lt(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_le(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_gt(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_ge(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}

  proc Z3_mk_distinct(c: RawZ3Context, num_args: cuint,
                      args: ptr UncheckedArray[RawZ3Ast]): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## All-pairs-distinct constraint; cheaper than the equivalent
    ## quadratic conjunction of `not (a == b)`.

  # --- Datatypes -----------------------------------------------------------

  proc Z3_mk_constructor(c: RawZ3Context, name: RawZ3Symbol,
                         recognizer: RawZ3Symbol,
                         num_fields: cuint,
                         field_names: ptr UncheckedArray[RawZ3Symbol],
                         sorts: ptr UncheckedArray[RawZ3Sort],
                         sort_refs: ptr UncheckedArray[cuint]): RawZ3Constructor
    {.cdecl, header: "z3.h".}
    ## Build a constructor descriptor. `sorts` may contain nil entries
    ## for fields that are recursive references; in that case the
    ## corresponding `sort_refs` index identifies which datatype in
    ## the same `Z3_mk_datatypes` call the field references (0 = the
    ## sole datatype for single-recursion).

  proc Z3_del_constructor(c: RawZ3Context, con: RawZ3Constructor)
    {.cdecl, header: "z3.h".}
    ## Release the constructor descriptor. After `Z3_mk_datatype` has
    ## consumed it and `Z3_query_constructor` has extracted the
    ## func_decls, the descriptor is no longer needed.

  proc Z3_mk_datatype(c: RawZ3Context, name: RawZ3Symbol,
                      num_constructors: cuint,
                      constructors: ptr UncheckedArray[RawZ3Constructor]): RawZ3Sort
    {.cdecl, header: "z3.h".}
    ## Finalise a single (non-mutually-recursive) datatype.

  proc Z3_mk_constructor_list(c: RawZ3Context, num_constructors: cuint,
                              constructors: ptr UncheckedArray[RawZ3Constructor]
                             ): RawZ3ConstructorList
    {.cdecl, header: "z3.h".}
    ## Bundle the constructors for one datatype in a multi-datatype
    ## (mutually recursive) declaration.

  proc Z3_del_constructor_list(c: RawZ3Context, cl: RawZ3ConstructorList)
    {.cdecl, header: "z3.h".}

  proc Z3_mk_datatypes(c: RawZ3Context, num_sorts: cuint,
                       sort_names: ptr UncheckedArray[RawZ3Symbol],
                       sorts_out: ptr UncheckedArray[RawZ3Sort],
                       cls: ptr UncheckedArray[RawZ3ConstructorList])
    {.cdecl, header: "z3.h".}
    ## Finalise N mutually-recursive datatypes simultaneously. The
    ## `sort_refs` indices each constructor used at `Z3_mk_constructor`
    ## time resolve against the N entries here in order. `cls` is
    ## implicitly `num_sorts` long (one constructor list per datatype).

  proc Z3_query_constructor(c: RawZ3Context, con: RawZ3Constructor,
                            num_fields: cuint,
                            constructor_out: ptr RawZ3FuncDecl,
                            tester_out: ptr RawZ3FuncDecl,
                            accessors_out: ptr UncheckedArray[RawZ3FuncDecl])
    {.cdecl, header: "z3.h".}
    ## Extract the constructor / recognizer / accessor `func_decl`s
    ## from a descriptor after `Z3_mk_datatype` has finalised the sort.

  proc Z3_mk_enumeration_sort(c: RawZ3Context,
                              name: RawZ3Symbol,
                              n: cuint,
                              enum_names: ptr UncheckedArray[RawZ3Symbol],
                              enum_consts: ptr UncheckedArray[RawZ3FuncDecl],
                              enum_testers: ptr UncheckedArray[RawZ3FuncDecl]
                             ): RawZ3Sort
    {.cdecl, header: "z3.h".}
    ## Build an enumeration sort with `n` members. On return,
    ## `enum_consts[i]` is the i-th nullary constructor func_decl and
    ## `enum_testers[i]` is the corresponding recognizer. Both output
    ## arrays must be pre-allocated by the caller to length `n`.

  proc Z3_mk_tuple_sort(c: RawZ3Context,
                        mk_tuple_name: RawZ3Symbol,
                        num_fields: cuint,
                        field_names: ptr UncheckedArray[RawZ3Symbol],
                        field_sorts: ptr UncheckedArray[RawZ3Sort],
                        mk_tuple_decl: ptr RawZ3FuncDecl,
                        proj_decl: ptr UncheckedArray[RawZ3FuncDecl]
                       ): RawZ3Sort
    {.cdecl, header: "z3.h".}
    ## Build a named tuple sort with `num_fields` fields. On return,
    ## `mk_tuple_decl` holds the constructor func_decl and `proj_decl[i]`
    ## holds the i-th projection func_decl. Both output args must be
    ## pre-allocated by the caller (`proj_decl` to length `num_fields`).
    ## Z3 emits func_decls at refcount 0; callers must `inc_ref` them.

  proc Z3_get_datatype_sort_num_constructors(c: RawZ3Context,
                                             t: RawZ3Sort): cuint
    {.cdecl, header: "z3.h".}
    ## Number of constructors in a datatype sort.
    ## Pre: `Z3_get_sort_kind(c, t) == Z3_DATATYPE_SORT`.

  proc Z3_get_datatype_sort_constructor(c: RawZ3Context,
                                        t: RawZ3Sort,
                                        idx: cuint): RawZ3FuncDecl
    {.cdecl, header: "z3.h".}
    ## Return the `idx`-th constructor func_decl.
    ## Pre: `idx < Z3_get_datatype_sort_num_constructors(c, t)`.

  proc Z3_get_datatype_sort_recognizer(c: RawZ3Context,
                                       t: RawZ3Sort,
                                       idx: cuint): RawZ3FuncDecl
    {.cdecl, header: "z3.h".}
    ## Return the `idx`-th recognizer func_decl.
    ## Pre: `idx < Z3_get_datatype_sort_num_constructors(c, t)`.

  proc Z3_get_datatype_sort_constructor_accessor(c: RawZ3Context,
                                                 t: RawZ3Sort,
                                                 idx_c: cuint,
                                                 idx_a: cuint): RawZ3FuncDecl
    {.cdecl, header: "z3.h".}
    ## Return the `idx_a`-th accessor of the `idx_c`-th constructor.
    ## Pre: `idx_c < numConstructors`; `idx_a < arity of constructor idx_c`.

  proc Z3_datatype_update_field(c: RawZ3Context,
                                field_access: RawZ3FuncDecl,
                                t: RawZ3Ast,
                                value: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Functional record update: return a copy of the datatype value `t`
    ## in which the field identified by accessor `field_access` has been
    ## replaced by `value`, all other fields unchanged.
    ##
    ## Pre: Z3_get_sort_kind(Z3_get_sort(c, t)) == Z3_DATATYPE_SORT
    ## Pre: Z3_get_sort(c, value) == Z3_get_range(c, field_access)

  proc Z3_mk_app(c: RawZ3Context, d: RawZ3FuncDecl,
                 num_args: cuint, args: ptr UncheckedArray[RawZ3Ast]): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Apply a function declaration to arguments. Used for constructor /
    ## recognizer / accessor invocations.

  proc Z3_mk_func_decl(c: RawZ3Context, s: RawZ3Symbol,
                       domain_size: cuint,
                       domain: ptr UncheckedArray[RawZ3Sort],
                       range: RawZ3Sort): RawZ3FuncDecl
    {.cdecl, header: "z3.h".}
    ## Declare an uninterpreted function with the given signature.
    ## Refcount discipline: route through `Z3_func_decl_to_ast` +
    ## `Z3_inc_ref` / `Z3_dec_ref` (datatypes.nim does the same).
    ## **v0.3 step 7.**

  proc Z3_mk_fresh_func_decl(c: RawZ3Context, prefix: cstring,
                              domain_size: cuint,
                              domain: ptr UncheckedArray[RawZ3Sort],
                              range: RawZ3Sort): RawZ3FuncDecl
    {.cdecl, header: "z3.h".}
    ## Declare a fresh uninterpreted function with a unique name derived from
    ## `prefix`. Unlike `Z3_mk_func_decl`, the generated name has a unique
    ## internal id so two calls with the same `prefix` produce structurally
    ## distinct func_decls. **N9.4.**

  proc Z3_mk_rec_func_decl(c: RawZ3Context, s: RawZ3Symbol,
                           domain_size: cuint,
                           domain: ptr UncheckedArray[RawZ3Sort],
                           range: RawZ3Sort): RawZ3FuncDecl
    {.cdecl, header: "z3.h".}
    ## Declare a recursive function. Must be followed by `Z3_add_rec_def`
    ## to provide the body. N5.5.

  proc Z3_add_rec_def(c: RawZ3Context, f: RawZ3FuncDecl,
                      n: cuint, args: ptr UncheckedArray[RawZ3Ast],
                      body: RawZ3Ast)
    {.cdecl, header: "z3.h".}
    ## Provide the body of a recursive function declared via
    ## `Z3_mk_rec_func_decl`. `args` are fresh constant ASTs (one per
    ## parameter) that appear free in `body`. N5.5.

  proc Z3_to_app(c: RawZ3Context, a: RawZ3Ast): RawZ3App
    {.cdecl, header: "z3.h".}
    ## Cast a constant `Ast` to its `App` form. `Z3_mk_forall_const`
    ## takes bound variables as `Z3_app[]`, not `Z3_ast[]` — every
    ## bound var must be a constant constructed via `Z3_mk_const`
    ## (or equivalently `mkIntVar` / `mkBitVecVar` / `mkDatatypeVar`).

  # --- Params --------------------------------------------------------------

  proc Z3_mk_params(c: RawZ3Context): RawZ3Params {.cdecl, header: "z3.h".}
  proc Z3_params_inc_ref(c: RawZ3Context, p: RawZ3Params) {.cdecl, header: "z3.h".}
  proc Z3_params_dec_ref(c: RawZ3Context, p: RawZ3Params) {.cdecl, header: "z3.h".}
  proc Z3_params_set_bool(c: RawZ3Context, p: RawZ3Params, k: RawZ3Symbol,
                          v: bool) {.cdecl, header: "z3.h".}
  proc Z3_params_set_uint(c: RawZ3Context, p: RawZ3Params, k: RawZ3Symbol,
                          v: cuint) {.cdecl, header: "z3.h".}
  proc Z3_params_set_double(c: RawZ3Context, p: RawZ3Params, k: RawZ3Symbol,
                            v: cdouble) {.cdecl, header: "z3.h".}
  proc Z3_params_set_symbol(c: RawZ3Context, p: RawZ3Params, k: RawZ3Symbol,
                            v: RawZ3Symbol) {.cdecl, header: "z3.h".}
  proc Z3_params_to_string(c: RawZ3Context, p: RawZ3Params): cstring
    {.cdecl, header: "z3.h".}

  # --- Goals ---------------------------------------------------------------

  proc Z3_mk_goal(c: RawZ3Context, models: bool, unsat_cores: bool,
                  proofs: bool): RawZ3Goal {.cdecl, header: "z3.h".}
  proc Z3_goal_inc_ref(c: RawZ3Context, g: RawZ3Goal) {.cdecl, header: "z3.h".}
  proc Z3_goal_dec_ref(c: RawZ3Context, g: RawZ3Goal) {.cdecl, header: "z3.h".}
  proc Z3_goal_assert(c: RawZ3Context, g: RawZ3Goal, a: RawZ3Ast)
    {.cdecl, header: "z3.h".}
  proc Z3_goal_size(c: RawZ3Context, g: RawZ3Goal): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_goal_formula(c: RawZ3Context, g: RawZ3Goal, idx: cuint): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_goal_inconsistent(c: RawZ3Context, g: RawZ3Goal): bool
    {.cdecl, header: "z3.h".}
  proc Z3_goal_is_decided_sat(c: RawZ3Context, g: RawZ3Goal): bool
    {.cdecl, header: "z3.h".}
  proc Z3_goal_is_decided_unsat(c: RawZ3Context, g: RawZ3Goal): bool
    {.cdecl, header: "z3.h".}
  proc Z3_goal_to_string(c: RawZ3Context, g: RawZ3Goal): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_goal_num_exprs(c: RawZ3Context, g: RawZ3Goal): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_goal_depth(c: RawZ3Context, g: RawZ3Goal): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_goal_reset(c: RawZ3Context, g: RawZ3Goal)
    {.cdecl, header: "z3.h".}
  proc Z3_goal_translate(source: RawZ3Context, g: RawZ3Goal,
                         target: RawZ3Context): RawZ3Goal
    {.cdecl, header: "z3.h".}
  proc Z3_goal_to_dimacs_string(c: RawZ3Context, g: RawZ3Goal,
                                include_names: bool): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_goal_precision(c: RawZ3Context, g: RawZ3Goal): Z3GoalPrec
    {.cdecl, header: "z3.h".}

  # --- Tactics -------------------------------------------------------------

  proc Z3_mk_tactic(c: RawZ3Context, name: cstring): RawZ3Tactic
    {.cdecl, header: "z3.h".}
  proc Z3_tactic_inc_ref(c: RawZ3Context, t: RawZ3Tactic) {.cdecl, header: "z3.h".}
  proc Z3_tactic_dec_ref(c: RawZ3Context, t: RawZ3Tactic) {.cdecl, header: "z3.h".}
  proc Z3_tactic_and_then(c: RawZ3Context, t1, t2: RawZ3Tactic): RawZ3Tactic
    {.cdecl, header: "z3.h".}
  proc Z3_tactic_or_else(c: RawZ3Context, t1, t2: RawZ3Tactic): RawZ3Tactic
    {.cdecl, header: "z3.h".}
  proc Z3_tactic_repeat(c: RawZ3Context, t: RawZ3Tactic, max: cuint): RawZ3Tactic
    {.cdecl, header: "z3.h".}
  proc Z3_tactic_try_for(c: RawZ3Context, t: RawZ3Tactic, ms: cuint): RawZ3Tactic
    {.cdecl, header: "z3.h".}
  proc Z3_tactic_using_params(c: RawZ3Context, t: RawZ3Tactic,
                              p: RawZ3Params): RawZ3Tactic
    {.cdecl, header: "z3.h".}
  proc Z3_tactic_skip(c: RawZ3Context): RawZ3Tactic {.cdecl, header: "z3.h".}
  proc Z3_tactic_fail(c: RawZ3Context): RawZ3Tactic {.cdecl, header: "z3.h".}
  # --- Tactic enumeration (N8.5) -------------------------------------------
  proc Z3_get_num_tactics(c: RawZ3Context): cuint {.cdecl, header: "z3.h".}
  proc Z3_get_tactic_name(c: RawZ3Context, i: cuint): cstring
    {.cdecl, header: "z3.h".}

  # --- Probes + condTactic (v0.4 step 12) ----------------------------------

  proc Z3_mk_probe(c: RawZ3Context, name: cstring): RawZ3Probe
    {.cdecl, header: "z3.h".}
  proc Z3_probe_inc_ref(c: RawZ3Context, p: RawZ3Probe)
    {.cdecl, header: "z3.h".}
  proc Z3_probe_dec_ref(c: RawZ3Context, p: RawZ3Probe)
    {.cdecl, header: "z3.h".}
  proc Z3_probe_apply(c: RawZ3Context, p: RawZ3Probe, g: RawZ3Goal): cdouble
    {.cdecl, header: "z3.h".}
  proc Z3_probe_const(c: RawZ3Context, value: cdouble): RawZ3Probe
    {.cdecl, header: "z3.h".}
  proc Z3_probe_lt(c: RawZ3Context, p1, p2: RawZ3Probe): RawZ3Probe
    {.cdecl, header: "z3.h".}
  proc Z3_probe_le(c: RawZ3Context, p1, p2: RawZ3Probe): RawZ3Probe
    {.cdecl, header: "z3.h".}
  proc Z3_probe_gt(c: RawZ3Context, p1, p2: RawZ3Probe): RawZ3Probe
    {.cdecl, header: "z3.h".}
  proc Z3_probe_ge(c: RawZ3Context, p1, p2: RawZ3Probe): RawZ3Probe
    {.cdecl, header: "z3.h".}
  proc Z3_probe_eq(c: RawZ3Context, p1, p2: RawZ3Probe): RawZ3Probe
    {.cdecl, header: "z3.h".}
  proc Z3_probe_and(c: RawZ3Context, p1, p2: RawZ3Probe): RawZ3Probe
    {.cdecl, header: "z3.h".}
  proc Z3_probe_or(c: RawZ3Context, p1, p2: RawZ3Probe): RawZ3Probe
    {.cdecl, header: "z3.h".}
  proc Z3_probe_not(c: RawZ3Context, p: RawZ3Probe): RawZ3Probe
    {.cdecl, header: "z3.h".}
  proc Z3_tactic_cond(c: RawZ3Context, p: RawZ3Probe,
                      t1, t2: RawZ3Tactic): RawZ3Tactic
    {.cdecl, header: "z3.h".}
  proc Z3_tactic_when(c: RawZ3Context, p: RawZ3Probe,
                      t: RawZ3Tactic): RawZ3Tactic
    {.cdecl, header: "z3.h".}
  # --- Parallel tactic combinators (N8.6) ----------------------------------
  proc Z3_tactic_par_or(c: RawZ3Context, num: cuint,
                         ts: ptr RawZ3Tactic): RawZ3Tactic
    {.cdecl, header: "z3.h".}
  proc Z3_tactic_par_and_then(c: RawZ3Context,
                               t1, t2: RawZ3Tactic): RawZ3Tactic
    {.cdecl, header: "z3.h".}
  # --- Probe enumeration (N8.5) --------------------------------------------
  proc Z3_get_num_probes(c: RawZ3Context): cuint {.cdecl, header: "z3.h".}
  proc Z3_get_probe_name(c: RawZ3Context, i: cuint): cstring
    {.cdecl, header: "z3.h".}

  # --- Simplifier enumeration (N8.5) ---------------------------------------
  proc Z3_get_num_simplifiers(c: RawZ3Context): cuint {.cdecl, header: "z3.h".}
  proc Z3_get_simplifier_name(c: RawZ3Context, i: cuint): cstring
    {.cdecl, header: "z3.h".}

  # --- Global parameters (v0.4 step 13) ------------------------------------
  # Process-wide; no context handle. `_get` populates an out-pointer and
  # returns Z3_TRUE iff the param was previously set, Z3_FALSE otherwise.
  proc Z3_global_param_set(param_id, param_value: cstring)
    {.cdecl, header: "z3.h".}
  proc Z3_global_param_reset_all()
    {.cdecl, header: "z3.h".}
  # `Z3_string_ptr` is `const char **`; Nim's `ptr cstring` decays to
  # `char **` which a strict cpp compiler rejects. Take an opaque
  # `pointer` and cast at the call site — semantics are unchanged
  # since Z3 only writes into the location.
  proc Z3_global_param_get(param_id: cstring,
                           param_value: pointer): bool
    {.cdecl, header: "z3.h".}

  # --- AST print mode (N8.10) -----------------------------------------------
  # `Z3_ast_print_mode` is a C enum; we pass it as `cuint` to avoid
  # importing a C enum into the FFI layer directly.  The enum values are
  # sequential from 0:
  #   Z3_PRINT_SMTLIB_FULL = 0, Z3_PRINT_LOW_LEVEL = 1,
  #   Z3_PRINT_SMTLIB2_COMPLIANT = 2
  proc Z3_set_ast_print_mode(c: RawZ3Context, mode: cuint)
    {.cdecl, header: "z3.h".}

  # --- Cross-thread interrupt (v1.0 audit round 2, item #1) ----------------
  # Z3_interrupt is the documented exception to the
  # "one-context-one-thread" discipline (see docs/THREADING.md): it is
  # safe to call from a different thread than the one currently
  # running `check()` / `optimize_check()` / `fixedpoint_query()`.
  # The in-flight call returns Z3_L_UNDEF ("unknown") with
  # reason_unknown = "interrupted".
  proc Z3_interrupt(c: RawZ3Context)
    {.cdecl, header: "z3.h".}

  proc Z3_tactic_apply(c: RawZ3Context, t: RawZ3Tactic, g: RawZ3Goal): RawZ3ApplyResult
    {.cdecl, header: "z3.h".}
  proc Z3_tactic_apply_ex(c: RawZ3Context, t: RawZ3Tactic, g: RawZ3Goal,
                          p: RawZ3Params): RawZ3ApplyResult
    {.cdecl, header: "z3.h".}

  proc Z3_apply_result_inc_ref(c: RawZ3Context, r: RawZ3ApplyResult)
    {.cdecl, header: "z3.h".}
  proc Z3_apply_result_dec_ref(c: RawZ3Context, r: RawZ3ApplyResult)
    {.cdecl, header: "z3.h".}
  proc Z3_apply_result_get_num_subgoals(c: RawZ3Context,
                                        r: RawZ3ApplyResult): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_apply_result_get_subgoal(c: RawZ3Context, r: RawZ3ApplyResult,
                                   idx: cuint): RawZ3Goal
    {.cdecl, header: "z3.h".}
  proc Z3_apply_result_to_string(c: RawZ3Context, r: RawZ3ApplyResult): cstring
    {.cdecl, header: "z3.h".}

  proc Z3_goal_convert_model(c: RawZ3Context, g: RawZ3Goal,
                             m: RawZ3Model): RawZ3Model
    {.cdecl, header: "z3.h".}
    ## Convert a model `m` satisfying sub-goal `g` into a model that
    ## satisfies the original goal `g` was derived from. The sub-goal
    ## carries the model-converter metadata Z3 produced when the
    ## tactic was applied.
    ##
    ## Replaces the v0.2-era `Z3_apply_result_convert_model` which
    ## was retired in Z3 4.8.0 (2018). The wrapper exposes a
    ## `convertModel(applyResult, idx, subModel)` ergonomic API that
    ## internally routes through this proc on the indexed sub-goal.

  # --- Optimize ------------------------------------------------------------

  proc Z3_mk_optimize(c: RawZ3Context): RawZ3Optimize
    {.cdecl, header: "z3.h".}
  proc Z3_optimize_inc_ref(c: RawZ3Context, o: RawZ3Optimize)
    {.cdecl, header: "z3.h".}
  proc Z3_optimize_dec_ref(c: RawZ3Context, o: RawZ3Optimize)
    {.cdecl, header: "z3.h".}

  proc Z3_optimize_assert(c: RawZ3Context, o: RawZ3Optimize, a: RawZ3Ast)
    {.cdecl, header: "z3.h".}
    ## Add a hard constraint (must be satisfied).

  proc Z3_optimize_assert_soft(c: RawZ3Context, o: RawZ3Optimize,
                               a: RawZ3Ast, weight: cstring,
                               id: RawZ3Symbol): cuint
    {.cdecl, header: "z3.h".}
    ## Add a soft constraint with a weight (decimal string,
    ## e.g. "1.0"). Z3 minimises the weighted sum of violated soft
    ## constraints. `id` groups soft constraints into named
    ## objectives — the empty-name symbol means "default group".
    ## Returns the objective index.

  proc Z3_optimize_maximize(c: RawZ3Context, o: RawZ3Optimize,
                            t: RawZ3Ast): cuint
    {.cdecl, header: "z3.h".}
    ## Register `t` as a maximisation objective. Returns the
    ## objective index used by `get_upper` / `get_lower`.

  proc Z3_optimize_minimize(c: RawZ3Context, o: RawZ3Optimize,
                            t: RawZ3Ast): cuint
    {.cdecl, header: "z3.h".}

  proc Z3_optimize_check(c: RawZ3Context, o: RawZ3Optimize,
                         num_assumptions: cuint,
                         assumptions: ptr UncheckedArray[RawZ3Ast]): Z3LBool
    {.cdecl, header: "z3.h".}

  proc Z3_optimize_get_model(c: RawZ3Context, o: RawZ3Optimize): RawZ3Model
    {.cdecl, header: "z3.h".}

  proc Z3_optimize_get_reason_unknown(c: RawZ3Context, o: RawZ3Optimize): cstring
    {.cdecl, header: "z3.h".}

  proc Z3_optimize_get_upper(c: RawZ3Context, o: RawZ3Optimize, idx: cuint): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Upper bound for objective `idx`. May be a numeric literal, an
    ## infinitesimal-plus-bound expression for reals (`epsilon + 10`),
    ## or a positive-infinity term if the objective is unbounded.

  proc Z3_optimize_get_lower(c: RawZ3Context, o: RawZ3Optimize, idx: cuint): RawZ3Ast
    {.cdecl, header: "z3.h".}

  proc Z3_optimize_push(c: RawZ3Context, o: RawZ3Optimize)
    {.cdecl, header: "z3.h".}
  proc Z3_optimize_pop(c: RawZ3Context, o: RawZ3Optimize)
    {.cdecl, header: "z3.h".}

  proc Z3_optimize_to_string(c: RawZ3Context, o: RawZ3Optimize): cstring
    {.cdecl, header: "z3.h".}

  proc Z3_optimize_set_params(c: RawZ3Context, o: RawZ3Optimize, p: RawZ3Params)
    {.cdecl, header: "z3.h".}
  proc Z3_optimize_get_param_descrs(c: RawZ3Context, o: RawZ3Optimize):
                                    RawZ3ParamDescrs
    {.cdecl, header: "z3.h".}
    ## Configure the optimiser. The most user-visible knob is the
    ## `priority` symbol value — `lex` (default), `box`, or `pareto`.
    ## See v0.2 plan §1 and `z3/optimize` docs for the semantic
    ## differences.

  proc Z3_optimize_assert_and_track(c: RawZ3Context, o: RawZ3Optimize,
                                    a: RawZ3Ast, t: RawZ3Ast)
    {.cdecl, header: "z3.h".}
    ## Assert hard constraint `a` tagged by tracker proposition `t`
    ## (a fresh Boolean literal). After an unsat `check()`,
    ## `Z3_optimize_get_unsat_core` returns the subset of trackers
    ## participating in the contradiction.

  proc Z3_optimize_get_unsat_core(c: RawZ3Context, o: RawZ3Optimize):
                                   RawZ3AstVector
    {.cdecl, header: "z3.h".}
    ## Extract the unsat core after `check() == zsUnsat`. Returns an
    ## `ast_vector` of tracker literals that participate in the
    ## contradiction. Mirrors `Z3_solver_get_unsat_core`.

  proc Z3_optimize_from_string(c: RawZ3Context, o: RawZ3Optimize, src: cstring)
    {.cdecl, header: "z3.h".}
    ## Parse an SMT2 string (with `(maximize ...)` / `(minimize ...)`
    ## directives) and assert directly into `o`. Mirrors
    ## `Z3_solver_from_string`.

  proc Z3_optimize_from_file(c: RawZ3Context, o: RawZ3Optimize,
                              file_name: cstring)
    {.cdecl, header: "z3.h".}
    ## File-input twin of `Z3_optimize_from_string`. Mirrors
    ## `Z3_solver_from_file`.

  proc Z3_optimize_get_help(c: RawZ3Context, o: RawZ3Optimize): cstring
    {.cdecl, header: "z3.h".}
    ## Z3's documentation for optimiser parameters. Returns a multiline
    ## string with each parameter name + meaning. Mirrors
    ## `Z3_fixedpoint_get_help`.

  # --- Optimize — N7.6b extensions -----------------------------------------

  proc Z3_optimize_get_statistics(c: RawZ3Context, o: RawZ3Optimize): RawZ3Stats
    {.cdecl, header: "z3.h".}
    ## Solver-style statistics for this optimiser. Mirrors
    ## `Z3_solver_get_statistics`.

  proc Z3_optimize_get_assertions(c: RawZ3Context, o: RawZ3Optimize): RawZ3AstVector
    {.cdecl, header: "z3.h".}
    ## Returns the set of asserted constraints as an AST vector. Each
    ## element corresponds to a `Z3_optimize_assert` / hard-assert call.

  proc Z3_optimize_get_objectives(c: RawZ3Context, o: RawZ3Optimize): RawZ3AstVector
    {.cdecl, header: "z3.h".}
    ## Returns the current set of objectives (maximize/minimize targets
    ## and soft-constraint pseudo-objectives) as an AST vector.

  proc Z3_optimize_set_initial_value(c: RawZ3Context, o: RawZ3Optimize,
                                     v: RawZ3Ast, val: RawZ3Ast)
    {.cdecl, header: "z3.h".}
    ## Provide a warm-start hint: tell Z3 to try `v = val` as an initial
    ## assignment. Z3 may ignore this hint; it is never an additional
    ## constraint.

  proc Z3_optimize_get_lower_as_vector(c: RawZ3Context, o: RawZ3Optimize,
                                       idx: cuint): RawZ3AstVector
    {.cdecl, header: "z3.h".}
    ## Multi-precision lower-bound representation for objective `idx`.
    ## Returns a vector whose elements encode the bound in Z3's internal
    ## extended-number representation (typically three elements: sign,
    ## value, infinitesimal coefficient).

  proc Z3_optimize_get_upper_as_vector(c: RawZ3Context, o: RawZ3Optimize,
                                       idx: cuint): RawZ3AstVector
    {.cdecl, header: "z3.h".}
    ## Multi-precision upper-bound representation. Twin of
    ## `Z3_optimize_get_lower_as_vector`.

  # Z3_optimize_register_model_eh — FFI stub only.
  # Typed closure wrapper is intrusive (requires a stable C-ABI thunk and
  # boxed closure state). Deferred to a dedicated follow-up parallel to
  # N7.8 fixedpoint callback handling.
  proc Z3_optimize_register_model_eh(c: RawZ3Context, o: RawZ3Optimize,
                                     m: RawZ3Model,
                                     ctx: pointer,
                                     model_eh: proc(ctx: pointer) {.cdecl.})
    {.cdecl, header: "z3.h".}
    ## Raw C callback registration. `model_eh` is called by Z3 whenever
    ## it finds an improved model during optimisation. See ADR-N0004 and
    ## `z3/fixedpoint` for the pattern used when a typed closure wrapper
    ## is eventually added.

  # --- Fixedpoint / CHC (v0.4 step 5) --------------------------------------

  proc Z3_mk_fixedpoint(c: RawZ3Context): RawZ3Fixedpoint
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_inc_ref(c: RawZ3Context, d: RawZ3Fixedpoint)
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_dec_ref(c: RawZ3Context, d: RawZ3Fixedpoint)
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_register_relation(c: RawZ3Context, d: RawZ3Fixedpoint,
                                       f: RawZ3FuncDecl)
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_add_rule(c: RawZ3Context, d: RawZ3Fixedpoint,
                              rule: RawZ3Ast, name: RawZ3Symbol)
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_add_fact(c: RawZ3Context, d: RawZ3Fixedpoint,
                              r: RawZ3FuncDecl, num_args: cuint,
                              args: ptr UncheckedArray[cuint])
    {.cdecl, header: "z3.h".}
    ## Z3's addFact takes the relation + an array of **integer
    ## arguments** (not raw asts). Used for finite-domain facts in
    ## the datalog engine.
  proc Z3_fixedpoint_assert(c: RawZ3Context, d: RawZ3Fixedpoint,
                            axiom: RawZ3Ast)
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_update_rule(c: RawZ3Context, d: RawZ3Fixedpoint,
                                 a: RawZ3Ast, name: RawZ3Symbol)
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_add_constraint(c: RawZ3Context, d: RawZ3Fixedpoint,
                                    e: RawZ3Ast, lvl: cuint)
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_add_cover(c: RawZ3Context, d: RawZ3Fixedpoint,
                               level: cint, pred: RawZ3FuncDecl,
                               property: RawZ3Ast)
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_query(c: RawZ3Context, d: RawZ3Fixedpoint,
                           query: RawZ3Ast): Z3LBool
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_query_relations(c: RawZ3Context, d: RawZ3Fixedpoint,
                                     num_rels: cuint,
                                     rels: ptr UncheckedArray[RawZ3FuncDecl]):
                                     Z3LBool
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_get_answer(c: RawZ3Context, d: RawZ3Fixedpoint): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_get_reason_unknown(c: RawZ3Context,
                                        d: RawZ3Fixedpoint): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_get_num_levels(c: RawZ3Context, d: RawZ3Fixedpoint,
                                    pred: RawZ3FuncDecl): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_get_cover_delta(c: RawZ3Context, d: RawZ3Fixedpoint,
                                     level: cint,
                                     pred: RawZ3FuncDecl): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_get_rules(c: RawZ3Context, f: RawZ3Fixedpoint):
                               RawZ3AstVector
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_get_assertions(c: RawZ3Context,
                                    f: RawZ3Fixedpoint): RawZ3AstVector
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_get_help(c: RawZ3Context, f: RawZ3Fixedpoint): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_set_params(c: RawZ3Context, f: RawZ3Fixedpoint,
                                p: RawZ3Params)
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_to_string(c: RawZ3Context, f: RawZ3Fixedpoint,
                               num_queries: cuint,
                               queries: ptr UncheckedArray[RawZ3Ast]): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_fixedpoint_get_param_descrs(c: RawZ3Context,
                                      f: RawZ3Fixedpoint): RawZ3ParamDescrs
    {.cdecl, header: "z3.h".}
    ## **N7.7.** Return the parameter schema for the fixedpoint solver.
    ## Parity with `Z3_solver_get_param_descrs` / `Z3_optimize_get_param_descrs`.
  proc Z3_fixedpoint_from_string(c: RawZ3Context, f: RawZ3Fixedpoint,
                                 s: cstring): RawZ3AstVector
    {.cdecl, header: "z3.h".}
    ## **N7.7.** Parse SMT-LIB2 fixedpoint declarations from a string.
    ## Adds rules/facts to `f` and returns the set of query formulas found.
  proc Z3_fixedpoint_from_file(c: RawZ3Context, f: RawZ3Fixedpoint,
                               s: cstring): RawZ3AstVector
    {.cdecl, header: "z3.h".}
    ## **N7.7.** File-input twin of `Z3_fixedpoint_from_string`.

  # --- N7.8 fixedpoint callback registration --------------------------------

  proc Z3_fixedpoint_init(c: RawZ3Context, d: RawZ3Fixedpoint, state: pointer)
    {.cdecl, header: "z3_fixedpoint.h".}
    ## **N7.8.** Initialise the fixedpoint context with a user-defined
    ## state pointer. Must be called before registering reduce-assign or
    ## reduce-app callbacks; `state` is threaded through every callback
    ## invocation so callers can recover their Nim-side data without
    ## globals.

  proc Z3_fixedpoint_set_reduce_assign_callback(
      c: RawZ3Context, d: RawZ3Fixedpoint,
      cb: pointer)
    {.cdecl, header: "z3_fixedpoint.h".}
    ## **N7.8.** Register a destructive-update callback. Z3 invokes the
    ## `Z3_fixedpoint_reduce_assign_callback_fptr`-typed function pointer
    ## `cb` whenever the engine performs a register-assign step. The
    ## parameter is declared as `pointer` to avoid a softlink
    ## `__typeof__`/`_Static_assert` const-qualification mismatch
    ## (`Z3_ast * const*` vs Nim's generated non-const ptr type);
    ## callers cast `Z3FixedpointReduceAssignCallbackFptr` to `pointer`.

  proc Z3_fixedpoint_set_reduce_app_callback(
      c: RawZ3Context, d: RawZ3Fixedpoint,
      cb: pointer)
    {.cdecl, header: "z3_fixedpoint.h".}
    ## **N7.8.** Register a term-building callback. The `pointer` param
    ## carries a `Z3_fixedpoint_reduce_app_callback_fptr`; same
    ## const-array rationale as `Z3_fixedpoint_set_reduce_assign_callback`.

  proc Z3_fixedpoint_add_callback(c: RawZ3Context, f: RawZ3Fixedpoint,
                                   state: pointer,
                                   newLemmaEh: Z3FixedpointNewLemmaEh,
                                   predecessorEh: Z3FixedpointPredecessorEh,
                                   unfoldEh: Z3FixedpointUnfoldEh)
    {.cdecl, header: "z3_fixedpoint.h".}
    ## **N7.8.** Register Spacer-engine export callbacks: `newLemmaEh`
    ## fires on each new lemma discovery, `predecessorEh` on predecessor
    ## exploration, `unfoldEh` on each unfolding step.

  # --- Spacer / IC3-PDR extensions (z3_spacer.h) -------------------------

  proc Z3_fixedpoint_query_from_lvl(c: RawZ3Context, d: RawZ3Fixedpoint,
                                    query: RawZ3Ast,
                                    lvl: cuint): Z3LBool
    {.cdecl, header: "z3_spacer.h".}
    ## Run the CHC query from induction level `lvl`. Returns L_TRUE (sat),
    ## L_FALSE (unsat), or L_UNDEF (unknown). Spacer-engine only.

  proc Z3_fixedpoint_add_invariant(c: RawZ3Context, d: RawZ3Fixedpoint,
                                   pred: RawZ3FuncDecl,
                                   property: RawZ3Ast)
    {.cdecl, header: "z3_spacer.h".}
    ## Inject an assumed invariant for `pred` into Spacer's state.

  proc Z3_fixedpoint_get_reachable(c: RawZ3Context, d: RawZ3Fixedpoint,
                                   pred: RawZ3FuncDecl): RawZ3Ast
    {.cdecl, header: "z3_spacer.h".}
    ## Retrieve the reachable states formula for `pred` after a query.

  proc Z3_fixedpoint_get_ground_sat_answer(c: RawZ3Context,
                                           d: RawZ3Fixedpoint): RawZ3Ast
    {.cdecl, header: "z3_spacer.h".}
    ## Retrieve the ground sat answer (bottom-up fact witness) after SAT.

  proc Z3_fixedpoint_get_rules_along_trace(c: RawZ3Context,
                                           d: RawZ3Fixedpoint): RawZ3AstVector
    {.cdecl, header: "z3_spacer.h".}
    ## Horn rules fired along the counterexample trace after a SAT query.

  proc Z3_model_extrapolate(c: RawZ3Context, m: RawZ3Model,
                             fml: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3_spacer.h".}
    ## Generalise a model of `fml` to a stronger (more general) formula.

  proc Z3_qe_lite(c: RawZ3Context, vars: RawZ3AstVector,
                  body: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3_spacer.h".}
    ## Best-effort quantifier elimination: project `vars` out of `body`.

  proc Z3_qe_model_project(c: RawZ3Context, m: RawZ3Model,
                            num_bounds: cuint,
                            bound: ptr UncheckedArray[RawZ3App],
                            body: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3_spacer.h".}
    ## Model-guided variable projection. Projects `bound` apps out of
    ## `body` using the model `m` to choose which branch to preserve.

  # --- Quantifiers + patterns ---------------------------------------------

  proc Z3_mk_pattern(c: RawZ3Context, num_patterns: cuint,
                     terms: ptr UncheckedArray[RawZ3Ast]): RawZ3Pattern
    {.cdecl, header: "z3.h".}
    ## Construct a multi-trigger pattern. Each pattern is a *conjunction*
    ## of trigger terms; Z3 instantiates the quantifier when ground
    ## terms in the context match all trigger terms simultaneously.

  proc Z3_pattern_to_ast(c: RawZ3Context, p: RawZ3Pattern): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Cast a pattern to its underlying AST for refcounting via the
    ## general `Z3_inc_ref` / `Z3_dec_ref` calls.

  proc Z3_mk_forall_const(c: RawZ3Context, weight: cuint,
                          num_bound: cuint,
                          bound: ptr UncheckedArray[RawZ3App],
                          num_patterns: cuint,
                          patterns: ptr UncheckedArray[RawZ3Pattern],
                          body: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Universal quantification over free constants `bound[]`, which
    ## Z3 re-binds inside `body`. `weight` defaults to 0 (no
    ## de-prioritisation); patterns may be empty (Z3 picks its own).

  proc Z3_mk_exists_const(c: RawZ3Context, weight: cuint,
                          num_bound: cuint,
                          bound: ptr UncheckedArray[RawZ3App],
                          num_patterns: cuint,
                          patterns: ptr UncheckedArray[RawZ3Pattern],
                          body: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Existential variant of `Z3_mk_forall_const`.

  proc Z3_mk_lambda_const(c: RawZ3Context, num_decls: cuint,
                          bound: ptr UncheckedArray[RawZ3App],
                          body: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Lambda binder over free constants. Returns an array sort
    ## `(Array K V)` where K is the bound consts' sort tuple and V
    ## the body's sort. See `z3/quantifier.lambda` for the typed
    ## wrapper (v1.0 audit round 2, item #2).

  proc Z3_func_decl_to_ast(c: RawZ3Context, d: RawZ3FuncDecl): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Cast a `func_decl` to its underlying `ast` for refcounting.
    ## `Z3_inc_ref` / `Z3_dec_ref` operate on `ast`; we use this to
    ## keep the func_decls alive while their datatype decl is in scope.

  # --- Z3FuncInterp (v0.5 step 6A) -----------------------------------------
  proc Z3_model_get_func_interp(c: RawZ3Context, m: RawZ3Model,
                                f: RawZ3FuncDecl): RawZ3FuncInterp
    {.cdecl, header: "z3.h".}
  proc Z3_func_interp_inc_ref(c: RawZ3Context, fi: RawZ3FuncInterp)
    {.cdecl, header: "z3.h".}
  proc Z3_func_interp_dec_ref(c: RawZ3Context, fi: RawZ3FuncInterp)
    {.cdecl, header: "z3.h".}
  proc Z3_func_interp_get_num_entries(c: RawZ3Context,
                                      fi: RawZ3FuncInterp): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_func_interp_get_entry(c: RawZ3Context, fi: RawZ3FuncInterp,
                                i: cuint): RawZ3FuncEntry
    {.cdecl, header: "z3.h".}
  proc Z3_func_interp_get_arity(c: RawZ3Context, fi: RawZ3FuncInterp): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_func_interp_get_else(c: RawZ3Context, fi: RawZ3FuncInterp): RawZ3Ast
    {.cdecl, header: "z3.h".}

  proc Z3_func_entry_inc_ref(c: RawZ3Context, e: RawZ3FuncEntry)
    {.cdecl, header: "z3.h".}
  proc Z3_func_entry_dec_ref(c: RawZ3Context, e: RawZ3FuncEntry)
    {.cdecl, header: "z3.h".}
  proc Z3_func_entry_get_value(c: RawZ3Context, e: RawZ3FuncEntry): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_func_entry_get_num_args(c: RawZ3Context, e: RawZ3FuncEntry): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_func_entry_get_arg(c: RawZ3Context, e: RawZ3FuncEntry,
                             i: cuint): RawZ3Ast
    {.cdecl, header: "z3.h".}

  # --- Model construction (N2.2) -------------------------------------------
  proc Z3_mk_model(c: RawZ3Context): RawZ3Model
    {.cdecl, header: "z3.h".}
  proc Z3_add_const_interp(c: RawZ3Context, m: RawZ3Model,
                            f: RawZ3FuncDecl, a: RawZ3Ast)
    {.cdecl, header: "z3.h".}
  proc Z3_add_func_interp(c: RawZ3Context, m: RawZ3Model,
                           f: RawZ3FuncDecl,
                           default_value: RawZ3Ast): RawZ3FuncInterp
    {.cdecl, header: "z3.h".}
  proc Z3_func_interp_set_else(c: RawZ3Context, fi: RawZ3FuncInterp,
                                else_value: RawZ3Ast)
    {.cdecl, header: "z3.h".}
  proc Z3_func_interp_add_entry(c: RawZ3Context, fi: RawZ3FuncInterp,
                                 args: RawZ3AstVector, value: RawZ3Ast)
    {.cdecl, header: "z3.h".}

  # --- Z3ParamDescrs (v0.5 step 6B) ----------------------------------------
  proc Z3_solver_get_param_descrs(c: RawZ3Context,
                                  s: RawZ3Solver): RawZ3ParamDescrs
    {.cdecl, header: "z3.h".}
  proc Z3_tactic_get_param_descrs(c: RawZ3Context,
                                  t: RawZ3Tactic): RawZ3ParamDescrs
    {.cdecl, header: "z3.h".}
  proc Z3_param_descrs_inc_ref(c: RawZ3Context, p: RawZ3ParamDescrs)
    {.cdecl, header: "z3.h".}
  proc Z3_param_descrs_dec_ref(c: RawZ3Context, p: RawZ3ParamDescrs)
    {.cdecl, header: "z3.h".}
  proc Z3_param_descrs_size(c: RawZ3Context, p: RawZ3ParamDescrs): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_param_descrs_get_name(c: RawZ3Context, p: RawZ3ParamDescrs,
                                i: cuint): RawZ3Symbol
    {.cdecl, header: "z3.h".}
  proc Z3_param_descrs_get_kind(c: RawZ3Context, p: RawZ3ParamDescrs,
                                n: RawZ3Symbol): Z3ParamKindFFI
    {.cdecl, header: "z3.h".}
  proc Z3_param_descrs_get_documentation(c: RawZ3Context, p: RawZ3ParamDescrs,
                                         s: RawZ3Symbol): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_param_descrs_to_string(c: RawZ3Context, p: RawZ3ParamDescrs): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_get_global_param_descrs(c: RawZ3Context): RawZ3ParamDescrs
    {.cdecl, header: "z3.h".}
    ## Returns the param-descrs for Z3's process-wide (manager-global)
    ## parameters. The handle is reference-counted via the normal
    ## `Z3_param_descrs_inc_ref` / `_dec_ref` pair.

  # --- N2.4c: AST-level predicates, identity ids, type variable ---------------

  proc Z3_is_well_sorted(c: RawZ3Context, t: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
    ## Returns `true` iff `t` is a well-sorted formula/term.

  proc Z3_is_app(c: RawZ3Context, a: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
    ## Returns `true` iff `a` is a function application (including
    ## 0-arity constants — free variables in Z3's vocabulary).

  proc Z3_is_numeral_ast(c: RawZ3Context, a: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
    ## Returns `true` iff `a` is a numeral literal.

  proc Z3_get_ast_id(c: RawZ3Context, t: RawZ3Ast): cuint
    {.cdecl, header: "z3.h".}
    ## Unique identifier for AST node `t` within context `c`.
    ## Stable for the lifetime of the context.

  proc Z3_get_sort_id(c: RawZ3Context, s: RawZ3Sort): cuint
    {.cdecl, header: "z3.h".}
    ## Unique identifier for sort `s` within context `c`.

  proc Z3_get_index_value(c: RawZ3Context, a: RawZ3Ast): cuint
    {.cdecl, header: "z3.h".}
    ## De-Bruijn index of a bound variable AST (kind `akVar`).

  proc Z3_mk_type_variable(c: RawZ3Context, s: RawZ3Symbol): RawZ3Sort
    {.cdecl, header: "z3.h".}
    ## Constructs a polymorphic type-variable sort with the given name.

  # --- Array sort + ops ----------------------------------------------------

  proc Z3_mk_array_sort(c: RawZ3Context, domain, range: RawZ3Sort): RawZ3Sort
    {.cdecl, header: "z3.h".}
    ## `(Array domain range)` — total function from `domain` to `range`.

  proc Z3_mk_const_array(c: RawZ3Context, domain: RawZ3Sort, v: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Array whose value is `v` at every index. `domain` is the index
    ## sort; the range sort is inferred from `v`'s sort.

  proc Z3_mk_store(c: RawZ3Context, a, i, v: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Functional update: returns an array `a'` with `a'[i] = v` and
    ## `a'[j] = a[j]` for every `j` distinct from `i`.

  proc Z3_mk_select(c: RawZ3Context, a, i: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Read `a[i]`. Result sort is the array's range sort.

  proc Z3_mk_array_default(c: RawZ3Context, a: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Extract the background-default value of an array `a` — the
    ## value at every index Z3 hasn't been forced to specialise. Dual
    ## of `Z3_mk_const_array`. v1.0 audit round 2, item #3.

  proc Z3_mk_array_sort_n(c: RawZ3Context, n: cuint,
      domain: ptr UncheckedArray[RawZ3Sort], range: RawZ3Sort): RawZ3Sort
    {.cdecl, header: "z3.h".}
    ## N-ary array sort `(Array domain[0] … domain[n-1] range)`.
    ## N9.3: multi-index arrays.

  proc Z3_mk_map(c: RawZ3Context, f: RawZ3FuncDecl, n: cuint,
      args: ptr UncheckedArray[RawZ3Ast]): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Map `f` pointwise over `n` arrays. Each `args[i]` must have sort
    ## `Array(domain, range_i)`; `f : range_0 × … × range_{n-1} → range`.
    ## Result sort is `Array(domain, range)`. N9.3.

  proc Z3_mk_array_ext(c: RawZ3Context, a1, a2: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Extensionality witness: returns a term `k` such that `a1[k] ≠ a2[k]`
    ## whenever `a1 ≠ a2`. N9.3.

  proc Z3_mk_as_array(c: RawZ3Context, f: RawZ3FuncDecl): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Lift unary function `f : K → V` to an array `Array(K, V)` such
    ## that `select(asArray(f), k) = f(k)` for all `k`. N9.3.

  # --- BitVec sort + numerals ----------------------------------------------

  proc Z3_mk_bv_sort(c: RawZ3Context, sz: cuint): RawZ3Sort
    {.cdecl, header: "z3.h".}
    ## Fixed-width bit-vector sort. `sz` is the width in bits.

  proc Z3_mk_unsigned_int64(c: RawZ3Context, v: uint64, ty: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Construct a BV numeral from an unsigned 64-bit value. For widths
    ## smaller than 64 the value is taken modulo 2^W; for widths up to
    ## 64 the full range is representable directly. Larger widths
    ## require `Z3_mk_numeral` with the string form.

  proc Z3_mk_int64(c: RawZ3Context, v: int64, ty: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Signed 64-bit variant of `Z3_mk_unsigned_int64`. Used for
    ## constructing signed-interpreted BV literals.

  proc Z3_get_numeral_uint64(c: RawZ3Context, v: RawZ3Ast,
                             out_val: ptr uint64): bool
    {.cdecl, header: "z3.h".}
    ## Extract an unsigned 64-bit value from a BV numeral. Returns false
    ## if the AST isn't a numeral or its magnitude exceeds 64 bits.

  proc Z3_get_numeral_int64(c: RawZ3Context, v: RawZ3Ast,
                            out_val: ptr int64): bool
    {.cdecl, header: "z3.h".}
    ## Signed 64-bit extraction. The numeral is interpreted as 2's-complement
    ## over its declared width before clamping to int64.

  proc Z3_get_bv_sort_size(c: RawZ3Context, t: RawZ3Sort): cuint
    {.cdecl, header: "z3.h".}
    ## Width (in bits) of a BV sort. Used at runtime by toUint to verify
    ## the AST's actual width matches the static type-level width.

  proc Z3_mk_bv2int(c: RawZ3Context, a: RawZ3Ast, isSigned: bool): RawZ3Ast
    {.cdecl, header: "z3.h".}

  proc Z3_mk_int2bv(c: RawZ3Context, n: cuint, a: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Convert an `Int` AST to an `n`-bit BV. The integer is taken
    ## mod 2^n. Used by `Z3Optimize.upper` / `.lower` to box bounds
    ## back as `Z3BitVec[W]` — Z3's optimisation API returns BV
    ## bounds as Int (the unsigned magnitude).
    ## Convert a bit-vector AST to an integer AST. When `isSigned` is
    ## false, the value is the unsigned magnitude. When true, the value
    ## is the two's-complement signed interpretation: an `n`-bit BV
    ## whose MSB is set maps to `value - 2^n`. This is the canonical
    ## way to extract the signed value of a BV regardless of width —
    ## simplify the resulting Int and read off its numeral string.

  proc Z3_get_sort(c: RawZ3Context, a: RawZ3Ast): RawZ3Sort
    {.cdecl, header: "z3.h".}
    ## Sort of an AST.

  # --- Structural introspection (v0.4 step 2) ------------------------------

  proc Z3_get_ast_kind(c: RawZ3Context, a: RawZ3Ast): Z3AstKindFFI
    {.cdecl, header: "z3.h".}
  proc Z3_get_sort_kind(c: RawZ3Context, s: RawZ3Sort): Z3SortKindFFI
    {.cdecl, header: "z3.h".}

  # --- Relation sort introspection (N9.5) ----------------------------------
  # Z3_RELATION_SORT is an internal sort kind produced by the datalog engine;
  # there is no Z3_mk_relation_sort public constructor. These accessors are
  # provided for completeness — they apply to sorts returned from the
  # datalog engine's internal machinery.

  proc Z3_get_relation_arity(c: RawZ3Context, s: RawZ3Sort): cuint
    {.cdecl, header: "z3.h".}
    ## Return the arity (number of columns) of a relation sort.
    ## Pre: `Z3_get_sort_kind(c, s) == Z3_RELATION_SORT`.

  proc Z3_get_relation_column(c: RawZ3Context, s: RawZ3Sort,
                               col: cuint): RawZ3Sort
    {.cdecl, header: "z3.h".}
    ## Return the sort at column `col` of a relation sort.
    ## Pre: `Z3_get_sort_kind(c, s) == Z3_RELATION_SORT` and
    ##      `col < Z3_get_relation_arity(c, s)`.

  proc Z3_get_app_decl(c: RawZ3Context, a: RawZ3App): RawZ3FuncDecl
    {.cdecl, header: "z3.h".}
  proc Z3_get_app_num_args(c: RawZ3Context, a: RawZ3App): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_get_app_arg(c: RawZ3Context, a: RawZ3App, i: cuint): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_get_array_sort_domain(c: RawZ3Context, s: RawZ3Sort): RawZ3Sort
    {.cdecl, header: "z3.h".}
  proc Z3_get_array_sort_range(c: RawZ3Context, s: RawZ3Sort): RawZ3Sort
    {.cdecl, header: "z3.h".}
  proc Z3_get_seq_sort_basis(c: RawZ3Context, s: RawZ3Sort): RawZ3Sort
    {.cdecl, header: "z3.h".}
  proc Z3_get_re_sort_basis(c: RawZ3Context, s: RawZ3Sort): RawZ3Sort
    {.cdecl, header: "z3.h".}
  proc Z3_fpa_get_ebits(c: RawZ3Context, s: RawZ3Sort): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_fpa_get_sbits(c: RawZ3Context, s: RawZ3Sort): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_get_sort_name(c: RawZ3Context, s: RawZ3Sort): RawZ3Symbol
    {.cdecl, header: "z3.h".}
  proc Z3_substitute(c: RawZ3Context, a: RawZ3Ast, num_exprs: cuint,
                     from_arr: ptr UncheckedArray[RawZ3Ast],
                     to_arr: ptr UncheckedArray[RawZ3Ast]): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 9.** Substitute subterms by-term. `from_arr[i]`
    ## occurrences in `a` are replaced by `to_arr[i]`.
  proc Z3_substitute_funs(c: RawZ3Context, a: RawZ3Ast, num_funs: cuint,
                          from_arr: ptr UncheckedArray[RawZ3FuncDecl],
                          to_arr: ptr UncheckedArray[RawZ3Ast]): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## **N9.4.** Substitute function-application subterms. Each application of
    ## `from_arr[i]` in `a` is replaced by `to_arr[i]`, where `to_arr[i]` may
    ## contain de-Bruijn free variables (index 0 = first argument of the
    ## replaced function, index 1 = second argument, etc.).
  proc Z3_substitute_vars(c: RawZ3Context, a: RawZ3Ast,
                          num_exprs: cuint,
                          to_arr: ptr UncheckedArray[RawZ3Ast]): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 9.** Substitute bound variables by de-Bruijn index.
    ## `to_arr[i]` replaces the `i`-th bound variable counted from
    ## innermost.
  proc Z3_mk_bound(c: RawZ3Context, index: cuint, ty: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 9.** Construct a bound-variable AST at the given
    ## de-Bruijn index. Useful for manually building quantifier
    ## bodies; required for testing `Z3_substitute_vars`.
  proc Z3_translate(srcCtx: RawZ3Context, a: RawZ3Ast,
                    targetCtx: RawZ3Context): RawZ3Ast
    {.cdecl, header: "z3.h".}

  # --- Quantifier introspection (v0.4 step 11) -----------------------------

  proc Z3_get_quantifier_num_bound(c: RawZ3Context, a: RawZ3Ast): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_get_quantifier_bound_name(c: RawZ3Context, a: RawZ3Ast,
                                    i: cuint): RawZ3Symbol
    {.cdecl, header: "z3.h".}
  proc Z3_get_quantifier_bound_sort(c: RawZ3Context, a: RawZ3Ast,
                                    i: cuint): RawZ3Sort
    {.cdecl, header: "z3.h".}
  proc Z3_get_quantifier_body(c: RawZ3Context, a: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_get_quantifier_num_patterns(c: RawZ3Context, a: RawZ3Ast): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_get_quantifier_pattern_ast(c: RawZ3Context, a: RawZ3Ast,
                                     i: cuint): RawZ3Pattern
    {.cdecl, header: "z3.h".}
  proc Z3_get_quantifier_num_no_patterns(c: RawZ3Context, a: RawZ3Ast): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_get_quantifier_no_pattern_ast(c: RawZ3Context, a: RawZ3Ast,
                                        i: cuint): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_is_quantifier_forall(c: RawZ3Context, a: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_is_quantifier_exists(c: RawZ3Context, a: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_is_lambda(c: RawZ3Context, a: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_get_quantifier_weight(c: RawZ3Context, a: RawZ3Ast): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_get_quantifier_id(c: RawZ3Context, a: RawZ3Ast): RawZ3Symbol
    {.cdecl, header: "z3.h".}
    ## **N2.5.** Returns the quantifier ID symbol. Used to retrieve a
    ## user-supplied or Z3-assigned name for the quantifier.
  proc Z3_get_quantifier_skolem_id(c: RawZ3Context, a: RawZ3Ast): RawZ3Symbol
    {.cdecl, header: "z3.h".}
    ## **N2.5.** Returns the Skolem ID symbol used for fresh names during
    ## Skolemization. Stable across calls on the same quantifier AST.
    ## **v0.4 step 10.** Transfer an AST from `srcCtx` to `targetCtx`.
    ## The returned AST is owned by `targetCtx`; the source AST is
    ## independent. Z3 validates that the target context can accept
    ## the AST; on incompatibility raises a Z3 error.
  proc Z3_get_decl_kind(c: RawZ3Context, d: RawZ3FuncDecl): Z3DeclKindFFI
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 4.** Returns the Z3-internal `Z3_decl_kind` enum
    ## value. The proof-rule subset is enumerated in `Z3DeclKindFFI`;
    ## other values pass through (`z3/proof.toProofRule`'s `else` maps
    ## them to `prUnknown`).
  proc Z3_solver_get_proof(c: RawZ3Context, s: RawZ3Solver): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 4.** Extract the proof witness after an unsat
    ## `check()` with `proof=true` enabled on the context. Returns
    ## nil if proof generation wasn't enabled or `check()` didn't
    ## conclude unsat.
  proc Z3_get_symbol_string(c: RawZ3Context, s: RawZ3Symbol): cstring
    {.cdecl, header: "z3.h".}

  # --- BitVec ops: arithmetic (sign-independent + signed/unsigned variants) -

  proc Z3_mk_bvadd(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvsub(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvmul(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvneg(c: RawZ3Context, t: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvudiv(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvsdiv(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvurem(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvsrem(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvsmod(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}

  # --- BitVec ops: bitwise -------------------------------------------------

  proc Z3_mk_bvand(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvor(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvxor(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvnot(c: RawZ3Context, t: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvnand(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvnor(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvxnor(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}

  # --- BitVec ops: shifts --------------------------------------------------

  proc Z3_mk_bvshl(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvlshr(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
    ## Logical (zero-fill) right shift. Pair with `bvashr` for arithmetic
    ## (sign-bit-fill) right shift.
  proc Z3_mk_bvashr(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}

  # --- BitVec ops: reduction (N3.2) ----------------------------------------

  proc Z3_mk_bvredand(c: RawZ3Context, t: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Bit-vector AND-reduction: BV[W] → BV[1], result is 1 iff all bits of
    ## `t` are 1.

  proc Z3_mk_bvredor(c: RawZ3Context, t: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Bit-vector OR-reduction: BV[W] → BV[1], result is 1 iff any bit of
    ## `t` is 1.

  # --- BitVec ops: extended rotations (N3.2) --------------------------------

  proc Z3_mk_ext_rotate_left(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Rotate `l` left by the amount given by BV `r` (symbolic shift amount,
    ## same width as `l`). Contrast with `Z3_mk_rotate_left` which takes a
    ## static integer shift.

  proc Z3_mk_ext_rotate_right(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Rotate `l` right by the amount given by BV `r` (symbolic shift amount,
    ## same width as `l`). Contrast with `Z3_mk_rotate_right` which takes a
    ## static integer shift.

  # --- BitVec ops: overflow/underflow predicates ---------------------------

  proc Z3_mk_bvadd_no_overflow(c: RawZ3Context, t1, t2: RawZ3Ast,
                               is_signed: bool): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## True iff `t1 + t2` does not overflow. `is_signed` selects
    ## signed vs unsigned interpretation.

  proc Z3_mk_bvadd_no_underflow(c: RawZ3Context, t1, t2: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## True iff signed `t1 + t2` does not underflow (signed-only per C API).

  proc Z3_mk_bvsub_no_overflow(c: RawZ3Context, t1, t2: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## True iff signed `t1 - t2` does not overflow (signed-only per C API).

  proc Z3_mk_bvsub_no_underflow(c: RawZ3Context, t1, t2: RawZ3Ast,
                                 is_signed: bool): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## True iff `t1 - t2` does not underflow. `is_signed` selects
    ## signed vs unsigned interpretation.

  proc Z3_mk_bvmul_no_overflow(c: RawZ3Context, t1, t2: RawZ3Ast,
                               is_signed: bool): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## True iff `t1 * t2` does not overflow. `is_signed` selects
    ## signed vs unsigned interpretation.

  proc Z3_mk_bvmul_no_underflow(c: RawZ3Context, t1, t2: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## True iff signed `t1 * t2` does not underflow (signed-only per C API).

  proc Z3_mk_bvneg_no_overflow(c: RawZ3Context, t1: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## True iff signed negation of `t1` does not overflow (signed-only per C API).

  proc Z3_mk_bvsdiv_no_overflow(c: RawZ3Context, t1, t2: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## True iff signed `t1 / t2` does not overflow (signed-only per C API;
    ## only case: INT_MIN / -1).

  # --- BitVec ops: comparison (unsigned + signed) --------------------------

  proc Z3_mk_bvult(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvule(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvugt(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvuge(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvslt(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvsle(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvsgt(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_bvsge(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}

  # --- BitVec ops: width manipulation --------------------------------------

  proc Z3_mk_extract(c: RawZ3Context, high, low: cuint, t: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Bit slice `[high..low]` inclusive. Result width = `high - low + 1`.

  proc Z3_mk_concat(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## `l` becomes the high-order bits, `r` the low-order. Result width
    ## is the sum.

  proc Z3_mk_zero_ext(c: RawZ3Context, i: cuint, t: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Prepend `i` zero bits.
  proc Z3_mk_sign_ext(c: RawZ3Context, i: cuint, t: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Prepend `i` copies of the sign bit (MSB).
  proc Z3_mk_repeat(c: RawZ3Context, i: cuint, t: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Tile `t` `i` times; result width = `i * width(t)`.

  # --- Solver --------------------------------------------------------------

  proc Z3_mk_solver(c: RawZ3Context): RawZ3Solver {.cdecl, header: "z3.h".}
  proc Z3_mk_simple_solver(c: RawZ3Context): RawZ3Solver
    {.cdecl, header: "z3.h".}
    ## A CDCL-style solver without the tactic wrapper. Supports
    ## `Z3_solver_get_trail` / `Z3_solver_get_units` / `Z3_solver_get_non_units`
    ## / `Z3_solver_get_levels`. Weaker on non-linear arithmetic but
    ## exposes the SAT-engine introspection surface. N8.1.
  proc Z3_mk_solver_from_tactic(c: RawZ3Context, t: RawZ3Tactic): RawZ3Solver
    {.cdecl, header: "z3.h".}
    ## **v0.3 step 8.** Wrap a tactic pipeline as a solver. The
    ## returned solver delegates its decision procedure to `t`; the
    ## familiar push / pop / add / check / model surface still applies.

  proc Z3_solver_set_params(c: RawZ3Context, s: RawZ3Solver, p: RawZ3Params)
    {.cdecl, header: "z3.h".}
    ## **v0.3 step 8.** Apply a typed params bag (timeout, model,
    ## random_seed, …) to an existing solver. Mirrors
    ## `Z3_optimize_set_params`.

  proc Z3_solver_assert(c: RawZ3Context, s: RawZ3Solver, a: RawZ3Ast)
    {.cdecl, header: "z3.h".}
  proc Z3_solver_assert_and_track(c: RawZ3Context, s: RawZ3Solver,
                                  a: RawZ3Ast, p: RawZ3Ast)
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 6.** Assert `a` tagged by tracker proposition `p`
    ## (a fresh Boolean literal). After an unsat `check()`,
    ## `Z3_solver_get_unsat_core` returns the subset of trackers
    ## whose assertions are in the minimal unsatisfiable core.
  proc Z3_solver_get_unsat_core(c: RawZ3Context, s: RawZ3Solver): RawZ3AstVector
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 6.** Extract the unsat core after `check() == zsUnsat`.
    ## Returns an `ast_vector` of tracker literals that participate in
    ## the contradiction.

  # --- Stats (v0.4 step 8) -------------------------------------------------

  proc Z3_stats_inc_ref(c: RawZ3Context, s: RawZ3Stats)
    {.cdecl, header: "z3.h".}
  proc Z3_stats_dec_ref(c: RawZ3Context, s: RawZ3Stats)
    {.cdecl, header: "z3.h".}
  proc Z3_stats_size(c: RawZ3Context, s: RawZ3Stats): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_stats_get_key(c: RawZ3Context, s: RawZ3Stats, i: cuint): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_stats_is_uint(c: RawZ3Context, s: RawZ3Stats, i: cuint): bool
    {.cdecl, header: "z3.h".}
  proc Z3_stats_is_double(c: RawZ3Context, s: RawZ3Stats, i: cuint): bool
    {.cdecl, header: "z3.h".}
  proc Z3_stats_get_uint_value(c: RawZ3Context, s: RawZ3Stats, i: cuint): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_stats_get_double_value(c: RawZ3Context, s: RawZ3Stats,
                                 i: cuint): cdouble
    {.cdecl, header: "z3.h".}
  proc Z3_stats_to_string(c: RawZ3Context, s: RawZ3Stats): cstring
    {.cdecl, header: "z3.h".}

  proc Z3_solver_get_statistics(c: RawZ3Context, s: RawZ3Solver): RawZ3Stats
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 8.** Retrieve solver runtime statistics.
  proc Z3_fixedpoint_get_statistics(c: RawZ3Context,
                                    d: RawZ3Fixedpoint): RawZ3Stats
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 8.** Retrieve fixedpoint runtime statistics (closes
    ## v0.4 step 5's deferral).

  proc Z3_solver_get_consequences(c: RawZ3Context, s: RawZ3Solver,
                                  assumptions: RawZ3AstVector,
                                  variables: RawZ3AstVector,
                                  consequences: RawZ3AstVector): Z3LBool
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 8.** Compute the consequences of the solver's
    ## assertions + the given assumptions over the literals in
    ## `variables`. Output is filled into the pre-allocated
    ## `consequences` vector as implication ASTs of the form
    ## `(=> (and a_1 ... a_n) lit)`.
  proc Z3_solver_check(c: RawZ3Context, s: RawZ3Solver): Z3LBool
    {.cdecl, header: "z3.h".}
  proc Z3_solver_check_assumptions(c: RawZ3Context, s: RawZ3Solver,
                                   num_assumptions: cuint,
                                   assumptions: ptr UncheckedArray[RawZ3Ast]):
                                   Z3LBool
    {.cdecl, header: "z3.h".}
    ## Check satisfiability under a temporary assumption set. Unlike
    ## `Z3_solver_check`, the assumptions are not retained on the
    ## solver — the next call sees only the persistent assertions.
    ## v1.0 audit round 2, item #4.
  proc Z3_solver_get_assertions(c: RawZ3Context, s: RawZ3Solver):
                                RawZ3AstVector
    {.cdecl, header: "z3.h".}
    ## Snapshot of the solver's current assertion set as an AST
    ## vector. Each element is a Z3Bool (Z3 only accepts Boolean
    ## assertions). v1.0 audit round 2, item #5.
  proc Z3_solver_translate(source_ctx: RawZ3Context, s: RawZ3Solver,
                           target_ctx: RawZ3Context): RawZ3Solver
    {.cdecl, header: "z3.h".}
    ## Translate a solver and all its assertions from `source_ctx` to
    ## `target_ctx`. The result is a fresh solver in target_ctx with
    ## an equivalent assertion stack. v1.0 audit round 2, item #6.
  proc Z3_solver_get_model(c: RawZ3Context, s: RawZ3Solver): RawZ3Model
    {.cdecl, header: "z3.h".}
  proc Z3_solver_push(c: RawZ3Context, s: RawZ3Solver) {.cdecl, header: "z3.h".}
  proc Z3_solver_pop(c: RawZ3Context, s: RawZ3Solver, n: cuint)
    {.cdecl, header: "z3.h".}
  proc Z3_solver_reset(c: RawZ3Context, s: RawZ3Solver)
    {.cdecl, header: "z3.h".}
  proc Z3_solver_get_reason_unknown(c: RawZ3Context, s: RawZ3Solver): cstring
    {.cdecl, header: "z3.h".}
    ## Diagnostic for `Z3_L_UNDEF` outcomes; surfaces "incomplete theory",
    ## timeout, etc.

  proc Z3_solver_get_trail(c: RawZ3Context, s: RawZ3Solver): RawZ3AstVector
    {.cdecl, header: "z3.h".}
    ## Return the current trail of the solver (literals decided / propagated
    ## since the last `check()`). N8.1.

  proc Z3_solver_get_units(c: RawZ3Context, s: RawZ3Solver): RawZ3AstVector
    {.cdecl, header: "z3.h".}
    ## Return the unit literals from the last check(). N8.1.

  proc Z3_solver_get_non_units(c: RawZ3Context, s: RawZ3Solver): RawZ3AstVector
    {.cdecl, header: "z3.h".}
    ## Return the non-unit literals from the last check(). N8.1.

  proc Z3_solver_get_levels(c: RawZ3Context, s: RawZ3Solver,
                            literals: RawZ3AstVector,
                            sz: cuint,
                            levels: ptr cuint)
    {.cdecl, header: "z3.h".}
    ## Fill `levels[0..sz-1]` with the decision level of each literal in
    ## `literals`. Caller pre-allocates the output array sized to `sz`.
    ## N8.1.

  proc Z3_solver_set_initial_value(c: RawZ3Context, s: RawZ3Solver,
                                   v: RawZ3Ast, value: RawZ3Ast)
    {.cdecl, header: "z3.h".}
    ## Hint: suggest `v` starts at `value`. No guarantee solver respects it.
    ## N8.1.

  proc Z3_solver_cube(c: RawZ3Context, s: RawZ3Solver,
                      vars: RawZ3AstVector,
                      backtrack_level: cuint): RawZ3AstVector
    {.cdecl, header: "z3.h".}
    ## Return a cube (conjunction of literals) the solver is willing to branch
    ## on. `vars` is a hint vector of variables to branch on (may be empty);
    ## `backtrack_level` limits the depth. A result containing a single `false`
    ## literal means UNSAT; an empty vector means the cube is trivially SAT.
    ## N8.2.

  proc Z3_solver_congruence_root(c: RawZ3Context, s: RawZ3Solver,
                                  a: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Return the congruence-closure root for `a`. Valid after `check()` on a
    ## solver using CDCL; reflects current case-split state. N8.2.

  proc Z3_solver_congruence_next(c: RawZ3Context, s: RawZ3Solver,
                                  a: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Return the next AST in `a`'s congruence class (cyclic list). N8.2.

  proc Z3_mk_solver_for_logic(c: RawZ3Context, logic: RawZ3Symbol): RawZ3Solver
    {.cdecl, header: "z3.h".}
    ## Create a solver specialised for the given SMT-LIB logic (e.g.,
    ## "QF_BV", "QF_LIA"). The solver selects a decision procedure tuned to
    ## the fragment. N8.3.

  proc Z3_solver_get_num_scopes(c: RawZ3Context, s: RawZ3Solver): cuint
    {.cdecl, header: "z3.h".}
    ## Return the number of `push()` calls that have not been matched by
    ## `pop()` — the current stack depth. N8.3.

  proc Z3_solver_to_dimacs_string(c: RawZ3Context, s: RawZ3Solver,
                                   include_names: bool): cstring
    {.cdecl, header: "z3.h".}
    ## Render the solver's current Boolean constraint set as a DIMACS CNF
    ## string. `include_names` controls whether variable-name comments are
    ## emitted. Meaningful only for pure SAT/propositional problems. N8.3.

  proc Z3_solver_import_model_converter(ctx: RawZ3Context,
                                        src: RawZ3Solver,
                                        dst: RawZ3Solver)
    {.cdecl, header: "z3.h".}
    ## Transfer `src`'s model converter to `dst`. Used to propagate model
    ## reconstruction steps across solver pipelines (e.g. tactic-simplified
    ## into a residual solver). N8.3.

  proc Z3_solver_interrupt(c: RawZ3Context, s: RawZ3Solver)
    {.cdecl, header: "z3.h".}
    ## Interrupt a running solver. Safe to call from another thread while
    ## `Z3_solver_check` is executing in this context; the check will return
    ## `Z3_L_UNDEF` with reason "interrupted". N8.3.

  # --- Model ----------------------------------------------------------------

  proc Z3_model_eval(c: RawZ3Context, m: RawZ3Model, t: RawZ3Ast,
                     model_completion: bool, v: ptr RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
    ## Out-param `v` receives the evaluated AST. Returns false if
    ## evaluation failed (rare; usually means the model was empty).

  proc Z3_get_numeral_int(c: RawZ3Context, v: RawZ3Ast, i: ptr cint): bool
    {.cdecl, header: "z3.h".}
    ## Out-param `i` receives a (clamped) int value. Returns false for
    ## non-integer or out-of-range. Use Z3_get_numeral_string for big
    ## numbers or rationals.

  proc Z3_get_numeral_string(c: RawZ3Context, v: RawZ3Ast): cstring
    {.cdecl, header: "z3.h".}
    ## Lossless string form of an integer/rational. The buffer is
    ## context-owned and invalidated by the next call.

  proc Z3_get_numeral_double(c: RawZ3Context, v: RawZ3Ast): cdouble
    {.cdecl, header: "z3.h".}
    ## Lossy float64 approximation of a Real / Int numeral. Z3 picks
    ## the closest representable double. Returns 0.0 for non-numeral
    ## AST (no out-param indicator — defensive callers should simplify
    ## first and inspect the AST kind).

  proc Z3_get_bool_value(c: RawZ3Context, a: RawZ3Ast): Z3LBool
    {.cdecl, header: "z3.h".}
    ## `Z3_L_TRUE` / `Z3_L_FALSE` for boolean literals, `Z3_L_UNDEF`
    ## otherwise.

  # --- Error handling -------------------------------------------------------

  proc Z3_get_error_code(c: RawZ3Context): Z3ErrorCode
    {.cdecl, header: "z3.h".}
  proc Z3_get_error_msg(c: RawZ3Context, err: Z3ErrorCode): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_set_error_handler(c: RawZ3Context, h: Z3ErrorHandler)
    {.cdecl, header: "z3.h".}
    ## Replace Z3's default error handler (which would abort the
    ## program) with our own no-op handler so the error code stays in
    ## the context for us to check after each call.

  # --- Simplifier ----------------------------------------------------------

  proc Z3_simplify(c: RawZ3Context, a: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Apply Z3's default simplifier to `a`. Folds constants, rewrites
    ## known identities, normalises forms — but doesn't run the full
    ## decision procedure. The returned AST is semantically equivalent
    ## to the input (same value under every interpretation) and has
    ## the same sort.

  proc Z3_simplify_ex(c: RawZ3Context, a: RawZ3Ast, p: RawZ3Params): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Params-customised simplifier. Same semantic guarantees as
    ## `Z3_simplify`; the params let you toggle normalisation knobs
    ## like `arith_lhs`, `som`, `flat`, `elim_and`, … Get the full
    ## list via `(get-help simplify)` in a Z3 CLI session.

  # --- SMT2 parser ---------------------------------------------------------

  proc Z3_parse_smtlib2_string(c: RawZ3Context, src: cstring,
                               num_sorts: cuint,
                               sort_names: ptr UncheckedArray[RawZ3Symbol],
                               sorts: ptr UncheckedArray[RawZ3Sort],
                               num_decls: cuint,
                               decl_names: ptr UncheckedArray[RawZ3Symbol],
                               decls: ptr UncheckedArray[RawZ3FuncDecl]
                              ): RawZ3AstVector
    {.cdecl, header: "z3.h".}
    ## Parse an SMT2 source string. The four name/handle arrays let the
    ## caller pre-bind sorts and uninterpreted-function declarations
    ## that appear free in the source; passing zero arrays only allows
    ## sources self-contained via their own `declare-...` forms (the
    ## common case). Returns an `ast_vector` of the parsed assertions.

  proc Z3_parse_smtlib2_file(c: RawZ3Context, file_name: cstring,
                             num_sorts: cuint,
                             sort_names: ptr UncheckedArray[RawZ3Symbol],
                             sorts: ptr UncheckedArray[RawZ3Sort],
                             num_decls: cuint,
                             decl_names: ptr UncheckedArray[RawZ3Symbol],
                             decls: ptr UncheckedArray[RawZ3FuncDecl]
                            ): RawZ3AstVector
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 14.** File-input twin of `Z3_parse_smtlib2_string`.

  proc Z3_eval_smtlib2_string(c: RawZ3Context, source: cstring): cstring
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 14.** Execute an SMT2 command script (asserts +
    ## `(check-sat)` + `(get-model)` etc.) and return the response as
    ## a string.

  proc Z3_benchmark_to_smtlib_string(c: RawZ3Context,
                                     name, logic, status, attributes: cstring,
                                     num_assumptions: cuint,
                                     assumptions: ptr UncheckedArray[RawZ3Ast],
                                     formula: RawZ3Ast): cstring
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 14.** Serialise a single formula (plus optional
    ## assumptions) as a self-contained SMT2 benchmark.

  proc Z3_solver_from_string(c: RawZ3Context, s: RawZ3Solver, src: cstring)
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 14.** Parse SMT2 and assert directly into `s`.
  proc Z3_solver_from_file(c: RawZ3Context, s: RawZ3Solver, file_name: cstring)
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 14.** File-input twin of `Z3_solver_from_string`.

  # --- Parser context (incremental SMT2 parser) ----------------------------
  proc Z3_mk_parser_context(c: RawZ3Context): RawZ3ParserContext
    {.cdecl, header: "z3.h".}
  proc Z3_parser_context_inc_ref(c: RawZ3Context, pc: RawZ3ParserContext)
    {.cdecl, header: "z3.h".}
  proc Z3_parser_context_dec_ref(c: RawZ3Context, pc: RawZ3ParserContext)
    {.cdecl, header: "z3.h".}
  proc Z3_parser_context_add_sort(c: RawZ3Context, pc: RawZ3ParserContext,
                                  s: RawZ3Sort)
    {.cdecl, header: "z3.h".}
  proc Z3_parser_context_add_decl(c: RawZ3Context, pc: RawZ3ParserContext,
                                  f: RawZ3FuncDecl)
    {.cdecl, header: "z3.h".}
  proc Z3_parser_context_from_string(c: RawZ3Context, pc: RawZ3ParserContext,
                                     src: cstring): RawZ3AstVector
    {.cdecl, header: "z3.h".}

  # --- ast_vector accessors ------------------------------------------------

  proc Z3_ast_vector_inc_ref(c: RawZ3Context, v: RawZ3AstVector)
    {.cdecl, header: "z3.h".}
  proc Z3_ast_vector_dec_ref(c: RawZ3Context, v: RawZ3AstVector)
    {.cdecl, header: "z3.h".}
  proc Z3_ast_vector_size(c: RawZ3Context, v: RawZ3AstVector): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_mk_ast_vector(c: RawZ3Context): RawZ3AstVector
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 1.** Constructor for a fresh empty AST vector.
    ## Caller takes ownership of the initial ref.
  proc Z3_ast_vector_set(c: RawZ3Context, v: RawZ3AstVector,
                         i: cuint, a: RawZ3Ast)
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 1.** Replace the AST at index `i`.
  proc Z3_ast_vector_resize(c: RawZ3Context, v: RawZ3AstVector, n: cuint)
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 1.** Resize to `n` elements. New slots are nil-AST
    ## until populated; shrinking releases trailing entries.
  proc Z3_ast_vector_push(c: RawZ3Context, v: RawZ3AstVector, a: RawZ3Ast)
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 1.** Append `a`. Z3 internally inc_refs the pushed
    ## AST; the wrapper does NOT inc_ref a second time.
  proc Z3_ast_vector_to_string(c: RawZ3Context, v: RawZ3AstVector): cstring
    {.cdecl, header: "z3.h".}
    ## **v0.4 step 1.** SMT-LIB rendering of the full vector.
  proc Z3_ast_vector_get(c: RawZ3Context, v: RawZ3AstVector, i: cuint): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_ast_vector_translate(source: RawZ3Context, v: RawZ3AstVector,
                               target: RawZ3Context): RawZ3AstVector
    {.cdecl, header: "z3.h".}
    ## Transfer every AST in `v` from `source` context into `target`.
    ## Returns a fresh vector owned by `target`; caller takes the initial ref.

  # --- AST identity --------------------------------------------------------

  proc Z3_get_ast_hash(c: RawZ3Context, a: RawZ3Ast): cuint
    {.cdecl, header: "z3.h".}
    ## Per-AST hash. Z3 hashcons every AST so structurally-equal
    ## ASTs share the same raw pointer and therefore the same hash.
    ## Surfaced via `astHash` + `hash[T: Z3Term]` for std/tables.

  # --- Pretty printing -----------------------------------------------------

  proc Z3_ast_to_string(c: RawZ3Context, a: RawZ3Ast): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_model_to_string(c: RawZ3Context, m: RawZ3Model): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_solver_to_string(c: RawZ3Context, s: RawZ3Solver): cstring
    {.cdecl, header: "z3.h".}

  # --- Model enumeration (N2.1) ---------------------------------------------
  proc Z3_model_has_interp(c: RawZ3Context, m: RawZ3Model,
                            a: RawZ3FuncDecl): bool
    {.cdecl, header: "z3.h".}
  proc Z3_model_get_num_consts(c: RawZ3Context, m: RawZ3Model): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_model_get_const_decl(c: RawZ3Context, m: RawZ3Model,
                                i: cuint): RawZ3FuncDecl
    {.cdecl, header: "z3.h".}
  proc Z3_model_get_num_funcs(c: RawZ3Context, m: RawZ3Model): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_model_get_func_decl(c: RawZ3Context, m: RawZ3Model,
                               i: cuint): RawZ3FuncDecl
    {.cdecl, header: "z3.h".}
  proc Z3_model_get_num_sorts(c: RawZ3Context, m: RawZ3Model): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_model_get_sort(c: RawZ3Context, m: RawZ3Model,
                          i: cuint): RawZ3Sort
    {.cdecl, header: "z3.h".}
  proc Z3_model_get_sort_universe(c: RawZ3Context, m: RawZ3Model,
                                   s: RawZ3Sort): RawZ3AstVector
    {.cdecl, header: "z3.h".}
  proc Z3_model_translate(c: RawZ3Context, m: RawZ3Model,
                           dst: RawZ3Context): RawZ3Model
    {.cdecl, header: "z3.h".}

  # --- Decl name/arity/domain/range introspection (N2.4a) ------------------

  proc Z3_get_decl_name(c: RawZ3Context, d: RawZ3FuncDecl): RawZ3Symbol
    {.cdecl, header: "z3.h".}
    ## Return the symbol carrying the declaration's name.  Pair with
    ## `Z3_get_symbol_string` to get a Nim string.
  proc Z3_get_decl_num_parameters(c: RawZ3Context, d: RawZ3FuncDecl): cuint
    {.cdecl, header: "z3.h".}
    ## Number of *sort parameters* in the declaration (not the domain
    ## arity of the function).  Used internally; `Z3_get_domain_size`
    ## is the correct arity accessor.

  # --- Decl parameter introspection (N2.4b) ---------------------------------

  proc Z3_get_decl_parameter_kind(c: RawZ3Context, d: RawZ3FuncDecl,
                                   idx: cuint): Z3ParameterKindFFI
    {.cdecl, header: "z3.h".}
    ## Kind of the idx-th parameter of `d`.
  proc Z3_get_decl_int_parameter(c: RawZ3Context, d: RawZ3FuncDecl,
                                  idx: cuint): cint
    {.cdecl, header: "z3.h".}
    ## Integer value of the idx-th parameter.
    ## Pre: kind == Z3_PARAMETER_INT.
  proc Z3_get_decl_double_parameter(c: RawZ3Context, d: RawZ3FuncDecl,
                                     idx: cuint): cdouble
    {.cdecl, header: "z3.h".}
    ## Double value of the idx-th parameter.
    ## Pre: kind == Z3_PARAMETER_DOUBLE.
  proc Z3_get_decl_symbol_parameter(c: RawZ3Context, d: RawZ3FuncDecl,
                                     idx: cuint): RawZ3Symbol
    {.cdecl, header: "z3.h".}
    ## Symbol value of the idx-th parameter.
    ## Pre: kind == Z3_PARAMETER_SYMBOL.
  proc Z3_get_decl_sort_parameter(c: RawZ3Context, d: RawZ3FuncDecl,
                                   idx: cuint): RawZ3Sort
    {.cdecl, header: "z3.h".}
    ## Sort value of the idx-th parameter.
    ## Pre: kind == Z3_PARAMETER_SORT.
  proc Z3_get_decl_ast_parameter(c: RawZ3Context, d: RawZ3FuncDecl,
                                  idx: cuint): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## AST value of the idx-th parameter.
    ## Pre: kind == Z3_PARAMETER_AST.
  proc Z3_get_decl_func_decl_parameter(c: RawZ3Context, d: RawZ3FuncDecl,
                                        idx: cuint): RawZ3FuncDecl
    {.cdecl, header: "z3.h".}
    ## FuncDecl value of the idx-th parameter.
    ## Pre: kind == Z3_PARAMETER_FUNC_DECL.
  proc Z3_get_decl_rational_parameter(c: RawZ3Context, d: RawZ3FuncDecl,
                                       idx: cuint): cstring
    {.cdecl, header: "z3.h".}
    ## Rational value (as a decimal string) of the idx-th parameter.
    ## Pre: kind == Z3_PARAMETER_RATIONAL.

  proc Z3_get_domain_size(c: RawZ3Context, d: RawZ3FuncDecl): cuint
    {.cdecl, header: "z3.h".}
    ## Number of domain sorts — the arity of the function declaration.
  proc Z3_get_domain(c: RawZ3Context, d: RawZ3FuncDecl, i: cuint): RawZ3Sort
    {.cdecl, header: "z3.h".}
    ## i-th domain sort (0-based).  Behaviour is undefined for i ≥ arity.
  proc Z3_get_range(c: RawZ3Context, d: RawZ3FuncDecl): RawZ3Sort
    {.cdecl, header: "z3.h".}
    ## Range (codomain) sort of the function declaration.
  proc Z3_get_func_decl_id(c: RawZ3Context, d: RawZ3FuncDecl): cuint
    {.cdecl, header: "z3.h".}
    ## Unique monotone identifier for the declaration within its context.
    ## Stable for the lifetime of the context.

  # --- Characters (v0.3 step 4) --------------------------------------------
  #
  # Z3's Char sort is a Unicode codepoint type. The string/regex theory
  # uses Char as the basis alphabet — re.range, in particular, requires
  # Char-sorted operands (not single-character strings) since 4.8.10+.

  proc Z3_mk_char_sort(c: RawZ3Context): RawZ3Sort
    {.cdecl, header: "z3.h".}
  proc Z3_mk_char(c: RawZ3Context, ch: cuint): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_char_to_int(c: RawZ3Context, ch: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_char_le(c: RawZ3Context, a, b: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_char_is_digit(c: RawZ3Context, ch: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}

  # --- Z3Char <-> Z3BitVec interop (v0.5 step 6C) --------------------------
  proc Z3_mk_char_to_bv(c: RawZ3Context, ch: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Convert a Z3Char to a `(_ BitVec unicode-char-width)`. The
    ## width is determined by Z3's `encoding` global param
    ## (default `unicode` = 18 bits).
  proc Z3_mk_char_from_bv(c: RawZ3Context, bv: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Inverse of `Z3_mk_char_to_bv`. The BV's width must match the
    ## current encoding width.

  # --- Strings + sequences (v0.3 step 4) -----------------------------------
  #
  # SMT-LIB strings are `(Seq Char)` sequences of unicode chars. Z3
  # exposes them via a first-class String sort plus the `seq_*` builders
  # which work over the sequence the string is. Step 4 covers the
  # String surface only; Z3Seq[E] generalisation lands in step 5.

  proc Z3_mk_string_sort(c: RawZ3Context): RawZ3Sort
    {.cdecl, header: "z3.h".}
  proc Z3_mk_string(c: RawZ3Context, s: cstring): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_lstring(c: RawZ3Context, length: cuint, s: cstring): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Length-prefixed string literal — preserves embedded nulls.
  proc Z3_get_lstring(c: RawZ3Context, s: RawZ3Ast, length: ptr cuint): cstring
    {.cdecl, header: "z3.h".}
    ## Length-prefixed model extraction. `length` is filled in on
    ## success. The returned `cstring` is owned by Z3 — copy before the
    ## next Z3 call that may invalidate it.
  proc Z3_is_string(c: RawZ3Context, s: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_get_string_length(c: RawZ3Context, s: RawZ3Ast): cuint
    {.cdecl, header: "z3.h".}
    ## Codepoint count of a string literal AST. Precondition:
    ## `Z3_is_string(c, s)`.
  proc Z3_get_string_contents(c: RawZ3Context, s: RawZ3Ast,
                               length: cuint, contents: ptr cuint)
    {.cdecl, header: "z3.h".}
    ## Fill the caller-allocated `contents` array (size ≥ `length`) with
    ## the Unicode codepoints of the string literal `s`. Precondition:
    ## `Z3_is_string(c, s)` and `length == Z3_get_string_length(c, s)`.

  proc Z3_mk_seq_sort(c: RawZ3Context, elem: RawZ3Sort): RawZ3Sort
    {.cdecl, header: "z3.h".}
  proc Z3_mk_seq_empty(c: RawZ3Context, seq: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_seq_unit(c: RawZ3Context, e: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_seq_nth(c: RawZ3Context, s, index: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_seq_length(c: RawZ3Context, s: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_seq_concat(c: RawZ3Context, n: cuint,
                        args: ptr UncheckedArray[RawZ3Ast]): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_seq_at(c: RawZ3Context, s, index: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_seq_extract(c: RawZ3Context, s, offset, length: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_seq_contains(c: RawZ3Context, s, sub: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_seq_prefix(c: RawZ3Context, prefix, s: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_seq_suffix(c: RawZ3Context, suffix, s: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_seq_index(c: RawZ3Context, s, sub, offset: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_seq_replace(c: RawZ3Context, s, src, dst: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_seq_last_index(c: RawZ3Context, s, sub: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}

  # N5.5 — Sequence HOF: map / mapi / foldl / foldli
  proc Z3_mk_seq_map(c: RawZ3Context, f, s: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## SMT `(seq.map f s)` — apply unary `f` over every element of `s`.
  proc Z3_mk_seq_mapi(c: RawZ3Context, f, i, s: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## SMT `(seq.mapi f i s)` — apply binary `f(index, elem)` starting
    ## at index `i`.
  proc Z3_mk_seq_foldl(c: RawZ3Context, f, a, s: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## SMT `(seq.foldl f a s)` — left fold with accumulator `a`.
  proc Z3_mk_seq_foldli(c: RawZ3Context, f, i, a, s: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## SMT `(seq.foldli f i a s)` — left fold with index tracking,
    ## starting index `i`, accumulator `a`.

  proc Z3_mk_str_to_int(c: RawZ3Context, s: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_int_to_str(c: RawZ3Context, s: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_string_to_code(c: RawZ3Context, a: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Unicode codepoint of the first (and only) character of a
    ## single-character string. Returns -1 for the empty string or any
    ## string of length != 1.
  proc Z3_mk_string_from_code(c: RawZ3Context, a: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Single-character string whose codepoint equals `a`.
  proc Z3_mk_ubv_to_str(c: RawZ3Context, s: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Unsigned bit-vector to decimal string representation.
  proc Z3_mk_sbv_to_str(c: RawZ3Context, s: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Signed bit-vector to decimal string representation.
  proc Z3_mk_str_lt(c: RawZ3Context, prefix, s: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Lexicographic strict less-than: `prefix <_lex s`.
  proc Z3_mk_str_le(c: RawZ3Context, prefix, s: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
    ## Lexicographic less-or-equal: `prefix <=_lex s`.

  # --- FloatingPoint (v0.3 step 6) -----------------------------------------
  #
  # IEEE 754 / SMT-LIB FP theory. Sort builders, rounding modes,
  # literals, arithmetic, comparisons, predicates, conversions.

  proc Z3_mk_fpa_sort(c: RawZ3Context, ebits, sbits: cuint): RawZ3Sort
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_sort_half(c: RawZ3Context): RawZ3Sort
    {.cdecl, header: "z3.h".}
    ## IEEE 754 binary16 (half-precision) sort — 5 exponent, 11 significand bits.
  proc Z3_mk_fpa_sort_single(c: RawZ3Context): RawZ3Sort
    {.cdecl, header: "z3.h".}
    ## IEEE 754 binary32 (single-precision) sort — 8 exponent, 24 significand bits.
  proc Z3_mk_fpa_sort_double(c: RawZ3Context): RawZ3Sort
    {.cdecl, header: "z3.h".}
    ## IEEE 754 binary64 (double-precision) sort — 11 exponent, 53 significand bits.
  proc Z3_mk_fpa_sort_quadruple(c: RawZ3Context): RawZ3Sort
    {.cdecl, header: "z3.h".}
    ## IEEE 754 binary128 (quadruple-precision) sort — 15 exponent, 113 significand bits.
  proc Z3_mk_fpa_rounding_mode_sort(c: RawZ3Context): RawZ3Sort
    {.cdecl, header: "z3.h".}

  # Rounding-mode constants
  proc Z3_mk_fpa_round_nearest_ties_to_even(c: RawZ3Context): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_round_nearest_ties_to_away(c: RawZ3Context): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_round_toward_positive(c: RawZ3Context): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_round_toward_negative(c: RawZ3Context): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_round_toward_zero(c: RawZ3Context): RawZ3Ast
    {.cdecl, header: "z3.h".}

  # Special literals
  proc Z3_mk_fpa_nan(c: RawZ3Context, s: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_inf(c: RawZ3Context, s: RawZ3Sort, negative: bool): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_zero(c: RawZ3Context, s: RawZ3Sort, negative: bool): RawZ3Ast
    {.cdecl, header: "z3.h".}

  # Bit-exact assembly from sign/exponent/significand BVs (N6.3)
  proc Z3_mk_fpa_fp(c: RawZ3Context, sgn, exp, sig: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}

  # Numeric literals
  proc Z3_mk_fpa_numeral_float(c: RawZ3Context, v: cfloat, ty: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_numeral_double(c: RawZ3Context, v: cdouble, ty: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_numeral_int(c: RawZ3Context, v: cint, ty: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}

  # Arithmetic — no rounding
  proc Z3_mk_fpa_abs(c: RawZ3Context, t: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_neg(c: RawZ3Context, t: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_rem(c: RawZ3Context, a, b: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_min(c: RawZ3Context, a, b: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_max(c: RawZ3Context, a, b: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}

  # Arithmetic — rounding-aware
  proc Z3_mk_fpa_add(c: RawZ3Context, rm, a, b: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_sub(c: RawZ3Context, rm, a, b: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_mul(c: RawZ3Context, rm, a, b: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_div(c: RawZ3Context, rm, a, b: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_fma(c: RawZ3Context, rm, a, b, ce: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_sqrt(c: RawZ3Context, rm, a: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_round_to_integral(c: RawZ3Context, rm, a: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}

  # Comparisons — Z3Bool-yielding
  proc Z3_mk_fpa_eq(c: RawZ3Context, a, b: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_leq(c: RawZ3Context, a, b: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_lt(c: RawZ3Context, a, b: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_geq(c: RawZ3Context, a, b: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_gt(c: RawZ3Context, a, b: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}

  # Predicates
  proc Z3_mk_fpa_is_normal(c: RawZ3Context, t: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_is_subnormal(c: RawZ3Context, t: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_is_zero(c: RawZ3Context, t: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_is_infinite(c: RawZ3Context, t: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_is_nan(c: RawZ3Context, t: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_is_negative(c: RawZ3Context, t: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_is_positive(c: RawZ3Context, t: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}

  # Numeral predicates — host-side bool (N6.4a)
  proc Z3_fpa_is_numeral_nan(c: RawZ3Context, t: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_fpa_is_numeral_inf(c: RawZ3Context, t: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_fpa_is_numeral_zero(c: RawZ3Context, t: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_fpa_is_numeral_normal(c: RawZ3Context, t: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_fpa_is_numeral_subnormal(c: RawZ3Context, t: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_fpa_is_numeral_positive(c: RawZ3Context, t: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_fpa_is_numeral_negative(c: RawZ3Context, t: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}

  # Conversions
  proc Z3_mk_fpa_to_fp_bv(c: RawZ3Context, bv: RawZ3Ast, s: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_to_fp_float(c: RawZ3Context, rm, t: RawZ3Ast, s: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_to_fp_real(c: RawZ3Context, rm, t: RawZ3Ast, s: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_to_fp_signed(c: RawZ3Context, rm, t: RawZ3Ast, s: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_to_fp_unsigned(c: RawZ3Context, rm, t: RawZ3Ast, s: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_to_ubv(c: RawZ3Context, rm, t: RawZ3Ast, sz: cuint): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_to_sbv(c: RawZ3Context, rm, t: RawZ3Ast, sz: cuint): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_to_real(c: RawZ3Context, t: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_fpa_to_ieee_bv(c: RawZ3Context, t: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}

  # Model extraction — Z3 doesn't ship a direct float-extractor for
  # FP literals. The path is via `Z3_mk_fpa_to_ieee_bv` → simplify →
  # `Z3_get_numeral_uint64`, then reinterpret-cast in Nim.

  # Numeral decomposition — N6.4b
  proc Z3_fpa_get_numeral_sign(c: RawZ3Context, t: RawZ3Ast,
                                sgn: ptr cint): bool
    {.cdecl, header: "z3.h".}
  proc Z3_fpa_get_numeral_significand_string(c: RawZ3Context,
                                              t: RawZ3Ast): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_fpa_get_numeral_significand_bv(c: RawZ3Context,
                                          t: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_fpa_get_numeral_significand_uint64(c: RawZ3Context, t: RawZ3Ast,
                                              n: ptr uint64): bool
    {.cdecl, header: "z3.h".}
  proc Z3_fpa_get_numeral_exponent_string(c: RawZ3Context, t: RawZ3Ast,
                                           biased: bool): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_fpa_get_numeral_exponent_int64(c: RawZ3Context, t: RawZ3Ast,
                                          n: ptr int64, biased: bool): bool
    {.cdecl, header: "z3.h".}
  proc Z3_fpa_get_numeral_exponent_bv(c: RawZ3Context, t: RawZ3Ast,
                                       biased: bool): RawZ3Ast
    {.cdecl, header: "z3.h".}

  # --- Regular expressions (v0.3 step 4) -----------------------------------

  proc Z3_mk_re_sort(c: RawZ3Context, basis: RawZ3Sort): RawZ3Sort
    {.cdecl, header: "z3.h".}
  proc Z3_mk_seq_to_re(c: RawZ3Context, s: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_seq_in_re(c: RawZ3Context, s, re: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_re_empty(c: RawZ3Context, re: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_re_full(c: RawZ3Context, re: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_re_allchar(c: RawZ3Context, re: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_re_plus(c: RawZ3Context, re: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_re_star(c: RawZ3Context, re: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_re_option(c: RawZ3Context, re: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_re_complement(c: RawZ3Context, re: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_re_concat(c: RawZ3Context, n: cuint,
                       args: ptr UncheckedArray[RawZ3Ast]): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_re_union(c: RawZ3Context, n: cuint,
                      args: ptr UncheckedArray[RawZ3Ast]): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_re_intersect(c: RawZ3Context, n: cuint,
                          args: ptr UncheckedArray[RawZ3Ast]): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_re_range(c: RawZ3Context, lo, hi: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_re_loop(c: RawZ3Context, re: RawZ3Ast, lo, hi: cuint): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_re_power(c: RawZ3Context, re: RawZ3Ast, n: cuint): RawZ3Ast
    {.cdecl, header: "z3.h".}

  # --- Set operations (z3_api.h) — N1.1 ------------------------------------

  proc Z3_mk_empty_set(c: RawZ3Context, domain: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_full_set(c: RawZ3Context, domain: RawZ3Sort): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_set_add(c: RawZ3Context, set: RawZ3Ast, elem: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_set_del(c: RawZ3Context, set: RawZ3Ast, elem: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_set_union(c: RawZ3Context, num_args: cuint,
                        args: ptr UncheckedArray[RawZ3Ast]): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_set_intersect(c: RawZ3Context, num_args: cuint,
                            args: ptr UncheckedArray[RawZ3Ast]): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_set_difference(c: RawZ3Context, arg1, arg2: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_set_complement(c: RawZ3Context, arg: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_set_member(c: RawZ3Context, elem, set: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_set_subset(c: RawZ3Context, arg1, arg2: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_set_has_size(c: RawZ3Context, set, k: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}

  # --- AST map (z3_ast_containers.h) — N1.2 --------------------------------

  proc Z3_mk_ast_map(c: RawZ3Context): RawZ3AstMap
    {.cdecl, header: "z3.h".}
  proc Z3_ast_map_inc_ref(c: RawZ3Context, m: RawZ3AstMap)
    {.cdecl, header: "z3.h".}
  proc Z3_ast_map_dec_ref(c: RawZ3Context, m: RawZ3AstMap)
    {.cdecl, header: "z3.h".}
  proc Z3_ast_map_contains(c: RawZ3Context, m: RawZ3AstMap,
                            k: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_ast_map_find(c: RawZ3Context, m: RawZ3AstMap,
                        k: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_ast_map_insert(c: RawZ3Context, m: RawZ3AstMap, k, v: RawZ3Ast)
    {.cdecl, header: "z3.h".}
  proc Z3_ast_map_erase(c: RawZ3Context, m: RawZ3AstMap, k: RawZ3Ast)
    {.cdecl, header: "z3.h".}
  proc Z3_ast_map_reset(c: RawZ3Context, m: RawZ3AstMap)
    {.cdecl, header: "z3.h".}
  proc Z3_ast_map_size(c: RawZ3Context, m: RawZ3AstMap): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_ast_map_keys(c: RawZ3Context, m: RawZ3AstMap): RawZ3AstVector
    {.cdecl, header: "z3.h".}
  proc Z3_ast_map_to_string(c: RawZ3Context, m: RawZ3AstMap): cstring
    {.cdecl, header: "z3.h".}

  # --- RCF (z3_rcf.h) — N1.6 -----------------------------------------------

  proc Z3_rcf_del(c: RawZ3Context, a: RawZ3RcfNum)
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_mk_rational(c: RawZ3Context, val: cstring): RawZ3RcfNum
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_mk_small_int(c: RawZ3Context, val: cint): RawZ3RcfNum
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_mk_pi(c: RawZ3Context): RawZ3RcfNum
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_mk_e(c: RawZ3Context): RawZ3RcfNum
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_mk_infinitesimal(c: RawZ3Context): RawZ3RcfNum
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_add(c: RawZ3Context, a, b: RawZ3RcfNum): RawZ3RcfNum
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_sub(c: RawZ3Context, a, b: RawZ3RcfNum): RawZ3RcfNum
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_mul(c: RawZ3Context, a, b: RawZ3RcfNum): RawZ3RcfNum
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_div(c: RawZ3Context, a, b: RawZ3RcfNum): RawZ3RcfNum
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_neg(c: RawZ3Context, a: RawZ3RcfNum): RawZ3RcfNum
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_inv(c: RawZ3Context, a: RawZ3RcfNum): RawZ3RcfNum
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_power(c: RawZ3Context, a: RawZ3RcfNum, k: cuint): RawZ3RcfNum
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_lt(c: RawZ3Context, a, b: RawZ3RcfNum): bool
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_le(c: RawZ3Context, a, b: RawZ3RcfNum): bool
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_gt(c: RawZ3Context, a, b: RawZ3RcfNum): bool
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_ge(c: RawZ3Context, a, b: RawZ3RcfNum): bool
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_eq(c: RawZ3Context, a, b: RawZ3RcfNum): bool
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_neq(c: RawZ3Context, a, b: RawZ3RcfNum): bool
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_num_to_string(c: RawZ3Context, a: RawZ3RcfNum,
                             compact, html: bool): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_rcf_num_to_decimal_string(c: RawZ3Context, a: RawZ3RcfNum,
                                    prec: cuint): cstring
    {.cdecl, header: "z3.h".}

  # --- Algebraic numbers (z3_algebraic.h) — N1.7a --------------------------

  proc Z3_algebraic_is_value(c: RawZ3Context, a: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_is_pos(c: RawZ3Context, a: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_is_neg(c: RawZ3Context, a: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_is_zero(c: RawZ3Context, a: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_sign(c: RawZ3Context, a: RawZ3Ast): cint
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_add(c: RawZ3Context, a, b: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_sub(c: RawZ3Context, a, b: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_mul(c: RawZ3Context, a, b: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_div(c: RawZ3Context, a, b: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_root(c: RawZ3Context, a: RawZ3Ast, k: cuint): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_power(c: RawZ3Context, a: RawZ3Ast, k: cuint): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_lt(c: RawZ3Context, a, b: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_gt(c: RawZ3Context, a, b: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_le(c: RawZ3Context, a, b: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_ge(c: RawZ3Context, a, b: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_eq(c: RawZ3Context, a, b: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_neq(c: RawZ3Context, a, b: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_roots(c: RawZ3Context, p: RawZ3Ast, n: cuint,
                           a: ptr UncheckedArray[RawZ3Ast]): RawZ3AstVector
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_eval(c: RawZ3Context, p: RawZ3Ast, n: cuint,
                         a: ptr UncheckedArray[RawZ3Ast]): cint
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_get_poly(c: RawZ3Context, a: RawZ3Ast): RawZ3AstVector
    {.cdecl, header: "z3.h".}
  proc Z3_algebraic_get_i(c: RawZ3Context, a: RawZ3Ast): cuint
    {.cdecl, header: "z3.h".}

  # --- Polynomial subresultants (z3_polynomial.h) — merged N1.7a -----------

  proc Z3_polynomial_subresultants(c: RawZ3Context,
                                   p, q, x: RawZ3Ast): RawZ3AstVector
    {.cdecl, header: "z3.h".}

  # --- Propagator (N8.4a — FFI surface) ------------------------------------

  proc Z3_solver_propagate_init(c: RawZ3Context, s: RawZ3Solver,
                                userCtx: pointer,
                                pushEh:  Z3PropagatorPushEh,
                                popEh:   Z3PropagatorPopEh,
                                freshEh: Z3PropagatorFreshEh)
    {.cdecl, header: "z3.h".}
    ## Register a user propagator with the solver. Must be called first;
    ## establishes the user context and mandatory push/pop/fresh hooks.

  proc Z3_solver_propagate_fixed(c: RawZ3Context, s: RawZ3Solver,
                                 fixedEh: Z3PropagatorFixedEh)
    {.cdecl, header: "z3.h".}
    ## Register a callback for when a registered expression is fixed to a value.

  proc Z3_solver_propagate_final(c: RawZ3Context, s: RawZ3Solver,
                                 finalEh: Z3PropagatorFinalEh)
    {.cdecl, header: "z3.h".}
    ## Register a callback at the final-check point.

  proc Z3_solver_propagate_eq(c: RawZ3Context, s: RawZ3Solver,
                              eqEh: Z3PropagatorEqEh)
    {.cdecl, header: "z3.h".}
    ## Register a callback for expression equalities.

  proc Z3_solver_propagate_diseq(c: RawZ3Context, s: RawZ3Solver,
                                 diseqEh: Z3PropagatorEqEh)
    {.cdecl, header: "z3.h".}
    ## Register a callback for expression disequalities.
    ## Shares the `Z3PropagatorEqEh` type with `Z3_solver_propagate_eq`
    ## (per C header and ADR-N0004).

  proc Z3_solver_propagate_created(c: RawZ3Context, s: RawZ3Solver,
                                   createdEh: Z3PropagatorCreatedEh)
    {.cdecl, header: "z3.h".}
    ## Register a callback when a new expression with a declared propagator
    ## function is first created by the solver.

  proc Z3_solver_propagate_decide(c: RawZ3Context, s: RawZ3Solver,
                                  decideEh: Z3PropagatorDecideEh)
    {.cdecl, header: "z3.h".}
    ## Register a callback when the solver splits on a registered expression.

  proc Z3_solver_next_split(c: RawZ3Context, cb: RawZ3PropagatorCtxBox,
                            t: RawZ3Ast, idx: cuint, phase: Z3LBool): bool
    {.cdecl, header: "z3.h".}
    ## Override the next decision variable and phase. Call from within a
    ## `Z3PropagatorDecideEh` callback. Returns false if `t` is already
    ## assigned internally.

  proc Z3_solver_propagate_declare(c: RawZ3Context, name: RawZ3Symbol,
                                   n: cuint,
                                   domain: ptr UncheckedArray[RawZ3Sort],
                                   range: RawZ3Sort): RawZ3FuncDecl
    {.cdecl, header: "z3.h".}
    ## Create an uninterpreted function declaration for use with the
    ## propagator. Expressions using it trigger `Z3PropagatorCreatedEh`.

  proc Z3_solver_propagate_register(c: RawZ3Context, s: RawZ3Solver,
                                    e: RawZ3Ast)
    {.cdecl, header: "z3.h".}
    ## Register a Bool or BitVec expression for propagation events
    ## (fixed/eq/diseq). Call at any time outside a callback.

  proc Z3_solver_propagate_register_cb(c: RawZ3Context,
                                       cb: RawZ3PropagatorCtxBox,
                                       e: RawZ3Ast)
    {.cdecl, header: "z3.h".}
    ## Like `Z3_solver_propagate_register` but callable from within a
    ## callback (takes the callback context, not the solver).

  proc Z3_solver_propagate_consequence(c: RawZ3Context,
                                       cb: RawZ3PropagatorCtxBox,
                                       numFixed: cuint,
                                       fixed: ptr UncheckedArray[RawZ3Ast],
                                       numEqs: cuint,
                                       eqLhs: ptr UncheckedArray[RawZ3Ast],
                                       eqRhs: ptr UncheckedArray[RawZ3Ast],
                                       conseq: RawZ3Ast): bool
    {.cdecl, header: "z3.h".}
    ## Assert a propagation consequence given a set of fixed premises and
    ## equality premises. Returns false if the consequence is already true.

  # N8.4d — Z3_solver_register_on_clause (available on Z3 4.12+).
  # The declaration is unconditional here because `dynlib` bodies may not
  # contain `when` blocks (the macro only accepts proc declarations).
  # The high-level typed surface (`z3/onclause`) is gated behind
  # `-d:z3WithoutOnClause`; on older builds the symbol simply won't be
  # called via the public API.
  #
  # The callback parameter is declared as `pointer` (not `Z3OnClauseEh`)
  # because the C typedef uses `const unsigned int*` for the deps param,
  # which Nim cannot express in a proc-type. Using `pointer` bypasses
  # softlink's static const-mismatch check; the cast to `Z3OnClauseEh`
  # is performed at the call site in `z3/onclause`.
  proc Z3_solver_register_on_clause(c: RawZ3Context, s: RawZ3Solver,
                                    userCtx: pointer,
                                    onClauseEh: pointer)
    {.cdecl, header: "z3.h".}
    ## Register a callback to receive asserted, inferred, and deleted
    ## clauses during Z3's CDCL(T) search. Matches `Z3_solver_register_on_clause`.

  # --- Simplifier object API (N8.7 — Z3 4.12+) --------------------------------
  # `Z3_simplifier_to_string` does not exist in Z3's C API; `getHelp` is
  # the nearest equivalent for human-readable descriptions.

  proc Z3_mk_simplifier(c: RawZ3Context, name: cstring): RawZ3Simplifier
    {.cdecl, header: "z3.h".}
    ## Return the simplifier associated with `name`. See
    ## `Z3_get_num_simplifiers` / `Z3_get_simplifier_name` for enumeration.

  proc Z3_simplifier_inc_ref(c: RawZ3Context, s: RawZ3Simplifier)
    {.cdecl, header: "z3.h".}

  proc Z3_simplifier_dec_ref(c: RawZ3Context, s: RawZ3Simplifier)
    {.cdecl, header: "z3.h".}

  proc Z3_simplifier_using_params(c: RawZ3Context, s: RawZ3Simplifier,
                                   p: RawZ3Params): RawZ3Simplifier
    {.cdecl, header: "z3.h".}
    ## Return a copy of `s` configured with parameter bag `p`.

  proc Z3_simplifier_and_then(c: RawZ3Context,
                               s1, s2: RawZ3Simplifier): RawZ3Simplifier
    {.cdecl, header: "z3.h".}
    ## Sequential composition: `s1` runs first, then `s2`.

  proc Z3_solver_add_simplifier(c: RawZ3Context, solver: RawZ3Solver,
                                 simplifier: RawZ3Simplifier): RawZ3Solver
    {.cdecl, header: "z3.h".}
    ## Return a new solver that is a copy of `solver` with `simplifier`
    ## installed for pre-processing assertions.

  proc Z3_simplifier_get_param_descrs(c: RawZ3Context,
                                       s: RawZ3Simplifier): RawZ3ParamDescrs
    {.cdecl, header: "z3.h".}
    ## Return the parameter-schema for `s`.

  proc Z3_simplifier_get_help(c: RawZ3Context, s: RawZ3Simplifier): cstring
    {.cdecl, header: "z3.h".}
    ## Human-readable help string listing the simplifier's parameters.

  # N9.2 — order theory + transitive closure.
  # Z3_mk_linear_order / _partial_order / _piecewise_linear_order / _tree_order
  # all have signature (Z3_context, Z3_sort, unsigned) → Z3_func_decl.
  # Z3_mk_transitive_closure has signature (Z3_context, Z3_func_decl) → Z3_func_decl.

  proc Z3_mk_linear_order(c: RawZ3Context, a: RawZ3Sort, id: cuint): RawZ3FuncDecl
    {.cdecl, header: "z3.h".}
    ## Create a strict total (linear) order on sort `a` with identifier `id`.
    ## Z3 injects irreflexivity, transitivity, and totality axioms.

  proc Z3_mk_partial_order(c: RawZ3Context, a: RawZ3Sort, id: cuint): RawZ3FuncDecl
    {.cdecl, header: "z3.h".}
    ## Create a partial order (reflexive, antisymmetric, transitive) on `a`.

  proc Z3_mk_piecewise_linear_order(c: RawZ3Context, a: RawZ3Sort,
                                     id: cuint): RawZ3FuncDecl
    {.cdecl, header: "z3.h".}
    ## Create a piecewise linear order on `a` (a forest of linear chains).

  proc Z3_mk_tree_order(c: RawZ3Context, a: RawZ3Sort, id: cuint): RawZ3FuncDecl
    {.cdecl, header: "z3.h".}
    ## Create a tree order on `a`.

  proc Z3_mk_transitive_closure(c: RawZ3Context,
                                 f: RawZ3FuncDecl): RawZ3FuncDecl
    {.cdecl, header: "z3.h".}
    ## Return the transitive closure of binary relation `f`.

  # --- Process-global logging API (N9.5) ------------------------------------
  # These functions have no `Z3_context` parameter; they affect process-wide
  # Z3 state. Matching the "extra_API" category in z3_api.h.

  proc Z3_open_log(filename: cstring): bool {.cdecl, header: "z3.h".}
    ## Open a log file at `filename`. Z3 will append every API call to it
    ## until `Z3_close_log` is called. Returns `true` on success.
    ## Only one log may be open at a time (subsequent opens replace the
    ## previous).

  proc Z3_append_log(s: cstring) {.cdecl, header: "z3.h".}
    ## Write a comment line `s` into the currently-open interaction log.
    ## No-op if no log is open.

  proc Z3_close_log() {.cdecl, header: "z3.h".}
    ## Close the currently-open interaction log (if any). Flushing and
    ## closing the file handle. After this call `Z3_append_log` is a no-op
    ## until `Z3_open_log` is called again.

  proc Z3_toggle_warning_messages(enabled: bool) {.cdecl, header: "z3.h".}
    ## Enable (`true`) or suppress (`false`) Z3's diagnostic warning output.
    ## Affects all contexts in the process. Useful for silencing expected
    ## warnings (e.g. "WARNING: quantifiers detected" in test suites) without
    ## disabling the error channel.

# N5.4 — Z3_mk_seq_replace_all / Z3_mk_seq_replace_re are absent from
# some Z3 builds (including the openSUSE Tumbleweed 4.15.0-1.3 package).
# Gate their FFI declarations behind `-d:z3WithSeqReplaceAll` and
# `-d:z3WithSeqReplaceRe` so users on capable builds can opt in.

when defined(z3WithSeqReplaceAll):
  dynlib "libz3.so(.4|.4.13|.4.12|.4.11|.4.10|)":
    proc Z3_mk_seq_replace_all(c: RawZ3Context, s, src, dst: RawZ3Ast): RawZ3Ast
      {.cdecl, header: "z3.h".}

when defined(z3WithSeqReplaceRe):
  dynlib "libz3.so(.4|.4.13|.4.12|.4.11|.4.10|)":
    proc Z3_mk_seq_replace_re(c: RawZ3Context, s, r, dst: RawZ3Ast): RawZ3Ast
      {.cdecl, header: "z3.h".}

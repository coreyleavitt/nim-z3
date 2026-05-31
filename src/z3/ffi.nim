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

proc isNil*(x: RawZ3Config | RawZ3Context | RawZ3Sort | RawZ3Ast | RawZ3App |
            RawZ3Symbol | RawZ3Solver | RawZ3Model | RawZ3FuncDecl |
            RawZ3AstVector | RawZ3Constructor | RawZ3ConstructorList |
            RawZ3Pattern | RawZ3Optimize | RawZ3Fixedpoint | RawZ3Stats |
            RawZ3Probe |
            RawZ3Goal | RawZ3Tactic | RawZ3ApplyResult |
            RawZ3Params | RawZ3ParserContext |
            RawZ3FuncInterp | RawZ3FuncEntry |
            RawZ3ParamDescrs): bool {.inline.} =
  ## Nil check for opaque value types. The `bycopy` emission doesn't
  ## expose the underlying pointer for standard `isNil` to bind to;
  ## reinterpret-cast through `pointer` for a single-instruction check.
  cast[pointer](x) == nil

# Identity-equality for opaque value types. Without these, Nim's
# default `==` compares the empty-from-Nim's-POV `bycopy` structs
# field-by-field — and since they expose no fields, all instances
# compare equal regardless of the underlying C pointer. That breaks
# the `=copy` short-circuit (`if dst.raw != src.raw`) and was the
# cause of a real refcount bug surfaced by step 4-5 testing.
proc `==`*[T: RawZ3Config | RawZ3Context | RawZ3Sort | RawZ3Ast | RawZ3App |
          RawZ3Symbol | RawZ3Solver | RawZ3Model | RawZ3FuncDecl |
          RawZ3AstVector | RawZ3Constructor | RawZ3ConstructorList |
          RawZ3Pattern | RawZ3Optimize | RawZ3Fixedpoint | RawZ3Stats |
          RawZ3Probe |
          RawZ3Goal | RawZ3Tactic | RawZ3ApplyResult | RawZ3Params |
          RawZ3ParserContext |
          RawZ3FuncInterp | RawZ3FuncEntry | RawZ3ParamDescrs](
    a, b: T): bool {.inline.} =
  cast[pointer](a) == cast[pointer](b)

proc `!=`*[T: RawZ3Config | RawZ3Context | RawZ3Sort | RawZ3Ast | RawZ3App |
          RawZ3Symbol | RawZ3Solver | RawZ3Model | RawZ3FuncDecl |
          RawZ3AstVector | RawZ3Constructor | RawZ3ConstructorList |
          RawZ3Pattern | RawZ3Optimize | RawZ3Fixedpoint | RawZ3Stats |
          RawZ3Probe |
          RawZ3Goal | RawZ3Tactic | RawZ3ApplyResult | RawZ3Params |
          RawZ3ParserContext |
          RawZ3FuncInterp | RawZ3FuncEntry | RawZ3ParamDescrs](
    a, b: T): bool {.inline.} =
  cast[pointer](a) != cast[pointer](b)

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

  # --- Pretty printing -----------------------------------------------------

  proc Z3_ast_to_string(c: RawZ3Context, a: RawZ3Ast): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_model_to_string(c: RawZ3Context, m: RawZ3Model): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_solver_to_string(c: RawZ3Context, s: RawZ3Solver): cstring
    {.cdecl, header: "z3.h".}

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
  proc Z3_mk_str_to_int(c: RawZ3Context, s: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}
  proc Z3_mk_int_to_str(c: RawZ3Context, s: RawZ3Ast): RawZ3Ast
    {.cdecl, header: "z3.h".}

  # --- FloatingPoint (v0.3 step 6) -----------------------------------------
  #
  # IEEE 754 / SMT-LIB FP theory. Sort builders, rounding modes,
  # literals, arithmetic, comparisons, predicates, conversions.

  proc Z3_mk_fpa_sort(c: RawZ3Context, ebits, sbits: cuint): RawZ3Sort
    {.cdecl, header: "z3.h".}
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

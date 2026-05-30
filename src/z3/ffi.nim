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
  RawZ3Goal* {.importc: "Z3_goal", header: "z3.h", bycopy.} = object
    ## Conjunction of formulas a tactic operates on. Refcounted.
  RawZ3Tactic* {.importc: "Z3_tactic", header: "z3.h", bycopy.} = object
    ## Strategy combinator that rewrites goals.
  RawZ3ApplyResult* {.importc: "Z3_apply_result", header: "z3.h", bycopy.} = object
    ## Output of a tactic — N sub-goals plus model/proof conversion
    ## metadata.
  RawZ3Params* {.importc: "Z3_params", header: "z3.h", bycopy.} = object
    ## Typed parameter bag for tactics / solvers / optimisers.

proc isNil*(x: RawZ3Config | RawZ3Context | RawZ3Sort | RawZ3Ast | RawZ3App |
            RawZ3Symbol | RawZ3Solver | RawZ3Model | RawZ3FuncDecl |
            RawZ3AstVector | RawZ3Constructor | RawZ3ConstructorList |
            RawZ3Pattern | RawZ3Optimize |
            RawZ3Goal | RawZ3Tactic | RawZ3ApplyResult |
            RawZ3Params): bool {.inline.} =
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
          RawZ3Pattern | RawZ3Optimize |
          RawZ3Goal | RawZ3Tactic | RawZ3ApplyResult | RawZ3Params](
    a, b: T): bool {.inline.} =
  cast[pointer](a) == cast[pointer](b)

proc `!=`*[T: RawZ3Config | RawZ3Context | RawZ3Sort | RawZ3Ast | RawZ3App |
          RawZ3Symbol | RawZ3Solver | RawZ3Model | RawZ3FuncDecl |
          RawZ3AstVector | RawZ3Constructor | RawZ3ConstructorList |
          RawZ3Pattern | RawZ3Optimize |
          RawZ3Goal | RawZ3Tactic | RawZ3ApplyResult | RawZ3Params](
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
  proc Z3_solver_assert(c: RawZ3Context, s: RawZ3Solver, a: RawZ3Ast)
    {.cdecl, header: "z3.h".}
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

  # --- ast_vector accessors ------------------------------------------------

  proc Z3_ast_vector_inc_ref(c: RawZ3Context, v: RawZ3AstVector)
    {.cdecl, header: "z3.h".}
  proc Z3_ast_vector_dec_ref(c: RawZ3Context, v: RawZ3AstVector)
    {.cdecl, header: "z3.h".}
  proc Z3_ast_vector_size(c: RawZ3Context, v: RawZ3AstVector): cuint
    {.cdecl, header: "z3.h".}
  proc Z3_ast_vector_get(c: RawZ3Context, v: RawZ3AstVector, i: cuint): RawZ3Ast
    {.cdecl, header: "z3.h".}

  # --- Pretty printing -----------------------------------------------------

  proc Z3_ast_to_string(c: RawZ3Context, a: RawZ3Ast): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_model_to_string(c: RawZ3Context, m: RawZ3Model): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_solver_to_string(c: RawZ3Context, s: RawZ3Solver): cstring
    {.cdecl, header: "z3.h".}

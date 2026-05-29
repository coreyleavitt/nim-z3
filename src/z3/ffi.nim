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

proc isNil*(x: RawZ3Config | RawZ3Context | RawZ3Sort | RawZ3Ast | RawZ3App |
            RawZ3Symbol | RawZ3Solver | RawZ3Model | RawZ3FuncDecl): bool {.inline.} =
  ## Nil check for opaque value types. The `bycopy` emission doesn't
  ## expose the underlying pointer for standard `isNil` to bind to;
  ## reinterpret-cast through `pointer` for a single-instruction check.
  cast[pointer](x) == nil

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

  # --- Pretty printing -----------------------------------------------------

  proc Z3_ast_to_string(c: RawZ3Context, a: RawZ3Ast): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_model_to_string(c: RawZ3Context, m: RawZ3Model): cstring
    {.cdecl, header: "z3.h".}
  proc Z3_solver_to_string(c: RawZ3Context, s: RawZ3Solver): cstring
    {.cdecl, header: "z3.h".}

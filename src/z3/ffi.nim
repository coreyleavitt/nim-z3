## Raw FFI layer — softlink `dynlib` block declaring Z3's C API.
##
## **Internal module.** Consumers should not import this directly; the
## idiomatic Nim layer (`z3/context`, `z3/sort`, `z3/ast`, `z3/solver`,
## `z3/model`) exposes the public surface.
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

# ----------------------------------------------------------------------------
# Opaque Z3 types — `typedef struct _Z3_X * Z3_X;` in C
# ----------------------------------------------------------------------------

type
  RawZ3Config*   {.importc: "Z3_config",   header: "z3.h", bycopy.} = object
  RawZ3Context*  {.importc: "Z3_context",  header: "z3.h", bycopy.} = object
  RawZ3Sort*     {.importc: "Z3_sort",     header: "z3.h", bycopy.} = object
  RawZ3Ast*      {.importc: "Z3_ast",      header: "z3.h", bycopy.} = object
  RawZ3App*      {.importc: "Z3_app",      header: "z3.h", bycopy.} = object
  RawZ3Symbol*   {.importc: "Z3_symbol",   header: "z3.h", bycopy.} = object
  RawZ3Solver*   {.importc: "Z3_solver",   header: "z3.h", bycopy.} = object
  RawZ3Model*    {.importc: "Z3_model",    header: "z3.h", bycopy.} = object
  RawZ3FuncDecl* {.importc: "Z3_func_decl", header: "z3.h", bycopy.} = object

proc isNil*(x: RawZ3Config | RawZ3Context | RawZ3Sort | RawZ3Ast | RawZ3App |
            RawZ3Symbol | RawZ3Solver | RawZ3Model | RawZ3FuncDecl): bool {.inline.} =
  ## Nil check for opaque value types. The `bycopy` emission doesn't
  ## expose the underlying pointer for standard `isNil` to bind to;
  ## reinterpret-cast through `pointer` for a single-instruction check.
  cast[pointer](x) == nil

# ----------------------------------------------------------------------------
# Z3 enums — must be importc with `size: sizeof(cint)` for ABI compat
# ----------------------------------------------------------------------------

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

# ----------------------------------------------------------------------------
# Z3 FFI declarations
# ----------------------------------------------------------------------------
#
# v0.0.1 surface: just enough to verify the wrapper loads and the
# version is reachable. Subsequent commits will expand this to the
# full v0.1 surface per IMPLEMENTATION_PLAN.md §11.

dynlib "libz3.so(.4|.4.13|.4.12|.4.11|.4.10|)":
  proc Z3_get_full_version(): cstring {.cdecl, header: "z3.h".}

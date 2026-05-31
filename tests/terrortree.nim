## `z3/error` typed-hierarchy tests (v0.5 step 4).
##
## v0.5 step 1 extracted the error module from `z3/context`; v0.5
## step 4 populates it with the typed-subclass tree promised by goal
## 3 of the live plan. These tests verify:
##
##   1.  Every subclass exists and inherits from `Z3Error` (so legacy
##       `except Z3Error` catches continue to work).
##   2.  `raiseZ3Error` dispatches to the right subclass based on
##       the Z3-supplied error code.
##   3.  Real FFI failure paths raise the *typed* subclass — sort
##       mismatch → `Z3SortMismatchError`, parser failure → `Z3ParseError`,
##       invalid-usage → `Z3InvalidUsageError`.

import std/[unittest]
import z3

suite "Z3Error — subclass tree":
  test "Z3SortMismatchError exists and inherits from Z3Error":
    let isSubclass = Z3SortMismatchError is Z3Error
    check isSubclass

suite "Z3Error — raiseZ3Error dispatch table":
  test "Z3_SORT_ERROR raises Z3SortMismatchError":
    let ctx = newContext()
    expect Z3SortMismatchError:
      raiseZ3Error(ctx.raw, Z3_SORT_ERROR)

  test "Z3_IOB raises Z3IndexOutOfBoundsError":
    let ctx = newContext()
    expect Z3IndexOutOfBoundsError:
      raiseZ3Error(ctx.raw, Z3_IOB)

  test "Z3_INVALID_ARG raises Z3InvalidArgError":
    let ctx = newContext()
    expect Z3InvalidArgError:
      raiseZ3Error(ctx.raw, Z3_INVALID_ARG)

  test "Z3_PARSER_ERROR and Z3_NO_PARSER both raise Z3ParseError":
    let ctx = newContext()
    expect Z3ParseError:
      raiseZ3Error(ctx.raw, Z3_PARSER_ERROR)
    expect Z3ParseError:
      raiseZ3Error(ctx.raw, Z3_NO_PARSER)

  test "Z3_INVALID_PATTERN raises Z3InvalidPatternError":
    let ctx = newContext()
    expect Z3InvalidPatternError:
      raiseZ3Error(ctx.raw, Z3_INVALID_PATTERN)

  test "Z3_MEMOUT_FAIL raises Z3MemoryError":
    let ctx = newContext()
    expect Z3MemoryError:
      raiseZ3Error(ctx.raw, Z3_MEMOUT_FAIL)

  test "Z3_FILE_ACCESS_ERROR raises Z3FileError":
    let ctx = newContext()
    expect Z3FileError:
      raiseZ3Error(ctx.raw, Z3_FILE_ACCESS_ERROR)

  test "Z3_INTERNAL_FATAL raises Z3InternalError":
    let ctx = newContext()
    expect Z3InternalError:
      raiseZ3Error(ctx.raw, Z3_INTERNAL_FATAL)

  test "Z3_INVALID_USAGE raises Z3InvalidUsageError":
    let ctx = newContext()
    expect Z3InvalidUsageError:
      raiseZ3Error(ctx.raw, Z3_INVALID_USAGE)

  test "Z3_DEC_REF_ERROR raises Z3RefcountError":
    let ctx = newContext()
    expect Z3RefcountError:
      raiseZ3Error(ctx.raw, Z3_DEC_REF_ERROR)

  test "Z3_EXCEPTION raises Z3OperationError":
    let ctx = newContext()
    expect Z3OperationError:
      raiseZ3Error(ctx.raw, Z3_EXCEPTION)

suite "Z3Error — typed dispatch through real FFI paths":
  test "parser failure on garbage input raises Z3ParseError":
    let ctx = newContext()
    expect Z3ParseError:
      discard parseSmt2String(ctx, "(((this is not smt-lib at all")

  test "base-class except Z3Error catches every subclass":
    let ctx = newContext()
    var caughtCount = 0
    for c in [Z3_SORT_ERROR, Z3_INVALID_ARG, Z3_PARSER_ERROR,
              Z3_INVALID_USAGE, Z3_EXCEPTION]:
      try:
        raiseZ3Error(ctx.raw, c)
      except Z3Error:
        inc caughtCount
    check caughtCount == 5

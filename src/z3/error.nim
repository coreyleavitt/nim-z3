## `z3/error` — Z3 error type + `checkErr` discipline.
##
## **v0.5 step 1.** Extracted from `z3/context` so the wrapper's
## error-handling concern (`Z3Error` + `checkErr` + `raiseZ3Error`)
## lives as a peer module rather than tangled with the context
## handle, threadvar, and library bootstrap.
##
## See [docs/GOTCHAS.md §6](../docs/GOTCHAS.md#6-typed-error-hierarchy-catch-the-specific-subclass-not-just-z3error)
## for the user-facing guide on which subclass to catch when.
##
## ## Layering
##
## `z3/error` depends only on `z3/ffi` (for `Z3ErrorCode` + the raw
## error-query procs). It does **not** import `z3/context` — `Z3Error`
## is the lower layer. This inverts the v0.1–v0.4 arrangement in
## which context defined errors: cross-cutting modules import
## `z3/error` for the discipline; `z3/context` itself imports
## `z3/error` to raise from `requireCurrentContext`.
##
## ## API shape
##
## - `Z3Error` exception type — carries the typed `Z3ErrorCode` plus
##   the Z3-supplied diagnostic message.
## - `raiseZ3Error(rawCtx, code)` — takes the **raw** context handle
##   (not `Z3Context`), so the layering stays one-directional.
##   Callers with a `Z3Context` pass `ctx.raw`.
## - `checkErr(ctx, callExpr)` — template, accepts `ctx` as
##   `untyped`. Dot-access (`ctx.raw`) is resolved at expansion time,
##   so the template doesn't need `Z3Context` visible at definition
##   site.
## - `checkErrVoid(ctx, callExpr)` — void-returning peer.
##
## In v0.5 step 4 this module gains the typed-subclass tree
## (`Z3SortError`, `Z3InvalidUsageError`, `Z3ParserError`, …);
## `raiseZ3Error` dispatches on `code` to the right subclass at
## that point.

import ./ffi

export Z3ErrorCode  # enum values are re-exported transitively with the type

type
  Z3Error* = object of CatchableError
    ## Abstract base for every Z3-originated error. Raised by
    ## `checkErr` when an FFI call sets an error code other than
    ## `Z3_OK`. `code` carries the typed `Z3ErrorCode`; `msg` is the
    ## human-readable diagnostic Z3 provides for that code. The
    ## concrete type is one of the subclasses below.
    code*: Z3ErrorCode
      ## The Z3-supplied error code. Redundant with the subclass
      ## type post-step-4 but the field stays for callers that want
      ## the raw enum (for `case`-dispatch in exception handlers).

  # --- subclass tree (v0.5 step 4) ---------------------------------------
  # Each subclass corresponds to one `Z3ErrorCode` (or, for parser, a
  # pair). Catch the specific subclass when your code can recover
  # from that kind; catch the base `Z3Error` when you want any Z3
  # error.

  Z3SortMismatchError* = object of Z3Error
    ## `Z3_SORT_ERROR` — sort mismatch in an FFI call (e.g. asking
    ## for the bit-vector width of an `Int` sort, mixing sorts in
    ## an operator that requires same-sort args). The wrapper's
    ## phantom-typed API catches most of these at Nim compile time;
    ## this raises when a runtime-erased path (`Z3AnyAst` lift,
    ## `Z3_get_sort_kind` mismatch, parser sort-check failure)
    ## reaches the FFI.
    ##
    ## **Naming note:** the FFI enum value is `Z3_SORT_ERROR`; per
    ## Nim's style-insensitive identifier rules `Z3SortError` and
    ## `Z3_SORT_ERROR` are the same identifier. The subclass name
    ## adds "Mismatch" to disambiguate; the semantics match the
    ## C-side name exactly.

  Z3IndexOutOfBoundsError* = object of Z3Error
    ## `Z3_IOB` — index out of bounds. Distinct from generic
    ## `Z3InvalidArgError` because index-shaped argument errors are
    ## frequent enough to deserve their own handler (`expect
    ## Z3IndexOutOfBoundsError` reads naturally on per-index ops).

  Z3InvalidArgError* = object of Z3Error
    ## `Z3_INVALID_ARG` — a specific argument failed Z3's validation
    ## (wrong shape, out-of-range value, null where non-null
    ## expected). Catch for "this input is bad" recovery.

  Z3ParseError* = object of Z3Error
    ## `Z3_PARSER_ERROR` (input rejected) or `Z3_NO_PARSER` (no
    ## parser output available — caller queried for parsed assertions
    ## without parsing first). Both are SMT-LIB-input-shaped failures,
    ## bundled together because callers handling one almost always
    ## want to handle the other identically.
    ##
    ## **Naming note:** the FFI enum value is `Z3_PARSER_ERROR`; per
    ## Nim's style-insensitive identifier rules `Z3ParserError` and
    ## `Z3_PARSER_ERROR` are the same identifier. The subclass drops
    ## the "r" to disambiguate (`Z3ParseError`); the semantics match
    ## the C-side name exactly.

  Z3InvalidPatternError* = object of Z3Error
    ## `Z3_INVALID_PATTERN` — quantifier trigger pattern doesn't
    ## match the body's free-variable shape. Catchable: pattern
    ## construction is something users sometimes get wrong.

  Z3MemoryError* = object of Z3Error
    ## `Z3_MEMOUT_FAIL` — Z3 ran out of memory mid-decision. Catch
    ## for retry-with-smaller-goal or timeout-graceful-degrade.

  Z3FileError* = object of Z3Error
    ## `Z3_FILE_ACCESS_ERROR` — file I/O failed (e.g. `parseSmt2File`
    ## couldn't open the path). Catchable like any `IOError`-shaped
    ## condition.

  Z3InternalError* = object of Z3Error
    ## `Z3_INTERNAL_FATAL` — Z3 itself hit an internal invariant
    ## violation. Almost certainly NOT user-caused; the right
    ## response is "log and re-raise" unless you're explicitly
    ## isolating Z3 in a subprocess.

  Z3InvalidUsageError* = object of Z3Error
    ## `Z3_INVALID_USAGE` — operation called in an invalid state
    ## (e.g. `getModel` before a `sat` `check()`, FFI op on a
    ## destroyed handle). Most user-caused errors land here; catch
    ## when the workflow's state is unclear.

  Z3RefcountError* = object of Z3Error
    ## `Z3_DEC_REF_ERROR` — refcount discipline violated (a handle
    ## was decremented past zero). Should never happen if the
    ## wrapper's lifecycle templates are correct; if it fires, file
    ## a bug. Subclass exists so the diagnostic is self-explanatory.

  Z3OperationError* = object of Z3Error
    ## `Z3_EXCEPTION` — generic Z3 exception (the C-side catch-all
    ## for "something went wrong but not in the more specific
    ## categories"). The diagnostic message is your only signal.

  Z3UnknownError* = object of Z3Error
    ## Z3 emitted an error code our `Z3ErrorCode` enum doesn't
    ## recognise. Imported-enum out-of-range fallback. Forward-
    ## compatible: a new Z3 version adding a code lands here until
    ## the wrapper is updated.

template raiseSubclass(SubT: untyped, fullMsg: string,
                       errCode: Z3ErrorCode) =
  ## Helper: raise a fully-initialised exception of subclass `SubT`
  ## with the `code` field set. Used inside `raiseZ3Error`'s
  ## case-dispatch so each arm is one expression.
  var e = newException(SubT, fullMsg)
  e.code = errCode
  raise e

proc raiseZ3Error*(rawCtx: RawZ3Context, code: Z3ErrorCode) {.noreturn.} =
  ## Raise the typed `Z3Error` subclass corresponding to `code`,
  ## with the Z3-supplied diagnostic message from `rawCtx`. Called
  ## by `checkErr` when an FFI call sets a non-OK error. Takes the
  ## raw handle rather than the typed `Z3Context` so this module
  ## stays at a lower layer than `z3/context`; callers with a typed
  ## handle pass `ctx.raw`.
  ##
  ## Dispatch table:
  ##
  ## | `code`                  | subclass                  |
  ## |-------------------------|---------------------------|
  ## | `Z3_SORT_ERROR`         | `Z3SortMismatchError`     |
  ## | `Z3_IOB`                | `Z3IndexOutOfBoundsError` |
  ## | `Z3_INVALID_ARG`        | `Z3InvalidArgError`       |
  ## | `Z3_PARSER_ERROR`       | `Z3ParseError`            |
  ## | `Z3_NO_PARSER`          | `Z3ParseError`            |
  ## | `Z3_INVALID_PATTERN`    | `Z3InvalidPatternError`   |
  ## | `Z3_MEMOUT_FAIL`        | `Z3MemoryError`           |
  ## | `Z3_FILE_ACCESS_ERROR`  | `Z3FileError`             |
  ## | `Z3_INTERNAL_FATAL`     | `Z3InternalError`         |
  ## | `Z3_INVALID_USAGE`      | `Z3InvalidUsageError`     |
  ## | `Z3_DEC_REF_ERROR`      | `Z3RefcountError`         |
  ## | `Z3_EXCEPTION`          | `Z3OperationError`        |
  ## | unrecognised            | `Z3UnknownError`          |
  ##
  ## `Z3_OK` is not a real error code; if `raiseZ3Error` is called
  ## with `Z3_OK` (a wrapper bug) it falls through to
  ## `Z3UnknownError`.
  let msg = $Z3_get_error_msg(rawCtx, code)
  let fullMsg = "Z3 " & $code & ": " & msg
  case code
  of Z3_SORT_ERROR:        raiseSubclass(Z3SortMismatchError,     fullMsg, code)
  of Z3_IOB:               raiseSubclass(Z3IndexOutOfBoundsError, fullMsg, code)
  of Z3_INVALID_ARG:       raiseSubclass(Z3InvalidArgError,       fullMsg, code)
  of Z3_PARSER_ERROR:      raiseSubclass(Z3ParseError,            fullMsg, code)
  of Z3_NO_PARSER:         raiseSubclass(Z3ParseError,            fullMsg, code)
  of Z3_INVALID_PATTERN:   raiseSubclass(Z3InvalidPatternError,   fullMsg, code)
  of Z3_MEMOUT_FAIL:       raiseSubclass(Z3MemoryError,           fullMsg, code)
  of Z3_FILE_ACCESS_ERROR: raiseSubclass(Z3FileError,             fullMsg, code)
  of Z3_INTERNAL_FATAL:    raiseSubclass(Z3InternalError,         fullMsg, code)
  of Z3_INVALID_USAGE:     raiseSubclass(Z3InvalidUsageError,     fullMsg, code)
  of Z3_DEC_REF_ERROR:     raiseSubclass(Z3RefcountError,         fullMsg, code)
  of Z3_EXCEPTION:         raiseSubclass(Z3OperationError,        fullMsg, code)
  else:                    raiseSubclass(Z3UnknownError,          fullMsg, code)

template checkErr*(ctx: untyped, callExpr: untyped): untyped =
  ## Wrap an FFI call: evaluate `callExpr`, query the context's error
  ## code, raise `Z3Error` if non-OK, otherwise yield the call's result.
  ##
  ## Usage in builders:
  ##
  ## ```nim
  ## let raw = ctx.checkErr Z3_mk_add(ctx.raw, 2, addr args[0])
  ## ```
  ##
  ## `ctx` is `untyped` so the template body resolves `ctx.raw` at
  ## expansion time — this lets `z3/error` live below `z3/context`
  ## without forward-declaring the `Z3Context` type. The call site
  ## must supply a value whose `.raw` is a `RawZ3Context`.
  ##
  ## Template (not proc) so the call site, not this body, appears in
  ## stack traces — Z3 errors point at the user's code, not deep into
  ## an FFI wrapper.
  let res = callExpr
  let err = Z3_get_error_code(ctx.raw)
  if err != Z3_OK:
    raiseZ3Error(ctx.raw, err)
  res

template checkErrVoid*(ctx: untyped, callExpr: untyped): untyped =
  ## Void-returning peer of `checkErr` — same error-discipline, no
  ## result. Use for FFI procs whose return type is `void`
  ## (`Z3_solver_assert`, `Z3_solver_push`, `Z3_solver_pop`, …).
  callExpr
  let err = Z3_get_error_code(ctx.raw)
  if err != Z3_OK:
    raiseZ3Error(ctx.raw, err)

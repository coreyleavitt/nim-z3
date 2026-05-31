## `z3/error` — Z3 error type + `checkErr` discipline.
##
## **v0.5 step 1.** Extracted from `z3/context` so the wrapper's
## error-handling concern (`Z3Error` + `checkErr` + `raiseZ3Error`)
## lives as a peer module rather than tangled with the context
## handle, threadvar, and library bootstrap.
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
    ## Raised when a Z3 FFI call sets an error code other than `Z3_OK`.
    ## `code` carries the typed `Z3ErrorCode`; `msg` is the
    ## human-readable diagnostic Z3 provides for that code.
    code*: Z3ErrorCode
      ## The Z3-supplied error code; useful for `case`-dispatch in
      ## exception handlers. In v0.5 step 4 this becomes redundant
      ## with the subclass type, but the field stays for callers
      ## that want the raw enum.

proc raiseZ3Error*(rawCtx: RawZ3Context, code: Z3ErrorCode) {.noreturn.} =
  ## Raise `Z3Error` with the Z3-supplied diagnostic for `code` against
  ## the raw context `rawCtx`. Called by `checkErr` when an FFI call
  ## sets a non-OK error. Takes the raw handle rather than the typed
  ## `Z3Context` so this module stays at a lower layer than
  ## `z3/context`; callers with a typed handle pass `ctx.raw`.
  let msg = $Z3_get_error_msg(rawCtx, code)
  var e = newException(Z3Error, "Z3 " & $code & ": " & msg)
  e.code = code
  raise e

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

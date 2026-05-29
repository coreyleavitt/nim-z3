## `Z3Context` — lifecycle wrapper around Z3's reference-counted
## context plus the error-handling discipline that wraps every FFI call.
##
## ## Two contexts of "context"
##
## Z3 uses *context* for a heavyweight per-session state object that owns
## sorts, ASTs, solvers, and models. We mirror that with `Z3Context` (a
## `ref Z3ContextOwn` whose `=destroy` calls `Z3_del_context`).
##
## Separately, this module maintains a per-thread *current context* — a
## `{.threadvar.}` slot set by `newContext()` and queryable via
## `currentContext()`. Idiomatic builders downstream (e.g. `mkIntVar(name)`)
## resolve against `currentContext()` when no explicit context is supplied.
## This is the same pattern Python's `z3` library popularized for ergonomic
## use; the explicit-context API stays available for users who want it
## (each builder also accepts a `ctx: Z3Context` form via UFCS:
## `ctx.mkIntVar("x")`).
##
## Multi-threaded use composes naturally because `currentContext()` is
## per-thread. `withContext(ctx): body` temporarily swaps the current
## context for the duration of `body` (and restores the prior context on
## exit) for scoped/library-internal use that needs an explicit context
## without disturbing the caller's current setting.
##
## ## Error handling discipline
##
## Z3's default error handler aborts the process on any API error. That's
## fatal for Nim — we can't catch `Z3_abort`. So `newContext` installs a
## no-op handler that just leaves the error code in the context. The
## `checkErr` template (used internally by every idiomatic builder)
## queries the error code after each FFI call and raises a `Z3Error`
## with both the code (as a typed `Z3ErrorCode` enum) and Z3's
## human-readable message.
##
## Users should rarely interact with `Z3Error` directly; most failures
## indicate a library bug we should fix. Specific codes worth catching:
##
## - `Z3_INVALID_USAGE` — a misuse pattern Z3 detected.
## - `Z3_MEMOUT_FAIL` — out of memory during solving.

import ./ffi
import softlink

# ============================================================================
# Z3Context — ref-typed lifecycle wrapper
# ============================================================================

type
  Z3ContextOwn = object
    raw: RawZ3Context
    cfg: RawZ3Config
  Z3Context* = ref Z3ContextOwn
    ## Heap-allocated, ref-counted by Nim's ORC. Held alive by anyone
    ## who needs the underlying Z3 context (ASTs, solvers, models).
    ## `=destroy` fires only when the last reference drops, at which
    ## point both the Z3 context and its config are freed.

  Z3Error* = object of CatchableError
    ## Raised when a Z3 FFI call sets an error code other than `Z3_OK`.
    ## `code` carries the typed `Z3ErrorCode`; `msg` is the
    ## human-readable diagnostic Z3 provides for that code.
    code*: Z3ErrorCode

# --- error handler installed at context creation ----------------------------

proc nimNoopErrorHandler(c: RawZ3Context, e: Z3ErrorCode) {.cdecl.} =
  ## Replaces Z3's default `abort()` handler. Doing nothing here lets
  ## the error code stay in the context for `checkErr` to inspect
  ## after the offending FFI call returns. Z3 has already set the
  ## code internally before invoking this callback.
  discard

# --- =destroy hook on the underlying object type ----------------------------
#
# Nim 2's hook signatures require the underlying object type, not the
# ref alias. {.raises: [].} + try/except CatchableError: discard because
# softlink-wrapped procs can raise SoftlinkError (e.g. if libz3 was
# unloaded mid-program); =destroy can't propagate exceptions.

proc `=destroy`(c: Z3ContextOwn) {.raises: [].} =
  try:
    if not c.raw.isNil: Z3_del_context(c.raw)
    if not c.cfg.isNil: Z3_del_config(c.cfg)
  except CatchableError:
    discard

# ============================================================================
# Current-context threadvar
# ============================================================================

var currentZ3Ctx {.threadvar.}: Z3Context

proc currentContext*(): Z3Context =
  ## The current context for this thread, or `nil` if none is set.
  ## Idiomatic builders called without an explicit context resolve
  ## against this. `newContext()` sets the current context on creation;
  ## `withContext` swaps it temporarily.
  currentZ3Ctx

proc setCurrentContext*(ctx: Z3Context) =
  ## Manually replace the current context. Most users shouldn't need
  ## this — `newContext` and `withContext` handle the common cases —
  ## but it's exposed for advanced uses (e.g. installing a shared
  ## context that survives `withContext` blocks).
  currentZ3Ctx = ctx

proc requireCurrentContext*(): Z3Context =
  ## `currentContext()` with a clear failure mode for builders that
  ## can't function without one. Raises `Z3Error` with a message
  ## explaining how to fix it.
  let c = currentZ3Ctx
  if c == nil:
    var e = newException(Z3Error,
      "no current Z3 context; call `newContext()` once before using " &
      "context-less builders, or pass an explicit context as the first " &
      "argument (e.g. `ctx.mkIntVar(\"x\")` instead of `mkIntVar(\"x\")`)")
    e.code = Z3_INVALID_USAGE
    raise e
  c

# ============================================================================
# Construction
# ============================================================================

type LibZ3UnavailableError* = object of Defect
  ## Raised by `newContext` when the system's `libz3.so` couldn't be
  ## loaded (not installed, wrong version pattern, permission issues).
  ## Inherits from `Defect` because this is an environmental
  ## misconfiguration — recovery isn't useful at the call site; the
  ## right fix is to install libz3 and rerun. The error message
  ## carries softlink's `LoadResult.kind` so the caller can distinguish
  ## "not installed" from "missing required symbol" (i.e. libz3 too
  ## old for the symbols we declared).

proc ensureLoaded() =
  ## Idempotent first-call hook that loads libz3 via softlink. Called
  ## by `newContext`; users don't normally need to invoke this
  ## directly, but it's idempotent and cheap so calling extra times
  ## is harmless.
  if z3Loaded(): return
  let r = loadZ3()
  case r.kind
  of lrOk, lrOkPartial:
    discard
  of lrLibNotFound:
    raise newException(LibZ3UnavailableError,
      "libz3 not found on system. Install libz3-dev (Debian/Ubuntu), " &
      "z3 (Homebrew/Arch), or copy libz3.so.4 from the Z3 GitHub releases " &
      "into the loader path.")
  of lrSymbolNotFound:
    raise newException(LibZ3UnavailableError,
      "libz3 loaded but a required symbol is missing (likely too-old Z3 " &
      "version): " & r.symbol & ". nim-z3 supports Z3 4.10+; upgrade your " &
      "libz3 install.")

proc newContext*(params: varargs[(string, string)]): Z3Context =
  ## Allocate a fresh Z3 context. Auto-loads libz3 on first call; no
  ## need to invoke `loadZ3()` separately. Optional `params` are
  ## key/value pairs passed to `Z3_set_param_value` before the context
  ## is constructed — examples:
  ##
  ## ```nim
  ## let ctx = newContext()
  ## let ctx = newContext(("model", "true"))
  ## let ctx = newContext(("model", "true"), ("proof", "true"))
  ## ```
  ##
  ## The complete list of recognized parameters lives at
  ## https://microsoft.github.io/z3guide/programming/Parameters/ .
  ## Most users want the defaults.
  ##
  ## On construction the new context becomes this thread's current
  ## context (overwriting whatever was there). To avoid that, save
  ## and restore yourself:
  ##
  ## ```nim
  ## let prev = currentContext()
  ## let ctx = newContext(...)
  ## setCurrentContext(prev)
  ## ```
  ensureLoaded()
  let cfg = Z3_mk_config()
  for (k, v) in params:
    Z3_set_param_value(cfg, k.cstring, v.cstring)
  let raw = Z3_mk_context_rc(cfg)
  # Replace Z3's default abort-on-error handler so error codes can
  # be inspected after each call rather than terminating the process.
  Z3_set_error_handler(raw, nimNoopErrorHandler)
  result = Z3Context(raw: raw, cfg: cfg)
  currentZ3Ctx = result

template withContext*(ctx: Z3Context, body: untyped) =
  ## Temporarily install `ctx` as the current context for the duration
  ## of `body`; restore the prior current context on exit. Use this
  ## when a code region needs to operate against a specific context
  ## without disturbing the caller's setting:
  ##
  ## ```nim
  ## let scratch = newContext()
  ## withContext(scratch):
  ##   let p = mkBoolVar("p")
  ##   # ... transient work in `scratch` ...
  ## # current context is restored here, scratch is destroyed when
  ## # the last reference drops.
  ## ```
  ##
  ## The restore happens via `finally` so an exception thrown inside
  ## `body` still leaves the caller's current context intact.
  let prev = currentZ3Ctx
  currentZ3Ctx = ctx
  try:
    body
  finally:
    currentZ3Ctx = prev

# ============================================================================
# Raw-handle accessors (for the FFI-facing layer)
# ============================================================================

proc raw*(ctx: Z3Context): RawZ3Context {.inline.} =
  ## Underlying `RawZ3Context` handle. Used by other idiomatic modules
  ## that pass the raw handle to FFI calls. Returns a nil handle if
  ## the context has already been finalized — callers should check
  ## with `not ctx.raw.isNil` before passing to FFI.
  if ctx == nil: result else: ctx.raw

# ============================================================================
# Error handling
# ============================================================================

proc raiseZ3Error*(ctx: Z3Context, code: Z3ErrorCode) {.noreturn.} =
  ## Raise `Z3Error` with the Z3-supplied diagnostic for `code` against
  ## `ctx`. Called by `checkErr` when an FFI call sets a non-OK error.
  ## Public so user code can mirror our error-raising pattern in custom
  ## FFI wrappers.
  let msg = $Z3_get_error_msg(ctx.raw, code)
  var e = newException(Z3Error, "Z3 " & $code & ": " & msg)
  e.code = code
  raise e

template checkErr*(ctx: Z3Context, callExpr: untyped): untyped =
  ## Wrap an FFI call: evaluate `callExpr`, query the context's error
  ## code, raise `Z3Error` if non-OK, otherwise yield the call's result.
  ##
  ## Usage in builders:
  ##
  ## ```nim
  ## let raw = ctx.checkErr Z3_mk_add(ctx.raw, 2, addr args[0])
  ## ```
  ##
  ## Template so the call site (not this template body) appears in
  ## stack traces — Z3 errors point at the user's code, not deep into
  ## an FFI wrapper.
  let res = callExpr
  let err = Z3_get_error_code(ctx.raw)
  if err != Z3_OK:
    raiseZ3Error(ctx, err)
  res

# ============================================================================
# Version probes
# ============================================================================
#
# Loading libz3 lazily means we don't know what version we got until
# someone asks. These probes are the canonical way to ask. They're
# also the public-facing test points for the multi-version CI matrix:
# `tversion.nim` calls them across every Z3 release the matrix targets.

type Z3VersionInfo* = tuple[major, minor, build, revision: int]
  ## Component-wise libz3 version. All four fields come from
  ## `Z3_get_version`; revision is the upstream build-number field
  ## (effectively a tiebreaker for same-release nightlies).

proc z3Version*(): Z3VersionInfo =
  ## Component-wise version of the loaded libz3. Triggers `ensureLoaded`
  ## if the library hasn't been loaded yet, so calling it before any
  ## `newContext()` is fine — the typical first-call pattern.
  ##
  ## ```nim
  ## let v = z3Version()
  ## if v.major == 4 and v.minor < 11:
  ##   echo "warning: libz3 ", v, " missing some features used by lib X"
  ## ```
  ensureLoaded()
  var mj, mn, bd, rv: cuint
  Z3_get_version(addr mj, addr mn, addr bd, addr rv)
  (int(mj), int(mn), int(bd), int(rv))

proc z3FullVersion*(): string =
  ## Vendor-formatted version string, e.g. "4.13.3.0". Always equivalent
  ## to `$z3Version().major & "." & …` modulo whitespace, but the vendor
  ## string is the canonical wire form (it's what `z3 --version` prints).
  ensureLoaded()
  $Z3_get_full_version()

proc finalizeZ3Memory*() =
  ## Process-wide Z3 cleanup. Frees Z3's internal globals (hash-cons
  ## tables, allocator pools) that survive per-context destruction.
  ## Call from a single shutdown hook if you want sanitisers to report
  ## clean exit; safe to call multiple times. **No further Z3 API may
  ## be invoked from this process after this returns.**
  if z3Loaded():
    Z3_finalize_memory()

template checkErrVoid*(ctx: Z3Context, callExpr: untyped): untyped =
  ## Void-returning peer of `checkErr` — same error-discipline, no
  ## result. Use for FFI procs whose return type is `void`
  ## (`Z3_solver_assert`, `Z3_solver_push`, `Z3_solver_pop`, …).
  ## We could in principle dispatch on `typeof(callExpr) is void`
  ## inside `checkErr` itself, but `untyped` template parameters
  ## don't have a known type at template-expansion time; splitting
  ## into two templates keeps the dispatch obvious at the call site.
  callExpr
  let err = Z3_get_error_code(ctx.raw)
  if err != Z3_OK:
    raiseZ3Error(ctx, err)

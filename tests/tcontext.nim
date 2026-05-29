## `z3/context` tests — lifecycle, current-context discipline,
## error handler installation, `checkErr` semantics.

import std/[unittest, strutils]
import z3

suite "Z3Context — construction + lifecycle":
  test "newContext returns a non-nil handle":
    let ctx = newContext()
    check ctx != nil
    check not ctx.raw.isNil

  test "newContext with params sets configuration before context creation":
    let ctx = newContext(("model", "true"))
    check ctx != nil
    # Hard to introspect the config from outside the FFI; the smoke
    # is that construction succeeds and the context is usable.

  test "newContext with multiple params":
    let ctx = newContext(("model", "true"), ("proof", "false"))
    check ctx != nil

  test "two independent contexts coexist":
    let c1 = newContext()
    let c2 = newContext()
    check c1 != nil and c2 != nil
    check cast[pointer](c1.raw) != cast[pointer](c2.raw)

  test "context goes out of scope without crashing":
    block:
      let ctx = newContext()
      discard ctx
    # If =destroy doubled-freed, we'd see a crash here.
    check true

suite "current context — threadvar discipline":
  test "newContext installs as current":
    let ctx = newContext()
    check currentContext() == ctx

  test "second newContext replaces current":
    let c1 = newContext()
    let c2 = newContext()
    check currentContext() == c2
    check currentContext() != c1

  test "setCurrentContext changes current without creating":
    let c1 = newContext()
    let c2 = newContext()
    setCurrentContext(c1)
    check currentContext() == c1

  test "requireCurrentContext raises Z3Error when none is set":
    setCurrentContext(nil)
    expect Z3Error:
      discard requireCurrentContext()

  test "requireCurrentContext error carries Z3_INVALID_USAGE":
    setCurrentContext(nil)
    try:
      discard requireCurrentContext()
      check false   # unreachable
    except Z3Error as e:
      check e.code == Z3_INVALID_USAGE

suite "withContext — scoped current-context swap":
  test "withContext temporarily installs ctx":
    let outer = newContext()
    let inner = newContext()
    # `inner` is current after its newContext.
    setCurrentContext(outer)
    check currentContext() == outer
    withContext inner:
      check currentContext() == inner
    check currentContext() == outer

  test "withContext restores on exception":
    let outer = newContext()
    let inner = newContext()
    setCurrentContext(outer)
    try:
      withContext inner:
        raise newException(ValueError, "deliberate")
    except ValueError:
      discard
    check currentContext() == outer

suite "Z3Error + checkErr template":
  test "checkErr passes through when no error occurred":
    let ctx = newContext()
    # A simple FFI call that should succeed without setting an error
    # code. We use Z3_mk_int_sort because it's idempotent and well-
    # defined on any valid context.
    let sort = ctx.checkErr Z3_mk_int_sort(ctx.raw)
    check not sort.isNil

  test "Z3Error carries the typed error code":
    # Manually raise via the helper so we exercise the path the user
    # might see if they custom-wrap an FFI call.
    let ctx = newContext()
    try:
      raiseZ3Error(ctx, Z3_INVALID_ARG)
      check false
    except Z3Error as e:
      check e.code == Z3_INVALID_ARG
      check e.msg.len > 0
      # The message should include the Z3-side diagnostic, not just
      # the enum name; check for the human form.
      check "invalid" in e.msg.toLowerAscii

suite "error handler installation — no longjmp/abort":
  # The default Z3 error handler aborts the program. After newContext
  # installs our no-op handler, FFI calls that would have aborted
  # instead leave the error code in the context for checkErr to
  # detect. We can't easily exercise this without an FFI call we know
  # will error reliably across Z3 versions; the indirect proof is that
  # the rest of the test suite, which makes many FFI calls per context,
  # has never aborted.

  test "many successive FFI calls on one context don't abort":
    let ctx = newContext()
    for i in 0 ..< 100:
      let s = Z3_mk_int_sort(ctx.raw)
      check not s.isNil

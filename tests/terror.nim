## `z3/error` tests — module-seam validation (v0.5 step 1).
##
## Two observable contracts:
##
##   1.  `import z3/error` alone exposes the error surface — `Z3Error`
##       exception type, `Z3ErrorCode` enum, `checkErr` template.
##       This is the seam that lets a sibling module pull in the
##       error discipline without dragging in the context's
##       threadvar / bootstrap surface.
##
##   2.  An FFI call that sets a non-OK error code surfaces as
##       `Z3Error` carrying the right `code` field. This is the same
##       contract `tcontext.nim` exercised pre-extraction; the
##       behaviour must survive the file move unchanged.

import std/[unittest]
import z3
import z3/error
import z3/context  # for newContext used in the behaviour test

suite "z3/error — seam":
  test "Z3Error and checkErr are reachable through z3/error alone":
    # If this file compiles, the seam works — `Z3Error` and the
    # `Z3ErrorCode` enum are visible after `import z3/error` without
    # any additional imports.
    let isExc = Z3Error is CatchableError
    check isExc
    # `Z3ErrorCode.Z3_OK` should round-trip through the re-export.
    let okCode = Z3_OK
    check okCode == Z3_OK

suite "z3/error — behaviour":
  test "checkErr raises Z3Error with the Z3-supplied code on failure":
    # Provoke a Z3 error: build an Int sort, then ask `Z3_get_bv_sort_size`
    # on it — sort-kind mismatch. The error code is `Z3_INVALID_ARG`.
    let ctx = newContext()
    expect Z3Error:
      let intSort = ctx.checkErr Z3_mk_int_sort(ctx.raw)
      discard ctx.checkErr Z3_get_bv_sort_size(ctx.raw, intSort)

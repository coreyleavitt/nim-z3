## Smoke test for the FFI layer.
##
## v0.0.1 just verifies softlink loads libz3 and we can call one
## trivial function (`Z3_get_full_version`). As the FFI layer grows
## this file will too.

import std/[unittest, strutils]
import softlink
import z3

suite "z3/ffi — softlink loads libz3":
  test "loadZ3 returns lrOk on a system with libz3 installed":
    let r = loadZ3()
    check r.kind == lrOk

  test "z3Loaded reports true after a successful load":
    discard loadZ3()
    check z3Loaded()

suite "z3/ffi — basic symbol smoke":
  test "Z3_get_full_version returns a non-empty version string":
    discard loadZ3()
    let v = $z3.Z3_get_full_version()
    check v.len > 0
    # Z3 versions are dotted strings starting with the major version 4.
    # Don't pin to exact value — CI matrix may swing across point releases.
    check v.startsWith("4.")

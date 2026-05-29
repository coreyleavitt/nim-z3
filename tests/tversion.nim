## Multi-version probe — exercises Z3_get_version + Z3_get_full_version
## across whatever libz3 the test runner happens to have loaded. This
## test runs identically on every matrix row of the CI version matrix;
## the matrix's job is to vary libz3 underneath while this test stays
## fixed.
##
## We assert the *minimum supported version* (Z3 4.10) and validate
## the version-string format. Any matrix row whose libz3 advertises
## itself as below 4.10 or refuses to load the symbols at all fails
## here.

import std/[unittest, strutils]
import z3

suite "z3Version":
  test "z3Version() returns (major, minor, build, revision) with major == 4":
    let v = z3Version()
    check v.major == 4
    check v.minor >= 10
    # build / revision are vendor-controlled; we don't assert their
    # values, only that they're cuints (already enforced by the
    # return type).

  test "z3FullVersion() looks like a dotted-version string":
    let s = z3FullVersion()
    check s.len > 0
    check '.' in s
    let parts = s.split('.')
    check parts.len >= 3      # major.minor.build at minimum
    check parts[0] == "4"
    check parts[1].parseInt >= 10

  test "Z3_finalize_memory completes cleanly after context churn":
    # Allocate, exercise, and drop a context; Z3's own leak tally
    # comes from Z3_finalize_memory's internal accounting. We don't
    # have a programmatic "did it leak?" return value (Z3 only logs
    # to stderr if Z3_DEBUG is on), but the call must not crash.
    for _ in 0 ..< 3:
      let ctx = newContext()
      let s = newSolver()
      let x = mkIntVar("x")
      s.add x > 0
      discard s.check()
    finalizeZ3Memory()
    check true

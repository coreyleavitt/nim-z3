## Multi-version load smoke test — RFC-regex-index.md §6.3 slice 4.
##
## Exercises `loadZ3()` (implicitly, via context creation) against whatever
## Z3 runtime the harness mounts. On Z3 4.16 the symbol `Z3_mk_set_has_size`
## was removed; before the slice-4 fix that made the whole load fail
## (`LibZ3UnavailableError`). After the fix, a missing optional symbol
## degrades the load to `lrOkPartial`, which `context.nim` accepts, and this
## test — which never touches `set_has_size` — passes on both 4.15 and 4.16.
##
## Also proves the *drifted-signature* half of slice 4:
## `Z3_fpa_get_numeral_sign`'s out-param is `int*` through 4.15 and `bool*`
## from 4.16 (same name, both versions, incompatible ABI). It's declared
## `until: "4.16.0"` (the historical `int*` shape) + `optional`, so
## `z3Compat()` — softlink's generated report proc — must show it as
## `mrDriftRefused` on a 4.16 runtime, and absent from `missingReasons`
## (i.e. usable) on 4.15.
##
## **M2 (code review):** the committed `src/z3/z3.compat.json` manifest
## harvests the corpus {4.13.3, 4.13.4, 4.14.1, 4.15.0, 4.16.0}. Its whole
## CI-guard value is unrealized unless something actually asserts what it
## promises, so this file also pins:
##
##   - `attestation == atAttested` on every harness runtime (all three are
##     in the corpus above).
##   - `Z3_mk_set_has_size` (removed at 4.16) classifies as `mrExpected` +
##     unavailable on 4.16, and is available + absent from
##     `missingReasons` on <= 4.15.
##   - `Z3_mk_seq_replace_all` (added at 4.16) classifies as `mrExpected` +
##     unavailable below 4.16, and is available + absent from
##     `missingReasons` on 4.16. Checkable on the default (4.15) harness.
##   - `z3CompatWarnings()` is empty and `z3LoadIsHealthy()` is `true`
##     on a clean, attested load (the fpa `mrDriftRefused` entry on 4.16 is
##     expected-for-that-version, not a warning — see `z3/ffi.nim`'s
##     `z3LoadIsHealthy` docstring for the exact rule).

import std/[unittest, strutils]
import z3  # z3Compat() + the softlink compat types (MissingReason/mrDriftRefused,
          # CompatReport, Attestation) are re-exported through the umbrella

suite "multi-version load — 4.15 / 4.16":
  test "context creation + trivial sat check succeeds regardless of Z3 minor version":
    let ctx = newContext()
    check ctx != nil

    let x = mkIntVar("x")
    let s = newSolver()
    s.add x == mkInt(1)
    check s.check() == zsSat

  test "z3Compat() attests the runtime version and partitions the drifted fpa symbol correctly":
    discard newContext()  # triggers loadZ3() + the versionProbe, if not already loaded

    let report = z3Compat()
    check report.runtimeVersion.len > 0
    check report.runtimeVersion.startsWith("4.")

    var fpaSignDrifted = false
    for (symbol, reason, _) in report.missingReasons:
      if symbol == "Z3_fpa_get_numeral_sign":
        check reason == mrDriftRefused
        fpaSignDrifted = true

    if report.runtimeVersion.startsWith("4.16"):
      check fpaSignDrifted
      check not Z3_fpa_get_numeral_signAvailable()
    else:
      check not fpaSignDrifted
      check Z3_fpa_get_numeral_signAvailable()

  test "z3Compat() attestation is atAttested on the harness runtimes":
    ## The committed manifest's corpus is {4.13.3, 4.13.4, 4.14.1, 4.15.0,
    ## 4.16.0} — every harness runtime (default 4.15.0, Z3DIR=z3-latest
    ## 4.16.0, Z3DIR=z3 4.13.4) falls inside it, so the load must be
    ## attested rather than merely probed.
    discard newContext()
    let report = z3Compat()
    check report.attestation == atAttested

  test "Z3_mk_set_has_size classifies as mrExpected, removed at 4.16":
    discard newContext()
    let report = z3Compat()
    var listed = false
    for (symbol, reason, _) in report.missingReasons:
      if symbol == "Z3_mk_set_has_size":
        listed = true
        check reason == mrExpected

    if report.runtimeVersion.startsWith("4.16"):
      check listed
      check not Z3_mk_set_has_sizeAvailable()
    else:
      check not listed
      check Z3_mk_set_has_sizeAvailable()

  test "Z3_mk_seq_replace_all classifies as mrExpected, added at 4.16":
    ## Checkable on the default (4.15) harness: the symbol is absent below
    ## 4.16 and this branch covers 4.13.4/4.15.0 alike.
    discard newContext()
    let report = z3Compat()
    var listed = false
    for (symbol, reason, _) in report.missingReasons:
      if symbol == "Z3_mk_seq_replace_all":
        listed = true
        check reason == mrExpected

    if report.runtimeVersion.startsWith("4.16"):
      check not listed
      check Z3_mk_seq_replace_allAvailable()
    else:
      check listed
      check not Z3_mk_seq_replace_allAvailable()

  test "z3CompatWarnings() is empty and z3LoadIsHealthy() is true on a clean load":
    ## No mrAnomalous entries are expected on any harness runtime — the
    ## manifest fully accounts for both drift points. This is the
    ## clean-load guard: a red flag here means an unexpected libz3 build
    ## or a stale manifest, not a normal version difference.
    discard newContext()
    check z3CompatWarnings().len == 0
    check z3LoadIsHealthy()

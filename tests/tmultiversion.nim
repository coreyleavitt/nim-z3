## Multi-version load smoke test — RFC-regex-index.md §6.3 slice 4.
##
## Exercises `loadZ3()` (implicitly, via context creation) against whatever
## Z3 runtime the harness mounts. At Z3 **4.15.5** the symbol
## `Z3_mk_set_has_size` was removed; before the slice-4 fix that made the
## whole load fail (`LibZ3UnavailableError`). After the fix, a missing
## optional symbol degrades the load to `lrOkPartial`, which `context.nim`
## accepts, and this test — which never touches `set_has_size` — passes on
## every supported runtime.
##
## Also proves the *drifted-signature* half of slice 4:
## `Z3_fpa_get_numeral_sign`'s out-param is `int*` through 4.15.4 and `bool*`
## from 4.15.5 (same name, incompatible ABI). It's declared
## `until: "4.15.5"` (the historical `int*` shape) + `optional`, so
## `z3Compat()` — softlink's generated report proc — must show it as
## `mrDriftRefused` on a >= 4.15.5 runtime, and absent from `missingReasons`
## (i.e. usable) below that.
##
## **Boundary note:** these three symbols (`set_has_size` removed,
## `fpa_get_numeral_sign` drifted, `seq_replace_all` added) all move at the
## SAME release, **4.15.5** — a hard API shuffle, verified against Z3's
## committed headers. The original harvest corpus sampled {…, 4.15.0,
## 4.16.0}, jumping the 4.15.x break, and so mis-recorded all three at
## 4.16.0; the corpus now samples 4.15.4/4.15.5/4.15.8 and the manifest
## pins them at 4.15.5. `postApiShuffle()` (below) is the single boundary.
##
## **M2 (code review):** the committed `src/z3/z3.compat.json` manifest
## harvests the corpus {4.13.3, 4.13.4, 4.14.1, 4.15.0, 4.15.4, 4.15.5,
## 4.15.8, 4.16.0}. Its whole CI-guard value is unrealized unless something
## actually asserts what it promises, so this file also pins:
##
##   - `attestation == atAttested` on every harness runtime (all are in the
##     corpus above).
##   - `Z3_mk_set_has_size` (removed at 4.15.5) classifies as `mrExpected` +
##     unavailable on >= 4.15.5, and is available + absent from
##     `missingReasons` below that.
##   - `Z3_mk_seq_replace_all` (added at 4.15.5) classifies as `mrExpected` +
##     unavailable below 4.15.5, and is available + absent from
##     `missingReasons` at/above it.
##   - `z3CompatWarnings()` is empty and `z3LoadIsHealthy()` is `true`
##     on a clean, attested load (the fpa `mrDriftRefused` entry on
##     >= 4.15.5 is expected-for-that-version, not a warning — see
##     `z3/ffi.nim`'s `z3LoadIsHealthy` docstring for the exact rule).

import std/[unittest, strutils]
import z3  # z3Compat() + the softlink compat types (MissingReason/mrDriftRefused,
          # CompatReport, Attestation) are re-exported through the umbrella

proc postApiShuffle(): bool =
  ## True on z3 >= 4.15.5, the patch release that shuffled three API symbols
  ## at once (ground-truth-verified against z3's committed headers + the
  ## harvested corpus, which now samples 4.15.4/4.15.5/4.15.8):
  ##   * Z3_fpa_get_numeral_sign  int* -> bool* out-param (drift-refused)
  ##   * Z3_mk_set_has_size        removed
  ##   * Z3_mk_seq_replace_all     added
  ## The original corpus jumped 4.15.0 -> 4.16.0 and so mis-recorded all
  ## three boundaries at 4.16.0; they are all 4.15.5.
  let v = z3Version()
  (v.major, v.minor, v.build) >= (4, 15, 5)

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

    # Z3_fpa_get_numeral_sign's out-param drifted int* -> bool* at 4.15.5
    # (declared `until: "4.15.5"` + optional), so it is drift-refused and
    # unavailable on >= 4.15.5 and usable below that.
    if postApiShuffle():
      check fpaSignDrifted
      check not Z3_fpa_get_numeral_signAvailable()
    else:
      check not fpaSignDrifted
      check Z3_fpa_get_numeral_signAvailable()

  test "z3Compat() attestation is atAttested on the harness runtimes":
    ## The committed manifest's corpus is {4.13.3, 4.13.4, 4.14.1, 4.15.0,
    ## 4.15.4, 4.15.5, 4.15.8, 4.16.0} — every CI matrix / harness runtime
    ## (4.13.4, 4.14.1, 4.15.8, 4.16.0) falls inside it, so the load must be
    ## attested rather than merely probed.
    discard newContext()
    let report = z3Compat()
    check report.attestation == atAttested

  test "Z3_mk_set_has_size classifies as mrExpected, removed at 4.15.5":
    discard newContext()
    let report = z3Compat()
    var listed = false
    for (symbol, reason, _) in report.missingReasons:
      if symbol == "Z3_mk_set_has_size":
        listed = true
        check reason == mrExpected

    # Removed from the header at 4.15.5 (not 4.16); `optional`, so absent +
    # mrExpected on >= 4.15.5 and present below that.
    if postApiShuffle():
      check listed
      check not Z3_mk_set_has_sizeAvailable()
    else:
      check not listed
      check Z3_mk_set_has_sizeAvailable()

  test "Z3_mk_seq_replace_all classifies as mrExpected, added at 4.15.5":
    ## Added to the header at 4.15.5 (not 4.16): absent + mrExpected below
    ## 4.15.5 (covers 4.13.4/4.14.1/4.15.0/4.15.4), present at/above it.
    discard newContext()
    let report = z3Compat()
    var listed = false
    for (symbol, reason, _) in report.missingReasons:
      if symbol == "Z3_mk_seq_replace_all":
        listed = true
        check reason == mrExpected

    if postApiShuffle():
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

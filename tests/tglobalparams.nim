## `z3/globalparams` tests — process-wide parameter control
## (v0.4 step 13).

import std/[unittest, options]
import z3

suite "Z3 global parameters — tracer":
  test "set then get round-trips through Z3's global param store":
    resetGlobalParams()
    setGlobalParam("verbose", "5")
    check getGlobalParam("verbose") == some("5")
    resetGlobalParams()

suite "Z3 global parameters — behaviors":
  test "known param at default reads as some(default-string)":
    # Z3's get returns the effective value (default or override),
    # so a known-but-never-touched param reads back its built-in
    # default. `verbose` defaults to "0".
    resetGlobalParams()
    check getGlobalParam("verbose") == some("0")

  test "resetGlobalParams restores Z3's built-in default":
    resetGlobalParams()
    setGlobalParam("verbose", "7")
    check getGlobalParam("verbose") == some("7")
    resetGlobalParams()
    check getGlobalParam("verbose") == some("0")

  test "boolean params round-trip the canonical 'true' / 'false'":
    # `model_validate` defaults to false; setting to true should
    # round-trip and not get clobbered.
    resetGlobalParams()
    check getGlobalParam("model_validate") == some("false")
    setGlobalParam("model_validate", "true")
    check getGlobalParam("model_validate") == some("true")
    resetGlobalParams()

  test "unknown parameter names read as none":
    # `Z3_global_param_get` returns FALSE for any name Z3 has no
    # registration for — we surface that as `none`. (Z3's `set`
    # writes a stderr warning for unknown names; that's expected.)
    resetGlobalParams()
    check getGlobalParam("definitely_not_a_real_z3_param_name").isNone

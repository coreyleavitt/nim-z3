## Slice A0 (RFC-fixedpoint-callbacks.md, ADR-FC-0002) — collection proof
## for `FixedpointCtxBox` rooted on `Z3Fixedpoint` via the erased
## `cbBox: RootRef` field.
##
## Proves both halves of the ADR-FC-0002 rooting+cleanup pair:
##
## 1. **Rooted while `fp` is alive** — assigning a `FixedpointCtxBox`
##    through `fp.cbBoxRef =` and dropping every other reference to the
##    box does not collect it: `fp` itself roots it. A `GC_fullCollect`
##    while `fp` is still alive does not disturb the box, and it is
##    still reachable back through `fp.cbBoxRef`.
## 2. **Collected when `fp` dies** — dropping the last reference to `fp`
##    releases `cbBox` (ORC-traced `RootRef`), and the box (and the
##    `ctx` ref it holds) go with it. Always-on via the multi-iteration
##    inner-scope idiom from `tests/td3_ctx_release.nim` (a valgrind
##    "definitely lost: 0 bytes" proof); the *precise* firing-count
##    proof (probe FACT B: a `ref object of RootObj` is reclaimed
##    deterministically on scope exit under `--mm:orc`, not merely
##    eventually via the cycle collector) is a dev-only instrument
##    gated behind `-d:z3FpBoxDestroyCount`, mirroring
##    `td3_ctx_release.nim`'s `z3CtxDestroyCount` suite (also not wired
##    into any nimble task with that define — run it manually:
##    `scratchpad/nimz3.sh c -d:z3FpBoxDestroyCount tests/tfixedpoint_ctxbox.nim`).

import std/unittest
import z3
import z3/fixedpoint_callbacks

when defined(z3WithoutFixedpointCallbacks):
  # Module excluded: emit a single skip suite so CI reports it cleanly.
  suite "fixedpoint_callbacks — disabled build (-d:z3WithoutFixedpointCallbacks)":
    test "fixedpoint typed callbacks are compiled out":
      skip()

else:
  const N = 25
    ## Fixture iteration count; see `td3_ctx_release.nim`'s module doc for
    ## why a loop (not a single drop) makes a valgrind leak signal
    ## unambiguous.

  suite "A0 — FixedpointCtxBox rooted on Z3Fixedpoint (ADR-FC-0002)":
    test "box survives GC_fullCollect while fp is alive; still reachable via cbBoxRef":
      let ctx = newContext()
      let fp = newFixedpoint(ctx)
      var box = FixedpointCtxBox(ctx: ctx)
      fp.cbBoxRef = cast[RootRef](box)
      box = nil  # drop the local ref; fp.cbBoxRef is now the sole owner

      GC_fullCollect()

      let recovered = cast[FixedpointCtxBox](fp.cbBoxRef)
      check recovered != nil
      check recovered.ctx == ctx

    test "fp + rooted box drop cleanly across N inner scopes (valgrind leak proof)":
      for i in 0 ..< N:
        block:
          let ctx = newContext()
          let fp = newFixedpoint(ctx)
          let box = FixedpointCtxBox(ctx: ctx)
          fp.cbBoxRef = cast[RootRef](box)
          # fp (and the box it roots) fall out of scope when this block
          # exits, below — ORC drops them deterministically, in-process.
      check true

  when defined(z3FpBoxDestroyCount):
    # Dev-only precise instrument (mirrors `td3_ctx_release.nim`'s
    # `z3CtxDestroyCount` suite): directly observe
    # `FixedpointCtxBoxObj.=destroy` firing exactly once per fp drop,
    # rather than inferring it from valgrind's aggregate leaked-bytes
    # total.
    suite "A0 — counting-hook: FixedpointCtxBoxObj.=destroy fires exactly once per fp drop":
      test "destroy counter rises by exactly N after N inner-scope fp drops":
        let before = z3FpBoxDestroyCounter
        for i in 0 ..< N:
          block:
            let ctx = newContext()
            let fp = newFixedpoint(ctx)
            let box = FixedpointCtxBox(ctx: ctx)
            fp.cbBoxRef = cast[RootRef](box)
        check z3FpBoxDestroyCounter - before == N

      test "destroy counter stays put while fp (and its rooted box) are still alive":
        let before = z3FpBoxDestroyCounter
        let ctx = newContext()
        let fp = newFixedpoint(ctx)
        let box = FixedpointCtxBox(ctx: ctx)
        fp.cbBoxRef = cast[RootRef](box)
        GC_fullCollect()
        check z3FpBoxDestroyCounter == before

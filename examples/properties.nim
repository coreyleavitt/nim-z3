## Property-based testing with proptest + nim-z3. A user-facing
## starter showing how to drive Z3 with random inputs and verify
## invariants. For the full property suite covering algebraic laws
## over random expression trees, see `tests/tproperty.nim`.
##
## This example demonstrates two property flavours:
##
## 1. **Soundness round-trip** — for any random `k: int32`, asserting
##    `x == k` is sat and the model gives `k` back. Tests that the
##    wrapper's literal-to-AST-to-model pipeline preserves value.
##
## 2. **Native vs. Z3 modular arithmetic agreement** — for any
##    `(a, b): uint8 × uint8`, `bvadd(BV(a), BV(b)).toUint` equals
##    `(a + b) mod 256` (native wraparound). Tests that the BV
##    operator surface matches the machine's own modular semantics.

import std/[strformat]
import proptest
import z3

proc soundnessRoundTrip(): Report[int] =
  let ctx = newContext()
  forAll(
    integers(low(int32).int, high(int32).int),
    proc(k: int) =
      let x = mkIntVar("x")
      let s = newSolver()
      s.add x == mkInt(k)
      ensure s.check() == zsSat
      ensure s.model()[x].toInt == k)

proc bvWraparound(): Report[(int, int)] =
  let ctx = newContext()
  forAll(
    tuples2(integers(0, 255), integers(0, 255)),
    proc(p: (int, int)) =
      let got = (mkBitVec(uint32(p[0]), 8) + mkBitVec(uint32(p[1]), 8)).toUint
      ensure got == uint64(uint8(p[0]) + uint8(p[1])))

proc main() =
  let r1 = soundnessRoundTrip()
  doAssert r1.outcome == otPassed
  echo &"soundness round-trip: {r1.examples} examples — passed"

  let r2 = bvWraparound()
  doAssert r2.outcome == otPassed
  echo &"bvadd ↔ uint8 wraparound: {r2.examples} examples — passed"

when isMainModule:
  main()

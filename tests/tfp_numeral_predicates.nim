## `z3/fp` — N6.4a: `isNumeralXxx` host-side bool predicates.
##
## `Z3_fpa_is_numeral_*` — operate on *concrete* FP numerals and return
## a Nim `bool` (host-side), not a `Z3Bool` (symbolic AST node).
## These are introspection procs: they answer "what kind of value IS this
## numeral?" without going through the solver.

import std/unittest
import z3

suite "isNumeralNaN — N6.4a":
  test "isNumeralNaN(mkNaN) is true":
    let ctx = newContext()
    check isNumeralNaN(mkNaN[8, 24]())

  test "isNumeralNaN(1.0) is false":
    let ctx = newContext()
    check not isNumeralNaN(mkFloat32(1.0'f32))

suite "isNumeralInf — N6.4a":
  test "isNumeralInf(+Inf) is true":
    let ctx = newContext()
    check isNumeralInf(mkInf[8, 24]())

  test "isNumeralInf(-Inf) is true":
    let ctx = newContext()
    check isNumeralInf(mkInf[8, 24](negative = true))

  test "isNumeralInf(1.0) is false":
    let ctx = newContext()
    check not isNumeralInf(mkFloat32(1.0'f32))

suite "isNumeralZero — N6.4a":
  test "isNumeralZero(+0) is true":
    let ctx = newContext()
    check isNumeralZero(mkFloat32(0.0'f32))

  test "isNumeralZero(-0) is true":
    let ctx = newContext()
    check isNumeralZero(mkZero[8, 24](negative = true))

  test "isNumeralZero(1.0) is false":
    let ctx = newContext()
    check not isNumeralZero(mkFloat32(1.0'f32))

suite "isNumeralNormal — N6.4a":
  test "isNumeralNormal(1.0) is true":
    let ctx = newContext()
    check isNumeralNormal(mkFloat32(1.0'f32))

  test "isNumeralNormal(0.0) is false":
    let ctx = newContext()
    check not isNumeralNormal(mkFloat32(0.0'f32))

suite "isNumeralSubnormal — N6.4a":
  test "isNumeralSubnormal for smallest Float32 subnormal is true":
    ## IEEE 754 binary32: bit pattern 0x00000001 = 2^-149, the smallest
    ## positive subnormal. `cast[float32](1'u32)` gives that exact bit
    ## pattern; `mkFloat32` lifts it to a Z3 FP numeral (not an `fpa.fp`
    ## application), which is what the numeral-predicate API requires.
    ## Note: `mkFpFromParts` builds an `fpa.fp(...)` application node;
    ## Z3's `Z3_fpa_is_numeral_*` family requires a *numeral* AST, not an
    ## application, so we use the float-literal path here.
    let ctx = newContext()
    let sub = cast[float32](1'u32)   # = 2^-149, smallest positive subnormal
    let fp  = mkFloat32(sub)
    check isNumeralSubnormal(fp)

  test "isNumeralSubnormal(1.0) is false":
    let ctx = newContext()
    check not isNumeralSubnormal(mkFloat32(1.0'f32))

suite "isNumeralPositive — N6.4a":
  test "isNumeralPositive(1.0) is true":
    let ctx = newContext()
    check isNumeralPositive(mkFloat32(1.0'f32))

  test "isNumeralPositive(-1.0) is false":
    let ctx = newContext()
    check not isNumeralPositive(mkFloat32(-1.0'f32))

suite "isNumeralNegative — N6.4a":
  test "isNumeralNegative(-1.0) is true":
    let ctx = newContext()
    check isNumeralNegative(mkFloat32(-1.0'f32))

  test "isNumeralNegative(1.0) is false":
    let ctx = newContext()
    check not isNumeralNegative(mkFloat32(1.0'f32))

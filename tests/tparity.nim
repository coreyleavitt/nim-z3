## `z3/parity` tests — cross-family `Z3Term` surface parity
## (v0.5 step 3).
##
## v0.3 step 1 introduced the `Z3Term` concept and unified `wrap[T]` /
## `eval[T]` / `smtEquiv[T]` over it. Several cross-family surfaces
## (`pretty`, `astEqual`, scalar-`evalXxx` shorthand, `$` per family)
## hadn't been migrated yet. v0.5 step 3 closes that gap. These tests
## verify the unified surfaces apply uniformly to every typed family.

import std/[unittest]
import z3

suite "astEqual — generic over Z3Term":
  test "Z3BitVec same-handle pair":
    let ctx = newContext()
    let x = mkBitVecVar[8]("x")
    check astEqual(x, x)

  test "Z3Char same-handle pair":
    let ctx = newContext()
    let c = mkChar('a')
    check astEqual(c, c)

  test "Z3Fp[Float32] same-handle pair":
    let ctx = newContext()
    let f = mkFloat32(3.14'f32)
    check astEqual(f, f)

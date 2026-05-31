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

suite "evalXxx shorthand — Z3BitVec":
  test "evalUint extracts the unsigned BV value from a solved model":
    let ctx = newContext()
    let x = mkBitVecVar[8]("x")
    let s = newSolver()
    s.add x == mkBitVec[8](42'u32)
    check s.check() == zsSat
    check evalUint(s.model(), x) == 42'u64

  test "evalInt extracts the signed BV value (negative case)":
    let ctx = newContext()
    let x = mkBitVecVar[8]("x")
    let s = newSolver()
    # 0xFF on BV[8] is -1 signed
    s.add x == mkBitVec[8](0xFF'u32)
    check s.check() == zsSat
    check evalInt(s.model(), x) == -1

suite "evalXxx shorthand — Z3Char + Z3Seq":
  test "evalChar extracts the codepoint as int":
    let ctx = newContext()
    let c = mkCharVar("c")
    let s = newSolver()
    s.add c == mkChar('Z')
    check s.check() == zsSat
    check evalChar(s.model(), c) == ord('Z')

  test "evalSeqLen extracts the integer length of a sequence":
    let ctx = newContext()
    let xs = mkSeqVar[Z3Int]("xs")
    let s = newSolver()
    s.add xs.len == mkInt(5)
    check s.check() == zsSat
    check evalSeqLen(s.model(), xs) == 5

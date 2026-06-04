## N10.7 — `Z3BitVec[W]` Option extractors: `toUintOpt`, `toIntOpt`, `toInt64Opt`.
##
## Covers:
##   - `toUintOpt` happy path: concrete BV literal → some(value)
##   - `toIntOpt` happy path: signed concrete BV literal → some(value)
##   - `toInt64Opt` happy path: wide (BV[64]) literal → some(value)
##   - All three return none for symbolic BV var (no solver, no model)
##   - `toUintOpt` works on model-extracted BV (solver round-trip)
##   - `toIntOpt` returns none for value that overflows `int` range
##     (BV[64] with value > int.high, relevant on 32-bit; on 64-bit same range)

import std/[unittest, options]
import z3

suite "Z3BitVec.toUintOpt":
  test "toUintOpt returns some(42) for mkBitVec[8](42)":
    let ctx = newContext()
    check mkBitVec[8](42).toUintOpt == some(42'u)

  test "toUintOpt returns none for symbolic BV variable":
    let ctx = newContext()
    let x = mkBitVecVar[8]("x")
    check toUintOpt(x) == none(uint)

  test "toUintOpt works on model-extracted BV after solver check":
    let ctx = newContext()
    let x = mkBitVecVar[8]("x")
    let s = newSolver()
    s.add x == mkBitVec[8](99)
    check s.check() == zsSat
    let m = s.model()
    check m[x].toUintOpt == some(99'u)

suite "Z3BitVec.toIntOpt":
  test "toIntOpt returns some(-1) for mkBitVec[8](-1) (signed read)":
    let ctx = newContext()
    check mkBitVec[8](-1).toIntOpt == some(-1)

  test "toIntOpt returns some(42) for positive BV literal":
    let ctx = newContext()
    check mkBitVec[8](42).toIntOpt == some(42)

  test "toIntOpt returns none for symbolic BV variable":
    let ctx = newContext()
    let x = mkBitVecVar[8]("x")
    check toIntOpt(x) == none(int)

suite "Z3BitVec.toInt64Opt":
  test "toInt64Opt returns some(2^40) for mkBitVec[64](2^40)":
    let ctx = newContext()
    let v: int64 = 1'i64 shl 40
    check mkBitVec[64](v).toInt64Opt == some(v)

  test "toInt64Opt returns some(-1) for mkBitVec[64](-1) (signed read)":
    let ctx = newContext()
    check mkBitVec[64](-1'i64).toInt64Opt == some(-1'i64)

  test "toInt64Opt returns none for symbolic BV variable":
    let ctx = newContext()
    let x = mkBitVecVar[64]("x")
    check toInt64Opt(x) == none(int64)

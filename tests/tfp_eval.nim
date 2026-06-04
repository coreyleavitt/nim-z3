## `z3/fp` — evalFloat32Opt / evalFloat64Opt / evalFp generic dispatcher (N6.6)

import std/[unittest, options]
import z3

suite "Z3Fp N6.6 — evalFloat64Opt":
  test "solve x == 3.14, evalFloat64Opt returns some(3.14)":
    let ctx = newContext()
    let x = mkFloat64Var("x")
    let s = newSolver()
    s.add x == mkFloat64(3.14)
    check s.check() == zsSat
    let m = s.model()
    let r = m.evalFloat64Opt(x)
    check r.isSome
    check r.get == 3.14

  test "solve x == 0.0, evalFloat64Opt returns some(0.0)":
    let ctx = newContext()
    let x = mkFloat64Var("x")
    let s = newSolver()
    s.add x == mkFloat64(0.0)
    check s.check() == zsSat
    let m = s.model()
    let r = m.evalFloat64Opt(x)
    check r.isSome
    check r.get == 0.0

  test "solve x == -1.5, evalFloat64Opt returns some(-1.5)":
    let ctx = newContext()
    let x = mkFloat64Var("x")
    let s = newSolver()
    s.add x == mkFloat64(-1.5)
    check s.check() == zsSat
    let m = s.model()
    let r = m.evalFloat64Opt(x)
    check r.isSome
    check r.get == -1.5

suite "Z3Fp N6.6 — evalFloat32Opt":
  test "solve x == 3.14f32, evalFloat32Opt returns some(3.14f32)":
    let ctx = newContext()
    let x = mkFloat32Var("x")
    let s = newSolver()
    s.add x == mkFloat32(3.14'f32)
    check s.check() == zsSat
    let m = s.model()
    let r = m.evalFloat32Opt(x)
    check r.isSome
    check r.get == 3.14'f32

  test "solve x == 0.0f32, evalFloat32Opt returns some(0.0f32)":
    let ctx = newContext()
    let x = mkFloat32Var("x")
    let s = newSolver()
    s.add x == mkFloat32(0.0'f32)
    check s.check() == zsSat
    let m = s.model()
    let r = m.evalFloat32Opt(x)
    check r.isSome
    check r.get == 0.0'f32

  test "solve x == -2.5f32, evalFloat32Opt returns some(-2.5f32)":
    let ctx = newContext()
    let x = mkFloat32Var("x")
    let s = newSolver()
    s.add x == mkFloat32(-2.5'f32)
    check s.check() == zsSat
    let m = s.model()
    let r = m.evalFloat32Opt(x)
    check r.isSome
    check r.get == -2.5'f32

suite "Z3Fp N6.6 — evalFp generic dispatcher":
  test "evalFp[11,53] dispatches to Option[float64]":
    let ctx = newContext()
    let x = mkFloat64Var("x")
    let s = newSolver()
    s.add x == mkFloat64(3.14)
    check s.check() == zsSat
    let m = s.model()
    let r = evalFp[11, 53](m, x)
    check r.isSome
    check r.get == 3.14

  test "evalFp[8,24] dispatches to Option[float32]":
    let ctx = newContext()
    let x = mkFloat32Var("x")
    let s = newSolver()
    s.add x == mkFloat32(3.14'f32)
    check s.check() == zsSat
    let m = s.model()
    let r = evalFp[8, 24](m, x)
    check r.isSome
    check r.get == 3.14'f32

  test "evalFp result type for [11,53] is Option[float64]":
    ## Compile-time type check: ensure the return type is Option[float64]
    ## (not Option[float32] or a string).
    let ctx = newContext()
    let x = mkFloat64Var("x")
    let s = newSolver()
    s.add x == mkFloat64(1.0)
    check s.check() == zsSat
    let m = s.model()
    let r = evalFp[11, 53](m, x)
    check (r is Option[float64])

  test "evalFp result type for [8,24] is Option[float32]":
    let ctx = newContext()
    let x = mkFloat32Var("x")
    let s = newSolver()
    s.add x == mkFloat32(1.0'f32)
    check s.check() == zsSat
    let m = s.model()
    let r = evalFp[8, 24](m, x)
    check (r is Option[float32])

  test "evalFp[5,11] (float16) returns bit-pattern string":
    ## Non-standard precision: must return a string repr, not a Nim float.
    let ctx = newContext()
    let x = mkFpVar[5, 11]("x")
    let s = newSolver()
    s.add x == mkFp[5, 11](1.0)
    check s.check() == zsSat
    let m = s.model()
    let r = evalFp[5, 11](m, x)
    check (r is string)
    check r.len > 0

suite "Z3Fp N6.6 — modelCompletion parameter forwarded":
  test "evalFloat64Opt on constrained var always returns some":
    ## A constrained variable always evaluates to a concrete numeral.
    let ctx = newContext()
    let x = mkFloat64Var("x")
    let s = newSolver()
    s.add x == mkFloat64(7.0)
    check s.check() == zsSat
    let m = s.model()
    check m.evalFloat64Opt(x).isSome
    check m.evalFloat64Opt(x).get == 7.0

  test "evalFloat32Opt on constrained var always returns some":
    let ctx = newContext()
    let x = mkFloat32Var("x")
    let s = newSolver()
    s.add x == mkFloat32(7.0'f32)
    check s.check() == zsSat
    let m = s.model()
    check m.evalFloat32Opt(x).isSome
    check m.evalFloat32Opt(x).get == 7.0'f32

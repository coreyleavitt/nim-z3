## N10.5 — `mkReal(ctx, float64)` + float-lift arithmetic + `toRealOpt`
##
## Covers:
##   - `mkReal(ctx, 3.14)` produces a Z3Real that evaluates close to 3.14
##   - `mkRealVar("x") + 0.5` compiles and is SAT
##   - `0.5 + mkRealVar("x")` (reverse orientation) compiles and is SAT
##   - `mkRealVar("x") - 1.5`, `1.5 - mkRealVar("x")` SAT
##   - `mkRealVar("x") * 2.0`, `2.0 * mkRealVar("x")` SAT
##   - `mkRealVar("x") / 2.0`, `2.0 / mkRealVar("x")` SAT
##   - Round-trip: solve `x == 3.14`, `toRealOpt(model.eval(x))` ≈ 3.14
##   - `toRealOpt` on a free symbolic variable returns none

import std/[unittest, options, math]
import z3

suite "N10.5 — mkReal(float64)":
  test "mkReal(ctx, 3.14) evaluates close to 3.14 via toRealOpt":
    let ctx = newContext()
    let r = mkReal(ctx, 3.14)
    let v = toRealOpt(r)
    check v.isSome
    check abs(v.get - 3.14) < 1e-10

  test "mkReal(ctx, 0.5) evaluates close to 0.5":
    let ctx = newContext()
    let r = mkReal(ctx, 0.5)
    let v = toRealOpt(r)
    check v.isSome
    check abs(v.get - 0.5) < 1e-10

suite "N10.5 — float-lift arithmetic: Z3Real op float":
  test "mkRealVar + 0.5 is SAT":
    let ctx = newContext()
    let s = newSolver()
    let x = mkRealVar("x")
    s.add (x + 0.5) > mkReal(0)
    check s.check() == zsSat

  test "0.5 + mkRealVar is SAT (reverse orientation)":
    let ctx = newContext()
    let s = newSolver()
    let x = mkRealVar("x")
    s.add (0.5 + x) > mkReal(0)
    check s.check() == zsSat

  test "mkRealVar - 1.5 is SAT":
    let ctx = newContext()
    let s = newSolver()
    let x = mkRealVar("x")
    s.add (x - 1.5) < mkReal(0)
    check s.check() == zsSat

  test "1.5 - mkRealVar is SAT (reverse orientation)":
    let ctx = newContext()
    let s = newSolver()
    let x = mkRealVar("x")
    s.add (1.5 - x) > mkReal(0)
    check s.check() == zsSat

  test "mkRealVar * 2.0 is SAT":
    let ctx = newContext()
    let s = newSolver()
    let x = mkRealVar("x")
    s.add (x * 2.0) > mkReal(0)
    check s.check() == zsSat

  test "2.0 * mkRealVar is SAT (reverse orientation)":
    let ctx = newContext()
    let s = newSolver()
    let x = mkRealVar("x")
    s.add (2.0 * x) > mkReal(0)
    check s.check() == zsSat

  test "mkRealVar / 2.0 is SAT":
    let ctx = newContext()
    let s = newSolver()
    let x = mkRealVar("x")
    s.add (x / 2.0) > mkReal(0)
    check s.check() == zsSat

  test "2.0 / mkRealVar is SAT (reverse orientation)":
    let ctx = newContext()
    let s = newSolver()
    let x = mkRealVar("x")
    s.add (2.0 / x) > mkReal(0)
    check s.check() == zsSat

suite "N10.5 — toRealOpt round-trip through solver model":
  test "solve x == 3.14, toRealOpt(model.eval(x)) ≈ 3.14":
    let ctx = newContext()
    let s = newSolver()
    let x = mkRealVar("x")
    s.add (x == mkReal(ctx, 3.14))
    check s.check() == zsSat
    let m = s.model()
    let v = toRealOpt(m.eval(x))
    check v.isSome
    check abs(v.get - 3.14) < 1e-10

  test "toRealOpt on free symbolic variable returns none":
    let ctx = newContext()
    let y = mkRealVar("y")
    check toRealOpt(y) == none(float)

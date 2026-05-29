## `z3/model` tests — model extraction, eval, scalar extractors,
## the headline end-to-end "find x, y" example.

import std/[unittest, options, strutils]
import z3

suite "Z3Model — extraction":
  test "model() raises if check() returned unsat":
    let ctx = newContext()
    let s = newSolver()
    s.add mkFalse()
    check s.check() == zsUnsat
    expect Z3Error:
      discard s.model()

  test "model() returns a model after sat":
    let ctx = newContext()
    let s = newSolver()
    let p = mkBoolVar("p")
    s.add p
    check s.check() == zsSat
    let m = s.model()
    check m != nil

suite "Z3Model — eval + [] indexing":
  test "m[x] returns Z3Int with extractable value":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.add x == 42
    check s.check() == zsSat
    let m = s.model()
    check m[x].toInt == 42

  test "m.eval(x) is the same as m[x]":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.add x == 7
    check s.check() == zsSat
    let m = s.model()
    check m.eval(x).toInt == m[x].toInt

  test "modelCompletion = true assigns unconstrained vars":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.add mkTrue()  # no constraint on x
    check s.check() == zsSat
    let m = s.model()
    # With completion, m.eval returns a concrete value (typically 0).
    let v = m.eval(x, modelCompletion = true)
    check v.toIntOpt.isSome

suite "Z3Model — scalar extractors":
  test "Z3Int.toInt":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.add x == 100
    discard s.check()
    let m = s.model()
    check m[x].toInt == 100

  test "Z3Int.toIntOpt returns some for literal":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.add x == 7
    discard s.check()
    let m = s.model()
    check m[x].toIntOpt == some(7)

  test "Z3Int.toIntOpt returns none for non-literal":
    let ctx = newContext()
    let x = mkIntVar("x")
    # x is a variable, not a numeral, so toIntOpt returns none.
    check x.toIntOpt == none(int)

  test "Z3Int.toInt raises on non-literal":
    let ctx = newContext()
    let x = mkIntVar("x")
    expect Z3Error:
      discard x.toInt

  test "Z3Int.toBigIntStr works for big numbers":
    let ctx = newContext()
    let big = mkBigInt("12345678901234567890")
    check big.toBigIntStr == "12345678901234567890"

  test "Z3Bool.toBool from literal":
    let ctx = newContext()
    check mkTrue().toBool == true
    check mkFalse().toBool == false

  test "Z3Bool.toBool from solved variable":
    let ctx = newContext()
    let s = newSolver()
    let p = mkBoolVar("p")
    s.add p == true
    discard s.check()
    let m = s.model()
    check m[p].toBool == true

  test "Z3Bool.toBoolOpt none for unevaluated variable":
    let ctx = newContext()
    let p = mkBoolVar("p")
    check p.toBoolOpt == none(bool)

  test "Z3Real.toBigRealStr":
    let ctx = newContext()
    let r = mkBigReal("1/2")
    check r.toBigRealStr == "1/2"

suite "Z3Model — composer helpers":
  test "evalInt — one-call eval + extract":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.add x == 99
    discard s.check()
    let m = s.model()
    check m.evalInt(x) == 99

  test "evalBool":
    let ctx = newContext()
    let s = newSolver()
    let p = mkBoolVar("p")
    s.add p == true
    discard s.check()
    let m = s.model()
    check m.evalBool(p) == true

suite "Z3Model — pretty-print":
  test "$ contains the variable assignments":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    s.add x == 42
    discard s.check()
    let m = s.model()
    let str = $m
    check str.contains("x")
    check str.contains("42")

suite "the headline end-to-end example":
  test "find x, y such that x + y == 10 and x > 3":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")

    let s = newSolver()
    s.add (x + y == 10) and (x > 3)

    check s.check() == zsSat
    let m = s.model()
    let xv = m.evalInt(x)
    let yv = m.evalInt(y)
    check xv + yv == 10
    check xv > 3

  test "find a Pythagorean triple with hypotenuse 5":
    let ctx = newContext()
    let a = mkIntVar("a")
    let b = mkIntVar("b")

    let s = newSolver()
    s.add(a > 0, b > 0,
          a * a + b * b == 25)

    check s.check() == zsSat
    let m = s.model()
    let av = m.evalInt(a)
    let bv = m.evalInt(b)
    check av > 0
    check bv > 0
    check av * av + bv * bv == 25

  test "8-queens-style row distinctness with 4 queens":
    # Find 4 integers in [0..3] all distinct (one queen per row, columns).
    let ctx = newContext()
    var cols: array[4, Z3Int]
    let s = newSolver()
    for i in 0..3:
      cols[i] = mkIntVar("c" & $i)
      s.add cols[i] >= 0
      s.add cols[i] <= 3
    s.add mkDistinct(cols[0], cols[1], cols[2], cols[3])

    check s.check() == zsSat
    let m = s.model()
    var vals: array[4, int]
    for i in 0..3:
      vals[i] = m.evalInt(cols[i])
    # All in range, all distinct
    for v in vals:
      check v >= 0 and v <= 3
    check vals[0] != vals[1] and vals[0] != vals[2] and vals[0] != vals[3]
    check vals[1] != vals[2] and vals[1] != vals[3]
    check vals[2] != vals[3]

## `z3/boolean` tests — boolean operators + lifts + ite + varargs.

import std/unittest
import z3

suite "boolean — basic operators":
  test "and / or / not (typed)":
    let ctx = newContext()
    let p = mkBoolVar("p")
    let q = mkBoolVar("q")
    check ($(p and q)) == "(and p q)"
    check ($(p or q))  == "(or p q)"
    check ($(not p))   == "(not p)"

  test "xor":
    let ctx = newContext()
    let p = mkBoolVar("p")
    let q = mkBoolVar("q")
    check ($(p xor q)) == "(xor p q)"

  test "implies / iff":
    let ctx = newContext()
    let p = mkBoolVar("p")
    let q = mkBoolVar("q")
    check ($(implies(p, q))) == "(=> p q)"
    check ($(iff(p, q)))     == "(= p q)"

suite "boolean — literal-lift overloads":
  test "Z3Bool and bool":
    let ctx = newContext()
    let p = mkBoolVar("p")
    check ($(p and true))  == "(and p true)"
    check ($(p and false)) == "(and p false)"
    check ($(true and p))  == "(and true p)"

  test "Z3Bool or bool":
    let ctx = newContext()
    let p = mkBoolVar("p")
    check ($(p or false)) == "(or p false)"
    check ($(true or p))  == "(or true p)"

  test "Z3Bool xor bool":
    let ctx = newContext()
    let p = mkBoolVar("p")
    check ($(p xor true)) == "(xor p true)"

  test "implies with bool":
    let ctx = newContext()
    let p = mkBoolVar("p")
    check ($(implies(p, true)))  == "(=> p true)"
    check ($(implies(false, p))) == "(=> false p)"

suite "boolean — ite":
  test "ite over Int":
    let ctx = newContext()
    let p = mkBoolVar("p")
    let r = ite(p, mkInt(1), mkInt(0))
    check ($r) == "(ite p 1 0)"

  test "ite over Bool":
    let ctx = newContext()
    let p = mkBoolVar("p")
    let q = mkBoolVar("q")
    let r = ite(p, q, mkTrue())
    check ($r) == "(ite p q true)"

  test "ite enforces same-sort branches at compile time":
    let ctx = newContext()
    let p = mkBoolVar("p")
    check not compiles(ite(p, mkInt(1), mkBoolVar("q")))

suite "boolean — equality on Z3Bool":
  test "Z3Bool == Z3Bool produces Z3Bool":
    let ctx = newContext()
    let p = mkBoolVar("p")
    let q = mkBoolVar("q")
    check ($(p == q)) == "(= p q)"

  test "Z3Bool == true (lift)":
    let ctx = newContext()
    let p = mkBoolVar("p")
    check ($(p == true)) == "(= p true)"

  test "Z3Bool != Z3Bool":
    let ctx = newContext()
    let p = mkBoolVar("p")
    let q = mkBoolVar("q")
    check ($(p != q)) == "(not (= p q))"

suite "boolean — varargs":
  test "mkAnd over a list":
    let ctx = newContext()
    let p = mkBoolVar("p")
    let q = mkBoolVar("q")
    let r = mkBoolVar("r")
    check ($mkAnd(p, q, r)) == "(and p q r)"

  test "mkAnd empty returns true":
    let ctx = newContext()
    check ($mkAnd()) == "true"

  test "mkAnd singleton returns the element unchanged":
    let ctx = newContext()
    let p = mkBoolVar("p")
    check astEqual(mkAnd(p), p)

  test "mkOr over a list":
    let ctx = newContext()
    let p = mkBoolVar("p")
    let q = mkBoolVar("q")
    check ($mkOr(p, q)) == "(or p q)"

  test "mkOr empty returns false":
    let ctx = newContext()
    check ($mkOr()) == "false"

suite "boolean — distinct":
  test "mkDistinct over Int":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let z = mkIntVar("z")
    check ($mkDistinct(x, y, z)) == "(distinct x y z)"

  test "mkDistinct over Bool":
    let ctx = newContext()
    let p = mkBoolVar("p")
    let q = mkBoolVar("q")
    check ($mkDistinct(p, q)) == "(distinct p q)"

suite "boolean — phantom-sort safety":
  test "and on Z3Int does NOT compile":
    let ctx = newContext()
    let x = mkIntVar("x")
    check not compiles(x and x)

  test "implies(Z3Int, _) does NOT compile":
    let ctx = newContext()
    let x = mkIntVar("x")
    let p = mkBoolVar("p")
    check not compiles(implies(x, p))

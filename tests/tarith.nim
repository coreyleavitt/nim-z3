## `z3/arith` tests — arithmetic, ordering, equality on Z3Int + Z3Real
## with literal-lift overloads, plus phantom-type safety.

import std/unittest
import z3

suite "arith — Int arithmetic":
  test "+, -, *, div, mod":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    check ($(x + y))    == "(+ x y)"
    check ($(x - y))    == "(- x y)"
    check ($(x * y))    == "(* x y)"
    check ($(x div y))  == "(div x y)"
    check ($(x mod y))  == "(mod x y)"

  test "unary minus":
    let ctx = newContext()
    let x = mkIntVar("x")
    check ($(-x)) == "(- x)"

  test "rem (separate from mod)":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    check ($rem(x, y)) == "(rem x y)"

suite "arith — Int literal lifts":
  test "Z3Int + int":
    let ctx = newContext()
    let x = mkIntVar("x")
    check ($(x + 3)) == "(+ x 3)"
    check ($(3 + x)) == "(+ 3 x)"

  test "Z3Int * int":
    let ctx = newContext()
    let x = mkIntVar("x")
    check ($(x * 2)) == "(* x 2)"
    check ($(2 * x)) == "(* 2 x)"

  test "Z3Int div int":
    let ctx = newContext()
    let x = mkIntVar("x")
    check ($(x div 5)) == "(div x 5)"

suite "arith — Real arithmetic":
  test "+, -, *, /":
    let ctx = newContext()
    let r = mkRealVar("r")
    let s = mkRealVar("s")
    check ($(r + s)) == "(+ r s)"
    check ($(r - s)) == "(- r s)"
    check ($(r * s)) == "(* r s)"
    check ($(r / s)) == "(/ r s)"

  test "unary minus on Real":
    let ctx = newContext()
    let r = mkRealVar("r")
    check ($(-r)) == "(- r)"

  test "Real literal lift (int → Real)":
    let ctx = newContext()
    let r = mkRealVar("r")
    check ($(r + 3)) == "(+ r 3.0)"
    check ($(3 + r)) == "(+ 3.0 r)"

suite "arith — ordering":
  test "Int <, <=, >, >=":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    check ($(x < y))  == "(< x y)"
    check ($(x <= y)) == "(<= x y)"
    check ($(x > y))  == "(> x y)"
    check ($(x >= y)) == "(>= x y)"

  test "Real <, <=, >, >=":
    let ctx = newContext()
    let r = mkRealVar("r")
    let s = mkRealVar("s")
    check ($(r < s))  == "(< r s)"
    check ($(r >= s)) == "(>= r s)"

  test "ordering literal lift (Int)":
    let ctx = newContext()
    let x = mkIntVar("x")
    check ($(x < 10))  == "(< x 10)"
    check ($(10 < x))  == "(< 10 x)"
    check ($(x >= 0))  == "(>= x 0)"

  test "ordering literal lift (Real)":
    let ctx = newContext()
    let r = mkRealVar("r")
    check ($(r > 0)) == "(> r 0.0)"

suite "arith — equality and inequality with lifts":
  test "Z3Int == Z3Int":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    check ($(x == y)) == "(= x y)"

  test "Z3Int == int (lift)":
    let ctx = newContext()
    let x = mkIntVar("x")
    check ($(x == 5)) == "(= x 5)"
    check ($(5 == x)) == "(= 5 x)"

  test "Z3Int != Z3Int":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    check ($(x != y)) == "(not (= x y))"

  test "Z3Int != int (lift)":
    let ctx = newContext()
    let x = mkIntVar("x")
    check ($(x != 0)) == "(not (= x 0))"

  test "Z3Real == int (lift)":
    let ctx = newContext()
    let r = mkRealVar("r")
    check ($(r == 1)) == "(= r 1.0)"

suite "arith — phantom-sort safety":
  test "Int + Bool does NOT compile":
    let ctx = newContext()
    let x = mkIntVar("x")
    let p = mkBoolVar("p")
    check not compiles(x + p)

  test "Bool < Bool does NOT compile":
    let ctx = newContext()
    let p = mkBoolVar("p")
    let q = mkBoolVar("q")
    check not compiles(p < q)

  test "Int < Real does NOT compile (sort mismatch even though both numeric)":
    let ctx = newContext()
    let x = mkIntVar("x")
    let r = mkRealVar("r")
    check not compiles(x < r)

  test "Int div Real does NOT compile":
    let ctx = newContext()
    let x = mkIntVar("x")
    let r = mkRealVar("r")
    check not compiles(x div r)

  test "Real div Real does NOT compile (use / for real division)":
    let ctx = newContext()
    let r = mkRealVar("r")
    let s = mkRealVar("s")
    check not compiles(r div s)

suite "arith — composite expressions":
  test "complex expression with multiple ops and lifts":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let expr = (x + y == 10) and (x > 3)
    check ($expr) == "(and (= (+ x y) 10) (> x 3))"

  test "negation + comparison + literal":
    let ctx = newContext()
    let x = mkIntVar("x")
    let expr = not (x == 0)
    check ($expr) == "(not (= x 0))"

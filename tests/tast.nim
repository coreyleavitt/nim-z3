## `z3/ast` + `z3/builder` tests — AST type, lifecycle, builders,
## phantom-type safety.

import std/unittest
import z3

suite "Z3Ast — boolean literals + variables":
  test "mkTrue, mkFalse, mkBool":
    let ctx = newContext()
    check ($mkTrue()) == "true"
    check ($mkFalse()) == "false"
    check ($mkBool(true)) == "true"
    check ($mkBool(false)) == "false"

  test "mkBoolVar produces a named free variable":
    let ctx = newContext()
    let p = mkBoolVar("p")
    check ($p) == "p"

suite "Z3Ast — integer literals + variables":
  test "mkInt literals":
    let ctx = newContext()
    check ($mkInt(0)) == "0"
    check ($mkInt(42)) == "42"
    check ($mkInt(-7)) == "(- 7)"  # SMT-LIB uses (- N) for negative literals

  test "mkBigInt handles values beyond int32":
    let ctx = newContext()
    let big = mkBigInt("123456789012345678901234567890")
    check ($big) == "123456789012345678901234567890"

  test "mkIntVar produces a named free variable":
    let ctx = newContext()
    let x = mkIntVar("x")
    check ($x) == "x"

suite "Z3Ast — real literals + variables":
  test "mkReal rationals":
    let ctx = newContext()
    check ($mkReal(1, 2)) == "(/ 1.0 2.0)"
    check ($mkReal(3, 4)) == "(/ 3.0 4.0)"

  test "mkReal int form":
    let ctx = newContext()
    check ($mkReal(7)) == "7.0"

  test "mkBigReal handles arbitrary-precision rationals":
    let ctx = newContext()
    check ($mkBigReal("355/113")) == "(/ 355.0 113.0)"

  test "mkRealVar produces a named free variable":
    let ctx = newContext()
    let y = mkRealVar("y")
    check ($y) == "y"

suite "Z3Ast — type aliases":
  test "Z3Int / Z3Real / Z3Bool resolve as expected":
    let ctx = newContext()
    proc takesInt(x: Z3Int) = discard
    proc takesReal(x: Z3Real) = discard
    proc takesBool(x: Z3Bool) = discard
    check compiles(takesInt(mkInt(1)))
    check compiles(takesReal(mkReal(1)))
    check compiles(takesBool(mkTrue()))
    check not compiles(takesInt(mkTrue()))
    check not compiles(takesBool(mkInt(1)))

suite "Z3Ast — phantom-type safety":
  test "Z3Ast[stInt] and Z3Ast[stBool] are distinct types":
    let ctx = newContext()
    proc takesIntAst(a: Z3Ast[stInt]) = discard
    proc takesBoolAst(a: Z3Ast[stBool]) = discard
    check compiles(takesIntAst(mkInt(0)))
    check compiles(takesBoolAst(mkTrue()))
    check not compiles(takesIntAst(mkTrue()))
    check not compiles(takesBoolAst(mkInt(0)))

  test "Z3Ast[stInt] and Z3Ast[stReal] are distinct types":
    let ctx = newContext()
    proc takesInt(a: Z3Ast[stInt]) = discard
    proc takesReal(a: Z3Ast[stReal]) = discard
    check not compiles(takesInt(mkReal(1)))
    check not compiles(takesReal(mkInt(1)))

suite "Z3Ast — lifecycle (refcount discipline)":
  # We can't easily inspect Z3's internal refcounts from the public
  # API, but the indirect proof is that the test suite runs many
  # builders + copies + destroys without crashing or producing
  # corrupted ASTs.

  test "100 ASTs construct and drop without crashing":
    let ctx = newContext()
    for i in 0 ..< 100:
      let x = mkInt(i)
      let y = mkIntVar("y_" & $i)
      check ($x).len > 0
      check ($y).len > 0

  test "copy via =copy preserves the underlying handle":
    let ctx = newContext()
    let x = mkIntVar("x")
    var y = x   # triggers =copy
    check astEqual(x, y)
    check ($x) == ($y)

  test "ASTs survive when their original goes out of scope (refcount works)":
    let ctx = newContext()
    var saved: Z3Int
    block:
      let local = mkInt(42)
      saved = local   # =copy bumps the ref; local's =destroy then drops it
    # If refcounting were wrong, the saved AST would now point at
    # freed memory; pretty-printing it would crash or produce garbage.
    check ($saved) == "42"

suite "Z3Ast — identity check":
  test "astEqual on the same builder result":
    let ctx = newContext()
    let a = mkInt(5)
    let b = a   # =copy: same underlying handle
    check astEqual(a, b)

  test "astEqual is true on structurally-identical separately-built ASTs":
    # Z3 hash-conses ASTs: building `mkInt(5)` twice returns the
    # same internal pointer. This is observable through astEqual.
    let ctx = newContext()
    let a = mkInt(5)
    let b = mkInt(5)
    check astEqual(a, b)

  test "astEqual is false on structurally-different ASTs":
    let ctx = newContext()
    let a = mkInt(5)
    let b = mkInt(6)
    check not astEqual(a, b)

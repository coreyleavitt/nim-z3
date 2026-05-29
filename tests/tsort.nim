## `z3/sort` tests — phantom-typed sort handles.

import std/unittest
import z3

suite "Z3Sort — construction":
  test "mkIntSort uses current context":
    let ctx = newContext()
    let s = mkIntSort()
    check not s.raw.isNil
    check s.ctx == ctx

  test "mkRealSort uses current context":
    let ctx = newContext()
    let s = mkRealSort()
    check not s.raw.isNil
    check s.ctx == ctx

  test "mkBoolSort uses current context":
    let ctx = newContext()
    let s = mkBoolSort()
    check not s.raw.isNil
    check s.ctx == ctx

  test "ctx.mkIntSort (explicit ctx via UFCS)":
    let outer = newContext()
    let scratch = newContext()
    # Two contexts coexist; explicit form picks scratch even though
    # currentContext() == scratch right now.
    setCurrentContext(outer)
    let s = scratch.mkIntSort()
    check s.ctx == scratch

suite "Z3Sort — pretty-print":
  test "$Int == \"Int\"":
    let ctx = newContext()
    check ($mkIntSort()) == "Int"

  test "$Real == \"Real\"":
    let ctx = newContext()
    check ($mkRealSort()) == "Real"

  test "$Bool == \"Bool\"":
    let ctx = newContext()
    check ($mkBoolSort()) == "Bool"

suite "Z3Sort — phantom-type discrimination":
  # These compile checks confirm the type system distinguishes
  # Z3Sort[stInt] from Z3Sort[stBool] etc. — a future caller can't
  # accidentally pass an Int sort where a Bool sort is expected.

  test "Z3Sort[stInt] and Z3Sort[stBool] are distinct types":
    let ctx = newContext()
    proc takesInt(s: Z3Sort[stInt]) = discard
    proc takesBool(s: Z3Sort[stBool]) = discard
    check compiles(takesInt(mkIntSort()))
    check compiles(takesBool(mkBoolSort()))
    check not compiles(takesInt(mkBoolSort()))
    check not compiles(takesBool(mkIntSort()))

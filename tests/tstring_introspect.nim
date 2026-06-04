## `z3/strings` — literal-AST introspection (N5.3).
##
## Covers:
##   - `getStringLength(s)` — codepoint count of a string literal AST.
##   - `getStringContents(s)` — codepoints of a string literal AST as
##                              a `seq[int]`.
##
## Both procs are only valid on literal string ASTs; they raise
## `Z3InvalidUsageError` when called on a symbolic string variable
## (mirrors the `toStr` contract).

import std/[unittest]
import z3

suite "Z3String — literal introspect (N5.3)":
  test "getStringLength(\"hello\") == 5":
    let ctx = newContext()
    check getStringLength(mkString("hello")) == 5

  test "getStringLength(\"\") == 0":
    let ctx = newContext()
    check getStringLength(mkString("")) == 0

  test "getStringContents(\"ABC\") == @[65, 66, 67]":
    let ctx = newContext()
    check getStringContents(mkString("ABC")) == @[65, 66, 67]

  test "getStringContents(\"Z\") == @[90]":
    let ctx = newContext()
    check getStringContents(mkString("Z")) == @[90]

  test "getStringContents(\"\") == @[]":
    let ctx = newContext()
    check getStringContents(mkString("")) == newSeq[int]()

  test "getStringLength on symbolic var raises Z3InvalidUsageError":
    let ctx = newContext()
    let x = mkStringVar("x")
    expect Z3InvalidUsageError:
      discard getStringLength(x)

  test "getStringContents on symbolic var raises Z3InvalidUsageError":
    let ctx = newContext()
    let x = mkStringVar("x")
    expect Z3InvalidUsageError:
      discard getStringContents(x)

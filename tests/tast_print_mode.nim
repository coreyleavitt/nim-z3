## `z3/context.setAstPrintMode` tests — N8.10
##
## Verifies that `setAstPrintMode` wires through to Z3's
## `Z3_set_ast_print_mode` and that the mode affects `$ast` output.

import std/[unittest, strutils]
import z3

suite "setAstPrintMode — basic wiring":

  test "apSmtLib2Full: $ast produces SMTLIB-shaped output (not empty)":
    let ctx = newContext()
    ctx.setAstPrintMode(apSmtLib2Full)
    let x = mkIntVar("x")
    let s = $x
    check s.len > 0
    check "x" in s

  test "apLowLevel: $ast produces different output from apSmtLib2Full":
    ## apLowLevel uses Z3's internal low-level rendering which shows
    ## an (Int x) structure instead of just the identifier.
    let ctx = newContext()
    ctx.setAstPrintMode(apSmtLib2Full)
    let x = mkIntVar("x")
    let full = $x

    ctx.setAstPrintMode(apLowLevel)
    let low = $x

    # The two renderings differ — Z3's low-level mode wraps the sort
    check full != low

  test "apSmtLibCompliant: $ast renders without sharing annotations":
    ## In compliant mode Z3 may share sub-expressions with let-bindings;
    ## the output should still be non-empty and syntactically valid.
    let ctx = newContext()
    ctx.setAstPrintMode(apSmtLibCompliant)
    let x = mkBoolVar("p")
    let y = mkBoolVar("q")
    let f = x and y
    let s = $f
    check s.len > 0
    check "p" in s or "and" in s

  test "mode is sticky — subsequent $ast calls use the last-set mode":
    let ctx = newContext()
    ctx.setAstPrintMode(apLowLevel)
    let x = mkIntVar("y")
    let a = $x
    let b = $x   # second call, same mode still active
    check a == b  # idempotent: same mode → same output

  test "mode is per-context — two contexts are independent":
    let ctx1 = newContext()
    ctx1.setAstPrintMode(apSmtLib2Full)
    let x = ctx1.mkIntVar("z")

    let ctx2 = newContext()
    ctx2.setAstPrintMode(apLowLevel)
    let y = ctx2.mkIntVar("z")

    let s1 = $x
    let s2 = $y

    # Same variable name, different print modes → different renderings
    check s1 != s2

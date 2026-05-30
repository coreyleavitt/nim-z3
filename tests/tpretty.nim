## `z3/pretty` tests — indented multi-line SMT-LIB rendering, SMT2
## script emission, and SMT2 parsing round-trips.

import std/[unittest, strutils, os, tempfiles]
import z3

suite "pretty — tracer":
  test "pretty inserts newlines for nested forms; $ stays flat":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let z = mkIntVar("z")
    let big = (x > 0) and (y < 0) and (z == x + y)
    let p = pretty(big, indent = 2, width = 20)
    check '\n' in p
    check '\n' notin $big

  test "small term fits on one line (no newlines)":
    let ctx = newContext()
    let x = mkIntVar("x")
    let p = pretty(x + 1, width = 80)
    check '\n' notin p
    # And it's semantically equivalent to the flat form (modulo whitespace).
    check p.replace(" ", "") == ($(x + 1)).replace(" ", "")

  test "narrow width forces stacking with indentation":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let p = pretty((x > 0) and (y < 0), indent = 2, width = 10)
    # Stacked form: opening "(and" on the first line, each child indented.
    let lines = p.splitLines
    check lines.len >= 3
    check lines[0].startsWith("(and")
    # Each child line is indented by `indent` (= 2) relative to opening.
    check lines[1].startsWith("  ")

  test "custom indent is respected":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let p = pretty((x > 0) and (y < 0), indent = 4, width = 10)
    let lines = p.splitLines
    check lines[1].startsWith("    ")   # 4-space indent

  test "input with no parens is unchanged":
    let ctx = newContext()
    let p = pretty(mkIntVar("hello"))
    check p == "hello"

  test "tokeniser preserves string literals containing parens":
    # A pathological case: a string-literal atom that *contains* parens.
    # The tokeniser must not break it.
    let out1 = reformat("""(model (define-fun s () String "(a b)"))""", 2, 80)
    check """"(a b)"""" in out1

  test "pretty(solver) shows each assertion on its own block":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let s = newSolver()
    s.add x > 0
    s.add y < 0
    s.add (x + y) == 100
    let p = pretty(s, width = 40)
    # Multi-assertion solvers always break across lines.
    check p.count('\n') >= 2

  test "pretty(model) shows each variable assignment on its own line":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let s = newSolver()
    s.add x == 42
    s.add y == 100
    discard s.check()
    let m = s.model()
    let p = pretty(m, width = 40)
    check p.count('\n') >= 1

# SMT2 round-trip + writeSmt2 tests live in `tests/tio.nim` after
# the v0.4 step 14 relocation of the SMT2 surface to `z3/io`.

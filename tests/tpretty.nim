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

suite "smt2Script":
  test "ends with (check-sat)":
    let ctx = newContext()
    let x = mkIntVar("x")
    let s = newSolver()
    s.add x > 0
    let script = smt2Script(s)
    check script.strip.endsWith("(check-sat)")

  test "includes declarations for free constants":
    let ctx = newContext()
    let x = mkIntVar("xyz")
    let s = newSolver()
    s.add x > 0
    let script = smt2Script(s)
    check "declare" in script
    check "xyz" in script

  test "writeSmt2 writes a non-empty file":
    let ctx = newContext()
    let x = mkIntVar("x")
    let s = newSolver()
    s.add x > 0
    let (_, path) = createTempFile("z3-test-", ".smt2")
    defer: removeFile(path)
    writeSmt2(s, path)
    let body = readFile(path)
    check body.len > 0
    check body.strip.endsWith("(check-sat)")

suite "parseSmt2":
  test "parses a simple assertion":
    let ctx = newContext()
    let asserts = parseSmt2(ctx, "(declare-const x Int) (assert (> x 0))")
    check asserts.len == 1

  test "parsed assertion is usable in a fresh solver":
    let ctx = newContext()
    let asserts = parseSmt2(ctx, "(declare-const x Int) (assert (> x 0))")
    let s = newSolver()
    for a in asserts:
      s.add a
    check s.check() == zsSat

  test "round-trip: smt2Script -> parseSmt2 preserves satisfiability":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let s1 = newSolver()
    s1.add x + y == 10
    s1.add x > 3
    let satOrig = s1.check()

    let script = smt2Script(s1)
    let asserts = parseSmt2(ctx, script)
    let s2 = newSolver()
    for a in asserts:
      s2.add a
    check s2.check() == satOrig
    check s2.check() == zsSat

  test "round-trip preserves unsat":
    let ctx = newContext()
    let x = mkIntVar("x")
    let s1 = newSolver()
    s1.add x > 10
    s1.add x < 5
    let script = smt2Script(s1)
    let asserts = parseSmt2(ctx, script)
    let s2 = newSolver()
    for a in asserts:
      s2.add a
    check s2.check() == zsUnsat

  test "parseSmt2 raises Z3Error on garbage input":
    let ctx = newContext()
    expect Z3Error:
      discard parseSmt2(ctx, "this is not smt-lib at all (((")

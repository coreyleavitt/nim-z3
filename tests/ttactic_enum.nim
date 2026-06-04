## N8.5 — Tactic / probe / simplifier enumeration tests.
##
## Verifies that Z3's built-in enumeration API surfaces the expected
## counts and well-known names for tactics, probes, and simplifiers.

import std/[unittest]
import z3

suite "tactic enumeration":
  test "numTactics returns a positive count":
    let ctx = newContext()
    check numTactics(ctx) > 0

  test "allTacticNames contains well-known tactics":
    let ctx = newContext()
    let names = allTacticNames(ctx)
    check names.len == numTactics(ctx)
    check "simplify" in names
    check "smt" in names
    check "qe" in names

suite "probe enumeration":
  test "numProbes returns a positive count":
    let ctx = newContext()
    check numProbes(ctx) > 0

  test "allProbeNames contains well-known probes":
    let ctx = newContext()
    let names = allProbeNames(ctx)
    check names.len == numProbes(ctx)
    check "size" in names
    check "depth" in names

suite "simplifier enumeration":
  test "numSimplifiers returns a positive count (Z3 4.12+)":
    let ctx = newContext()
    # Z3_get_num_simplifiers was introduced in Z3 4.12; this build ships
    # 25 simplifiers — document that the call is safe and returns > 0.
    check numSimplifiers(ctx) > 0

  test "allSimplifierNames contains well-known simplifiers":
    let ctx = newContext()
    let names = allSimplifierNames(ctx)
    check names.len == numSimplifiers(ctx)
    check "bit-blast" in names
    check "elim-term-ite" in names

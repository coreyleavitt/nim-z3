## `z3/strings` ordering tests — N5.1 slice.
##
## Covers `<`, `<=`, `>`, `>=` on `Z3String` (lexicographic order).
## `<` and `<=` wrap `Z3_mk_str_lt` / `Z3_mk_str_le` directly.
## `>` and `>=` are derived by swapping arguments.

import std/[unittest]
import z3

# ── helpers ──────────────────────────────────────────────────────────────────

proc sat(p: Z3Bool): bool =
  let s = newSolver(p.ctx)
  s.add p
  s.check() == zsSat

proc unsat(p: Z3Bool): bool =
  let s = newSolver(p.ctx)
  s.add p
  s.check() == zsUnsat

# ── tests ─────────────────────────────────────────────────────────────────────

suite "Z3String — ordering":
  test "< strict: abc < abd is SAT":
    let ctx = newContext()
    check sat(mkString("abc") < mkString("abd"))

  test "< strict: abc < abc is UNSAT":
    let ctx = newContext()
    check unsat(mkString("abc") < mkString("abc"))

  test "<= reflexive: abc <= abc is SAT":
    let ctx = newContext()
    check sat(mkString("abc") <= mkString("abc"))

  test "> derived: abc > abb is SAT":
    let ctx = newContext()
    check sat(mkString("abc") > mkString("abb"))

  test ">= reflexive: abc >= abc is SAT":
    let ctx = newContext()
    check sat(mkString("abc") >= mkString("abc"))

  test "symbolic: exists s such that s < \"z\" (length-1 prefix SAT model)":
    let ctx = newContext()
    let s = mkStringVar("s")
    # Length = 1 keeps the query tractable for the incomplete string solver.
    let constraint = (s < mkString("z")) and (s.len == mkInt(1))
    let sol = newSolver()
    sol.add constraint
    check sol.check() == zsSat

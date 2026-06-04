## Pseudo-boolean cardinality constraints: atMost, atLeast, pbLe, pbGe, pbEq.
##
## These map directly to Z3's `Z3_mk_atmost`, `Z3_mk_atleast`,
## `Z3_mk_pble`, `Z3_mk_pbge`, `Z3_mk_pbeq`.

import std/unittest
import z3

suite "pseudo-boolean — atMost / atLeast":
  test "atMost(1): UNSAT when two of a/b/c are forced true":
    let ctx = newContext()
    let a = mkBoolVar("a")
    let b = mkBoolVar("b")
    let c = mkBoolVar("c")
    let s = newSolver()
    s.add atMost([a, b, c], 1'u)
    s.add a
    s.add b
    check s.check() == zsUnsat

  test "atMost(1): SAT when only one of a/b/c is true":
    let ctx = newContext()
    let a = mkBoolVar("a")
    let b = mkBoolVar("b")
    let c = mkBoolVar("c")
    let s = newSolver()
    s.add atMost([a, b, c], 1'u)
    s.add a
    s.add(not b)
    s.add(not c)
    check s.check() == zsSat

  test "atLeast(2): SAT when two of a/b/c are forced true":
    let ctx = newContext()
    let a = mkBoolVar("a")
    let b = mkBoolVar("b")
    let c = mkBoolVar("c")
    let s = newSolver()
    s.add atLeast([a, b, c], 2'u)
    s.add a
    s.add b
    check s.check() == zsSat

  test "atLeast(2): UNSAT when only one of a/b/c can be true":
    let ctx = newContext()
    let a = mkBoolVar("a")
    let b = mkBoolVar("b")
    let c = mkBoolVar("c")
    let s = newSolver()
    s.add atLeast([a, b, c], 2'u)
    s.add a
    s.add(not b)
    s.add(not c)
    check s.check() == zsUnsat

suite "pseudo-boolean — pbLe / pbGe / pbEq":
  test "pbLe: weights [1,2,3] <= 3 — SAT when a+b (weight 3) selected":
    ## a=T, b=T, c=F → 1+2 = 3 ≤ 3  ✓
    let ctx = newContext()
    let a = mkBoolVar("a")
    let b = mkBoolVar("b")
    let c = mkBoolVar("c")
    let s = newSolver()
    s.add pbLe([a, b, c], [1, 2, 3], 3)
    s.add a
    s.add b
    s.add(not c)
    check s.check() == zsSat

  test "pbLe: weights [1,2,3] <= 3 — SAT when c alone (weight 3) selected":
    ## a=F, b=F, c=T → 3 ≤ 3  ✓
    let ctx = newContext()
    let a = mkBoolVar("a")
    let b = mkBoolVar("b")
    let c = mkBoolVar("c")
    let s = newSolver()
    s.add pbLe([a, b, c], [1, 2, 3], 3)
    s.add(not a)
    s.add(not b)
    s.add c
    check s.check() == zsSat

  test "pbLe: weights [1,2,3] <= 3 — UNSAT when b+c (weight 5) selected":
    ## a=F, b=T, c=T → 2+3 = 5 > 3  ✗
    let ctx = newContext()
    let a = mkBoolVar("a")
    let b = mkBoolVar("b")
    let c = mkBoolVar("c")
    let s = newSolver()
    s.add pbLe([a, b, c], [1, 2, 3], 3)
    s.add(not a)
    s.add b
    s.add c
    check s.check() == zsUnsat

  test "pbEq: weights [1,1] = 1 — UNSAT when both a and b are true":
    let ctx = newContext()
    let a = mkBoolVar("a")
    let b = mkBoolVar("b")
    let s = newSolver()
    s.add pbEq([a, b], [1, 1], 1)
    s.add a
    s.add b
    check s.check() == zsUnsat

  test "pbEq: weights [1,1] = 1 — SAT when only a is true":
    let ctx = newContext()
    let a = mkBoolVar("a")
    let b = mkBoolVar("b")
    let s = newSolver()
    s.add pbEq([a, b], [1, 1], 1)
    s.add a
    s.add(not b)
    check s.check() == zsSat

  test "pbGe: weights [1,2,3] >= 4 — SAT when b+c (weight 5) selected":
    let ctx = newContext()
    let a = mkBoolVar("a")
    let b = mkBoolVar("b")
    let c = mkBoolVar("c")
    let s = newSolver()
    s.add pbGe([a, b, c], [1, 2, 3], 4)
    s.add(not a)
    s.add b
    s.add c
    check s.check() == zsSat

  test "pbGe: weights [1,2,3] >= 4 — UNSAT when only a+b (weight 3)":
    let ctx = newContext()
    let a = mkBoolVar("a")
    let b = mkBoolVar("b")
    let c = mkBoolVar("c")
    let s = newSolver()
    s.add pbGe([a, b, c], [1, 2, 3], 4)
    s.add a
    s.add b
    s.add(not c)
    check s.check() == zsUnsat

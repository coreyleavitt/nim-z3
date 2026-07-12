## Minimal-build smoke test (v0.5 step 10).
##
## Exercises the **core** surface — Int, Bool, BV, Solver, Model —
## under the full set of `z3WithoutX` feature flags so the test
## verifies the umbrella module still exposes the core capabilities
## when every gated theory is hidden.
##
## Compile with:
##
## ```
## nim c -r --threads:on \
##     -d:z3WithoutFP -d:z3WithoutSeq -d:z3WithoutStrings \
##     -d:z3WithoutRegex -d:z3WithoutFuncDecl -d:z3WithoutDatatypes \
##     -d:z3WithoutOptimize -d:z3WithoutTactics \
##     tests/tminimal.nim
## ```
##
## Run via `nimble test-minimal` to get the canonical config.
##
## The test also asserts the **scope-hiding** invariant: gated
## families are not in scope via `import z3`. Compile-time
## `compiles()` checks pin this — if a gated identifier becomes
## reachable through the umbrella, the test catches it.

import std/[unittest]
import z3

suite "minimal build — core surface still works":
  test "Int arithmetic + solver + model round-trip":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let s = newSolver()
    s.add (x + y == mkInt(10)) and (x > mkInt(3))
    check s.check() == zsSat
    let m = s.model()
    check m.evalInt(x) + m.evalInt(y) == 10
    check m.evalInt(x) > 3

  test "Bool operators + Z3Status":
    let ctx = newContext()
    let p = mkBoolVar("p")
    let s = newSolver()
    s.add p and (not p)
    check s.check() == zsUnsat

  test "BV width-typed concat":
    let ctx = newContext()
    let lo = mkBitVecVar[4]("lo")
    let hi = mkBitVecVar[4]("hi")
    let s = newSolver()
    s.add concat(hi, lo) == mkBitVec[8](0xAB'u32)
    check s.check() == zsSat
    let m = s.model()
    check m[hi].toUint == 0xA
    check m[lo].toUint == 0xB

  test "SMT-LIB2 round-trip works without theory extensions":
    let ctx = newContext()
    let x = mkIntVar("x")
    let s = newSolver()
    s.add x == mkInt(42)
    let script = smt2Script(s)
    let asserts = parseSmt2String(ctx, script)
    let s2 = newSolver()
    for a in asserts: s2.add a
    check s2.check() == zsSat
    check s2.model().evalInt(x) == 42

suite "minimal build — scope-hiding invariants":
  test "Z3Fp is not in scope when z3WithoutFP":
    when defined(z3WithoutFP):
      check not compiles(mkFloat32(0.0'f32))
    else:
      check compiles(mkFloat32(0.0'f32))

  test "Z3Seq is not in scope when z3WithoutSeq":
    when defined(z3WithoutSeq):
      check not compiles(mkSeqEmpty[Z3Int]())
    else:
      check compiles(mkSeqEmpty[Z3Int]())

  test "Z3FuncDecl is not in scope when z3WithoutFuncDecl":
    when defined(z3WithoutFuncDecl):
      check not compiles(mkFuncDecl[(Z3Int,), Z3Int]("f"))
    else:
      check compiles(mkFuncDecl[(Z3Int,), Z3Int]("f"))

  test "Z3Optimize is not in scope when z3WithoutOptimize":
    when defined(z3WithoutOptimize):
      check not compiles(newOptimize())
    else:
      check compiles(newOptimize())

  test "Z3Tactic is not in scope when z3WithoutTactics":
    when defined(z3WithoutTactics):
      check not compiles(mkTactic("simplify"))
    else:
      check compiles(mkTactic("simplify"))

  test "typed fixedpoint callbacks are not in scope when z3WithoutFixedpointCallbacks":
    when defined(z3WithoutFixedpointCallbacks):
      check not compiles((var h: Z3FixedpointHandlers))
    else:
      check compiles((var h: Z3FixedpointHandlers))

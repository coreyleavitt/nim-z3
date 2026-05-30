## `z3/array` tests — phantom-typed Z3Array[Key, Val] with store /
## select / mkConstArray / extensionality via `==`.

import std/[unittest]
import proptest
import z3
import ./recipes

suite "Z3Array — tracer":
  test "store then select round-trips a stored value":
    let ctx = newContext()
    let a = mkArrayVar[Z3Int, Z3Int]("a")
    let stored = a.store(mkInt(5), mkInt(42))
    check smtEquiv(stored.select(mkInt(5)), mkInt(42))

  test "mkConstArray returns default at every index":
    let ctx = newContext()
    let a = mkConstArray[Z3Int, Z3Int](mkInt(99))
    check smtEquiv(a[mkInt(0)], mkInt(99))
    check smtEquiv(a[mkInt(7)], mkInt(99))
    check smtEquiv(a[mkInt(-3)], mkInt(99))

  test "store at i doesn't affect select at j (i != j)":
    let ctx = newContext()
    let a = mkConstArray[Z3Int, Z3Int](mkInt(0))
    let a2 = a.store(mkInt(5), mkInt(42))
    # Reading index 7 from the updated array still gives the default 0,
    # because store at 5 doesn't touch index 7.
    check smtEquiv(a2[mkInt(7)], mkInt(0))

suite "Z3Array — phantom type preservation":
  test "select(Z3Array[Z3Int, Z3Int], Z3Int) is Z3Int":
    let ctx = newContext()
    let a = mkArrayVar[Z3Int, Z3Int]("a")
    let r = a[mkInt(0)]
    check r is Z3Int

  test "select(Z3Array[Z3Int, Z3Bool], Z3Int) is Z3Bool":
    let ctx = newContext()
    let a = mkArrayVar[Z3Int, Z3Bool]("a")
    let r = a[mkInt(0)]
    check r is Z3Bool

  test "select on BV-keyed BV-valued array preserves BV widths":
    let ctx = newContext()
    let mem = mkArrayVar[Z3BitVec[32], Z3BitVec[8]]("mem")
    let r = mem[mkBitVec(0'u32, 32)]
    check r is Z3BitVec[8]

suite "Z3Array — memory model (BV[32] → BV[8])":
  test "store-and-read round-trips a byte":
    let ctx = newContext()
    let mem = mkConstArray[Z3BitVec[32], Z3BitVec[8]](mkBitVec(0'u8, 8))
    let mem2 = mem.store(mkBitVec(0x1000'u32, 32), mkBitVec(0xAB'u8, 8))
    check smtEquiv(mem2[mkBitVec(0x1000'u32, 32)], mkBitVec(0xAB'u8, 8))

  test "two stores at distinct addresses don't collide":
    let ctx = newContext()
    let mem = mkConstArray[Z3BitVec[32], Z3BitVec[8]](mkBitVec(0'u8, 8))
    let mem2 = mem
      .store(mkBitVec(0x100'u32, 32), mkBitVec(0xAA'u8, 8))
      .store(mkBitVec(0x200'u32, 32), mkBitVec(0xBB'u8, 8))
    check smtEquiv(mem2[mkBitVec(0x100'u32, 32)], mkBitVec(0xAA'u8, 8))
    check smtEquiv(mem2[mkBitVec(0x200'u32, 32)], mkBitVec(0xBB'u8, 8))
    check smtEquiv(mem2[mkBitVec(0x300'u32, 32)], mkBitVec(0x00'u8, 8))

suite "Z3Array — solver integration":
  test "free array with constrained index solves":
    let ctx = newContext()
    let a = mkArrayVar[Z3Int, Z3Int]("a")
    let i = mkIntVar("i")
    let s = newSolver()
    s.add a[i] == mkInt(42)
    s.add i == mkInt(7)
    check s.check() == zsSat
    # The model must satisfy a[7] = 42.
    let m = s.model()
    check m.evalInt(m[a[i]]) == 42

  test "contradictory store/select is unsat":
    let ctx = newContext()
    let a = mkArrayVar[Z3Int, Z3Int]("a")
    let s = newSolver()
    s.add a.store(mkInt(0), mkInt(1))[mkInt(0)] == mkInt(2)
    check s.check() == zsUnsat

suite "Z3Array — read-over-write axioms (random shapes)":
  test "select(store(a, i, v), i) ≡ v":
    let ctx = newContext()
    let a = mkArrayVar[Z3Int, Z3Int]("a")
    let prop = proc(t: (IntRecipe, IntRecipe)) =
      let i = interpret(t[0], ctx)
      let v = interpret(t[1], ctx)
      ensure smtEquiv(a.store(i, v)[i], v)
    let report = forAll(
      tuples2(intRecipes(maxDepth = 2), intRecipes(maxDepth = 2)),
      prop, fewExamples())
    check report.outcome == otPassed

  test "select(store(a, i, v), j) ≡ ite(i == j, v, select(a, j))":
    let ctx = newContext()
    let a = mkArrayVar[Z3Int, Z3Int]("a")
    let prop = proc(t: ((IntRecipe, IntRecipe), IntRecipe)) =
      let i = interpret(t[0][0], ctx)
      let j = interpret(t[0][1], ctx)
      let v = interpret(t[1], ctx)
      let lhs = a.store(i, v)[j]
      let rhs = ite(i == j, v, a[j])
      ensure smtEquiv(lhs, rhs)
    let report = forAll(
      tuples2(
        tuples2(intRecipes(maxDepth = 2), intRecipes(maxDepth = 2)),
        intRecipes(maxDepth = 2)),
      prop, fewExamples())
    check report.outcome == otPassed

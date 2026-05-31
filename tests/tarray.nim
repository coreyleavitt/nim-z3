## `z3/arrays` tests — phantom-typed Z3Array[Key, Val] with store /
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
    let r = mem[mkBitVec[32](0'u32)]
    check r is Z3BitVec[8]

suite "Z3Array — memory model (BV[32] → BV[8])":
  test "store-and-read round-trips a byte":
    let ctx = newContext()
    let mem = mkConstArray[Z3BitVec[32], Z3BitVec[8]](mkBitVec[8](0'u8))
    let mem2 = mem.store(mkBitVec[32](0x1000'u32), mkBitVec[8](0xAB'u8))
    check smtEquiv(mem2[mkBitVec[32](0x1000'u32)], mkBitVec[8](0xAB'u8))

  test "two stores at distinct addresses don't collide":
    let ctx = newContext()
    let mem = mkConstArray[Z3BitVec[32], Z3BitVec[8]](mkBitVec[8](0'u8))
    let mem2 = mem
      .store(mkBitVec[32](0x100'u32), mkBitVec[8](0xAA'u8))
      .store(mkBitVec[32](0x200'u32), mkBitVec[8](0xBB'u8))
    check smtEquiv(mem2[mkBitVec[32](0x100'u32)], mkBitVec[8](0xAA'u8))
    check smtEquiv(mem2[mkBitVec[32](0x200'u32)], mkBitVec[8](0xBB'u8))
    check smtEquiv(mem2[mkBitVec[32](0x300'u32)], mkBitVec[8](0x00'u8))

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

suite "Z3Array — nested arrays (v0.3 step 9 closes v0.2 §8 deferral)":
  test "Z3Array[Z3Int, Z3Array[Z3Int, Z3Int]] round-trips through store+select":
    # v0.2 §8 deferred nested arrays citing 'typedesc-reflection limit'.
    # Step 9's mixin-based sortOf dispatch closes that gap — the outer
    # array's sortOf[K, V] now recurses through sortOfType[V] for any V
    # that has a sortOf overload in scope, including Z3Array itself.
    let ctx = newContext()
    let outer = mkArrayVar[Z3Int, Z3Array[Z3Int, Z3Int]]("outer")
    let inner0 = mkConstArray[Z3Int, Z3Int](mkInt(0))
    let inner0_at_5_is_42 = inner0.store(mkInt(5), mkInt(42))
    let outer1 = outer.store(mkInt(0), inner0_at_5_is_42)
    let s = newSolver()
    s.add outer1.select(mkInt(0)).select(mkInt(5)) == mkInt(42)
    check s.check() == zsSat

suite "Z3Array — arrayDefault (v1.0 audit round 2, HIGH #3)":
  test "arrayDefault on mkConstArray returns the constant value":
    let ctx = newContext()
    let arr = mkConstArray[Z3Int, Z3Int](mkInt(42))
    check smtValid(arrayDefault(arr) == mkInt(42))

  test "arrayDefault on store(constArr, k, v) is unchanged":
    let ctx = newContext()
    let arr = mkConstArray[Z3Int, Z3Int](mkInt(7))
    let arr2 = arr.store(mkInt(0), mkInt(99))
    check smtValid(arrayDefault(arr2) == mkInt(7))

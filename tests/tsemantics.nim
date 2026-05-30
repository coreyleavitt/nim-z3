## Tests for `z3/semantics` (generic `smtEquiv` over typed families)
## and the generalised `Z3Model.eval[T]` / `[][T]` covering
## `Z3Array[K, V]` and `Z3DatatypeValue[T]`.

import std/[unittest]
import z3

type ListMarker = object   # marker for the IntList datatype below

suite "smtEquiv — generic over typed families":
  test "smtEquiv works for Z3Array[Z3Int, Z3Int]":
    let ctx = newContext()
    let a = mkArrayVar[Z3Int, Z3Int]("a")
    let i = mkIntVar("i")
    let v = mkIntVar("v")
    # store-then-select is the value, regardless of how arrived at
    check smtEquiv(a.store(i, v)[i], v)

  test "smtEquiv works for Z3DatatypeValue[T]":
    let ctx = newContext()
    let L = declareDatatype[ListMarker](@[
      constructor("nilL"),
      constructor("consL", @[field("head", Z3Int), selfField("tail")])
    ])
    let nilC = L.con("nilL").apply()
    let consC = L.con("consL")
    let head = L.accessor("consL", "head", Z3Int)
    let v = consC.apply(mkInt(42), nilC)
    # Reading head gives back 42 in the same context
    check smtEquiv(head.read(v), mkInt(42))

suite "Z3Model.eval — generic across families":
  test "eval[Z3Array]: round-trip a constrained array variable":
    let ctx = newContext()
    let a = mkArrayVar[Z3Int, Z3Int]("a")
    let s = newSolver()
    s.add a[mkInt(0)] == mkInt(7)
    s.add a[mkInt(1)] == mkInt(8)
    check s.check() == zsSat
    let m = s.model()
    # m.eval(a) gives back an array AST; verifying via select
    let aEval = m.eval(a)
    check smtEquiv(aEval[mkInt(0)], mkInt(7))
    check smtEquiv(aEval[mkInt(1)], mkInt(8))

  test "m[arr] sugar works":
    let ctx = newContext()
    let a = mkArrayVar[Z3Int, Z3Int]("a")
    let s = newSolver()
    s.add a[mkInt(5)] == mkInt(42)
    check s.check() == zsSat
    let m = s.model()
    let aEval = m[a]
    check smtEquiv(aEval[mkInt(5)], mkInt(42))

  test "eval[Z3DatatypeValue]: round-trip an asserted constructor":
    let ctx = newContext()
    let L = declareDatatype[ListMarker](@[
      constructor("nilL"),
      constructor("consL", @[field("head", Z3Int), selfField("tail")])
    ])
    let x = L.mkDatatypeVar("x")
    let consC = L.con("consL")
    let nilC = L.con("nilL")
    let isCons = L.recognizer("consL")
    let head = L.accessor("consL", "head", Z3Int)
    let s = newSolver()
    s.add isCons.test(x)
    s.add head.read(x) == mkInt(99)
    check s.check() == zsSat
    let m = s.model()
    let xEval = m.eval(x)
    check smtValid(isCons.test(xEval))
    check smtEquiv(head.read(xEval), mkInt(99))

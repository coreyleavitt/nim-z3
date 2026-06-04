## `z3/funcdecl` tests — uninterpreted function declarations.

import std/[unittest]
import z3

suite "Z3FuncDecl — tracer":
  test "unary Int → Int function: assert f(0) == 42, model gives 42":
    let ctx = newContext()
    let f = mkFuncDecl[(Z3Int,), Z3Int]("f")
    let s = newSolver()
    s.add f(mkInt(0)) == mkInt(42)
    check s.check() == zsSat
    let m = s.model()
    check m.evalAt(f, (mkInt(0),)).toInt64 == 42

suite "Z3FuncDecl — arity variations":
  test "nullary (constant) — Z3FuncDecl[(), Z3Int]":
    let ctx = newContext()
    let c = mkFuncDecl[(), Z3Int]("c")
    let s = newSolver()
    s.add c() == mkInt(7)
    check s.check() == zsSat
    let m = s.model()
    check m.evalAt(c, ()).toInt64 == 7

  test "binary — Z3FuncDecl[(Z3Int, Z3Int), Z3Bool]":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int, Z3Int), Z3Bool]("p")
    let s = newSolver()
    s.add p(mkInt(1), mkInt(2))
    s.add not p(mkInt(3), mkInt(4))
    check s.check() == zsSat
    let m = s.model()
    check m.evalAt(p, (mkInt(1), mkInt(2))).toBool == true
    check m.evalAt(p, (mkInt(3), mkInt(4))).toBool == false

  test "arity-3 with mixed sorts — (Z3Int, Z3Bool, Z3Real) → Z3Int":
    let ctx = newContext()
    let g = mkFuncDecl[(Z3Int, Z3Bool, Z3Real), Z3Int]("g")
    let s = newSolver()
    s.add g(mkInt(1), mkTrue(), mkReal(1, 2)) == mkInt(100)
    check s.check() == zsSat
    let m = s.model()
    check m.evalAt(g, (mkInt(1), mkTrue(), mkReal(1, 2))).toInt64 == 100

suite "Z3FuncDecl — application syntax":
  test "f(x, y) and f.apply(x, y) produce equivalent ASTs":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int, Z3Int), Z3Bool]("p")
    # Both invocation styles should produce semantically equal ASTs.
    check smtValid(p(mkInt(1), mkInt(2)) == p.apply(mkInt(1), mkInt(2)))

suite "Z3FuncDecl — composition":
  test "f(g(x)) — uninterpreted functions compose with concrete witnesses":
    let ctx = newContext()
    let f = mkFuncDecl[(Z3Int,), Z3Int]("f")
    let g = mkFuncDecl[(Z3Int,), Z3Int]("g")
    let s = newSolver()
    # Pin g(0) = 99 and require f(g(0)) = 42; solver derives f(99) = 42.
    s.add g(mkInt(0)) == mkInt(99)
    s.add f(g(mkInt(0))) == mkInt(42)
    check s.check() == zsSat
    let m = s.model()
    check m.evalAt(g, (mkInt(0),)).toInt64 == 99
    check m.evalAt(f, (mkInt(99),)).toInt64 == 42

suite "Z3FuncDecl — element-type coverage":
  test "Z3BitVec[W] arg + return":
    let ctx = newContext()
    let h = mkFuncDecl[(Z3BitVec[8],), Z3BitVec[8]]("h")
    let s = newSolver()
    s.add h(mkBitVec[8](1'u8)) == mkBitVec[8](2'u8)
    check s.check() == zsSat
    let m = s.model()
    check m.evalAt(h, (mkBitVec[8](1'u8),)).toUint == 2'u64

  test "Z3String arg + return":
    let ctx = newContext()
    let upper = mkFuncDecl[(Z3String,), Z3String]("upper")
    let s = newSolver()
    s.add upper(mkString("hi")) == mkString("HI")
    check s.check() == zsSat
    let m = s.model()
    check m.evalAt(upper, (mkString("hi"),)).toStr == "HI"

  test "Z3Fp arg + return":
    let ctx = newContext()
    let q = mkFuncDecl[(Z3Float32,), Z3Float32]("q")
    let s = newSolver()
    s.add q(mkFloat32(1.0'f32)) == mkFloat32(2.0'f32)
    check s.check() == zsSat
    let m = s.model()
    check m.evalAt(q, (mkFloat32(1.0'f32),)).toFloat32 == 2.0'f32

  test "Z3Seq element type":
    let ctx = newContext()
    let r = mkFuncDecl[(Z3Seq[Z3Int],), Z3Int]("r")
    let s = newSolver()
    let oneTwo = concat(mkSeqUnit(mkInt(1)), mkSeqUnit(mkInt(2)))
    s.add r(oneTwo) == mkInt(12)
    check s.check() == zsSat
    let m = s.model()
    check m.evalAt(r, (oneTwo,)).toInt64 == 12

suite "Z3FuncDecl — sort safety":
  test "passing wrong-sort args is a compile error":
    let f = mkFuncDecl[(Z3Int,), Z3Int]("f")
    # Calling with a Z3Bool where Z3Int expected mustn't compile.
    check not compiles((f(mkTrue())))
    # Right sort compiles.
    check compiles((f(mkInt(0))))

suite "Z3FuncDecl — Z3Array element type (v0.3 step 9)":
  test "predicate over Z3Array[Z3Int, Z3Int]: decides a sat formula":
    # Pre step-9 this failed to compile — funcdecl's sortOf cascade
    # didn't include Z3Array. The consolidation in step 9 made every
    # typed family own its sortOf overload, so Z3Array element types
    # now flow through automatically.
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Array[Z3Int, Z3Int],), Z3Bool]("p")
    let a = mkConstArray[Z3Int, Z3Int](mkInt(0))
    let s = newSolver()
    s.add p(a)
    check s.check() == zsSat

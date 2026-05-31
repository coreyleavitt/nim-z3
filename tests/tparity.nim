## `z3/parity` tests — cross-family `Z3Term` surface parity
## (v0.5 step 3).
##
## v0.3 step 1 introduced the `Z3Term` concept and unified `wrap[T]` /
## `eval[T]` / `smtEquiv[T]` over it. Several cross-family surfaces
## (`pretty`, `astEqual`, scalar-`evalXxx` shorthand, `$` per family)
## hadn't been migrated yet. v0.5 step 3 closes that gap. These tests
## verify the unified surfaces apply uniformly to every typed family.

import std/[unittest]
import z3

suite "astEqual — generic over Z3Term":
  test "Z3BitVec same-handle pair":
    let ctx = newContext()
    let x = mkBitVecVar[8]("x")
    check astEqual(x, x)

  test "Z3Char same-handle pair":
    let ctx = newContext()
    let c = mkChar('a')
    check astEqual(c, c)

  test "Z3Fp[Float32] same-handle pair":
    let ctx = newContext()
    let f = mkFloat32(3.14'f32)
    check astEqual(f, f)

suite "evalXxx shorthand — Z3BitVec":
  test "evalUint extracts the unsigned BV value from a solved model":
    let ctx = newContext()
    let x = mkBitVecVar[8]("x")
    let s = newSolver()
    s.add x == mkBitVec[8](42'u32)
    check s.check() == zsSat
    check evalUint(s.model(), x) == 42'u64

  test "evalInt extracts the signed BV value (negative case)":
    let ctx = newContext()
    let x = mkBitVecVar[8]("x")
    let s = newSolver()
    # 0xFF on BV[8] is -1 signed
    s.add x == mkBitVec[8](0xFF'u32)
    check s.check() == zsSat
    check evalInt(s.model(), x) == -1

suite "evalXxx shorthand — Z3Char + Z3Seq":
  test "evalChar extracts the codepoint as int":
    let ctx = newContext()
    let c = mkCharVar("c")
    let s = newSolver()
    s.add c == mkChar('Z')
    check s.check() == zsSat
    check evalChar(s.model(), c) == ord('Z')

  test "evalSeqLen extracts the integer length of a sequence":
    let ctx = newContext()
    let xs = mkSeqVar[Z3Int]("xs")
    let s = newSolver()
    s.add xs.len == mkInt(5)
    check s.check() == zsSat
    check evalSeqLen(s.model(), xs) == 5

suite "pretty — generic over Z3Renderable":
  test "pretty applies to Z3Char (no explicit overload pre-v0.5)":
    let ctx = newContext()
    let c = mkChar('a')
    let p = pretty(c)
    check p.len > 0

  test "pretty applies to Z3Fp[Float32]":
    let ctx = newContext()
    let f = mkFloat32(3.14'f32)
    let p = pretty(f, width = 40)
    check p.len > 0

  test "pretty applies to Z3Regex[Z3String]":
    let ctx = newContext()
    let r = mkRegex(mkString("abc"))
    let p = pretty(r)
    check p.len > 0

suite "\\$ — generic over Z3Term":
  test "\\$ renders Z3Char as SMT-LIB":
    let ctx = newContext()
    check ($mkChar('a')).len > 0

  test "\\$ renders Z3Seq[Z3Int] as SMT-LIB":
    let ctx = newContext()
    let xs = mkSeqVar[Z3Int]("xs")
    check ($xs).len > 0

  test "\\$ renders Z3Fp[Float32] as SMT-LIB":
    let ctx = newContext()
    check ($mkFloat32(3.14'f32)).len > 0

  test "\\$ renders Z3Regex[Z3String] as SMT-LIB":
    let ctx = newContext()
    check ($mkRegex(mkString("abc"))).len > 0

  test "\\$ renders Z3RoundingMode as SMT-LIB":
    let ctx = newContext()
    check ($rmRNE()).len > 0

  test "\\$ renders Z3FuncDecl as SMT-LIB":
    let ctx = newContext()
    let f = mkFuncDecl[(Z3Int,), Z3Int]("f")
    check ($f).len > 0

suite "Z3RoundingMode — sortOf + equality":
  test "sortOf overload makes Z3RoundingMode usable as element type":
    # Without sortOf, mkSeq[Z3RoundingMode] / mkFuncDecl with
    # Z3RoundingMode args wouldn't compile — exercised by actually
    # building each form and rendering it.
    let ctx = newContext()
    let empty = mkSeqEmpty[Z3RoundingMode]()
    check ($empty).len > 0
    let pred = mkFuncDecl[(Z3RoundingMode,), Z3Bool]("predicate")
    check ($pred).len > 0

  test "Z3RoundingMode == itself is valid; == differs from a different mode":
    let ctx = newContext()
    check smtValid(rmRNE() == rmRNE())
    # rmRNE != rmRTZ at the SMT level (distinct enum values).
    check smtValid(rmRNE() != rmRTZ())

suite "B1/B4/B5 — generic simplify / ite / mkDistinct across families":
  test "simplify[T: Z3Term] works on Z3Fp, Z3Seq, Z3Char":
    let ctx = newContext()
    let f = mkFloat32(3.14'f32)
    let s = mkSeqUnit(mkInt(7))
    let c = mkChar('A')
    # Generic dispatch — phantom type preserved.
    let f2: Z3Fp[8, 24] = simplify(f)
    let s2: Z3Seq[Z3Int] = simplify(s)
    let c2: Z3Char       = simplify(c)
    check ($f2).len > 0
    check ($s2).len > 0
    check ($c2).len > 0

  test "ite[T: Z3Term] works for Z3Fp, Z3Seq, Z3Char":
    let ctx = newContext()
    let p = mkBoolVar("p")
    # When p is true, ite picks the first branch; when false, the
    # second. Force p in each direction and assert the resulting
    # SMT-level equality.
    let f = ite(p, mkFloat32(1.0'f32), mkFloat32(2.0'f32))
    let s = ite(p, mkSeqUnit(mkInt(1)), mkSeqUnit(mkInt(2)))
    let c = ite(p, mkChar('a'), mkChar('b'))
    # p=true → first branch.
    check smtValid((p == mkBool(true)).implies(f == mkFloat32(1.0'f32)))
    check smtValid((p == mkBool(true)).implies(s == mkSeqUnit(mkInt(1))))
    check smtValid((p == mkBool(true)).implies(c == mkChar('a')))
    # p=false → second branch.
    check smtValid((p == mkBool(false)).implies(f == mkFloat32(2.0'f32)))
    check smtValid((p == mkBool(false)).implies(s == mkSeqUnit(mkInt(2))))
    check smtValid((p == mkBool(false)).implies(c == mkChar('b')))

  test "mkDistinct[T: Z3Term] enforces same-sort at compile time":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let b = mkBoolVar("b")
    let f1 = mkFloat32(1.0'f32)
    let f2 = mkFloat32(2.0'f32)
    # Same-family inputs compile.
    check compiles(mkDistinct(x, y))
    check compiles(mkDistinct(f1, f2))
    # Cross-family is a compile error.
    check not compiles(mkDistinct(x, b))

suite "model.eval / m[] are constrained to Z3Term":
  test "m.eval(intAst) compiles (Z3Int is Z3Term)":
    let ctx = newContext()
    let x = mkIntVar("x")
    let s = newSolver()
    s.add x == mkInt(42)
    check s.check() == zsSat
    let m = s.model()
    check compiles(m.eval(x))
    check compiles(m[x])

  test "maximize/minimize only accept numeric families":
    # Compile-time guard: maximize on a Z3Bool was previously a runtime
    # sort error that the wrapper then routed through wrapBound to
    # produce a malformed result. The type constraint now rejects it.
    let ctx = newContext()
    let o = newOptimize()
    let x = mkIntVar("x")
    let b = mkBoolVar("b")
    let bv = mkBitVecVar[8]("bv")
    check compiles(o.maximize(x))
    check compiles(o.minimize(x))
    check compiles(o.maximize(bv))
    check not compiles(o.maximize(b))
    check not compiles(o.minimize(b))

  test "m.eval(int) does NOT compile (Nim int is not Z3Term)":
    # Constraint guard from v0.5.0 audit. A plain Nim `int` has no
    # `.raw is RawZ3Ast` field; the typed-eval generic correctly
    # rejects it at compile time rather than blowing up inside the
    # body with an obscure dot-access error.
    let ctx = newContext()
    let s = newSolver()
    discard s.check()
    let m = s.model()
    check not compiles(m.eval(42))
    check not compiles(m[42])

## `z3/quantifier` tests — forall / exists with optional patterns.

import std/[unittest]
import z3

suite "quantifier — tracer":
  test "forall x: Int. x + 1 > x is valid":
    let ctx = newContext()
    let x = mkIntVar("x")
    check smtValid(forall(x, x + mkInt(1) > x))

  test "exists x: Int. x == 42 is valid":
    let ctx = newContext()
    let x = mkIntVar("x")
    check smtValid(exists(x, x == mkInt(42)))

suite "quantifier — multi-var":
  test "forall x, y. x + y == y + x":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    check smtValid(forall(x, y, x + y == y + x))

  test "exists x, y. x + y == 10 and x > y":
    let ctx = newContext()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    check smtValid(exists(x, y, (x + y == mkInt(10)) and (x > y)))

suite "quantifier — heterogeneous sorts":
  test "forall x: Int, p: Bool. ite(p, x, x) == x":
    let ctx = newContext()
    let x = mkIntVar("x")
    let p = mkBoolVar("p")
    check smtValid(forall(x, p, ite(p, x, x) == x))

  test "forall x: BV[8]. x + 0 == x":
    let ctx = newContext()
    let x = mkBitVecVar[8]("x")
    check smtValid(forall(x, (x + mkBitVec[8](0'u8)) == x))

  test "forall x: BV[8], y: BV[8]. x + y == y + x":
    let ctx = newContext()
    let x = mkBitVecVar[8]("x")
    let y = mkBitVecVar[8]("y")
    check smtValid(forall(x, y, (x + y) == (y + x)))

type IntList = object   # for the datatype-bound-var tests

suite "quantifier — datatype-sorted bound var":
  test "forall l: IntList. (is-cons l) ⟹ (is-cons l) (trivial)":
    let ctx = newContext()
    let L = declareDatatype[IntList](@[
      constructor("nil"),
      constructor("cons", @[
        field("head", Z3Int),
        selfField("tail")
      ])
    ])
    let isCons = L.recognizer("cons")
    let l = L.mkDatatypeVar("l")
    # Trivial implication — quantification still threads through.
    check smtValid(forall(l, isCons.test(l).implies(isCons.test(l))))

  test "forall l: IntList. is-cons l or is-nil l":
    let ctx = newContext()
    let L = declareDatatype[IntList](@[
      constructor("nil"),
      constructor("cons", @[
        field("head", Z3Int),
        selfField("tail")
      ])
    ])
    let isCons = L.recognizer("cons")
    let isNil = L.recognizer("nil")
    let l = L.mkDatatypeVar("l")
    # Every IntList is either cons or nil — datatype exhaustiveness.
    check smtValid(forall(l, isCons.test(l) or isNil.test(l)))

  test "exists l: IntList. is-nil l":
    let ctx = newContext()
    let L = declareDatatype[IntList](@[
      constructor("nil"),
      constructor("cons", @[
        field("head", Z3Int),
        selfField("tail")
      ])
    ])
    let isNil = L.recognizer("nil")
    let l = L.mkDatatypeVar("l")
    check smtValid(exists(l, isNil.test(l)))

suite "quantifier — de Morgan duality":
  test "not (forall x. x > 0) ≡ exists x. not (x > 0)":
    let ctx = newContext()
    # We need fresh quantifier bindings on each side, but the body
    # references the same external constant `x`. Using the same `x` is
    # fine — Z3 captures it.
    let x = mkIntVar("x")
    let lhs = not forall(x, x > mkInt(0))
    let rhs = exists(x, not (x > mkInt(0)))
    check smtEquiv(lhs, rhs)

  test "not (exists x. x == 42) ≡ forall x. x != 42":
    let ctx = newContext()
    let x = mkIntVar("x")
    let lhs = not exists(x, x == mkInt(42))
    let rhs = forall(x, x != mkInt(42))
    check smtEquiv(lhs, rhs)

suite "quantifier — pattern threading":
  test "forall x. body with explicit pattern: validity preserved":
    let ctx = newContext()
    let x = mkIntVar("x")
    let body = x + mkInt(1) > x
    # Pattern must contain at least one function application —
    # bare variables aren't valid Z3 triggers. `x + 1` is the
    # `+` application over (x, 1).
    let p = mkPattern(x + mkInt(1))
    check smtValid(forall(x, body, patterns = [p]))

  test "forall x with two patterns is still valid":
    let ctx = newContext()
    let x = mkIntVar("x")
    let body = x + mkInt(1) > x
    # Both patterns are function applications (+, >).
    let p1 = mkPattern(x + mkInt(1))
    let p2 = mkPattern(x + mkInt(1) > x)
    check smtValid(forall(x, body, patterns = [p1, p2]))

  test "mkPattern rejects bare variables (Z3 constraint)":
    let ctx = newContext()
    let x = mkIntVar("x")
    let body = x + mkInt(1) > x
    # Z3 itself enforces that patterns must contain at least one
    # function application. We surface the failure as Z3Error.
    expect Z3Error:
      let p = mkPattern(x)
      discard forall(x, body, patterns = [p])

  test "array read pattern: forall i. select(a, i) == 0 (with pattern)":
    let ctx = newContext()
    let a = mkConstArray[Z3Int, Z3Int](mkInt(0))
    let i = mkIntVar("i")
    let sel = select(a, i)
    # Pattern is the select term — Z3 triggers when it sees
    # select(a, ?) in the context.
    let p = mkPattern(sel)
    check smtValid(forall(i, sel == mkInt(0), patterns = [p]))

suite "quantifier introspection — pattern survives source AST drop":
  test "getQuantifierPattern result outlives the original quantifier scope":
    # incRefPattern path (v0.5.0 audit A5 / round-2 L24): extracting
    # a pattern from a quantifier must give the caller an independently-
    # refcounted handle, so the pattern survives even if the original
    # quantifier AST goes out of scope. This test would crash with a
    # use-after-free if the inc_ref were missing.
    let ctx = newContext()
    proc buildAndExtract(): Z3Pattern =
      let x = mkIntVar("x")
      let body = (x > mkInt(0))
      let trig = mkPattern(body)
      let q = forall(x, body, patterns = [trig])
      result = getQuantifierPattern(q, 0)
      # q, x, body, trig go out of scope here when the proc returns.
    let extracted = buildAndExtract()
    # Force a GC pass to make sure anything that should be collected is.
    GC_fullCollect()
    # If the pattern's refcount was correctly bumped, this proc call
    # is safe; rendering accesses the underlying raw handle.
    let rendered = $extracted
    check rendered.len > 0

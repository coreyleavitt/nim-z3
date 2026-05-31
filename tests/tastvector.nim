## `z3/astvector` tests — typed ref-handle for Z3's `Z3_ast_vector` C type.

import std/[unittest, strutils]
import z3

suite "Z3AstVector — tracer":
  test "newAstVector returns an empty vector":
    let ctx = newContext()
    let v = newAstVector()
    check v.len == 0

suite "Z3AstVector — mutation":
  test "add(typed) increases length":
    let ctx = newContext()
    let v = newAstVector()
    let p = mkBoolVar("p")
    v.add p
    check v.len == 1
    v.add p
    check v.len == 2

  test "items iterator yields entries that survive typed conversion":
    let ctx = newContext()
    let v = newAstVector()
    let p = mkBoolVar("p")
    v.add p
    var count = 0
    for _ in v:
      inc count
    check count == 1
    # Observable through the typed surface: the iterated entries are
    # the same Z3 ASTs we pushed, verifiable via smtEquiv after typed
    # extraction.
    let extracted = v.toSeq(Z3Bool)
    check smtValid(extracted[0] == p)

  test "[i] indexed access returns the AST at position i (observed via typed extraction)":
    let ctx = newContext()
    let v = newAstVector()
    let p = mkBoolVar("p")
    let q = mkBoolVar("q")
    v.add p
    v.add q
    # Verify positional ordering through the typed extractor, which
    # uses [i] under the hood.
    let bools = v.toSeq(Z3Bool)
    check smtValid(bools[0] == p)
    check smtValid(bools[1] == q)

  test "resize(n) sets length to n":
    let ctx = newContext()
    let v = newAstVector()
    let p = mkBoolVar("p")
    v.add p
    v.add p
    v.add p
    check v.len == 3
    v.resize(1)
    check v.len == 1
    v.resize(5)
    check v.len == 5

suite "Z3AstVector — typed conversion (toSeq)":
  test "toSeq[Z3Bool] returns typed Z3Bools that round-trip semantically":
    let ctx = newContext()
    let v = newAstVector()
    let p = mkBoolVar("p")
    let q = mkBoolVar("q")
    v.add p
    v.add q
    let bools = v.toSeq(Z3Bool)
    check bools.len == 2
    check smtValid(bools[0] == p)
    check smtValid(bools[1] == q)

  test "toSeq[Z3BitVec[W]] dispatches via the unified wrap[T]":
    # Proves the mixin-based sortOf / wrap dispatch generalises across
    # the typed-family set, not just the trivial Z3Bool case.
    let ctx = newContext()
    let v = newAstVector()
    let a = mkBitVec[8](0xAA'u8)
    let b = mkBitVec[8](0xBB'u8)
    v.add a
    v.add b
    let bvs = v.toSeq(Z3BitVec[8])
    check bvs.len == 2
    check smtValid(bvs[0] == a)
    check smtValid(bvs[1] == b)

suite "Z3AstVector — heterogeneous storage":
  test "vector holds mixed-sort ASTs simultaneously":
    # Z3's ast_vector is sort-agnostic; the wrapper preserves that.
    let ctx = newContext()
    let v = newAstVector()
    let i = mkIntVar("i")
    let p = mkBoolVar("p")
    v.add i
    v.add p
    check v.len == 2
    # The vector accepts both; the rendered form contains both.
    let s = $v
    check s.contains("i")
    check s.contains("p")

suite "Z3AstVector — pretty-print":
  test "$v renders Z3's SMT-LIB representation including pushed entries":
    let ctx = newContext()
    let v = newAstVector()
    v.add mkBoolVar("alpha")
    v.add mkBoolVar("beta")
    let s = $v
    check s.contains("alpha")
    check s.contains("beta")

suite "Z3AstVector — indexed setter (medium C11)":
  test "v[i] = q overwrites entry i":
    let ctx = newContext()
    let v = newAstVector()
    let p = mkBoolVar("p")
    let q = mkBoolVar("q")
    v.add p
    v.add p
    let before = v.toSeq(Z3Bool)
    check astEqual(before[0], p)
    check astEqual(before[1], p)
    v[0] = q
    let after = v.toSeq(Z3Bool)
    check astEqual(after[0], q)
    check astEqual(after[1], p)

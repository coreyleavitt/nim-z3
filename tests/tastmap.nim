## `z3/astmap` tests — Z3AstMap ref-counted handle.
##
## Covers:
##   - Constructor: newAstMap
##   - Round-trip: insert→find returns Some(value)
##   - Find on missing key returns None
##   - contains-then-erase removes the entry
##   - len after inserting same key multiple times is 1
##   - keys() returns a Z3AstVector containing the inserted key
##   - reset clears all entries
##   - ref-alias semantics: let m2 = m1; m2.insert(...); m1.contains(...) == true
##   - $: produces non-empty string

import std/unittest
import std/options
import z3

suite "Z3AstMap — constructor":
  test "newAstMap returns non-nil Z3AstMap":
    let ctx = newContext()
    let m = newAstMap(ctx)
    check m != nil
    check m is Z3AstMap

suite "Z3AstMap — basic insert / find":
  test "round-trip insert→find returns Some(value)":
    let ctx = newContext()
    let m = newAstMap(ctx)
    let k = mkIntVar(ctx, "x")
    let v = mkInt(ctx, 42)
    m.insert(k, v)
    let found = m.find(toAnyAst(k), Z3Int)
    check found.isSome
    # The found value should be structurally equal to v
    let s = newSolver(ctx)
    s.add(found.get() == v)
    check s.check() == zsSat

  test "find on missing key returns None":
    let ctx = newContext()
    let m = newAstMap(ctx)
    let k = mkIntVar(ctx, "x")
    let found = m.find(toAnyAst(k), Z3Int)
    check found.isNone

suite "Z3AstMap — contains / erase":
  test "contains returns true after insert":
    let ctx = newContext()
    let m = newAstMap(ctx)
    let k = mkIntVar(ctx, "x")
    let v = mkInt(ctx, 1)
    m.insert(k, v)
    check m.contains(toAnyAst(k))

  test "contains returns false for absent key":
    let ctx = newContext()
    let m = newAstMap(ctx)
    let k = mkIntVar(ctx, "x")
    check not m.contains(toAnyAst(k))

  test "erase removes the entry":
    let ctx = newContext()
    let m = newAstMap(ctx)
    let k = mkIntVar(ctx, "x")
    let v = mkInt(ctx, 7)
    m.insert(k, v)
    check m.contains(toAnyAst(k))
    m.erase(toAnyAst(k))
    check not m.contains(toAnyAst(k))

suite "Z3AstMap — len":
  test "len after multiple inserts of same key is 1":
    let ctx = newContext()
    let m = newAstMap(ctx)
    let k = mkIntVar(ctx, "x")
    let v1 = mkInt(ctx, 1)
    let v2 = mkInt(ctx, 2)
    let v3 = mkInt(ctx, 3)
    m.insert(k, v1)
    m.insert(k, v2)
    m.insert(k, v3)
    check m.len == 1

  test "len grows with distinct keys":
    let ctx = newContext()
    let m = newAstMap(ctx)
    let k1 = mkIntVar(ctx, "x")
    let k2 = mkIntVar(ctx, "y")
    let k3 = mkIntVar(ctx, "z")
    m.insert(k1, mkInt(ctx, 1))
    m.insert(k2, mkInt(ctx, 2))
    m.insert(k3, mkInt(ctx, 3))
    check m.len == 3

suite "Z3AstMap — keys":
  test "keys() returns AstVector containing inserted key":
    let ctx = newContext()
    let m = newAstMap(ctx)
    let k = mkIntVar(ctx, "x")
    let v = mkInt(ctx, 10)
    m.insert(k, v)
    let ks = m.keys()
    check ks.len == 1
    # The single key should have the same raw pointer as k
    let rawKey = ks[0]
    check rawKey == k.raw

suite "Z3AstMap — reset":
  test "reset clears all entries":
    let ctx = newContext()
    let m = newAstMap(ctx)
    let k1 = mkIntVar(ctx, "a")
    let k2 = mkIntVar(ctx, "b")
    m.insert(k1, mkInt(ctx, 1))
    m.insert(k2, mkInt(ctx, 2))
    check m.len == 2
    m.reset()
    check m.len == 0
    check not m.contains(toAnyAst(k1))
    check not m.contains(toAnyAst(k2))

suite "Z3AstMap — ref alias semantics":
  test "let m2 = m1 shares identity — insert via m2 visible through m1":
    let ctx = newContext()
    let m1 = newAstMap(ctx)
    let m2 = m1  # ref alias — same underlying object
    let k = mkIntVar(ctx, "shared")
    let v = mkInt(ctx, 99)
    m2.insert(k, v)
    check m1.contains(toAnyAst(k))
    check m1.len == 1

suite "Z3AstMap — pretty print":
  test "$ produces a non-empty string":
    let ctx = newContext()
    let m = newAstMap(ctx)
    let k = mkIntVar(ctx, "x")
    m.insert(k, mkInt(ctx, 5))
    let s = $m
    check s.len > 0

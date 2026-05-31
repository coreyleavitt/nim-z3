## astHash — Z3-side structural-identity hash for typed ASTs, plus
## the distinct-wrapper pattern for std/tables integration.
## v1.0 audit round 2, item L27.

import std/[unittest, tables, hashes]
import z3

suite "astHash — Z3-side AST hashcons":
  test "structurally equal ASTs share the same astHash":
    let ctx = newContext()
    check astHash(mkInt(42)) == astHash(mkInt(42))
    check astHash(mkInt(1)) != astHash(mkInt(2))

  test "astHash generic across every typed family":
    let ctx = newContext()
    discard astHash(mkInt(1))
    discard astHash(mkBool(true))
    discard astHash(mkBitVec[8](7'u32))
    discard astHash(mkChar('a'))
    discard astHash(mkFloat32(0.0'f32))
    discard astHash(mkSeqUnit(mkInt(0)))

  test "astHash equality implies astEqual":
    # Hashcons contract: same hash ↔ same raw pointer ↔ astEqual.
    let ctx = newContext()
    let a = mkInt(42)
    let b = mkInt(42)
    check astHash(a) == astHash(b)
    check astEqual(a, b)

# Documented pattern: wrap the AST in a distinct type whose `==` uses
# `astEqual` (Z3-side structural identity, returning Nim bool) and
# whose `hash` uses `astHash`. See GOTCHAS.md.
#
# Lives at module scope so std/tables finds the overloads during
# generic instantiation. Defining `==` / `hash` inside a `suite`/`test`
# block hides them.
type Z3IntKey = distinct Z3Int
proc `==`(a, b: Z3IntKey): bool = astEqual(Z3Int(a), Z3Int(b))
proc hash(k: Z3IntKey): Hash = cast[Hash](astHash(Z3Int(k)))

suite "Z3AstKey — distinct-wrapper pattern for std/tables":
  test "Z3IntKey works as a Table key":
    let ctx = newContext()
    var t: Table[Z3IntKey, string]
    t[Z3IntKey(mkInt(1))] = "one"
    t[Z3IntKey(mkInt(2))] = "two"
    check t[Z3IntKey(mkInt(1))] == "one"
    check t[Z3IntKey(mkInt(2))] == "two"
    check Z3IntKey(mkInt(3)) notin t

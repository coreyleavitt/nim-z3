## N2.4a — FuncDecl name / arity / domain / range / id introspection.
##
## Tests for `declName`, `declArity`, `declDomain`, `declRange`, and
## `declFuncId` on `RawZ3FuncDecl` values obtained from a typed
## `Z3FuncDecl[(Z3Int, Z3Int), Z3Bool]`.

import std/[unittest]
import z3

suite "N2.4a — declName":
  test "name of a declared funcDecl is the string passed to mkFuncDecl":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "P")
    check declName(ctx, p.raw) == "P"

  test "name is stable across repeated calls":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "P")
    check declName(ctx, p.raw) == declName(ctx, p.raw)

  test "two differently-named decls have distinct names":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "P")
    let q = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "Q")
    check declName(ctx, p.raw) != declName(ctx, q.raw)

suite "N2.4a — declArity":
  test "binary (Int, Int) → Bool decl has arity 2":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "P")
    check declArity(ctx, p.raw) == 2

  test "unary (Int,) → Bool decl has arity 1":
    let ctx = newContext()
    let f = mkFuncDecl[(Z3Int,), Z3Bool](ctx, "F")
    check declArity(ctx, f.raw) == 1

  test "nullary () → Int decl has arity 0":
    let ctx = newContext()
    let c = mkFuncDecl[tuple[], Z3Int](ctx, "C")
    check declArity(ctx, c.raw) == 0

  test "arity is stable across repeated calls":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "P")
    check declArity(ctx, p.raw) == declArity(ctx, p.raw)

suite "N2.4a — declDomain":
  test "domain(0) of (Int, Int) → Bool decl is an Int sort":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "P")
    let d0 = declDomain(ctx, p.raw, 0)
    check getSortKind(ctx, d0) == skInt

  test "domain(1) of (Int, Int) → Bool decl is an Int sort":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "P")
    let d1 = declDomain(ctx, p.raw, 1)
    check getSortKind(ctx, d1) == skInt

  test "domain(0) of (Bool, Int) → Int decl is a Bool sort":
    let ctx = newContext()
    let g = mkFuncDecl[(Z3Bool, Z3Int), Z3Int](ctx, "G")
    check getSortKind(ctx, declDomain(ctx, g.raw, 0)) == skBool

  test "domain(1) of (Bool, Int) → Int decl is an Int sort":
    let ctx = newContext()
    let g = mkFuncDecl[(Z3Bool, Z3Int), Z3Int](ctx, "G")
    check getSortKind(ctx, declDomain(ctx, g.raw, 1)) == skInt

  test "out-of-range domain index raises":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "P")
    expect AssertionDefect:
      discard declDomain(ctx, p.raw, 2)

  test "negative domain index raises":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "P")
    expect AssertionDefect:
      discard declDomain(ctx, p.raw, -1)

suite "N2.4a — declRange":
  test "range of (Int, Int) → Bool decl is a Bool sort":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "P")
    check getSortKind(ctx, declRange(ctx, p.raw)) == skBool

  test "range of (Int, Int) → Int decl is an Int sort":
    let ctx = newContext()
    let f = mkFuncDecl[(Z3Int, Z3Int), Z3Int](ctx, "F")
    check getSortKind(ctx, declRange(ctx, f.raw)) == skInt

  test "range is stable across repeated calls":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "P")
    # Sorts are interned in Z3 — same handle means pointer equality.
    let r1 = declRange(ctx, p.raw)
    let r2 = declRange(ctx, p.raw)
    check cast[pointer](r1) == cast[pointer](r2)

suite "N2.4a — declFuncId":
  test "funcId of a declared decl is non-zero":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "P")
    check declFuncId(ctx, p.raw) != 0

  test "funcId is stable across repeated calls":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "P")
    check declFuncId(ctx, p.raw) == declFuncId(ctx, p.raw)

  test "two distinct decls have distinct ids":
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "P")
    let q = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "Q")
    check declFuncId(ctx, p.raw) != declFuncId(ctx, q.raw)

suite "N2.4a — round-trip via getAppDecl":
  test "declName round-trips through an application's head decl":
    ## Build `P(x, y)`, extract the head decl via `getAppDecl`, and
    ## verify name/arity/range match the original declaration.
    let ctx = newContext()
    let p = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "P")
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let app = p(x, y)          # Z3Bool application
    let hd  = getAppDecl(app)  # RawZ3FuncDecl from the head of the app
    check declName(ctx, hd)   == "P"
    check declArity(ctx, hd)  == 2
    check getSortKind(ctx, declRange(ctx, hd)) == skBool
    check declFuncId(ctx, hd) == declFuncId(ctx, p.raw)

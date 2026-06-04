## `z3/rewrite` N9.4 tests — `substituteFuns`, `freshConst`, `freshFuncDecl`.

import std/[unittest]
import z3

suite "substituteFuns — replace func applications":
  test "f(5) + f(10) with f->g via bound vars becomes g(5) + g(10)":
    let ctx = newContext()
    let f = mkFuncDecl[(Z3Int,), Z3Int](ctx, "f")
    let g = mkFuncDecl[(Z3Int,), Z3Int](ctx, "g")
    # Build f(5) + f(10)
    let expr = f(mkInt(5)) + f(mkInt(10))
    # The 'to' expression is g(bound_var_0) — free var 0 = first arg of f.
    let intSort = sortOf(Z3Int, ctx)
    let bound0 = asZ3Int(mkBound(ctx, 0, intSort))
    let toExpr = toAnyAst(g(bound0))
    let result = substituteFuns(expr, @[f.raw], @[toExpr])
    # result should be g(5) + g(10) semantically
    let expected = g(mkInt(5)) + g(mkInt(10))
    check smtValid(result == expected)

  test "substituteFuns with empty arrays is identity":
    let ctx = newContext()
    let f = mkFuncDecl[(Z3Int,), Z3Int](ctx, "f")
    let expr = f(mkInt(3))
    let result = substituteFuns(expr,
      newSeq[RawZ3FuncDecl](), newSeq[Z3AnyAst]())
    check smtValid(result == expr)

  test "substituteFuns preserves typed return T":
    let ctx = newContext()
    let f = mkFuncDecl[(Z3Int,), Z3Int](ctx, "f")
    let g = mkFuncDecl[(Z3Int,), Z3Int](ctx, "g")
    let expr = f(mkInt(7))
    let intSort = sortOf(Z3Int, ctx)
    let bound0 = asZ3Int(mkBound(ctx, 0, intSort))
    let result: Z3Int = substituteFuns(expr, @[f.raw], @[toAnyAst(g(bound0))])
    check smtValid(result == g(mkInt(7)))

suite "freshConst — typed fresh constant constructor":
  test "freshConst[Z3Int] returns a non-nil Z3Int":
    let ctx = newContext()
    let x = freshConst[Z3Int](ctx, "x")
    check not x.raw.isNil

  test "two freshConst[Z3Int] calls return distinct constants":
    let ctx = newContext()
    let a = freshConst[Z3Int](ctx, "a")
    let b = freshConst[Z3Int](ctx, "a")
    # Structurally distinct — Z3 assigns unique ids
    check not smtValid(a == b)

  test "freshConst[Z3Bool] returns a Z3Bool":
    let ctx = newContext()
    let p = freshConst[Z3Bool](ctx, "p")
    check not p.raw.isNil

suite "freshFuncDecl — typed fresh function declaration":
  test "two freshFuncDecl calls return distinct decls":
    let ctx = newContext()
    let f = freshFuncDecl[(Z3Int,), Z3Int](ctx, "f")
    let g = freshFuncDecl[(Z3Int,), Z3Int](ctx, "f")
    # Structurally distinct — different internal ids
    let x = mkIntVar("x")
    check not smtValid(f(x) == g(x))

  test "freshFuncDecl result is callable":
    let ctx = newContext()
    let f = freshFuncDecl[(Z3Int,), Z3Int](ctx, "f")
    let x = mkIntVar("x")
    let app = f(x)
    check not app.raw.isNil

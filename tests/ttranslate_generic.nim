## N10.3 — `translate` for `Z3FuncDecl[ArgsTup, Ret]` and `Z3Sort[S]`.
##
## Verifies:
##   - Z3FuncDecl.translate: decl built in ctx1, moved to ctx2, usable in ctx2
##   - Z3Sort[stInt].translate: sort built in ctx1, moved to ctx2, renders correctly
##   - Z3Model.translate regression (N2.1 — already covered in tmodel_enum, smoke here)

import std/[unittest]
import z3

suite "translate — Z3FuncDecl.translate":
  test "translated Z3FuncDecl lives in target context":
    let ctx1 = newContext()
    let ctx2 = newContext()
    let f = mkFuncDecl[(Z3Int,), Z3Int](ctx1, "f")
    let f2 = f.translate(ctx2)
    check f2.ctx.raw == ctx2.raw

  test "translated Z3FuncDecl can be applied in target context":
    let ctx1 = newContext()
    let ctx2 = newContext()
    let f = mkFuncDecl[(Z3Int,), Z3Int](ctx1, "f")
    let f2 = f.translate(ctx2)
    # Apply f2 to an Int built in ctx2 — should produce a valid Z3Int in ctx2
    let x2 = mkIntVar(ctx2, "x")
    let app = f2(x2)
    check app.ctx.raw == ctx2.raw

  test "Z3FuncDecl round-trip ctx1 → ctx2 → ctx1 preserves SMT-LIB rendering":
    let ctx1 = newContext()
    let ctx2 = newContext()
    let f = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx1, "g")
    let f2 = f.translate(ctx2)
    let f3 = f2.translate(ctx1)
    check $f == $f3

suite "translate — Z3Sort.translate":
  test "translated Z3Sort[stInt] lives in target context":
    let ctx1 = newContext()
    let ctx2 = newContext()
    let s1 = mkIntSort(ctx1)
    let s2 = s1.translate(ctx2)
    check s2.ctx.raw == ctx2.raw

  test "translated Z3Sort[stInt] renders identically to a fresh sort in ctx2":
    let ctx1 = newContext()
    let ctx2 = newContext()
    let s1 = mkIntSort(ctx1)
    let s2 = s1.translate(ctx2)
    let fresh = mkIntSort(ctx2)
    check $s2 == $fresh

  test "Z3Sort[stBool] translates across contexts":
    let ctx1 = newContext()
    let ctx2 = newContext()
    let s1 = mkBoolSort(ctx1)
    let s2: Z3Sort[stBool] = s1.translate(ctx2)
    check $s2 == $mkBoolSort(ctx2)

suite "translate — Z3Model.translate regression (N2.1)":
  test "translated model is usable in target context":
    let ctx1 = newContext()
    let x = mkIntVar(ctx1, "x")
    let s = newSolver(ctx1)
    s.add (x > mkInt(ctx1, 0)) and (x < mkInt(ctx1, 5))
    let status = s.check()
    check status == zsSat
    let m1 = s.model()
    let ctx2 = newContext()
    let m2 = m1.translate(ctx2)
    # Model lives in ctx2 — numConsts is a structural check
    check m2.numConsts >= 1

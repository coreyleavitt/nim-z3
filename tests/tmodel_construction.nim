## `z3/model` construction tests — N2.2 slice.
##
## Exercises the model-construction surface:
##   newModel / addConstInterp / addFuncInterp / setElse / addEntry
##
## These procs let callers build hand-crafted models (e.g. for testing
## a formula's falsity by constructing a counterexample model, or for
## consumers that synthesise models from scratch).

import std/[unittest]
import z3

# ---------------------------------------------------------------------------
# Suite 1 — newModel
# ---------------------------------------------------------------------------

suite "Z3Model — construction: newModel":

  test "newModel returns a usable model with no entries":
    let ctx = newContext()
    let m = newModel(ctx)
    check m.numConsts == 0
    check m.numFuncs == 0

# ---------------------------------------------------------------------------
# Suite 2 — addConstInterp
# ---------------------------------------------------------------------------

suite "Z3Model — construction: addConstInterp":

  test "addConstInterp pins a value; eval returns that value":
    let ctx = newContext()
    let m = newModel(ctx)
    # Use a nullary func decl ("x : Int") — same as a constant.
    let fd = mkFuncDecl[(), Z3Int]("x")
    addConstInterp(m, fd.raw, mkInt(42).toAnyAst)
    # Evaluate the constant application x() against the hand-crafted model.
    let evaled = m.eval(fd()).toInt
    check evaled == 42

  test "addConstInterp: model gains one const entry":
    let ctx = newContext()
    let m = newModel(ctx)
    let fd = mkFuncDecl[(), Z3Int]("c")
    addConstInterp(m, fd.raw, mkInt(7).toAnyAst)
    check m.numConsts == 1
    check m.hasInterp(m.constDecl(0))

# ---------------------------------------------------------------------------
# Suite 3 — addFuncInterp / setElse / addEntry
# ---------------------------------------------------------------------------

suite "Z3Model — construction: addFuncInterp / setElse / addEntry":

  test "else-only interp: f(any) returns else-value for uncovered args":
    let ctx = newContext()
    let m = newModel(ctx)
    let fd = mkFuncDecl[(Z3Int,), Z3Int]("f")
    # addFuncInterp sets the initial else-value.
    let fi = addFuncInterp(m, fd.raw, mkInt(0).toAnyAst)
    # No entries; every arg maps to else=0.
    let result = m.eval(fd(mkInt(99))).toInt
    check result == 0

  test "addEntry: f(42)=100, f(0) falls back to else=0":
    let ctx = newContext()
    let m = newModel(ctx)
    let fd = mkFuncDecl[(Z3Int,), Z3Int]("f")
    let fi = addFuncInterp(m, fd.raw, mkInt(0).toAnyAst)
    addEntry(fi, [mkInt(42).toAnyAst], mkInt(100).toAnyAst)
    check m.eval(fd(mkInt(42))).toInt == 100
    check m.eval(fd(mkInt(0))).toInt == 0

  test "setElse changes the else-value post-construction":
    let ctx = newContext()
    let m = newModel(ctx)
    let fd = mkFuncDecl[(Z3Int,), Z3Int]("f")
    let fi = addFuncInterp(m, fd.raw, mkInt(0).toAnyAst)
    setElse(fi, mkInt(99).toAnyAst)
    # No entry for 5; returns updated else=99.
    check m.eval(fd(mkInt(5))).toInt == 99

  test "addEntry with multiple args":
    let ctx = newContext()
    let m = newModel(ctx)
    let fd = mkFuncDecl[(Z3Int, Z3Int), Z3Int]("g")
    let fi = addFuncInterp(m, fd.raw, mkInt(0).toAnyAst)
    addEntry(fi, [mkInt(3).toAnyAst, mkInt(4).toAnyAst], mkInt(7).toAnyAst)
    check m.eval(fd(mkInt(3), mkInt(4))).toInt == 7
    check m.eval(fd(mkInt(1), mkInt(2))).toInt == 0

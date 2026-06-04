## `z3/model` enumeration tests — N2.1 slice.
##
## Exercises the model-introspection surface added in N2.1:
##   numConsts / constDecl / numFuncs / funcDecl
##   numSorts  / sort      / sortUniverse
##   hasInterp / translate

import std/[unittest]
import z3


# ---------------------------------------------------------------------------
# Suite 1 — numConsts / constDecl / numFuncs / funcDecl / hasInterp
# ---------------------------------------------------------------------------

suite "Z3Model — numConsts / constDecl / numFuncs / funcDecl / hasInterp":

  test "numConsts >= 2 after solving with two int vars":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    s.add x + y == mkInt(10)
    s.add x > mkInt(3)
    check s.check() == zsSat
    let m = s.model()
    # At minimum x and y are in the model as const decls.
    check m.numConsts >= 2

  test "constDecl returns non-nil RawZ3FuncDecl for each const":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    s.add x + y == mkInt(10)
    s.add x > mkInt(3)
    check s.check() == zsSat
    let m = s.model()
    let n = m.numConsts
    check n >= 2
    for i in 0 ..< n:
      let fd = m.constDecl(i)
      check not fd.isNil

  test "hasInterp returns true for each enumerated const decl":
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    s.add x + y == mkInt(10)
    s.add x > mkInt(3)
    check s.check() == zsSat
    let m = s.model()
    let n = m.numConsts
    check n >= 2
    for i in 0 ..< n:
      let fd = m.constDecl(i)
      # Every const in the enumeration has an interpretation in the model.
      check m.hasInterp(fd)

  test "numFuncs and funcDecl on a model with an uninterpreted function":
    let ctx = newContext()
    let s = newSolver()
    let f = mkFuncDecl[(Z3Int,), Z3Int]("f")
    let x = mkIntVar("x")
    # pin f at one specific point so Z3 builds a func interp
    s.add f(x) == mkInt(7)
    s.add x == mkInt(3)
    check s.check() == zsSat
    let m = s.model()
    # 'f' is an uninterpreted function; 'x' is a const.
    check m.numFuncs >= 1
    var foundInterp = false
    for i in 0 ..< m.numFuncs:
      let fd = m.funcDecl(i)
      check not fd.isNil
      if m.hasInterp(fd):
        foundInterp = true
    check foundInterp

  test "hasInterp returns false for a decl not in the model":
    # Declare a function but never assert anything about it.  After check()
    # the model has no obligation to include an interpretation for it.
    let ctx = newContext()
    let s = newSolver()
    let g = mkFuncDecl[(Z3Int,), Z3Int]("g")
    let x = mkIntVar("x")
    s.add x == mkInt(0)   # only x is in the model; g is unconstrained
    check s.check() == zsSat
    let m = s.model()
    check not m.hasInterp(g.raw)

# ---------------------------------------------------------------------------
# Suite 2 — numSorts / sort / sortUniverse
# ---------------------------------------------------------------------------

suite "Z3Model — numSorts / sort / sortUniverse":
  # Use mkUninterpretedSort (exported from z3/sort) and Z3_mk_const from the
  # exported ffi module to create two values of an opaque sort.
  # Use Z3_mk_distinct (takes ptr UncheckedArray) to assert they differ.

  test "numSorts >= 1 after asserting constraint on an uninterpreted sort":
    let ctx = newContext()
    let s = newSolver()
    let colorSort = mkUninterpretedSort(ctx, "Color")
    let symRed  = Z3_mk_string_symbol(ctx.raw, "red")
    let symBlue = Z3_mk_string_symbol(ctx.raw, "blue")
    let rawRed  = Z3_mk_const(ctx.raw, symRed,  colorSort.raw)
    let rawBlue = Z3_mk_const(ctx.raw, symBlue, colorSort.raw)
    # Use Z3_mk_distinct to assert red != blue.
    var args = [rawRed, rawBlue]
    let neq = Z3_mk_distinct(ctx.raw, 2'u32,
                              cast[ptr UncheckedArray[RawZ3Ast]](addr args[0]))
    s.add wrap[Z3Bool](ctx, neq)
    check s.check() == zsSat
    let m = s.model()
    check m.numSorts >= 1

  test "sort(i) returns non-nil RawZ3Sort for each tracked sort":
    let ctx = newContext()
    let s = newSolver()
    let colorSort = mkUninterpretedSort(ctx, "Color")
    let symRed  = Z3_mk_string_symbol(ctx.raw, "red")
    let symBlue = Z3_mk_string_symbol(ctx.raw, "blue")
    let rawRed  = Z3_mk_const(ctx.raw, symRed,  colorSort.raw)
    let rawBlue = Z3_mk_const(ctx.raw, symBlue, colorSort.raw)
    var args = [rawRed, rawBlue]
    let neq = Z3_mk_distinct(ctx.raw, 2'u32,
                              cast[ptr UncheckedArray[RawZ3Ast]](addr args[0]))
    s.add wrap[Z3Bool](ctx, neq)
    check s.check() == zsSat
    let m = s.model()
    let ns = m.numSorts
    check ns >= 1
    for i in 0 ..< ns:
      let rawSort = m.sort(i)
      check not rawSort.isNil

  test "sortUniverse for Color has >= 2 elements when red != blue":
    let ctx = newContext()
    let s = newSolver()
    let colorSort = mkUninterpretedSort(ctx, "Color")
    let symRed  = Z3_mk_string_symbol(ctx.raw, "red")
    let symBlue = Z3_mk_string_symbol(ctx.raw, "blue")
    let rawRed  = Z3_mk_const(ctx.raw, symRed,  colorSort.raw)
    let rawBlue = Z3_mk_const(ctx.raw, symBlue, colorSort.raw)
    var args = [rawRed, rawBlue]
    let neq = Z3_mk_distinct(ctx.raw, 2'u32,
                              cast[ptr UncheckedArray[RawZ3Ast]](addr args[0]))
    s.add wrap[Z3Bool](ctx, neq)
    check s.check() == zsSat
    let m = s.model()
    let ns = m.numSorts
    check ns >= 1
    # The universe of at least one tracked sort should have >= 2 elements.
    var found = false
    for i in 0 ..< ns:
      let rawSort = m.sort(i)
      let univ = m.sortUniverse(rawSort)
      if univ.len >= 2:
        found = true
        break
    check found

# ---------------------------------------------------------------------------
# Suite 3 — translate
# ---------------------------------------------------------------------------

suite "Z3Model — translate":

  test "translate produces a model usable in the target context":
    let ctx1 = newContext()
    let ctx2 = newContext()
    let s = newSolver(ctx1)
    let x = mkIntVar(ctx1, "x")
    s.add x == mkInt(ctx1, 42)
    check s.check() == zsSat
    let m1 = s.model()
    let m2 = m1.translate(ctx2)
    # The translated model belongs to ctx2.
    check m2 != nil
    check m2.ctx == ctx2
    # The translated model should still have at least one const.
    check m2.numConsts >= 1

  test "translate — numConsts preserved across contexts":
    let ctx1 = newContext()
    let ctx2 = newContext()
    let s = newSolver(ctx1)
    let a = mkIntVar(ctx1, "a")
    let b = mkIntVar(ctx1, "b")
    s.add a + b == mkInt(ctx1, 5)
    s.add a > mkInt(ctx1, 0)
    check s.check() == zsSat
    let m1 = s.model()
    let n1 = m1.numConsts
    let m2 = m1.translate(ctx2)
    let n2 = m2.numConsts
    check n1 == n2

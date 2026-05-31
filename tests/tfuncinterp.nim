## `z3/funcdecl.Z3FuncInterp` tests — tabular UF model extraction
## (v0.5 step 6A).
##
## Z3 represents the model interpretation of an uninterpreted
## function as a sequence of `(args, value)` entries plus an
## else-value that applies to all other arg tuples. v0.3 step 7
## shipped `evalAt(m, f, args)` for point queries; this step ships
## the full tabular view — the canonical "show me what value `f`
## takes everywhere the solver pinned it" surface.

import std/[unittest]
import z3

suite "Z3FuncInterp — tracer":
  test "getFuncInterp extracts an interpretation handle from a solved model":
    let ctx = newContext()
    let f = mkFuncDecl[(Z3Int,), Z3Int]("f")
    let s = newSolver()
    s.add f(mkInt(0)) == mkInt(7)
    s.add f(mkInt(1)) == mkInt(11)
    check s.check() == zsSat
    let fi = getFuncInterp(s.model(), f)
    # arity = 1 (the (Z3Int,) tuple).
    check fi.arity == 1

suite "Z3FuncInterp — entries + else":
  test "interpretation captures both constrained points":
    # Z3 chooses how to store the interpretation: it may emit both
    # constraints as explicit entries, or fold one into the else-value
    # — the choice is solver-dependent and not part of our contract.
    # What IS our contract: walking the entries + else reproduces the
    # solver's pinned values exactly.
    let ctx = newContext()
    let f = mkFuncDecl[(Z3Int,), Z3Int]("f")
    let s = newSolver()
    s.add f(mkInt(0)) == mkInt(7)
    s.add f(mkInt(1)) == mkInt(11)
    check s.check() == zsSat
    let m = s.model()
    let fi = getFuncInterp(m, f)

    # Semantic check: every entry's value matches what `evalAt` says
    # at the same arg, AND `evalAt` at f(0) returns 7, f(1) returns 11.
    check evalAt(m, f, (mkInt(0),)).toInt == 7
    check evalAt(m, f, (mkInt(1),)).toInt == 11

    # Walk the entries and verify each is self-consistent: the
    # interpretation says f(entry.args) == entry.value, and so does
    # `evalAt`.
    for i in 0 ..< fi.len:
      let entry = fi[i]
      let argVal = entry.args[0].toInt
      let viaEntry = entry.value.toInt
      let viaEval = evalAt(m, f, entry.args).toInt
      check viaEntry == viaEval

    # The else-value is whatever Z3 picked — smoke: extractable.
    let elseVal = fi.elseValue.toInt
    discard elseVal

  test "zero-entry interpretation: f only constrained at one point":
    # When Z3 only pins f at one point, the table may have ONE entry
    # plus an else, OR zero entries with an else carrying the pinned
    # value — solver-dependent. Either way the total interpretation
    # captures the constraint.
    let ctx = newContext()
    let f = mkFuncDecl[(Z3Int,), Z3Int]("f")
    let s = newSolver()
    s.add f(mkInt(42)) == mkInt(99)
    check s.check() == zsSat
    let fi = getFuncInterp(s.model(), f)
    check fi.arity == 1
    # Shape contract: Z3 may report 0 entries (all signal in elseValue)
    # or 1 entry (the pinned point). Anything else would be a wrapper
    # bug.
    check fi.len in {0, 1}
    let m = s.model()
    # Regardless of which shape Z3 chose, the value at the pinned
    # point must be 99. AND: if Z3 chose the zero-entry shape, the
    # else-value MUST be 99 (it's the only thing carrying the
    # constraint). If Z3 chose the one-entry shape, the elseValue is
    # unconstrained — we don't pin it.
    check evalAt(m, f, (mkInt(42),)).toInt == 99
    if fi.len == 0:
      check fi.elseValue.toInt == 99

  test "two-arg function: f(Int, Int) -> Bool":
    let ctx = newContext()
    let f = mkFuncDecl[(Z3Int, Z3Int), Z3Bool]("f")
    let s = newSolver()
    s.add f(mkInt(1), mkInt(2)) == mkBool(true)
    s.add f(mkInt(3), mkInt(4)) == mkBool(false)
    check s.check() == zsSat
    let m = s.model()
    let fi = getFuncInterp(m, f)
    check fi.arity == 2
    # Semantic check: both constraints reproduce through evalAt.
    check evalAt(m, f, (mkInt(1), mkInt(2))).toBool == true
    check evalAt(m, f, (mkInt(3), mkInt(4))).toBool == false
    # Walk entries (however many Z3 chose to emit) and verify
    # each entry's value matches the model's interpretation.
    for i in 0 ..< fi.len:
      let entry = fi[i]
      let viaEntry = entry.value.toBool
      let viaEval = evalAt(m, f, entry.args).toBool
      check viaEntry == viaEval

suite "Z3FuncInterp — error path":
  test "model that didn't constrain the function raises Z3InvalidUsageError":
    # If the solver never sees the function in an asserted constraint,
    # the model has no interpretation for it; the wrapper raises rather
    # than returning a nil handle.
    let ctx = newContext()
    let f = mkFuncDecl[(Z3Int,), Z3Int]("f")
    let g = mkFuncDecl[(Z3Int,), Z3Int]("g")
    let s = newSolver()
    s.add g(mkInt(0)) == mkInt(7)  # constrain g only
    check s.check() == zsSat
    expect Z3InvalidUsageError:
      discard getFuncInterp(s.model(), f)

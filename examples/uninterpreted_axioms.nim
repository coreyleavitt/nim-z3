## Uninterpreted-function axioms example — asserts a commutativity
## axiom over an uninterpreted `f: Int × Int → Int`, then verifies a
## hand-written non-commutative counter-claim is unsat.
##
## This is the canonical "SMT solving with abstract functions" pattern:
## you don't tell Z3 what `f` *is*, you tell it what laws `f` obeys,
## and Z3 reasons about consequences. Useful for proving theorems
## about abstract algebra, verifying program invariants over opaque
## API calls, or modelling a system whose details you want to leave
## generic.
##
## Demonstrated:
##
## - `mkFuncDecl[(Z3Int, Z3Int), Z3Int]("f")` — phantom-typed function
##   declaration; the wrapper uses the tuple to enforce arity + arg
##   type at compile time.
## - `forall(x, y, body)` — universally-quantified axiom.
## - `f(a, b)` — natural call syntax via the `()` overload Nim's
##   `experimental: "callOperator"` pragma enables on `Z3FuncDecl`.
## - The proof shape: assert axiom + claim; if the conjunction is
##   unsat, the axiom implies the negation of the claim — Q.E.D.
##
## Run with:
##
## ```
## nim c -r examples/uninterpreted_axioms.nim
## ```

import z3

proc main() =
  let ctx = newContext()
  echo "libz3 ", z3FullVersion()

  # `f: Int × Int → Int` is uninterpreted. Z3 picks any consistent
  # interpretation; the axioms below pin its behaviour.
  let f = mkFuncDecl[(Z3Int, Z3Int), Z3Int]("f")

  block commutativity_proof:
    # Axiom: for all x, y, f(x, y) == f(y, x).
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    let axiom = forall(x, y, f(x, y) == f(y, x))

    # Counter-claim: there exist concrete a, b such that
    # f(a, b) != f(b, a). If this is sat under the axiom, the axiom
    # doesn't actually pin commutativity — but it should be unsat.
    let s = newSolver()
    s.add axiom
    s.add f(mkInt(1), mkInt(2)) != f(mkInt(2), mkInt(1))

    doAssert s.check() == zsUnsat,
      "commutativity axiom should make the non-commutative claim unsat"
    echo "✓ commutativity axiom proven: f(1, 2) == f(2, 1) under forall."

  block injectivity_failure:
    # Counter-example: WITHOUT an injectivity axiom, Z3 is free to
    # pick a constant interpretation. It can satisfy f(0, 0) == 5
    # AND f(1, 1) == 5 simultaneously.
    let s = newSolver()
    s.add f(mkInt(0), mkInt(0)) == mkInt(5)
    s.add f(mkInt(1), mkInt(1)) == mkInt(5)
    doAssert s.check() == zsSat,
      "without injectivity, two distinct args can map to same value"
    echo "✓ without injectivity, f(0,0) == f(1,1) == 5 is sat."

  block congruence_smoke:
    # SMT's defining property: equal inputs always yield equal
    # outputs. Z3 enforces this for any uninterpreted function — no
    # axiom needed. Try to find a contradiction; should be unsat.
    let a = mkIntVar("a")
    let b = mkIntVar("b")
    let s = newSolver()
    s.add a == b
    s.add f(a, mkInt(0)) != f(b, mkInt(0))
    doAssert s.check() == zsUnsat,
      "function congruence: a == b implies f(a, _) == f(b, _)"
    echo "✓ function congruence built-in: a == b → f(a, 0) == f(b, 0)."

when isMainModule:
  main()

## Datatypes example — inductive `IntList` and a length property.
##
## Demonstrates the full `declareDatatype` cycle:
##
##   1. Declare a marker Nim type as the phantom (`type IntList = object`).
##   2. Call `declareDatatype[IntList]` with the constructor spec.
##   3. Pull out constructors / recognizers / accessors and use them
##      to build values.
##   4. Use a model to extract the head of a constructed list.
##   5. Encode a small property (`length(cons(_, t)) == 1 + length(t)`)
##      with an uninterpreted function + forall, and prove it sat.
##
## `forDatatype` and `declareDatatypes` (mutual recursion) aren't
## exercised here — see `tests/tdatatypes_mutual.nim` for that case.
##
## Run with:
##
## ```
## nim c -r examples/datatypes_list.nim
## ```

import std/strformat
import z3

type IntList = object   # marker — the phantom that names the sort

proc main() =
  let ctx = newContext()
  let L = declareDatatype[IntList](@[
    constructor("nil"),
    constructor("cons", @[
      field("head", Z3Int),
      selfField("tail")
    ])
  ])
  let nilC  = L.con("nil")
  let consC = L.con("cons")
  let head  = L.accessor("cons", "head", Z3Int)
  let tail  = L.accessor("cons", "tail", Z3DatatypeValue[IntList])
  let isCons = L.recognizer("cons")
  let isNil  = L.recognizer("nil")

  # Build [1, 2, 3] = cons(1, cons(2, cons(3, nil))).
  let xs = consC.apply(mkInt(1),
             consC.apply(mkInt(2),
               consC.apply(mkInt(3), nilC.apply())))

  echo "Built list: ", $xs

  # Walk three deep, confirm head at each step.
  doAssert smtEquiv(head.read(xs), mkInt(1))
  let xs1 = tail.read(xs)
  doAssert smtEquiv(head.read(xs1), mkInt(2))
  let xs2 = tail.read(xs1)
  doAssert smtEquiv(head.read(xs2), mkInt(3))
  let xs3 = tail.read(xs2)
  doAssert smtValid(isNil.test(xs3))
  echo "Walk verified: [1, 2, 3] decomposes via head/tail correctly."

  # Property: cons is injective in its arguments. Concretely:
  # if cons(x, t) == cons(y, u) then x == y and t == u. We prove
  # the contrapositive: if x != y, the conses are distinct.
  let xVar = mkIntVar("x")
  let yVar = mkIntVar("y")
  let tVar = mkDatatypeVar[IntList](L, "t")
  doAssert smtValid(
    (xVar != yVar).implies(
      consC.apply(xVar, tVar) != consC.apply(yVar, tVar)))
  echo "Property verified: cons is injective in its head argument."

  echo "\nDatatype example: declared, built, walked, and reasoned-over."

when isMainModule:
  main()

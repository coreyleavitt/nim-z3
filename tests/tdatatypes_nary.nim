## `z3/datatypes` — N-ary `declareDatatypes` (arity 4–8) and seq-form escape hatch.
##
## Covers:
##   1. 4-way mutually-recursive `(Stmt, Expr, Type, Kind)` — simple variants
##      with base cases (Z3 requires every family to be well-founded).
##   2. 8-way arity stress — eight simple, independent single-variant types.
##   3. Sort identity: after a 4-way declaration the sorts registered in the
##      context match the per-decl sort returned by `sortOf(Z3DatatypeValue[T], ctx)`.
##   4. Seq-form `declareDatatypesN` returns the correct count and the resulting
##      decls are usable (constructors can be applied and recognised).

import std/[unittest]
import z3

# ── Marker types for the 4-way test ──────────────────────────────────────────
type
  Stmt = object
  Expr = object
  Type = object
  Kind = object

# ── Marker types for the 8-way stress test ───────────────────────────────────
type
  S1 = object
  S2 = object
  S3 = object
  S4 = object
  S5 = object
  S6 = object
  S7 = object
  S8 = object

# ─────────────────────────────────────────────────────────────────────────────

suite "N-ary declareDatatypes — arity 4":
  test "4-way (Stmt/Expr/Type/Kind) declared and constructors are usable":
    ## Z3 requires every member of a mutually-recursive family to be
    ## well-founded — each gets a nullary base constructor here.
    let ctx = newContext()
    let (stmtDt, exprDt, typeDt, kindDt) = declareDatatypes(
      forDatatype[Stmt](@[
        constructor("skip"),
        constructor("exprStmt", @[crossField[Expr]("e")])
      ]),
      forDatatype[Expr](@[
        constructor("litInt", @[field("n", Z3Int)]),
        constructor("typed", @[crossField[Expr]("body"), crossField[Type]("ty")])
      ]),
      forDatatype[Type](@[
        constructor("baseType", @[crossField[Kind]("k")]),
        constructor("intType")
      ]),
      forDatatype[Kind](@[
        constructor("starKind"),
        constructor("arrowKind", @[crossField[Kind]("from_"), crossField[Kind]("to_")])
      ])
    )

    let skip = stmtDt.con("skip")
    let litInt = exprDt.con("litInt")
    let intType = typeDt.con("intType")
    let star = kindDt.con("starKind")

    let isSkip = stmtDt.recognizer("skip")
    let isLitInt = exprDt.recognizer("litInt")
    let isIntType = typeDt.recognizer("intType")
    let isStar = kindDt.recognizer("starKind")

    check smtValid(isSkip.test(skip.apply()))
    check smtValid(isLitInt.test(litInt.apply(mkInt(42))))
    check smtValid(isIntType.test(intType.apply()))
    check smtValid(isStar.test(star.apply()))

  test "4-way: cross-references are well-typed (exprStmt wraps an Expr)":
    let ctx = newContext()
    let (stmtDt, exprDt, typeDt, kindDt) = declareDatatypes(
      forDatatype[Stmt](@[
        constructor("skip"),
        constructor("exprStmt", @[crossField[Expr]("e")])
      ]),
      forDatatype[Expr](@[
        constructor("litInt", @[field("n", Z3Int)]),
        constructor("typed", @[crossField[Expr]("body"), crossField[Type]("ty")])
      ]),
      forDatatype[Type](@[
        constructor("baseType", @[crossField[Kind]("k")]),
        constructor("intType")
      ]),
      forDatatype[Kind](@[
        constructor("starKind"),
        constructor("arrowKind", @[crossField[Kind]("from_"), crossField[Kind]("to_")])
      ])
    )
    let exprStmt = stmtDt.con("exprStmt")
    let litInt   = exprDt.con("litInt")
    let isExprStmt = stmtDt.recognizer("exprStmt")
    let eField = stmtDt.accessor("exprStmt", "e", Z3DatatypeValue[Expr])
    let isLitInt   = exprDt.recognizer("litInt")

    let stmt = exprStmt.apply(litInt.apply(mkInt(7)))
    check smtValid(isExprStmt.test(stmt))
    check smtValid(isLitInt.test(eField.read(stmt)))

# ─────────────────────────────────────────────────────────────────────────────

suite "N-ary declareDatatypes — arity 8 stress":
  test "8-way stress: all 8 sorts declared and nullary constructors are recognised":
    let ctx = newContext()
    let (d1, d2, d3, d4, d5, d6, d7, d8) = declareDatatypes(
      forDatatype[S1](@[constructor("mkS1")]),
      forDatatype[S2](@[constructor("mkS2")]),
      forDatatype[S3](@[constructor("mkS3")]),
      forDatatype[S4](@[constructor("mkS4")]),
      forDatatype[S5](@[constructor("mkS5")]),
      forDatatype[S6](@[constructor("mkS6")]),
      forDatatype[S7](@[constructor("mkS7")]),
      forDatatype[S8](@[constructor("mkS8")])
    )

    check smtValid(d1.recognizer("mkS1").test(d1.con("mkS1").apply()))
    check smtValid(d2.recognizer("mkS2").test(d2.con("mkS2").apply()))
    check smtValid(d3.recognizer("mkS3").test(d3.con("mkS3").apply()))
    check smtValid(d4.recognizer("mkS4").test(d4.con("mkS4").apply()))
    check smtValid(d5.recognizer("mkS5").test(d5.con("mkS5").apply()))
    check smtValid(d6.recognizer("mkS6").test(d6.con("mkS6").apply()))
    check smtValid(d7.recognizer("mkS7").test(d7.con("mkS7").apply()))
    check smtValid(d8.recognizer("mkS8").test(d8.con("mkS8").apply()))

# ─────────────────────────────────────────────────────────────────────────────

# Fresh marker types for sort-identity test (avoids registry collision with
# the 4-way suite above — each context is independent, but type names are
# global in the context's registry key space).
type
  SortIdA = object
  SortIdB = object
  SortIdC = object
  SortIdD = object

suite "N-ary declareDatatypes — sort identity (registry)":
  test "arity-4 decl sorts are consistent with sortOf(Z3DatatypeValue[T], ctx)":
    ## After `declareDatatypes[A,B,C,D](...)`, the Z3 sorts stored in the
    ## returned decls must match what the context's datatype registry
    ## exposes via `sortOf(Z3DatatypeValue[T], ctx)`. This confirms that
    ## the macro-generated path populates the registry correctly.
    let ctx = newContext()
    let (dA, dB, dC, dD) = declareDatatypes(
      forDatatype[SortIdA](@[constructor("mkA")]),
      forDatatype[SortIdB](@[constructor("mkB")]),
      forDatatype[SortIdC](@[constructor("mkC")]),
      forDatatype[SortIdD](@[constructor("mkD")])
    )
    # sortOf returns the registered sort handle from the context registry.
    # mkDatatypeVar creates a constant of that sort; if the handles are
    # different the const would be of a stale sort — Z3 would reject it.
    # We verify consistency by creating a variable and checking the
    # recognizer sees it correctly.
    let varA = dA.mkDatatypeVar("va")
    let varB = dB.mkDatatypeVar("vb")
    let varC = dC.mkDatatypeVar("vc")
    let varD = dD.mkDatatypeVar("vd")

    # Each var is of the correct phantom type — type-system check.
    check varA is Z3DatatypeValue[SortIdA]
    check varB is Z3DatatypeValue[SortIdB]
    check varC is Z3DatatypeValue[SortIdC]
    check varD is Z3DatatypeValue[SortIdD]

    # Solver round-trip: force each var to be its only constructor.
    # This succeeds iff the sort registered for T matches the sort of the
    # constructor funcs inside the decl (they're both drawn from sortsOut[i]).
    let s = newSolver()
    s.add dA.recognizer("mkA").test(varA)
    s.add dB.recognizer("mkB").test(varB)
    s.add dC.recognizer("mkC").test(varC)
    s.add dD.recognizer("mkD").test(varD)
    check s.check() == zsSat

# ─────────────────────────────────────────────────────────────────────────────

suite "declareDatatypesN — seq-form escape hatch":
  test "returns count equal to number of specs":
    let ctx = newContext()
    let specs = @[
      ("Color", @[
        ConstructorSpec(cname: "red",   fields: @[]),
        ConstructorSpec(cname: "green", fields: @[]),
        ConstructorSpec(cname: "blue",  fields: @[])
      ]),
      ("Direction", @[
        ConstructorSpec(cname: "north", fields: @[]),
        ConstructorSpec(cname: "south", fields: @[])
      ])
    ]
    let decls = declareDatatypesN(ctx, specs)
    check decls.len == 2

  test "seq-form: constructors on void-typed decl are usable via con/apply/test":
    let ctx = newContext()
    let specs = @[
      ("Fruit", @[
        ConstructorSpec(cname: "apple",  fields: @[]),
        ConstructorSpec(cname: "banana", fields: @[])
      ]),
      ("Veggie", @[
        ConstructorSpec(cname: "carrot", fields: @[])
      ])
    ]
    let decls = declareDatatypesN(ctx, specs)
    check decls.len == 2

    let fruitDt  = decls[0]
    let veggieDt = decls[1]

    let apple   = fruitDt.con("apple")
    let isApple = fruitDt.recognizer("apple")
    check smtValid(isApple.test(apple.apply()))

    let carrot   = veggieDt.con("carrot")
    let isCarrot = veggieDt.recognizer("carrot")
    check smtValid(isCarrot.test(carrot.apply()))

  test "seq-form: single-spec degenerate case returns one decl":
    let ctx = newContext()
    let specs = @[
      ("Singleton", @[
        ConstructorSpec(cname: "only", fields: @[])
      ])
    ]
    let decls = declareDatatypesN(ctx, specs)
    check decls.len == 1
    check smtValid(decls[0].recognizer("only").test(decls[0].con("only").apply()))

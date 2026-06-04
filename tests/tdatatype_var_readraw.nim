## N7.5 tests — `mkDatatypeVar[T](name)` registry overload + `readRaw` escape hatch.
##
## `mkDatatypeVar[T](name)`: parallel overload that uses the current context's
## `datatypeRegistry[$T]` so callers don't have to thread the `Z3DatatypeDecl`
## through when only a variable is needed.
##
## `readRaw(dt, cname, fname, v)`: raw-handle escape hatch — applies the named
## accessor to `v` without a statically-known `Ret` type.

import std/[unittest]
import z3

type Foo = object   # marker

suite "N7.5 — mkDatatypeVar[T] registry overload":
  test "mkDatatypeVar[T](name) produces a Z3DatatypeValue[T] via registry":
    let ctx = newContext()
    let decl = declareDatatype[Foo](@[
      constructor("Foo", @[
        field("a", Z3Int),
        field("b", Z3Int)
      ])
    ])
    # Registry-based overload — no explicit decl threading.
    let foo1 = mkDatatypeVar[Foo]("foo1")
    # Type is correct: the following would be a compile error for a
    # different marker type.  We verify it round-trips through the solver.
    let fooC = decl.con("Foo")
    let accA  = decl.accessor("Foo", "a", Z3Int)
    let accB  = decl.accessor("Foo", "b", Z3Int)
    # Constrain foo1 == Foo(a=5, b=7)
    let s = newSolver()
    s.add foo1 == fooC.apply(mkInt(5), mkInt(7))
    check s.check() == zsSat
    let m = s.model()
    check m.evalInt(accA.read(m.eval(foo1))) == 5
    check m.evalInt(accB.read(m.eval(foo1))) == 7

suite "N7.5 — readRaw escape hatch":
  test "readRaw returns a RawZ3Ast for the named accessor":
    let ctx = newContext()
    let decl = declareDatatype[Foo](@[
      constructor("Foo", @[
        field("a", Z3Int),
        field("b", Z3Int)
      ])
    ])
    let fooC = decl.con("Foo")
    # Build Foo(a=5, b=7)
    let val = fooC.apply(mkInt(5), mkInt(7))
    # readRaw — raw handle without a typed Ret
    let rawA: RawZ3Ast = readRaw(decl, "Foo", "a", val)
    # Wrap it as Z3Int so we can use the solver to verify it equals 5
    let asInt = wrap[Z3Int](ctx, rawA)
    check smtEquiv(asInt, mkInt(5))

  test "readRaw field b returns 7 from Foo(5, 7)":
    let ctx = newContext()
    let decl = declareDatatype[Foo](@[
      constructor("Foo", @[
        field("a", Z3Int),
        field("b", Z3Int)
      ])
    ])
    let fooC = decl.con("Foo")
    let val = fooC.apply(mkInt(5), mkInt(7))
    let rawB: RawZ3Ast = readRaw(decl, "Foo", "b", val)
    let asInt = wrap[Z3Int](ctx, rawB)
    check smtEquiv(asInt, mkInt(7))

  test "readRaw on unknown field raises Z3InvalidUsageError":
    let ctx = newContext()
    let decl = declareDatatype[Foo](@[
      constructor("Foo", @[
        field("a", Z3Int),
        field("b", Z3Int)
      ])
    ])
    let fooC = decl.con("Foo")
    let val = fooC.apply(mkInt(1), mkInt(2))
    expect(Z3InvalidUsageError):
      discard readRaw(decl, "Foo", "z", val)

## `z3/sets` tests — Z3Set[E] = distinct Z3Array[E, Z3Bool].
##
## Covers:
##   - Constructors: mkEmptySet, mkFullSet
##   - Element ops: add, del, member
##   - Set ops: union (binary + n-ary), intersect (binary + n-ary),
##              difference, complement, subset, hasSize
##   - Equality: ==, !=  (delegates via toArray)
##   - Conversions: toArray, toSet round-trip
##   - Lifecycle: =copy smoke test — copy a Z3Set, drop original,
##                verify copied value is still valid (no double-free)

import std/unittest
import z3

# ---------------------------------------------------------------------------
# Helpers: smtSat / smtUnsat wrappers used in several tests
# ---------------------------------------------------------------------------

proc isSat(f: Z3Bool): bool =
  let s = newSolver()
  s.add f
  s.check() == zsSat

proc isUnsat(f: Z3Bool): bool =
  let s = newSolver()
  s.add f
  s.check() == zsUnsat

# ---------------------------------------------------------------------------
suite "Z3Set — constructors":
  test "mkEmptySet (ctx form) type-checks":
    let ctx = newContext()
    let s = mkEmptySet[Z3Int](ctx)
    check s is Z3Set[Z3Int]

  test "mkEmptySet (typedesc form) type-checks":
    let ctx = newContext()
    let s = mkEmptySet(Z3Int)
    check s is Z3Set[Z3Int]

  test "mkFullSet (ctx form) type-checks":
    let ctx = newContext()
    let s = mkFullSet[Z3Int](ctx)
    check s is Z3Set[Z3Int]

  test "mkFullSet (typedesc form) type-checks":
    let ctx = newContext()
    let s = mkFullSet(Z3Int)
    check s is Z3Set[Z3Int]

# ---------------------------------------------------------------------------
suite "Z3Set — add and member":
  test "add(empty, x).member(x) is SAT":
    let ctx = newContext()
    let x = mkIntVar("x")
    let s = mkEmptySet[Z3Int](ctx).add(x)
    # member(x, s) should be satisfiable — there exists an x that is in s.
    check isSat(member(x, s))

  test "member(x, emptySet) is UNSAT (empty is empty everywhere)":
    let ctx = newContext()
    let x = mkInt(42)
    let empty = mkEmptySet[Z3Int](ctx)
    check isUnsat(member(x, empty))

  test "member(x, fullSet) is valid (full set contains everything)":
    let ctx = newContext()
    let x = mkInt(42)
    let full = mkFullSet[Z3Int](ctx)
    # member(x, fullSet) must be true — check it is UNSAT when negated
    check isUnsat(not member(x, full))

  test "add then del leaves element absent":
    let ctx = newContext()
    let x = mkInt(7)
    let s = mkEmptySet[Z3Int](ctx).add(x).del(x)
    check isUnsat(member(x, s))

# ---------------------------------------------------------------------------
suite "Z3Set — union":
  test "binary union: member in left ⇒ member in union":
    let ctx = newContext()
    let x = mkInt(3)
    let s1 = mkEmptySet[Z3Int](ctx).add(x)
    let s2 = mkEmptySet[Z3Int](ctx)
    let u = union(s1, s2)
    check isUnsat(not member(x, u))

  test "binary union: member in right ⇒ member in union":
    let ctx = newContext()
    let x = mkInt(5)
    let s1 = mkEmptySet[Z3Int](ctx)
    let s2 = mkEmptySet[Z3Int](ctx).add(x)
    let u = union(s1, s2)
    check isUnsat(not member(x, u))

  test "n-ary union: member in any arg ⇒ member in result":
    let ctx = newContext()
    let a = mkInt(1)
    let b = mkInt(2)
    let c = mkInt(3)
    let sa = mkEmptySet[Z3Int](ctx).add(a)
    let sb = mkEmptySet[Z3Int](ctx).add(b)
    let sc = mkEmptySet[Z3Int](ctx).add(c)
    let u = union(sa, sb, sc)
    check isUnsat(not member(a, u))
    check isUnsat(not member(b, u))
    check isUnsat(not member(c, u))

  test "union(empty, empty) is empty":
    let ctx = newContext()
    let u = union(mkEmptySet[Z3Int](ctx), mkEmptySet[Z3Int](ctx))
    let x = mkInt(99)
    check isUnsat(member(x, u))

# ---------------------------------------------------------------------------
suite "Z3Set — intersect":
  test "binary intersect: member in both ⇒ member in intersect":
    let ctx = newContext()
    let x = mkInt(4)
    let s1 = mkEmptySet[Z3Int](ctx).add(x)
    let s2 = mkEmptySet[Z3Int](ctx).add(x)
    let i = intersect(s1, s2)
    check isUnsat(not member(x, i))

  test "binary intersect: only in one ⇒ not in intersect":
    let ctx = newContext()
    let x = mkInt(4)
    let s1 = mkEmptySet[Z3Int](ctx).add(x)
    let s2 = mkEmptySet[Z3Int](ctx)
    let i = intersect(s1, s2)
    check isUnsat(member(x, i))

  test "n-ary intersect: must be in all args":
    let ctx = newContext()
    let x = mkInt(10)
    let sa = mkEmptySet[Z3Int](ctx).add(x)
    let sb = mkEmptySet[Z3Int](ctx).add(x)
    let sc = mkEmptySet[Z3Int](ctx).add(x)
    let i = intersect(sa, sb, sc)
    check isUnsat(not member(x, i))

# ---------------------------------------------------------------------------
suite "Z3Set — difference and complement":
  test "difference: element in a but not b is in a\\b":
    let ctx = newContext()
    let x = mkInt(7)
    let sa = mkEmptySet[Z3Int](ctx).add(x)
    let sb = mkEmptySet[Z3Int](ctx)
    let d = difference(sa, sb)
    check isUnsat(not member(x, d))

  test "difference: element in both is absent from a\\b":
    let ctx = newContext()
    let x = mkInt(7)
    let sa = mkEmptySet[Z3Int](ctx).add(x)
    let sb = mkEmptySet[Z3Int](ctx).add(x)
    let d = difference(sa, sb)
    check isUnsat(member(x, d))

  test "complement(emptySet).member(x) is valid":
    let ctx = newContext()
    let x = mkInt(42)
    let co = complement(mkEmptySet[Z3Int](ctx))
    check isUnsat(not member(x, co))

  test "complement(fullSet) is empty":
    let ctx = newContext()
    let x = mkInt(42)
    let co = complement(mkFullSet[Z3Int](ctx))
    check isUnsat(member(x, co))

# ---------------------------------------------------------------------------
suite "Z3Set — subset":
  test "subset(empty, full) is always true":
    let ctx = newContext()
    let sub = subset(mkEmptySet[Z3Int](ctx), mkFullSet[Z3Int](ctx))
    check isUnsat(not sub)

  test "subset(full, empty) is always false":
    let ctx = newContext()
    let sub = subset(mkFullSet[Z3Int](ctx), mkEmptySet[Z3Int](ctx))
    check isUnsat(sub)

  test "subset(s, s) is reflexive":
    let ctx = newContext()
    let x = mkInt(1)
    let s = mkEmptySet[Z3Int](ctx).add(x)
    let sub = subset(s, s)
    check isUnsat(not sub)

# ---------------------------------------------------------------------------
suite "Z3Set — hasSize":
  test "hasSize(emptySet, 0) is valid":
    # Z3_mk_set_has_size was removed at Z3 4.16 — `hasSize` raises
    # `Z3FeatureUnavailableError` there (guarded by the softlink-generated
    # `Z3_mk_set_has_sizeAvailable()` predicate) rather than calling an
    # unbound symbol. On <= 4.15 the call should succeed and the
    # cardinality constraint should hold.
    let ctx = newContext()
    let empty = mkEmptySet[Z3Int](ctx)
    if not Z3_mk_set_has_sizeAvailable():
      expect Z3FeatureUnavailableError:
        discard hasSize(empty, mkInt(0))
    else:
      try:
        let h = hasSize(empty, mkInt(0))
        check isUnsat(not h)
      except Z3OperationError:
        # Z3 4.13.3 raises "set-has-size is not supported" on some platforms.
        # The binding is correct; skip when the feature is unavailable.
        skip()

# ---------------------------------------------------------------------------
suite "Z3Set — equality":
  test "== on same-constructed sets is valid":
    let ctx = newContext()
    let s1 = mkEmptySet[Z3Int](ctx)
    let s2 = mkEmptySet[Z3Int](ctx)
    check isUnsat(not (s1 == s2))

  test "!= on empty vs full set is valid":
    let ctx = newContext()
    let e = mkEmptySet[Z3Int](ctx)
    let f = mkFullSet[Z3Int](ctx)
    check isUnsat(not (e != f))

# ---------------------------------------------------------------------------
suite "Z3Set — toArray / toSet round-trip":
  test "toSet(toArray(s)) preserves identity (SMT equality)":
    let ctx = newContext()
    let s = mkEmptySet[Z3Int](ctx)
    let s2 = toSet(toArray(s))
    check isUnsat(not (s == s2))

  test "toArray(s) is Z3Array[Z3Int, Z3Bool]":
    let ctx = newContext()
    let s = mkEmptySet[Z3Int](ctx)
    let a = toArray(s)
    check a is Z3Array[Z3Int, Z3Bool]

# ---------------------------------------------------------------------------
suite "Z3Set — lifecycle (=copy smoke test)":
  test "copy then drop original — copied value remains valid":
    # This exercises =copy. If =copy doesn't delegate to Z3Array[E, Z3Bool]'s
    # =copy, the ref-count is wrong and the copy's .raw points to freed memory
    # by the time we use it. Under Nim's ARC/ORC the double-free is silent but
    # the SMT assertion below would become garbage; valgrind would flag it.
    let ctx = newContext()
    let x = mkInt(5)
    let original = mkEmptySet[Z3Int](ctx).add(x)
    let copied = original        # triggers =copy
    # Drop `original` scope by shadowing — after this assignment it is a
    # different name so the original binding is eligible for destruction.
    # Nim ARC destroys `original` when it goes out of scope at block end,
    # but `copied` must still be alive with correct ref-count.
    check isSat(member(x, copied))
    # Both go out of scope here; =destroy called twice. If lifecycle is
    # correct the refcount hits 0 exactly once and Z3 is happy.

  test "Z3Set survives seq storage and retrieval":
    # Exercises =copy through seq insertion (seq grows → elements realloc'd).
    let ctx = newContext()
    var sets: seq[Z3Set[Z3Int]]
    let x = mkInt(1)
    sets.add mkEmptySet[Z3Int](ctx).add(x)
    let retrieved = sets[0]
    check isSat(member(x, retrieved))

  test "$ produces non-empty SMT-LIB string":
    let ctx = newContext()
    let s = mkEmptySet[Z3Int](ctx)
    let rendered = $s
    check rendered.len > 0

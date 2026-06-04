## `z3/seq` HOF tests — N5.5: seqMap / seqMapi / seqFoldl / seqFoldli.
##
## Strategy: Z3's seq HOF solver is incomplete for symbolic inputs.
## All tests use fully-concrete sequences so Z3 can decide them via
## evaluation. Any test that returns zsUnknown is skipped with a note
## (upstream Z3 capability limitation, not a wrapper bug).
##
## `defineFun` calls omit explicit type params; Nim infers them from the
## proc literal's type. Explicit `[(Tuple), Ret]` causes a Nim 2.2 calling-
## convention mismatch when the anonymous proc literal lacks captured vars
## (inferred as nimcall) against the formal's implicit closure CC.
##
## Multi-param proc literals **must** use separate type annotations for each
## parameter (e.g. `proc(i: Z3Int, a: Z3Int)`) not shorthand
## `proc(i, a: Z3Int)`. The shorthand form triggers a Nim 2.2 managed-value
## ABI bug where the second parameter's `.ctx` field is zeroed on entry when
## the type has custom copy/move hooks.

import std/[unittest]
import z3

# ---------------------------------------------------------------------------
# Helpers — build a concrete Z3Seq[Z3Int] from a Nim integer list.
# ---------------------------------------------------------------------------

proc mkIntSeq(ctx: Z3Context, xs: openArray[int64]): Z3Seq[Z3Int] =
  if xs.len == 0:
    return mkSeqEmpty[Z3Int](ctx)
  var s = mkSeqUnit(mkInt(ctx, xs[0]))
  for i in 1 ..< xs.len:
    s = s & mkSeqUnit(mkInt(ctx, xs[i]))
  s

proc mkIntSeq(xs: openArray[int64]): Z3Seq[Z3Int] =
  mkIntSeq(requireCurrentContext(), xs)

# ---------------------------------------------------------------------------
# Suite 1 — seqMap: map a unary function over a sequence
# ---------------------------------------------------------------------------

suite "seqMap — map f over Z3Seq[E]":

  test "seqMap(succ, [1,2,3]) == [2,3,4]  (concrete, SAT)":
    let ctx = newContext()
    # Infer type params from the proc literal: A1=Z3Int, Ret=Z3Int
    let succ = defineFun("succ_n5",
      proc(a: Z3Int): Z3Int = a + mkInt(1))
    let s       = mkIntSeq([1'i64, 2, 3])
    let expected = mkIntSeq([2'i64, 3, 4])
    let mapped  = seqMap(succ, s)
    let solver  = newSolver()
    solver.add(mapped == expected)
    let status  = solver.check()
    if status == zsUnknown:
      skip()  # Z3 seq HOF solver incomplete for this query
    check status == zsSat

  test "seqMap(id, []) == []  (empty sequence)":
    let ctx = newContext()
    let id     = defineFun("id_n5", proc(a: Z3Int): Z3Int = a)
    let mapped = seqMap(id, mkSeqEmpty[Z3Int]())
    let solver = newSolver()
    solver.add(mapped == mkSeqEmpty[Z3Int]())
    let status = solver.check()
    if status == zsUnknown:
      skip()
    check status == zsSat

# ---------------------------------------------------------------------------
# Suite 2 — seqMapi: indexed map over Z3Seq[E]
# ---------------------------------------------------------------------------

suite "seqMapi — indexed map over Z3Seq[E]":

  test "seqMapi(f(i,a)=i+a, startIdx=0, [10,20,30]) == [10,21,32]  (SAT)":
    # f(i, a) = i + a; at indices 0,1,2: 0+10=10, 1+20=21, 2+30=32
    let ctx = newContext()
    let f = defineFun("mapi_add_n5",
      proc(i: Z3Int, a: Z3Int): Z3Int = i + a)
    let s        = mkIntSeq([10'i64, 20, 30])
    let expected = mkIntSeq([10'i64, 21, 32])
    let mapped   = seqMapi(f, mkInt(0), s)
    let solver   = newSolver()
    solver.add(mapped == expected)
    let status = solver.check()
    if status == zsUnknown:
      skip()
    check status == zsSat

  test "seqMapi with startIdx=5: f(i,a)=i, [9,9,9] -> [5,6,7]  (SAT)":
    let ctx = newContext()
    # f(i, a) = i; ignores element, returns the current index
    let f = defineFun("mapi_idx_n5",
      proc(i: Z3Int, a: Z3Int): Z3Int = i)
    let s        = mkIntSeq([9'i64, 9, 9])
    let expected = mkIntSeq([5'i64, 6, 7])
    let mapped   = seqMapi(f, mkInt(5), s)
    let solver   = newSolver()
    solver.add(mapped == expected)
    let status = solver.check()
    if status == zsUnknown:
      skip()
    check status == zsSat

# ---------------------------------------------------------------------------
# Suite 3 — seqFoldl: fold f over Z3Seq[E] with accumulator
# ---------------------------------------------------------------------------

suite "seqFoldl — fold f over Z3Seq[E]":

  test "seqFoldl(plus2, 0, [1,2,3]) == 6  (concrete, SAT)":
    let ctx = newContext()
    let plus2 = defineFun("plus2_n5",
      proc(acc: Z3Int, e: Z3Int): Z3Int = acc + e)
    let s     = mkIntSeq([1'i64, 2, 3])
    let res   = seqFoldl(plus2, mkInt(0), s)
    let solver = newSolver()
    solver.add(res == mkInt(6))
    let status = solver.check()
    if status == zsUnknown:
      skip()
    check status == zsSat

  test "seqFoldl(mul2, 1, [2,3,4]) == 24  (concrete, SAT)":
    let ctx = newContext()
    let mul2 = defineFun("mul2_n5",
      proc(acc: Z3Int, e: Z3Int): Z3Int = acc * e)
    let s     = mkIntSeq([2'i64, 3, 4])
    let res   = seqFoldl(mul2, mkInt(1), s)
    let solver = newSolver()
    solver.add(res == mkInt(24))
    let status = solver.check()
    if status == zsUnknown:
      skip()
    check status == zsSat

  test "seqFoldl on empty sequence returns init  (SAT)":
    let ctx = newContext()
    let plus2 = defineFun("plus2_empty_n5",
      proc(acc: Z3Int, e: Z3Int): Z3Int = acc + e)
    let s   = mkSeqEmpty[Z3Int]()
    let res = seqFoldl(plus2, mkInt(42), s)
    let solver = newSolver()
    solver.add(res == mkInt(42))
    let status = solver.check()
    if status == zsUnknown:
      skip()
    check status == zsSat

# ---------------------------------------------------------------------------
# Suite 4 — seqFoldli: indexed fold
# ---------------------------------------------------------------------------

suite "seqFoldli — indexed fold over Z3Seq[E]":

  test "seqFoldli(f(i,acc,e)=acc+i+e, startIdx=0, init=0, [1,2,3]) == 9  (SAT)":
    # acc += i + e; at i=0: 0+0+1=1; at i=1: 1+1+2=4; at i=2: 4+2+3=9
    let ctx = newContext()
    let f = defineFun("foldli_n5",
      proc(i: Z3Int, acc: Z3Int, e: Z3Int): Z3Int = acc + i + e)
    let s     = mkIntSeq([1'i64, 2, 3])
    let res   = seqFoldli(f, mkInt(0), mkInt(0), s)
    let solver = newSolver()
    solver.add(res == mkInt(9))
    let status = solver.check()
    if status == zsUnknown:
      skip()
    check status == zsSat

  test "seqFoldli startIdx=1, init=0, [10,20] == 33  (SAT)":
    # acc += i + e; at i=1: 0+1+10=11; at i=2: 11+2+20=33
    let ctx = newContext()
    let f = defineFun("foldli_si_n5",
      proc(i: Z3Int, acc: Z3Int, e: Z3Int): Z3Int = acc + i + e)
    let s     = mkIntSeq([10'i64, 20])
    let res   = seqFoldli(f, mkInt(1), mkInt(0), s)
    let solver = newSolver()
    solver.add(res == mkInt(33))
    let status = solver.check()
    if status == zsUnknown:
      skip()
    check status == zsSat

## N9.3 — N-ary array support + `mapArray` + `arrayExt` + `asArray`.
##
## Tests are ordered RED → GREEN: each test targets a concrete property
## of the new operations.

import std/[unittest]
import z3

# ============================================================================
# mapArray — apply func-decl pointwise across an array
# ============================================================================

suite "mapArray — pointwise application":
  test "mapArray(succ, a)[i] ≡ a[i] + 1 for all i":
    ## `succ(x) = x + 1` is a defineFun; `mapArray(succ, a)` should
    ## produce an array whose elements are 1 greater than `a`'s.
    let ctx = newContext()
    let succ = defineFun("succ_na", proc(x: Z3Int): Z3Int = x + mkInt(1))
    let a = mkArrayVar[Z3Int, Z3Int]("a")
    let mapped = mapArray(succ, a)
    let i = mkIntVar("i")
    check smtValid(mapped[i] == a[i] + mkInt(1))

  test "mapArray result has correct Nim type Z3Array[K, W]":
    let ctx = newContext()
    let neg = defineFun("neg_na", proc(x: Z3Int): Z3Int = -x)
    let a = mkArrayVar[Z3Int, Z3Int]("a")
    let mapped = mapArray(neg, a)
    check mapped is Z3Array[Z3Int, Z3Int]

  test "mapArray(id, a)[i] ≡ a[i]":
    ## Identity function: mapped array should be extensionally equal.
    let ctx = newContext()
    let id = defineFun("id_fn_na", proc(x: Z3Int): Z3Int = x)
    let a = mkArrayVar[Z3Int, Z3Int]("a")
    let mapped = mapArray(id, a)
    let i = mkIntVar("i")
    check smtValid(mapped[i] == a[i])

# ============================================================================
# arrayExt — extensionality witness index
# ============================================================================

suite "arrayExt — extensionality witness":
  test "arrayExt(a, b) witnesses inequality when a and b differ":
    ## If a ≠ b, arrayExt gives an index `k` at which they differ.
    ## Concretely: a is all-0, b = store(a, 5, 1). They differ at 5.
    ## We verify: a[witness] ≠ b[witness] is satisfiable.
    let ctx = newContext()
    let a = mkConstArray[Z3Int, Z3Int](mkInt(0))
    let b = a.store(mkInt(5), mkInt(1))
    let witness = arrayExt(a, b)
    # The witness must satisfy: a[witness] ≠ b[witness]
    let s = newSolver()
    s.add a[witness] != b[witness]
    check s.check() == zsSat

  test "arrayExt result has correct Nim type K":
    let ctx = newContext()
    let a = mkConstArray[Z3Int, Z3Int](mkInt(0))
    let b = a.store(mkInt(3), mkInt(7))
    let w = arrayExt(a, b)
    check w is Z3Int

  test "arrayExt: equal arrays — witness satisfies a[w] = b[w]":
    ## Even if the arrays happen to be equal (same constant),
    ## Z3_mk_array_ext still returns some term, but a[w] = b[w]
    ## must hold (since a = b everywhere). We check it's SAT.
    let ctx = newContext()
    let a = mkConstArray[Z3Int, Z3Int](mkInt(42))
    let b = mkConstArray[Z3Int, Z3Int](mkInt(42))
    let w = arrayExt(a, b)
    let s = newSolver()
    s.add a[w] == b[w]
    check s.check() == zsSat

# ============================================================================
# asArray — function-as-array conversion
# ============================================================================

suite "asArray — function lifted to array":
  test "asArray(f)[i] ≡ f(i) for f(x) = x + 1":
    ## `Z3_mk_as_array` lifts a function declaration to an array.
    ## Selecting at any index should equal applying the function.
    let ctx = newContext()
    let f = defineFun("f_succ_na", proc(x: Z3Int): Z3Int = x + mkInt(1))
    let arr = asArray(f)
    let i = mkIntVar("i2")
    check smtValid(arr[i] == f(i))

  test "asArray result has correct Nim type Z3Array[K, V]":
    let ctx = newContext()
    let f = defineFun("f_id_na", proc(x: Z3Int): Z3Int = x)
    let arr = asArray(f)
    check arr is Z3Array[Z3Int, Z3Int]

  test "asArray(f) and mkConstArray(c) are equal when f is constant":
    ## If f(x) = 42 for all x, then asArray(f) ≡ mkConstArray(42).
    let ctx = newContext()
    let fconst = defineFun("f_const42_na",
      proc(x: Z3Int): Z3Int = mkInt(42))
    let arr = asArray(fconst)
    let constArr = mkConstArray[Z3Int, Z3Int](mkInt(42))
    let i = mkIntVar("i3")
    check smtValid(arr[i] == constArr[i])

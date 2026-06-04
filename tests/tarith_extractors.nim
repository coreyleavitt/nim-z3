## N4.4 — `Z3Int.toIntOpt`, `Z3Real.toRealOpt`, `Z3Int.toInt64` rename.
##
## Covers:
##   - `toIntOpt` happy path (concrete literal)
##   - `toIntOpt` symbolic variable → none
##   - `toIntOpt` overflow (value doesn't fit in cint) → none
##   - `toRealOpt` happy path (concrete rational literal)
##   - `toRealOpt` symbolic variable → none
##   - `toInt64` happy path (renamed from `toInt`)
##   - `toInt64` uses 64-bit range (value fits int64 but not cint)

import std/[unittest, options, math]
import z3

suite "Z3Int.toIntOpt":
  test "toIntOpt returns some(42) for literal mkInt(42)":
    let ctx = newContext()
    check toIntOpt(mkInt(42)) == some(42)

  test "toIntOpt returns none for symbolic variable":
    let ctx = newContext()
    let x = mkIntVar("x")
    check toIntOpt(x) == none(int)

  test "toIntOpt returns none for value that overflows cint":
    ## 10_000_000_000 is 10^10 — fits int64 but not 32-bit cint.
    let ctx = newContext()
    let big = mkBigInt("10000000000")
    check toIntOpt(big) == none(int)

suite "Z3Real.toRealOpt":
  test "toRealOpt returns some(3.5) for mkReal(7, 2)":
    let ctx = newContext()
    let r = mkReal(7, 2)
    let v = toRealOpt(r)
    check v.isSome
    check abs(v.get - 3.5) < 1e-10

  test "toRealOpt returns none for symbolic variable":
    let ctx = newContext()
    let y = mkRealVar("y")
    check toRealOpt(y) == none(float)

suite "Z3Int.toInt64":
  test "toInt64 returns 42'i64 for mkInt(42)":
    let ctx = newContext()
    check toInt64(mkInt(42)) == 42'i64

  test "toInt64 handles negative value":
    let ctx = newContext()
    check toInt64(mkInt(-7)) == -7'i64

  test "toInt64 handles value beyond 32-bit cint range":
    ## 5_000_000_000 > 2^31-1; must work via Z3_get_numeral_int64.
    let ctx = newContext()
    let big = mkBigInt("5000000000")
    check toInt64(big) == 5_000_000_000'i64

  test "toInt64 raises Z3Error on symbolic variable":
    let ctx = newContext()
    let x = mkIntVar("x")
    expect Z3Error:
      discard toInt64(x)

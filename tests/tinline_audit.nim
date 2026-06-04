## N10.9 — Inline-pragma discipline audit
##
## Meta-test: compile-checks that representative procs from recent RFC slices
## (N3.x, N4.x, N6.x, N9.x, N10.x) are callable and produce well-typed
## results.  This does NOT check the pragma itself at runtime — Nim carries no
## runtime tag for `{.inline.}`.  The audit is structural: all trivial 1-line
## forwarding procs should carry `{.inline.}`; non-trivial multi-statement procs
## should not.  The pragmas were verified by source-code inspection (see commit
## message) and these smoke tests confirm no accidental signature regressions
## from the pass.
##
## Discipline applied in this pass:
##   ADD {.inline.}   — 1-line delegating/forwarding procs (ctx-free overloads,
##                       single wrap[T](…) calls, single FFI-to-typed-result)
##   KEEP no-inline   — multi-statement procs, procs with non-trivial logic,
##                       lifecycle hooks (=destroy / =copy / =dup),
##                       procs that allocate seqs or do branching

import ../src/z3/[context, builder, arith, bitvec, boolean, sort,
                  strings, arrays, translate, rewrite]

proc runAudit() =
  let ctx = newContext()
  withContext(ctx):

    # -----------------------------------------------------------------------
    # arith — 1-line base ops (N baseline; got {.inline.} in this pass)
    # -----------------------------------------------------------------------
    let i  = mkIntVar("i")
    let j  = mkIntVar("j")
    let r  = mkRealVar("r")
    let s  = mkRealVar("s")

    discard i + j             # +: Z3Int × Z3Int
    discard i - j             # -: Z3Int × Z3Int
    discard i * j             # *: Z3Int × Z3Int
    discard i div j           # div: Z3Int × Z3Int
    discard i mod j           # mod: Z3Int × Z3Int
    discard r + s             # +: Z3Real × Z3Real
    discard r - s             # -: Z3Real × Z3Real
    discard r * s             # *: Z3Real × Z3Real
    discard r / s             # /: Z3Real × Z3Real
    discard -i                # unary -: Z3Int
    discard -r                # unary -: Z3Real
    discard (i < j)           # <: Z3Int
    discard (i <= j)          # <=: Z3Int
    discard (i > j)           # >: Z3Int
    discard (i >= j)          # >=: Z3Int
    discard abs(i)            # abs(Z3Int)
    discard abs(r)            # abs(Z3Real)
    discard divides(mkInt(2), i)  # divides predicate (d must be a numeral)
    discard isInt(r)          # isInt predicate
    discard intToReal(i)      # coercion Int → Real
    discard realToInt(r)      # coercion Real → Int (floor)
    discard mkRealInt64(currentContext(), 1i64, 2i64)  # exact rational

    # -----------------------------------------------------------------------
    # bitvec N3.1 — overflow / underflow predicates
    # -----------------------------------------------------------------------
    let a8  = mkBitVecVar[8]("a8")
    let b8  = mkBitVecVar[8]("b8")

    discard addNoOverflow(a8, b8, false)   # unsigned add-overflow
    discard addNoOverflow(a8, b8, true)    # signed add-overflow
    discard addNoUnderflow(a8, b8)         # signed add-underflow
    discard subNoOverflow(a8, b8)          # signed sub-overflow
    discard subNoUnderflow(a8, b8, false)  # unsigned sub-underflow
    discard subNoUnderflow(a8, b8, true)   # signed sub-underflow
    discard mulNoOverflow(a8, b8, false)   # unsigned mul-overflow
    discard mulNoOverflow(a8, b8, true)    # signed mul-overflow
    discard mulNoUnderflow(a8, b8)         # signed mul-underflow
    discard negNoOverflow(a8)              # signed neg-overflow
    discard sdivNoOverflow(a8, b8)         # signed sdiv-overflow

    # -----------------------------------------------------------------------
    # bitvec N3.2 — reduction + extended rotation
    # -----------------------------------------------------------------------
    discard redAnd(a8)                     # AND-reduction BV[8] → BV[1]
    discard redOr(a8)                      # OR-reduction BV[8] → BV[1]
    discard extRotateLeft(a8, b8)          # symbolic left-rotate
    discard extRotateRight(a8, b8)         # symbolic right-rotate

    # -----------------------------------------------------------------------
    # bitvec N3.3 — theory-level conversions
    # -----------------------------------------------------------------------
    discard bvToInt(a8)                    # BV → Z3Int (unsigned)
    discard bvToInt(a8, signed = true)     # BV → Z3Int (signed)
    discard intToBv(i, Z3BitVec[8])        # Z3Int → BV[8]
    discard toBitVec(mkTrue())             # Z3Bool → BV[1]

    # -----------------------------------------------------------------------
    # bitvec N10.7 — Option extractors (non-trivial, no inline — audit-only)
    # -----------------------------------------------------------------------
    let bvLit = mkBitVec[8](42'u)
    discard bvLit.toUintOpt                # Option[uint] extractor
    discard bvLit.toIntOpt                 # Option[int]  extractor
    discard bvLit.toInt64Opt               # Option[int64] extractor

    # -----------------------------------------------------------------------
    # strings — single-wrap procs (got {.inline.} in this pass)
    # -----------------------------------------------------------------------
    let strVar = mkStringVar("sv")
    let strLit = mkString("hello")

    discard toCode(strLit)                 # Z3String → Z3Int (codepoint)
    discard fromCode(currentContext(), toCode(strLit))  # Z3Int → Z3String
    discard fromCode(toCode(strLit))       # ctx-free variant
    discard strLit.toInt                   # str.to.int
    discard toStr(mkInt(42))               # str.from.int

    # -----------------------------------------------------------------------
    # translate — single-wrap translate[T] (got {.inline.} in this pass)
    # -----------------------------------------------------------------------
    block:
      let ctx2 = newContext()
      discard translate(i, ctx2)           # Z3Term translate
      # ctx2 cleaned up by =destroy on scope exit

    # -----------------------------------------------------------------------
    # rewrite — freshConst (N9.4, non-trivial, no inline)
    # -----------------------------------------------------------------------
    discard freshConst[Z3Int](currentContext(), "fresh_x")

    # -----------------------------------------------------------------------
    # sort — ctx-free delegates (got {.inline.} in this pass)
    # -----------------------------------------------------------------------
    discard mkIntSort()
    discard mkRealSort()
    discard mkBoolSort()
    discard mkBitVecSort(8'u32)

    # -----------------------------------------------------------------------
    # builder — ctx-free delegates (got {.inline.} in this pass)
    # -----------------------------------------------------------------------
    discard mkTrue()
    discard mkFalse()
    discard mkBool(true)
    discard mkInt(42)
    discard mkReal(3)
    discard mkReal(3, 2)
    discard mkReal(1.5'f64)

runAudit()
echo "tinline_audit: all smoke checks passed"

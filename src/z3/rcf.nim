## `z3/rcf` — move-only Nim wrapper for Z3's Real Closed Field (RCF) solver.
##
## ## Type
##
## `Z3RcfNum` is a **plain `object`** (not a `ref`), making it move-only:
##
## ```nim
## type Z3RcfNum* = object
##   raw*: RawZ3RcfNum
##   ctx*: Z3Context
## ```
##
## The `=copy` and `=dup` hooks are `{.error.}`, so every binding is a
## *move*. The destructor (`=destroy`) calls `Z3_rcf_del` exactly once,
## guarded by a nil check so a moved-from value (whose `raw` field is
## zero-initialised by Nim's move optimiser) does not double-free.
##
## ## Why plain object, not ref?
##
## A `ref` type defeats move-only semantics: `let b = a` for a `ref T` does
## a pointer copy, bypassing `=copy`. Only a plain `object` intercepts all
## copies via `=copy {.error.}`. See ADR-N0006 v3 in RFC-completeness.md for
## the full rationale.
##
## ## Common patterns
##
## ```nim
## # WORKS — arithmetic produces a fresh value each time
## let result = mkPi(ctx) + mkSmallInt(ctx, 2)
##
## # WORKS — returning from a proc moves into the result slot
## proc twoPi(ctx: Z3Context): Z3RcfNum =
##   result = mkSmallInt(ctx, 2) * mkPi(ctx)
##
## # FAILS at compile time — second binding copies the first
## # let x = mkPi(ctx); let y = x   # =copy {.error.}
##
## # WORKS — re-derive a fresh value instead of copying
## let x = mkPi(ctx); let y = mkPi(ctx)
## ```
##
## ## Collections
##
## `Z3RcfNum` is NOT a `Z3_ast` handle, so `Z3AstVector` does not apply.
## To store multiple RCF numerals:
##
## - Keep `RawZ3RcfNum` raw handles in a `seq` and re-wrap on demand
##   (caller manages lifetimes).
## - Re-derive each value on demand from a recipe (numerics are cheap to
##   recreate).
## - Heap-box each value: `let boxed = new Z3RcfNum; boxed[] = mkPi(ctx)`
##   trades the move-only contract for ref semantics at that level.
##
## ## Build gate
##
## Gated on `-d:z3WithoutRcf`. When built with that flag, this file
## imports cleanly but exports nothing.

when not defined(z3WithoutRcf):

  import std/strformat
  import ./ffi, ./context

  # ==========================================================================
  # Type + lifecycle hooks
  # ==========================================================================

  type
    Z3RcfNum* = object
      ## Exact real-closed-field numeral. Move-only: every ownership transfer
      ## is a move; attempting to copy produces a compile-time error.
      raw*: RawZ3RcfNum
      ctx*: Z3Context

  proc `=destroy`(a: Z3RcfNum) {.raises: [].} =
    ## Release the underlying RCF numeral. Guards against double-free by
    ## checking that `raw` is not nil (moved-from values are zero-initialised
    ## by Nim's move optimiser, so their `raw` field is nil).
    try:
      if not a.raw.isNil and a.ctx != nil and not a.ctx.raw.isNil:
        Z3_rcf_del(a.ctx.raw, a.raw)
    except CatchableError:
      discard  # softlink may raise SoftlinkError; silently ignore in destructor

  proc `=copy`(dst: var Z3RcfNum, src: Z3RcfNum) {.
      error: "Z3RcfNum is move-only; re-derive via arithmetic (e.g. `a + mkSmallInt(ctx, 0)`)".}
    ## Copying a Z3RcfNum is explicitly prohibited. Each `Z3_rcf_*` producer
    ## returns a fresh handle and there is no ref-count mechanism to share one.
    ## Re-derive a new value via any arithmetic expression.

  proc `=dup`(src: Z3RcfNum): Z3RcfNum {.
      error: "Z3RcfNum is move-only; re-derive via arithmetic".}

  # ==========================================================================
  # Internal wrap helper
  # ==========================================================================

  proc wrapRcf(ctx: Z3Context, raw: RawZ3RcfNum): Z3RcfNum {.inline.} =
    ## Adopt a freshly returned raw RCF numeral handle. The caller must
    ## ensure `raw` was produced by a `Z3_rcf_*` constructor and has not
    ## yet been freed.
    Z3RcfNum(raw: raw, ctx: ctx)

  # ==========================================================================
  # Constants
  # ==========================================================================

  proc mkRational*(ctx: Z3Context, numerator, denominator: int): Z3RcfNum =
    ## Build the exact rational `numerator / denominator` as an RCF numeral.
    ## Z3 parses the string `"num/den"` and stores the exact rational.
    ##
    runnableExamples:
      import z3
      let ctx = newContext()
      let half = mkRational(ctx, 1, 2)
      let one = mkSmallInt(ctx, 1)
      # 1/2 < 1 in the reals
      doAssert half < one
    let s = &"{numerator}/{denominator}"
    wrapRcf(ctx, Z3_rcf_mk_rational(ctx.raw, cstring(s)))

  proc mkSmallInt*(ctx: Z3Context, n: int): Z3RcfNum =
    ## Build the integer `n` as an RCF numeral.
    wrapRcf(ctx, Z3_rcf_mk_small_int(ctx.raw, cint(n)))

  proc mkPi*(ctx: Z3Context): Z3RcfNum =
    ## Build the exact RCF representation of π.
    ##
    runnableExamples:
      import z3
      let ctx = newContext()
      let pi = mkPi(ctx)
      let three = mkSmallInt(ctx, 3)
      let four  = mkSmallInt(ctx, 4)
      # π is between 3 and 4.
      doAssert three < pi
      doAssert pi < four
    wrapRcf(ctx, Z3_rcf_mk_pi(ctx.raw))

  proc mkE*(ctx: Z3Context): Z3RcfNum =
    ## Build the exact RCF representation of Euler's number e.
    wrapRcf(ctx, Z3_rcf_mk_e(ctx.raw))

  proc mkInfinitesimal*(ctx: Z3Context): Z3RcfNum =
    ## Build a positive infinitesimal RCF numeral — smaller than every
    ## positive rational.
    wrapRcf(ctx, Z3_rcf_mk_infinitesimal(ctx.raw))

  # ==========================================================================
  # Arithmetic
  # ==========================================================================

  proc `+`*(a, b: Z3RcfNum): Z3RcfNum =
    ## RCF addition. Returns a fresh numeral; neither `a` nor `b` is consumed.
    ## Note: both `a` and `b` are passed by value — each call generates a
    ## short-lived copy of the `Z3RcfNum` shell (ctx + raw pointer), which
    ## is fine because Nim passes plain objects by value; the underlying Z3
    ## handle is NOT refcounted, so we must not free `a` or `b` here. The
    ## inputs' `=destroy` will call `Z3_rcf_del` when they go out of scope.
    ##
    runnableExamples:
      import z3
      let ctx = newContext()
      let two  = mkSmallInt(ctx, 2)
      let pi   = mkPi(ctx)
      let sum  = mkSmallInt(ctx, 2) + mkPi(ctx)
      let five = mkSmallInt(ctx, 5)
      # 2 + π > 5 is false; 2 + π > 4 is true.
      doAssert not (sum > five)
      doAssert sum > mkSmallInt(ctx, 4)
    wrapRcf(a.ctx, Z3_rcf_add(a.ctx.raw, a.raw, b.raw))

  proc `-`*(a, b: Z3RcfNum): Z3RcfNum =
    ## RCF subtraction.
    wrapRcf(a.ctx, Z3_rcf_sub(a.ctx.raw, a.raw, b.raw))

  proc `*`*(a, b: Z3RcfNum): Z3RcfNum =
    ## RCF multiplication.
    wrapRcf(a.ctx, Z3_rcf_mul(a.ctx.raw, a.raw, b.raw))

  proc `/`*(a, b: Z3RcfNum): Z3RcfNum =
    ## RCF division.
    wrapRcf(a.ctx, Z3_rcf_div(a.ctx.raw, a.raw, b.raw))

  proc `-`*(a: Z3RcfNum): Z3RcfNum =
    ## RCF unary negation.
    wrapRcf(a.ctx, Z3_rcf_neg(a.ctx.raw, a.raw))

  proc inv*(a: Z3RcfNum): Z3RcfNum =
    ## RCF multiplicative inverse (1/a). Behaviour is undefined when a = 0.
    wrapRcf(a.ctx, Z3_rcf_inv(a.ctx.raw, a.raw))

  proc `^`*(a: Z3RcfNum, k: int): Z3RcfNum =
    ## RCF integer power: a^k. `k` must be non-negative (Z3's C API takes
    ## an unsigned int; passing a negative value wraps to a large uint and
    ## the result is meaningless).
    wrapRcf(a.ctx, Z3_rcf_power(a.ctx.raw, a.raw, cuint(k)))

  # ==========================================================================
  # Ordering
  # ==========================================================================
  #
  # These return Nim `bool` — they are *concrete* numeric comparisons
  # evaluated immediately by Z3's RCF decision procedure, NOT symbolic Z3Bool
  # ASTs. The RCF solver maintains exact algebraic representations of all
  # numerals and can answer ordering queries without approximation.

  proc `<`*(a, b: Z3RcfNum): bool =
    ## True iff a < b in the real numbers.
    Z3_rcf_lt(a.ctx.raw, a.raw, b.raw)

  proc `<=`*(a, b: Z3RcfNum): bool =
    ## True iff a ≤ b.
    Z3_rcf_le(a.ctx.raw, a.raw, b.raw)

  proc `>`*(a, b: Z3RcfNum): bool =
    ## True iff a > b.
    Z3_rcf_gt(a.ctx.raw, a.raw, b.raw)

  proc `>=`*(a, b: Z3RcfNum): bool =
    ## True iff a ≥ b.
    Z3_rcf_ge(a.ctx.raw, a.raw, b.raw)

  proc `==`*(a, b: Z3RcfNum): bool =
    ## True iff a = b exactly.
    Z3_rcf_eq(a.ctx.raw, a.raw, b.raw)

  proc `!=`*(a, b: Z3RcfNum): bool =
    ## True iff a ≠ b.
    Z3_rcf_neq(a.ctx.raw, a.raw, b.raw)

  # ==========================================================================
  # Conversion / display
  # ==========================================================================

  proc `$`*(a: Z3RcfNum): string =
    ## Render the RCF numeral as a string (non-compact, non-html defaults).
    $Z3_rcf_num_to_string(a.ctx.raw, a.raw, false, false)

  proc toString*(a: Z3RcfNum, compact = false, html = false): string =
    ## Render the RCF numeral as a string with configurable formatting.
    ## `compact = true` suppresses extra whitespace.
    ## `html = true` emits HTML entities (for web display).
    $Z3_rcf_num_to_string(a.ctx.raw, a.raw, compact, html)

  proc toDecimalString*(a: Z3RcfNum, precision: int): string =
    ## Render the RCF numeral as a decimal approximation with `precision`
    ## significant decimal digits.
    $Z3_rcf_num_to_decimal_string(a.ctx.raw, a.raw, cuint(precision))

  # ==========================================================================
  # Polynomial root-finding
  # ==========================================================================

  proc mkRoots*(ctx: Z3Context, coeffs: openArray[Z3RcfNum]): seq[Z3RcfNum] =
    ## Find the real roots of the polynomial whose coefficients are `coeffs`.
    ##
    ## `coeffs` is ordered from lowest to highest degree: `coeffs[0]` is the
    ## constant term, `coeffs[n-1]` is the leading coefficient.
    ##
    ## `Z3_rcf_mk_roots` requires the output buffer to have exactly
    ## `coeffs.len` slots (the C contract in `z3_rcf.h`: *"The output
    ## vector `roots` must have size `n`"* where `n` is the coefficient
    ## count). A polynomial of degree N (len = N+1) has at most N real
    ## roots, so the actual count returned by Z3 will be ≤ `coeffs.len - 1`
    ## — but the buffer itself must be sized to `coeffs.len`. Only the
    ## `0..count-1` prefix is wrapped and returned.
    ##
    ## Returns the (possibly shorter) prefix of the output buffer that was
    ## actually populated.
    ##
    ## Example — x^2 - 2 = 0 has two roots (±√2):
    ##
    ## ```nim
    ## let ctx = newContext()
    ## # coefficients: -2 (const), 0 (x), 1 (x^2)
    ## let roots = mkRoots(ctx, [mkSmallInt(ctx, -2),
    ##                           mkSmallInt(ctx, 0),
    ##                           mkSmallInt(ctx, 1)])
    ## doAssert roots.len == 2
    ## ```
    if coeffs.len < 2:
      return @[]
    let maxRoots = coeffs.len  # buffer size per z3_rcf.h contract (size n)
    # Build a raw array of input coefficients (index loop avoids =copy on
    # the move-only Z3RcfNum; we only read the .raw field).
    var rawCoeffs = newSeq[RawZ3RcfNum](coeffs.len)
    for i in 0 ..< coeffs.len:
      rawCoeffs[i] = coeffs[i].raw
    # Allocate the output buffer (maxRoots slots).
    var rawRoots = newSeq[RawZ3RcfNum](maxRoots)
    let count = Z3_rcf_mk_roots(ctx.raw,
                                cuint(coeffs.len),
                                cast[ptr UncheckedArray[RawZ3RcfNum]](addr rawCoeffs[0]),
                                cast[ptr UncheckedArray[RawZ3RcfNum]](addr rawRoots[0]))
    result = newSeq[Z3RcfNum](int(count))
    for i in 0 ..< int(count):
      result[i] = wrapRcf(ctx, rawRoots[i])

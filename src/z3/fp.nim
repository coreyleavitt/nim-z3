## `z3/fp` — SMT-LIB FloatingPoint theory (IEEE 754).
##
## `Z3Fp[Ebits, Sbits]` is a phantom-typed FP value parameterised over
## the IEEE encoding widths. Common precisions have typed aliases:
##
## ```nim
## type
##   Z3Float16  = Z3Fp[5, 11]
##   Z3Float32  = Z3Fp[8, 24]
##   Z3Float64  = Z3Fp[11, 53]
##   Z3Float128 = Z3Fp[15, 113]
## ```
##
## ## NaN semantics — read this before using `==`
##
## **`==` and `!=` on `Z3Fp[E, S]` use IEEE equality, not structural
## equality.** This is a deliberate divergence from every other typed
## family (`Z3Int`, `Z3BitVec[W]`, …). In IEEE land:
##
## - `nan == nan` → **false**
## - `+0 == -0` → **true**
##
## The wrapper picks IEEE semantics because that's what users writing
## FP code overwhelmingly want. The other typed families use
## structural equality only because they have no other notion. If you
## genuinely want structural equality on FPs (rarely needed; mostly
## for solver internals), drop to `astEqual` for pointer identity, or
## build the structural-eq predicate via the raw FFI directly.
##
## ## Rounding modes
##
## FP arithmetic is rounding-mode parameterised. Two shapes ship:
##
## 1. `RoundingMode` Nim enum (`rmRNE`, `rmRNA`, `rmRTP`, `rmRTN`,
##    `rmRTZ`) — what you want 99% of the time.
## 2. `Z3RoundingMode` typed AST family — needed when you quantify
##    over rounding modes (`forall rm. add(rm, x, y) == add(rm, y, x)`).
##
## Every rounding-aware op (`fpAdd`, `fpSub`, `fpMul`, `fpDiv`, `sqrt`,
## `fma`, `roundToIntegral`) overloads on both. The `+`/`-`/`*`/`/`
## operators default to `rmRNE` (IEEE default round-half-to-even);
## use the named forms with an explicit `rmRTZ` etc. when rounding
## direction matters.

import ./ffi, ./context, ./error, ./ast, ./model, ./bitvec

# ============================================================================
# Z3Fp[Ebits, Sbits] — phantom-typed FP value family
# ============================================================================

type
  Z3Fp*[Ebits, Sbits: static int] = object
    ## IEEE 754 FP value with `Ebits` exponent bits and `Sbits`
    ## significand bits (including the implicit hidden bit, per
    ## SMT-LIB convention).
    raw*: RawZ3Ast
    ctx*: Z3Context

  Z3Float16*  = Z3Fp[5, 11]
  Z3Float32*  = Z3Fp[8, 24]
  Z3Float64*  = Z3Fp[11, 53]
  Z3Float128* = Z3Fp[15, 113]

proc `=destroy`[E, S: static int](v: Z3Fp[E, S]) {.raises: [].} =
  termDestroy(v, Z3_dec_ref)
proc `=copy`[E, S: static int](dst: var Z3Fp[E, S], src: Z3Fp[E, S]) {.raises: [].} =
  termCopy(dst, src, Z3_dec_ref, Z3_inc_ref)
proc `=dup`[E, S: static int](src: Z3Fp[E, S]): Z3Fp[E, S] {.raises: [].} =
  termDup(result, src, Z3_inc_ref)

# Step 9 sortOf overload — participates in z3/sortdispatch's resolution.
proc sortOf*[E, S: static int](_: typedesc[Z3Fp[E, S]],
                               ctx: Z3Context): RawZ3Sort {.inline.} =
  ctx.checkErr Z3_mk_fpa_sort(ctx.raw, cuint(E), cuint(S))

# ============================================================================
# Z3RoundingMode — typed AST family for quantification over rounding
# ============================================================================

type
  Z3RoundingMode* = object
    ## SMT-LIB `RoundingMode` sort as a typed AST. Most users want the
    ## `RoundingMode` enum below instead; this exists for the
    ## `forall rm. ...` quantification use case.
    raw*: RawZ3Ast
    ctx*: Z3Context

  RoundingMode* = enum
    ## Nim-side rounding-mode enum; lifts to `Z3RoundingMode` at op
    ## call sites via `mkRoundingMode`.
    rmRNE   ## round-nearest, ties to even (IEEE 754 default)
    rmRNA   ## round-nearest, ties away from zero
    rmRTP   ## round toward positive infinity
    rmRTN   ## round toward negative infinity
    rmRTZ   ## round toward zero (truncation)

emitTermLifecycle(Z3RoundingMode, Z3_dec_ref, Z3_inc_ref)

proc mkRoundingMode*(ctx: Z3Context, rm: RoundingMode): Z3RoundingMode =
  ## Lift a Nim `RoundingMode` enum value to a Z3 rounding-mode AST.
  let raw = case rm
    of rmRNE: ctx.checkErr Z3_mk_fpa_round_nearest_ties_to_even(ctx.raw)
    of rmRNA: ctx.checkErr Z3_mk_fpa_round_nearest_ties_to_away(ctx.raw)
    of rmRTP: ctx.checkErr Z3_mk_fpa_round_toward_positive(ctx.raw)
    of rmRTN: ctx.checkErr Z3_mk_fpa_round_toward_negative(ctx.raw)
    of rmRTZ: ctx.checkErr Z3_mk_fpa_round_toward_zero(ctx.raw)
  wrap[Z3RoundingMode](ctx, raw)
proc mkRoundingMode*(rm: RoundingMode): Z3RoundingMode =
  mkRoundingMode(requireCurrentContext(), rm)

proc mkRoundingModeVar*(ctx: Z3Context, name: string): Z3RoundingMode =
  ## Free rounding-mode variable — usable as a bound var under
  ## `forall` / `exists` for quantified RM properties.
  let sort = ctx.checkErr Z3_mk_fpa_rounding_mode_sort(ctx.raw)
  let sym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)
  wrap[Z3RoundingMode](ctx, ctx.checkErr Z3_mk_const(ctx.raw, sym, sort))
proc mkRoundingModeVar*(name: string): Z3RoundingMode =
  mkRoundingModeVar(requireCurrentContext(), name)

# ============================================================================
# Sort helpers
# ============================================================================

proc fpSort[E, S: static int](ctx: Z3Context): RawZ3Sort {.inline.} =
  ctx.checkErr Z3_mk_fpa_sort(ctx.raw, cuint(E), cuint(S))

# ============================================================================
# Literals + variables
# ============================================================================

proc mkFp*[E, S: static int](ctx: Z3Context, v: float64): Z3Fp[E, S] =
  ## FP literal from a Nim `float` (float64). Rounded to the target
  ## precision using Z3's default (rmRNE).
  wrap[Z3Fp[E, S]](ctx,
    ctx.checkErr Z3_mk_fpa_numeral_double(ctx.raw, cdouble(v), fpSort[E, S](ctx)))
proc mkFp*[E, S: static int](v: float64): Z3Fp[E, S] =
  mkFp[E, S](requireCurrentContext(), v)

proc mkFp*[E, S: static int](ctx: Z3Context, v: float32): Z3Fp[E, S] =
  ## FP literal from a Nim `float32`.
  wrap[Z3Fp[E, S]](ctx,
    ctx.checkErr Z3_mk_fpa_numeral_float(ctx.raw, cfloat(v), fpSort[E, S](ctx)))
proc mkFp*[E, S: static int](v: float32): Z3Fp[E, S] =
  mkFp[E, S](requireCurrentContext(), v)

proc mkFpVar*[E, S: static int](ctx: Z3Context, name: string): Z3Fp[E, S] =
  ## Free FP variable of width `Fp[E, S]`.
  let sym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)
  wrap[Z3Fp[E, S]](ctx,
    ctx.checkErr Z3_mk_const(ctx.raw, sym, fpSort[E, S](ctx)))
proc mkFpVar*[E, S: static int](name: string): Z3Fp[E, S] =
  mkFpVar[E, S](requireCurrentContext(), name)

# Common-width ergonomic helpers — what users will reach for first.

proc mkFloat32*(ctx: Z3Context, v: float32): Z3Float32 {.inline.} =
  mkFp[8, 24](ctx, v)
proc mkFloat32*(v: float32): Z3Float32 {.inline.} =
  mkFp[8, 24](v)
proc mkFloat64*(ctx: Z3Context, v: float64): Z3Float64 {.inline.} =
  mkFp[11, 53](ctx, v)
proc mkFloat64*(v: float64): Z3Float64 {.inline.} =
  mkFp[11, 53](v)

proc mkFloat32Var*(ctx: Z3Context, name: string): Z3Float32 {.inline.} =
  mkFpVar[8, 24](ctx, name)
proc mkFloat32Var*(name: string): Z3Float32 {.inline.} =
  mkFpVar[8, 24](name)
proc mkFloat64Var*(ctx: Z3Context, name: string): Z3Float64 {.inline.} =
  mkFpVar[11, 53](ctx, name)
proc mkFloat64Var*(name: string): Z3Float64 {.inline.} =
  mkFpVar[11, 53](name)

# ============================================================================
# IEEE equality (==, !=) — DIFFERS from structural equality on other families
# ============================================================================

proc `==`*[E, S: static int](a, b: Z3Fp[E, S]): Z3Bool =
  ## IEEE equality (`Z3_mk_fpa_eq`). **NaN == NaN is false**;
  ## +0 == -0 is true. See module docs.
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_fpa_eq(a.ctx.raw, a.raw, b.raw))

proc `!=`*[E, S: static int](a, b: Z3Fp[E, S]): Z3Bool =
  ## IEEE non-equality. `nan != nan` is **true**.
  let eq = a == b
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_not(a.ctx.raw, eq.raw))

# ============================================================================
# Model extraction
# ============================================================================

proc fpBitsToUint64(a: Z3Fp): uint64 =
  ## Internal: extract the IEEE 754 bit pattern of an FP literal as a
  ## uint64. Z3 doesn't ship a direct float-extractor; the route is
  ## via `Z3_mk_fpa_to_ieee_bv` + `simplify` + the existing BV numeral
  ## extractor. Raises `Z3Error` if the AST doesn't reduce to a
  ## literal numeral.
  let ieee = a.ctx.checkErr Z3_mk_fpa_to_ieee_bv(a.ctx.raw, a.raw)
  let folded = a.ctx.checkErr Z3_simplify(a.ctx.raw, ieee)
  var bits: uint64
  if not Z3_get_numeral_uint64(a.ctx.raw, folded, addr bits):
    var e = newException(Z3Error,
      "Z3Fp.toFloat*: AST `" & $Z3_ast_to_string(a.ctx.raw, a.raw) &
      "` does not reduce to a literal FP value (most commonly: a free " &
      "FP variable that hasn't been evaluated through the model).")
    e.code = Z3_INVALID_USAGE
    raise e
  bits

proc toFloat64*(a: Z3Float64): float =
  ## Extract a Nim `float` (float64) from a concrete `Z3Float64`
  ## literal. Lossless — every IEEE-754 binary64 bit pattern
  ## round-trips, including NaN payloads. Raises `Z3Error` if the AST
  ## isn't a literal.
  let bits = fpBitsToUint64(a)
  cast[float64](bits)

proc toFloat32*(a: Z3Float32): float32 =
  ## Extract a Nim `float32` from a concrete `Z3Float32` literal.
  ## Lossless on the IEEE-754 binary32 bit pattern.
  let bits = fpBitsToUint64(a)
  cast[float32](uint32(bits))

proc evalFloat64*(m: Z3Model, a: Z3Float64, modelCompletion = true): float {.inline.} =
  m.eval(a, modelCompletion).toFloat64

proc evalFloat32*(m: Z3Model, a: Z3Float32,
                  modelCompletion = true): float32 {.inline.} =
  m.eval(a, modelCompletion).toFloat32

# ============================================================================
# Special-value literals + predicates
# ============================================================================

proc mkNaN*[E, S: static int](ctx: Z3Context): Z3Fp[E, S] =
  ## Not-a-number literal. Note: there's an entire space of NaN bit
  ## patterns in IEEE 754; this builds *a* NaN, not a specific one.
  wrap[Z3Fp[E, S]](ctx,
    ctx.checkErr Z3_mk_fpa_nan(ctx.raw, fpSort[E, S](ctx)))
proc mkNaN*[E, S: static int](): Z3Fp[E, S] =
  mkNaN[E, S](requireCurrentContext())

proc mkInf*[E, S: static int](ctx: Z3Context, negative = false): Z3Fp[E, S] =
  ## ±Infinity. Pass `negative = true` for −∞.
  wrap[Z3Fp[E, S]](ctx,
    ctx.checkErr Z3_mk_fpa_inf(ctx.raw, fpSort[E, S](ctx), negative))
proc mkInf*[E, S: static int](negative = false): Z3Fp[E, S] =
  mkInf[E, S](requireCurrentContext(), negative)

proc mkZero*[E, S: static int](ctx: Z3Context, negative = false): Z3Fp[E, S] =
  ## ±0. `+0 == -0` under IEEE equality (our `==`).
  wrap[Z3Fp[E, S]](ctx,
    ctx.checkErr Z3_mk_fpa_zero(ctx.raw, fpSort[E, S](ctx), negative))
proc mkZero*[E, S: static int](negative = false): Z3Fp[E, S] =
  mkZero[E, S](requireCurrentContext(), negative)

template predicate(name, ffi: untyped) =
  proc name*[E, S: static int](a: Z3Fp[E, S]): Z3Bool =
    wrap[Z3Bool](a.ctx, a.ctx.checkErr ffi(a.ctx.raw, a.raw))

predicate(isNaN,       Z3_mk_fpa_is_nan)
predicate(isInf,       Z3_mk_fpa_is_infinite)
predicate(isZero,      Z3_mk_fpa_is_zero)
predicate(isNormal,    Z3_mk_fpa_is_normal)
predicate(isSubnormal, Z3_mk_fpa_is_subnormal)
predicate(isNegative,  Z3_mk_fpa_is_negative)
predicate(isPositive,  Z3_mk_fpa_is_positive)

# ============================================================================
# Comparisons — signaling (NaN ordered with nothing)
# ============================================================================

template fpCmp(name, ffi: untyped) =
  proc name*[E, S: static int](a, b: Z3Fp[E, S]): Z3Bool =
    wrap[Z3Bool](a.ctx, a.ctx.checkErr ffi(a.ctx.raw, a.raw, b.raw))

fpCmp(`<`,  Z3_mk_fpa_lt)
fpCmp(`<=`, Z3_mk_fpa_leq)
fpCmp(`>`,  Z3_mk_fpa_gt)
fpCmp(`>=`, Z3_mk_fpa_geq)

# ============================================================================
# No-rounding arithmetic
# ============================================================================

proc abs*[E, S: static int](a: Z3Fp[E, S]): Z3Fp[E, S] =
  wrap[Z3Fp[E, S]](a.ctx, a.ctx.checkErr Z3_mk_fpa_abs(a.ctx.raw, a.raw))

proc `-`*[E, S: static int](a: Z3Fp[E, S]): Z3Fp[E, S] =
  ## Unary negation — flips the sign bit. No rounding (exact).
  wrap[Z3Fp[E, S]](a.ctx, a.ctx.checkErr Z3_mk_fpa_neg(a.ctx.raw, a.raw))

proc rem*[E, S: static int](a, b: Z3Fp[E, S]): Z3Fp[E, S] =
  ## IEEE remainder (`a − round(a/b) · b`). Exact, no rounding.
  wrap[Z3Fp[E, S]](a.ctx, a.ctx.checkErr Z3_mk_fpa_rem(a.ctx.raw, a.raw, b.raw))

proc min*[E, S: static int](a, b: Z3Fp[E, S]): Z3Fp[E, S] =
  ## IEEE 754-2008 `minNum`. NaN handling per SMT-LIB convention.
  wrap[Z3Fp[E, S]](a.ctx, a.ctx.checkErr Z3_mk_fpa_min(a.ctx.raw, a.raw, b.raw))

proc max*[E, S: static int](a, b: Z3Fp[E, S]): Z3Fp[E, S] =
  wrap[Z3Fp[E, S]](a.ctx, a.ctx.checkErr Z3_mk_fpa_max(a.ctx.raw, a.raw, b.raw))

# ============================================================================
# Rounding-aware arithmetic
# ============================================================================
#
# Each op overloads three ways:
#   1. `name(rm: Z3RoundingMode, ...)` — full AST form
#   2. `name(rm: RoundingMode, ...)`   — Nim-enum convenience
#   3. `name(...)` — default-RM (rmRNE)
#
# The infix operators `+ - * /` use form 3 (default RM). Users wanting
# explicit RM call the `fpAdd` / `fpSub` / `fpMul` / `fpDiv` named
# forms.

template fpBin(named, ffi: untyped) =
  proc named*[E, S: static int](rm: Z3RoundingMode,
                                a, b: Z3Fp[E, S]): Z3Fp[E, S] =
    wrap[Z3Fp[E, S]](a.ctx,
      a.ctx.checkErr ffi(a.ctx.raw, rm.raw, a.raw, b.raw))
  proc named*[E, S: static int](rm: RoundingMode,
                                a, b: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} =
    named(mkRoundingMode(a.ctx, rm), a, b)
  proc named*[E, S: static int](a, b: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} =
    named(rmRNE, a, b)

fpBin(fpAdd, Z3_mk_fpa_add)
fpBin(fpSub, Z3_mk_fpa_sub)
fpBin(fpMul, Z3_mk_fpa_mul)
fpBin(fpDiv, Z3_mk_fpa_div)

proc `+`*[E, S: static int](a, b: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} = fpAdd(a, b)
proc `-`*[E, S: static int](a, b: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} = fpSub(a, b)
proc `*`*[E, S: static int](a, b: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} = fpMul(a, b)
proc `/`*[E, S: static int](a, b: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} = fpDiv(a, b)

proc sqrt*[E, S: static int](rm: Z3RoundingMode, a: Z3Fp[E, S]): Z3Fp[E, S] =
  wrap[Z3Fp[E, S]](a.ctx, a.ctx.checkErr Z3_mk_fpa_sqrt(a.ctx.raw, rm.raw, a.raw))
proc sqrt*[E, S: static int](rm: RoundingMode, a: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} =
  sqrt(mkRoundingMode(a.ctx, rm), a)
proc sqrt*[E, S: static int](a: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} =
  sqrt(rmRNE, a)

proc fma*[E, S: static int](rm: Z3RoundingMode,
                            a, b, c: Z3Fp[E, S]): Z3Fp[E, S] =
  ## Fused multiply-add — `a * b + c` computed with a single rounding.
  wrap[Z3Fp[E, S]](a.ctx,
    a.ctx.checkErr Z3_mk_fpa_fma(a.ctx.raw, rm.raw, a.raw, b.raw, c.raw))
proc fma*[E, S: static int](rm: RoundingMode,
                            a, b, c: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} =
  fma(mkRoundingMode(a.ctx, rm), a, b, c)
proc fma*[E, S: static int](a, b, c: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} =
  fma(rmRNE, a, b, c)

proc roundToIntegral*[E, S: static int](rm: Z3RoundingMode,
                                       a: Z3Fp[E, S]): Z3Fp[E, S] =
  wrap[Z3Fp[E, S]](a.ctx,
    a.ctx.checkErr Z3_mk_fpa_round_to_integral(a.ctx.raw, rm.raw, a.raw))
proc roundToIntegral*[E, S: static int](rm: RoundingMode,
                                       a: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} =
  roundToIntegral(mkRoundingMode(a.ctx, rm), a)
proc roundToIntegral*[E, S: static int](a: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} =
  roundToIntegral(rmRNE, a)

# ============================================================================
# Conversions
# ============================================================================

proc toIeeeBv*[E, S: static int](a: Z3Fp[E, S]): Z3BitVec[E + S] =
  ## IEEE 754 bit pattern as a BV of width `E + S` (e.g. 32 for
  ## `Z3Float32`). Lossless and rounding-free; the result is unspecified
  ## only on NaN payloads (per SMT-LIB FP-to-BV semantics).
  wrap[Z3BitVec[E + S]](a.ctx,
    a.ctx.checkErr Z3_mk_fpa_to_ieee_bv(a.ctx.raw, a.raw))

proc toFp*[Bw, E, S: static int](bv: Z3BitVec[Bw],
                                 _: typedesc[Z3Fp[E, S]]): Z3Fp[E, S] =
  ## Re-interpret the BV bits as an FP value of sort `Z3Fp[E, S]`. The
  ## BV width must equal `E + S`; mismatches are rejected at compile
  ## time.
  static: assert Bw == E + S,
    "toFp[Z3Fp[E,S]]: BV width must equal E + S"
  wrap[Z3Fp[E, S]](bv.ctx,
    bv.ctx.checkErr Z3_mk_fpa_to_fp_bv(bv.ctx.raw, bv.raw, fpSort[E, S](bv.ctx)))

template fpToFp3(name, ffi, srcConstraint: untyped) =
  proc name*[E, S: static int](rm: Z3RoundingMode,
                               x: srcConstraint,
                               _: typedesc[Z3Fp[E, S]]): Z3Fp[E, S] =
    wrap[Z3Fp[E, S]](x.ctx,
      x.ctx.checkErr ffi(x.ctx.raw, rm.raw, x.raw, fpSort[E, S](x.ctx)))
  proc name*[E, S: static int](rm: RoundingMode,
                               x: srcConstraint,
                               t: typedesc[Z3Fp[E, S]]): Z3Fp[E, S] {.inline.} =
    name(mkRoundingMode(x.ctx, rm), x, t)
  proc name*[E, S: static int](x: srcConstraint,
                               t: typedesc[Z3Fp[E, S]]): Z3Fp[E, S] {.inline.} =
    name(rmRNE, x, t)

fpToFp3(toFp,           Z3_mk_fpa_to_fp_float,    Z3Fp)
fpToFp3(toFp,           Z3_mk_fpa_to_fp_real,     Z3Real)
fpToFp3(toFpFromSigned, Z3_mk_fpa_to_fp_signed,   Z3BitVec)
fpToFp3(toFpFromUnsigned, Z3_mk_fpa_to_fp_unsigned, Z3BitVec)

proc toReal*[E, S: static int](a: Z3Fp[E, S]): Z3Real =
  ## Exact rational approximation (`Z3_mk_fpa_to_real`). Defined for
  ## finite values; on NaN / ±∞ the result is unspecified per SMT-LIB.
  wrap[Z3Real](a.ctx, a.ctx.checkErr Z3_mk_fpa_to_real(a.ctx.raw, a.raw))

proc toSbv*[E, S, W: static int](rm: Z3RoundingMode,
                                 a: Z3Fp[E, S]): Z3BitVec[W] =
  ## FP → signed BV of width `W`. Rounding-aware.
  wrap[Z3BitVec[W]](a.ctx,
    a.ctx.checkErr Z3_mk_fpa_to_sbv(a.ctx.raw, rm.raw, a.raw, cuint(W)))
proc toSbv*[E, S, W: static int](rm: RoundingMode,
                                 a: Z3Fp[E, S]): Z3BitVec[W] {.inline.} =
  toSbv[E, S, W](mkRoundingMode(a.ctx, rm), a)
proc toSbv*[E, S, W: static int](a: Z3Fp[E, S]): Z3BitVec[W] {.inline.} =
  toSbv[E, S, W](rmRNE, a)

proc toUbv*[E, S, W: static int](rm: Z3RoundingMode,
                                 a: Z3Fp[E, S]): Z3BitVec[W] =
  wrap[Z3BitVec[W]](a.ctx,
    a.ctx.checkErr Z3_mk_fpa_to_ubv(a.ctx.raw, rm.raw, a.raw, cuint(W)))
proc toUbv*[E, S, W: static int](rm: RoundingMode,
                                 a: Z3Fp[E, S]): Z3BitVec[W] {.inline.} =
  toUbv[E, S, W](mkRoundingMode(a.ctx, rm), a)
proc toUbv*[E, S, W: static int](a: Z3Fp[E, S]): Z3BitVec[W] {.inline.} =
  toUbv[E, S, W](rmRNE, a)

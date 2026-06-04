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
## See [docs/GOTCHAS.md §1](../docs/GOTCHAS.md#1-floating-point--uses-ieee-semantics--nan--nan)
## for the user-facing summary.
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
## FP arithmetic is rounding-mode parameterised. Rounding modes are
## **first-class typed ASTs** — values of the `Z3RoundingMode`
## family — constructed via the literal helpers `rmRNE()`,
## `rmRNA()`, `rmRTP()`, `rmRTN()`, `rmRTZ()`. The same family is
## used for the ergonomic case (passing a literal rounding mode to
## `fpAdd`) and for quantification (`forall rm. add(rm, x, y) ==
## add(rm, y, x)` — `rm` is a `Z3RoundingMode` bound variable from
## `mkRoundingModeVar`).
##
## Every rounding-aware op (`fpAdd`, `fpSub`, `fpMul`, `fpDiv`,
## `sqrt`, `fma`, `roundToIntegral`, `toSbv`, `toUbv`) takes one
## `Z3RoundingMode` argument. The `+`/`-`/`*`/`/` operators default
## to round-nearest-ties-to-even (the IEEE 754 default); use the
## named forms with an explicit `rmRTZ()` etc. when rounding
## direction matters.
##
## **v0.5 step 2C consolidation:** the previous dual representation
## (`RoundingMode` Nim enum + `Z3RoundingMode` AST + `mkRoundingMode`
## lifter) collapsed into one family. Source delta is mostly
## `rmRNE` → `rmRNE()` and `mkRoundingMode(rmX)` → `rmX()`.

import std/options
import ./ffi, ./context, ./error, ./ast, ./model, ./bitvec, ./sort

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
    ## SMT-LIB `RoundingMode` sort as a typed AST. Construct literal
    ## values via `rmRNE()` / `rmRNA()` / `rmRTP()` / `rmRTN()` /
    ## `rmRTZ()`; construct free variables for quantification via
    ## `mkRoundingModeVar(name)`.
    raw*: RawZ3Ast
    ctx*: Z3Context

emitTermLifecycle(Z3RoundingMode, Z3_dec_ref, Z3_inc_ref)

# Step 9 sortOf overload — participates in z3/sortdispatch's resolution
# so `Z3RoundingMode` can be an element of `Z3Seq[Z3RoundingMode]`,
# `Z3Array[K, Z3RoundingMode]`, or a `Z3FuncDecl` arg / return type.
proc sortOf*(_: typedesc[Z3RoundingMode],
             ctx: Z3Context): RawZ3Sort {.inline.} =
  ctx.checkErr Z3_mk_fpa_rounding_mode_sort(ctx.raw)

# Structural equality. Unlike `Z3Fp`'s IEEE `==`, rounding modes
# have no NaN/Inf concept — there are exactly five distinct values
# (rmRNE / rmRNA / rmRTP / rmRTN / rmRTZ), so SMT structural
# equality is what users want.
proc `==`*(a, b: Z3RoundingMode): Z3Bool =
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_eq(a.ctx.raw, a.raw, b.raw))

proc `!=`*(a, b: Z3RoundingMode): Z3Bool =
  let eq = a == b
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_not(a.ctx.raw, eq.raw))

# ----------------------------------------------------------------------------
# Literal helpers — one proc per IEEE-754 rounding mode. Each returns a
# `Z3RoundingMode` AST built on `ctx` (or the current context). Generated via
# a template so the five entry points share one body.
# ----------------------------------------------------------------------------

template defRm(name: untyped, ffi: untyped, descr: string) =
  proc name*(ctx: Z3Context): Z3RoundingMode =
    ## **descr** — `Z3RoundingMode` literal on `ctx`.
    wrap[Z3RoundingMode](ctx, ctx.checkErr ffi(ctx.raw))
  proc name*(): Z3RoundingMode =
    name(requireCurrentContext())

defRm(rmRNE, Z3_mk_fpa_round_nearest_ties_to_even,
      "round-nearest, ties to even (IEEE 754 default)")
defRm(rmRNA, Z3_mk_fpa_round_nearest_ties_to_away,
      "round-nearest, ties away from zero")
defRm(rmRTP, Z3_mk_fpa_round_toward_positive,
      "round toward positive infinity")
defRm(rmRTN, Z3_mk_fpa_round_toward_negative,
      "round toward negative infinity")
defRm(rmRTZ, Z3_mk_fpa_round_toward_zero,
      "round toward zero (truncation)")

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

# ----------------------------------------------------------------------------
# Named-precision sort-handle constructors (N6.2)
#
# Each returns a typed `Z3Sort[stFp]` — the sort-level counterpart to the
# `Z3Fp[E, S]` value aliases `Z3Float16/32/64/128`. Sort IDs match those
# returned by `sortOf[Z3FloatXxx](ctx)` for the corresponding precision.
# ----------------------------------------------------------------------------

proc mkFpSortHalf*(ctx: Z3Context): Z3Sort[stFp] =
  ## IEEE 754 binary16 (half-precision) sort handle: 5 exponent + 11 significand bits.
  ## Matches `sortOf[Z3Float16](ctx)` by sort ID.
  Z3Sort[stFp](raw: ctx.checkErr Z3_mk_fpa_sort_half(ctx.raw), ctx: ctx)

proc mkFpSortSingle*(ctx: Z3Context): Z3Sort[stFp] =
  ## IEEE 754 binary32 (single-precision) sort handle: 8 exponent + 24 significand bits.
  ## Matches `sortOf[Z3Float32](ctx)` by sort ID.
  Z3Sort[stFp](raw: ctx.checkErr Z3_mk_fpa_sort_single(ctx.raw), ctx: ctx)

proc mkFpSortDouble*(ctx: Z3Context): Z3Sort[stFp] =
  ## IEEE 754 binary64 (double-precision) sort handle: 11 exponent + 53 significand bits.
  ## Matches `sortOf[Z3Float64](ctx)` by sort ID.
  Z3Sort[stFp](raw: ctx.checkErr Z3_mk_fpa_sort_double(ctx.raw), ctx: ctx)

proc mkFpSortQuadruple*(ctx: Z3Context): Z3Sort[stFp] =
  ## IEEE 754 binary128 (quadruple-precision) sort handle: 15 exponent + 113 significand bits.
  ## Matches `sortOf[Z3Float128](ctx)` by sort ID.
  Z3Sort[stFp](raw: ctx.checkErr Z3_mk_fpa_sort_quadruple(ctx.raw), ctx: ctx)

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
    var e = newException(Z3InvalidUsageError,
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

proc evalFloat64Opt*(m: Z3Model, a: Z3Float64,
                     modelCompletion = true): Option[float64] =
  ## Option-returning variant of `evalFloat64`. Returns `some(v)` when
  ## `a` evaluates to a concrete FP numeral under `m`; `none` if the
  ## evaluated AST is not a numeral (e.g. unconstrained variable with
  ## `modelCompletion = false`). Raises `Z3Error` on a hard solver
  ## error (mismatched context, etc.).
  try:
    some(m.eval(a, modelCompletion).toFloat64)
  except Z3InvalidUsageError:
    none(float64)

proc evalFloat32Opt*(m: Z3Model, a: Z3Float32,
                     modelCompletion = true): Option[float32] =
  ## Option-returning variant of `evalFloat32`. Returns `some(v)` when
  ## `a` evaluates to a concrete FP numeral under `m`; `none` if the
  ## evaluated AST is not a numeral.
  try:
    some(m.eval(a, modelCompletion).toFloat32)
  except Z3InvalidUsageError:
    none(float32)

proc evalFp*[E, S: static int](m: Z3Model, a: Z3Fp[E, S],
                                modelCompletion = true): auto =
  ## Generic FP model extractor dispatching on `[E, S]`:
  ##
  ## - `[11, 53]` (binary64 / `Z3Float64`): returns `Option[float64]`.
  ## - `[8, 24]`  (binary32 / `Z3Float32`): returns `Option[float32]`.
  ## - All other shapes: returns a `string` encoding the SMT-LIB FP
  ##   numeral via `getNumeralSignificandString` and
  ##   `getNumeralExponentString` extracted from the evaluated AST.
  ##   The string form is lossless for any IEEE-style precision not
  ##   directly representable as a Nim scalar.
  ##
  ## The three branches are resolved at compile time via `when`; no
  ## runtime dispatch occurs.
  when E == 11 and S == 53:
    m.evalFloat64Opt(a, modelCompletion)
  elif E == 8 and S == 24:
    m.evalFloat32Opt(a, modelCompletion)
  else:
    let evaled = m.eval(a, modelCompletion)
    let sig = evaled.getNumeralSignificandString()
    let exp = evaled.getNumeralExponentString()
    "sig=" & sig & " exp=" & exp

# ============================================================================
# Special-value literals + predicates
# ============================================================================

proc mkFpFromParts*[E, S: static int](sgn: Z3BitVec[1],
                                      exp: Z3BitVec[E],
                                      sig: Z3BitVec[S - 1]): Z3Fp[E, S] =
  ## Assembles an FP value from sign/exponent/significand bit vectors.
  ##
  ## Wraps `Z3_mk_fpa_fp`. The resulting sort is inferred by Z3 from the
  ## BV widths: `E`-bit exponent and `(S-1)`-bit explicit significand
  ## (the hidden bit is implicit, per IEEE 754). No rounding mode — this
  ## is bit-exact assembly. For lossy float-to-FP, use `toFp(rm, fp, _)`.
  ##
  ## Width relationships for common precisions:
  ##   `Z3Float32 = Z3Fp[8, 24]` → exp is `Z3BitVec[8]`, sig is `Z3BitVec[23]`
  ##   `Z3Float64 = Z3Fp[11, 53]` → exp is `Z3BitVec[11]`, sig is `Z3BitVec[52]`
  wrap[Z3Fp[E, S]](sgn.ctx,
    sgn.ctx.checkErr Z3_mk_fpa_fp(sgn.ctx.raw, sgn.raw, exp.raw, sig.raw))

proc mkFpNaN*[E, S: static int](ctx: Z3Context): Z3Fp[E, S] =
  ## Not-a-number literal. Note: there's an entire space of NaN bit
  ## patterns in IEEE 754; this builds *a* NaN, not a specific one.
  wrap[Z3Fp[E, S]](ctx,
    ctx.checkErr Z3_mk_fpa_nan(ctx.raw, fpSort[E, S](ctx)))
proc mkFpNaN*[E, S: static int](): Z3Fp[E, S] =
  mkFpNaN[E, S](requireCurrentContext())

proc mkFpInf*[E, S: static int](ctx: Z3Context, negative = false): Z3Fp[E, S] =
  ## ±Infinity. Pass `negative = true` for −∞.
  wrap[Z3Fp[E, S]](ctx,
    ctx.checkErr Z3_mk_fpa_inf(ctx.raw, fpSort[E, S](ctx), negative))
proc mkFpInf*[E, S: static int](negative = false): Z3Fp[E, S] =
  mkFpInf[E, S](requireCurrentContext(), negative)

proc mkFpZero*[E, S: static int](ctx: Z3Context, negative = false): Z3Fp[E, S] =
  ## ±0. `+0 == -0` under IEEE equality (our `==`).
  wrap[Z3Fp[E, S]](ctx,
    ctx.checkErr Z3_mk_fpa_zero(ctx.raw, fpSort[E, S](ctx), negative))
proc mkFpZero*[E, S: static int](negative = false): Z3Fp[E, S] =
  mkFpZero[E, S](requireCurrentContext(), negative)

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

proc isFinite*[E, S: static int](a: Z3Fp[E, S]): Z3Bool =
  ## True iff `a` is a finite number — i.e. neither NaN nor ±∞.
  ## Composite of `not isNaN(a) and not isInf(a)`; IEEE 754 doesn't
  ## ship a primitive "is_finite" predicate (and Z3's C API doesn't
  ## either), so the wrapper synthesises it once here rather than
  ## leaving every caller to re-derive the same composition.
  (not isNaN(a)) and (not isInf(a))

# ============================================================================
# N6.4a — Host-side numeral predicates (concrete bool, not Z3Bool)
# ============================================================================
#
# These are introspection procs operating on *concrete* FP numerals.
# They invoke `Z3_fpa_is_numeral_*` which returns a C `bool` directly —
# no solver round-trip, no SMT formula construction.
# Contrast with the symbolic `isNaN`/`isInf`/… above, which build Z3Bool
# AST nodes for use in assertions.

template numeralPredicate(name, ffi: untyped) =
  proc name*[E, S: static int](a: Z3Fp[E, S]): bool =
    ffi(a.ctx.raw, a.raw)

numeralPredicate(isNumeralNaN,       Z3_fpa_is_numeral_nan)
numeralPredicate(isNumeralInf,       Z3_fpa_is_numeral_inf)
numeralPredicate(isNumeralZero,      Z3_fpa_is_numeral_zero)
numeralPredicate(isNumeralNormal,    Z3_fpa_is_numeral_normal)
numeralPredicate(isNumeralSubnormal, Z3_fpa_is_numeral_subnormal)
numeralPredicate(isNumeralPositive,  Z3_fpa_is_numeral_positive)
numeralPredicate(isNumeralNegative,  Z3_fpa_is_numeral_negative)

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
# N6.5a — comparison literal lifts (Z3Fp op float64/float32)
# ============================================================================
#
# Each binary comparison has four overloads: (Z3Fp, float64), (float64, Z3Fp),
# (Z3Fp, float32) on Z3Float32, (float32, Z3Float32).
#
# `==` uses `Z3_mk_fpa_eq` (IEEE equality) — matching the Z3Fp×Z3Fp `==`
# above. `!=` is `not (a == b)`. `<`, `<=`, `>`, `>=` delegate to their
# Z3Fp×Z3Fp siblings after lifting the literal.

template liftFpCmp(name: untyped) =
  ## For each comparison `name` already defined on `(Z3Fp[E,S], Z3Fp[E,S])`,
  ## add two float64 overloads and two float32 overloads.
  proc `name`*[E, S: static int](a: Z3Fp[E, S], b: float64): Z3Bool {.inline.} =
    `name`(a, mkFp[E, S](a.ctx, b))
  proc `name`*[E, S: static int](a: float64, b: Z3Fp[E, S]): Z3Bool {.inline.} =
    `name`(mkFp[E, S](b.ctx, a), b)
  proc `name`*(a: Z3Float32, b: float32): Z3Bool {.inline.} =
    `name`(a, mkFloat32(a.ctx, b))
  proc `name`*(a: float32, b: Z3Float32): Z3Bool {.inline.} =
    `name`(mkFloat32(b.ctx, a), b)

liftFpCmp(`==`)
liftFpCmp(`!=`)
liftFpCmp(`<`)
liftFpCmp(`<=`)
liftFpCmp(`>`)
liftFpCmp(`>=`)

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
# Each op has two overloads:
#   1. `name(rm: Z3RoundingMode, ...)` — explicit rounding mode
#   2. `name(...)` — default RM (rmRNE, IEEE 754 default)
#
# The infix operators `+ - * /` use form 2. Users wanting explicit RM
# call the `fpAdd` / `fpSub` / `fpMul` / `fpDiv` named forms with a
# literal `rmRTZ()` etc.

template fpBin(named, ffi: untyped) =
  proc named*[E, S: static int](rm: Z3RoundingMode,
                                a, b: Z3Fp[E, S]): Z3Fp[E, S] =
    wrap[Z3Fp[E, S]](a.ctx,
      a.ctx.checkErr ffi(a.ctx.raw, rm.raw, a.raw, b.raw))
  proc named*[E, S: static int](a, b: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} =
    named(rmRNE(a.ctx), a, b)

fpBin(fpAdd, Z3_mk_fpa_add)
fpBin(fpSub, Z3_mk_fpa_sub)
fpBin(fpMul, Z3_mk_fpa_mul)
fpBin(fpDiv, Z3_mk_fpa_div)

proc `+`*[E, S: static int](a, b: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} = fpAdd(a, b)
proc `-`*[E, S: static int](a, b: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} = fpSub(a, b)
proc `*`*[E, S: static int](a, b: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} = fpMul(a, b)
proc `/`*[E, S: static int](a, b: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} = fpDiv(a, b)

# ============================================================================
# N6.5b — arithmetic literal lifts (Z3Fp op float64/float32)
# ============================================================================
#
# Each binary arithmetic operator has four overloads: (Z3Fp, float64),
# (float64, Z3Fp), (Z3Float32, float32), (float32, Z3Float32).
# All use rmRNE (round-nearest-ties-to-even, IEEE 754 default) by lifting the
# literal with `mkFp` then delegating to the existing Z3Fp×Z3Fp operator.

template liftFpBin(name: untyped) =
  ## For each arithmetic operator `name` already defined on `(Z3Fp[E,S], Z3Fp[E,S])`,
  ## add two float64 overloads and two float32 overloads.
  proc `name`*[E, S: static int](a: Z3Fp[E, S], b: float64): Z3Fp[E, S] {.inline.} =
    `name`(a, mkFp[E, S](a.ctx, b))
  proc `name`*[E, S: static int](a: float64, b: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} =
    `name`(mkFp[E, S](b.ctx, a), b)
  proc `name`*(a: Z3Float32, b: float32): Z3Float32 {.inline.} =
    `name`(a, mkFloat32(a.ctx, b))
  proc `name`*(a: float32, b: Z3Float32): Z3Float32 {.inline.} =
    `name`(mkFloat32(b.ctx, a), b)

liftFpBin(`+`)
liftFpBin(`-`)
liftFpBin(`*`)
liftFpBin(`/`)

proc sqrt*[E, S: static int](rm: Z3RoundingMode, a: Z3Fp[E, S]): Z3Fp[E, S] =
  wrap[Z3Fp[E, S]](a.ctx, a.ctx.checkErr Z3_mk_fpa_sqrt(a.ctx.raw, rm.raw, a.raw))
proc sqrt*[E, S: static int](a: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} =
  sqrt(rmRNE(a.ctx), a)

proc fma*[E, S: static int](rm: Z3RoundingMode,
                            a, b, c: Z3Fp[E, S]): Z3Fp[E, S] =
  ## Fused multiply-add — `a * b + c` computed with a single rounding.
  wrap[Z3Fp[E, S]](a.ctx,
    a.ctx.checkErr Z3_mk_fpa_fma(a.ctx.raw, rm.raw, a.raw, b.raw, c.raw))
proc fma*[E, S: static int](a, b, c: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} =
  fma(rmRNE(a.ctx), a, b, c)

proc roundToIntegral*[E, S: static int](rm: Z3RoundingMode,
                                       a: Z3Fp[E, S]): Z3Fp[E, S] =
  wrap[Z3Fp[E, S]](a.ctx,
    a.ctx.checkErr Z3_mk_fpa_round_to_integral(a.ctx.raw, rm.raw, a.raw))
proc roundToIntegral*[E, S: static int](a: Z3Fp[E, S]): Z3Fp[E, S] {.inline.} =
  roundToIntegral(rmRNE(a.ctx), a)

# ============================================================================
# Conversions
# ============================================================================

proc toIeeeBv*[E, S: static int](a: Z3Fp[E, S]): Z3BitVec[E + S] =
  ## IEEE 754 bit pattern as a BV of width `E + S` (e.g. 32 for
  ## `Z3Float32`). Lossless and rounding-free; the result is unspecified
  ## only on NaN payloads (per SMT-LIB FP-to-BV semantics).
  wrap[Z3BitVec[E + S]](a.ctx,
    a.ctx.checkErr Z3_mk_fpa_to_ieee_bv(a.ctx.raw, a.raw))

proc bvToFpBits*[Bw, E, S: static int](bv: Z3BitVec[Bw],
                                       _: typedesc[Z3Fp[E, S]]): Z3Fp[E, S] =
  ## Re-interpret the BV bits as an FP value of sort `Z3Fp[E, S]`. The
  ## BV width must equal `E + S`; mismatches are rejected at compile
  ## time. This is the bit-pattern reinterpret cast (no rounding).
  ## For lossy float-to-FP conversion, use `toFp(rm, fp, _)` instead.
  static: assert Bw == E + S,
    "bvToFpBits[Z3Fp[E,S]]: BV width must equal E + S"
  wrap[Z3Fp[E, S]](bv.ctx,
    bv.ctx.checkErr Z3_mk_fpa_to_fp_bv(bv.ctx.raw, bv.raw, fpSort[E, S](bv.ctx)))

template fpToFp3(name, ffi, srcConstraint: untyped) =
  proc name*[E, S: static int](rm: Z3RoundingMode,
                               x: srcConstraint,
                               _: typedesc[Z3Fp[E, S]]): Z3Fp[E, S] =
    wrap[Z3Fp[E, S]](x.ctx,
      x.ctx.checkErr ffi(x.ctx.raw, rm.raw, x.raw, fpSort[E, S](x.ctx)))
  proc name*[E, S: static int](x: srcConstraint,
                               t: typedesc[Z3Fp[E, S]]): Z3Fp[E, S] {.inline.} =
    name(rmRNE(x.ctx), x, t)

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
proc toSbv*[E, S, W: static int](a: Z3Fp[E, S]): Z3BitVec[W] {.inline.} =
  toSbv[E, S, W](rmRNE(a.ctx), a)

proc toUbv*[E, S, W: static int](rm: Z3RoundingMode,
                                 a: Z3Fp[E, S]): Z3BitVec[W] =
  wrap[Z3BitVec[W]](a.ctx,
    a.ctx.checkErr Z3_mk_fpa_to_ubv(a.ctx.raw, rm.raw, a.raw, cuint(W)))
proc toUbv*[E, S, W: static int](a: Z3Fp[E, S]): Z3BitVec[W] {.inline.} =
  toUbv[E, S, W](rmRNE(a.ctx), a)

# Pretty-print (v0.5 step 3D)

proc `$`*[E, S: static int](a: Z3Fp[E, S]): string = termToSmt2(a)
  ## SMT-LIB rendering of the FP AST.

proc `$`*(rm: Z3RoundingMode): string = termToSmt2(rm)
  ## SMT-LIB rendering of the rounding-mode AST.

# ============================================================================
# N6.4b — FPA numeral decomposition
# ============================================================================
#
# These procs extract components from *concrete* FP numerals. The C API
# uses bool success-flag + pointer-output for most values; the Nim wrappers
# translate failure → `none(T)`, success → `some(v)`.
#
# Note on `Option` vs direct return:
#   - bool-success APIs → `Option[T]`
#   - direct-return APIs (strings, BV nodes) → plain return (callers should
#     only invoke on actual numerals; misuse raises Z3Error via the context).

proc getNumeralSign*[E, S: static int](a: Z3Fp[E, S]): Option[bool] =
  ## Extract the sign of a concrete FP numeral.
  ## Returns `some(false)` for positive, `some(true)` for negative.
  ## Returns `none` when `a` is not a numeral (e.g. a free variable).
  ## NaN is not a valid argument; results are unspecified.
  var sgn: cint
  if Z3_fpa_get_numeral_sign(a.ctx.raw, a.raw, addr sgn):
    some(sgn != 0)
  else:
    none(bool)

proc getNumeralSignificandString*[E, S: static int](a: Z3Fp[E, S]): string =
  ## Return the significand of a concrete FP numeral as a decimal string.
  ## The value is in the range [0.0, 2.0). Callers should only invoke on
  ## concrete numerals; behaviour on free variables is unspecified.
  $Z3_fpa_get_numeral_significand_string(a.ctx.raw, a.raw)

proc getNumeralSignificandBv*[E, S: static int](a: Z3Fp[E, S]): Z3BitVec[S - 1] =
  ## Return the significand of a concrete FP numeral as a `Z3BitVec[S-1]`.
  ## The `S-1` width is because `S` includes the implicit hidden bit per the
  ## N6.3 convention; the returned BV holds the explicit (non-hidden) bits.
  ## Callers should only invoke on concrete numerals.
  wrap[Z3BitVec[S - 1]](a.ctx,
    a.ctx.checkErr Z3_fpa_get_numeral_significand_bv(a.ctx.raw, a.raw))

proc getNumeralSignificandUint64*[E, S: static int](
    a: Z3Fp[E, S]): Option[uint64] =
  ## Return the significand of a concrete FP numeral as a `uint64`.
  ## Returns `none` when `a` is not a numeral, or when the significand
  ## bits do not fit into a `uint64` (e.g. >64-bit FP sorts).
  ## NaN is an invalid argument.
  var n: uint64
  if Z3_fpa_get_numeral_significand_uint64(a.ctx.raw, a.raw, addr n):
    some(n)
  else:
    none(uint64)

proc getNumeralExponentString*[E, S: static int](
    a: Z3Fp[E, S], biased: bool = false): string =
  ## Return the exponent of a concrete FP numeral as a decimal string.
  ## Pass `biased = true` for the biased (stored) exponent;
  ## `biased = false` (the default) for the unbiased mathematical exponent.
  ## Callers should only invoke on concrete numerals.
  $Z3_fpa_get_numeral_exponent_string(a.ctx.raw, a.raw, biased)

proc getNumeralExponentInt64*[E, S: static int](
    a: Z3Fp[E, S], biased: bool = false): Option[int64] =
  ## Return the exponent of a concrete FP numeral as an `int64`.
  ## Returns `none` when `a` is not a numeral or the exponent overflows
  ## `int64`. Pass `biased = true` for the stored biased exponent.
  var n: int64
  if Z3_fpa_get_numeral_exponent_int64(a.ctx.raw, a.raw, addr n, biased):
    some(n)
  else:
    none(int64)

proc getNumeralExponentBv*[E, S: static int](
    a: Z3Fp[E, S], biased: bool = false): Z3BitVec[E] =
  ## Return the exponent of a concrete FP numeral as a `Z3BitVec[E]`.
  ## Pass `biased = true` for the stored biased exponent.
  ## Callers should only invoke on concrete numerals.
  wrap[Z3BitVec[E]](a.ctx,
    a.ctx.checkErr Z3_fpa_get_numeral_exponent_bv(a.ctx.raw, a.raw, biased))

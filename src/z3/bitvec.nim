## `Z3BitVec[W]` — width-tracked bit-vector ASTs.
##
## Bit-vectors carry a *width* — the number of bits in the vector —
## that's part of their identity: `Z3BitVec[8]` and `Z3BitVec[16]` are
## distinct types and the compiler prevents mixing them. The width is
## a `static int` generic parameter, so most width-arithmetic shows up
## at the *type* level: `extract[7, 0]` on a `Z3BitVec[32]` returns
## `Z3BitVec[8]`, `concat` adds widths, `zeroExtend[N]` adds N.
##
## ## Why a separate type from `Z3Ast[S]`
##
## Width is a Π-type over ℕ; sort tag is a Π-type over a finite enum.
## Forcing both into one `Z3Ast[S, W]` would mean every existing generic
## proc over `Z3Ast[S]` gains a `W: static int = 0` second parameter it
## never uses, and the sentinel-value `W=0` for non-BV sorts would have
## to be policed by hand. A separate type keeps each phantom-typed
## family clean.
##
## The cost: `==`, `!=`, `ite`, `mkDistinct` need parallel overloads
## here for `Z3BitVec[W]` (they're polymorphic over any sort). That's
## ~30 lines, mechanical.
##
## ## Sign discipline
##
## Many BV operations are *sign-dependent*: comparison, division,
## remainder, right-shift. We refuse to overload the obvious operators
## (`<`, `div`, `mod`, `shr`) for these — picking unsigned or signed by
## default silently hides a semantic choice. Instead we expose explicit
## variants: `bvult` / `bvslt`, `bvudiv` / `bvsdiv`, `bvurem` / `bvsrem`,
## `lshr` / `ashr`.
##
## Sign-*independent* ops (`+`, `-`, unary `-`, `*`, `and`, `or`, `xor`,
## `not`, `shl`, equality) overload normally; the result is bit-for-bit
## identical under either sign interpretation.

import std/[options]
import ./ffi, ./context, ./error, ./sort, ./ast, ./model
# `solver` and `model` were imported in v0.2 for the BV-specific
# `smtEquiv` and `eval` / `[]` overloads; v0.3 step 2 absorbed both
# into generic versions in `z3/semantics` and `z3/model`, so the
# imports are gone.
export sort   # users get SortTag (incl. stBitVec) via this import

type
  Z3BitVec*[W: static int] = object
    ## Phantom-typed bit-vector AST. The `W` parameter pins the width
    ## at the type level; `wrap` enforces that the underlying Z3 AST
    ## actually has the matching width when constructed from FFI.
    raw*: RawZ3Ast
    ctx*: Z3Context

# ============================================================================
# Lifecycle hooks (parallel Z3Ast[S])
# ============================================================================

proc `=destroy`[W: static int](a: Z3BitVec[W]) {.raises: [].} =
  termDestroy(a, Z3_dec_ref)

proc `=copy`[W: static int](dst: var Z3BitVec[W], src: Z3BitVec[W]) {.raises: [].} =
  termCopy(dst, src, Z3_dec_ref, Z3_inc_ref)

proc `=dup`[W: static int](src: Z3BitVec[W]): Z3BitVec[W] {.raises: [].} =
  termDup(result, src, Z3_inc_ref)

# ============================================================================
# sortOf overload (v0.3 step 9)
# ============================================================================

proc sortOf*[W: static int](_: typedesc[Z3BitVec[W]],
                            ctx: Z3Context): RawZ3Sort {.inline.} =
  ## Width-parameterised BV sort. Participates in the step-9
  ## `sortdispatch` resolution — `Z3BitVec[W]` is now reachable as a
  ## funcdecl arg / seq element / array key or value automatically.
  ctx.checkErr Z3_mk_bv_sort(ctx.raw, cuint(W))

# `wrapBv` removed v0.3 step 1 — call sites use the unified
# `wrap[Z3BitVec[W]](ctx, raw)` from `z3/lifecycle` directly.

# ============================================================================
# Construction
# ============================================================================

proc mkBitVecVar*[W: static int](ctx: Z3Context, name: string): Z3BitVec[W] =
  ## Free bit-vector variable of width `W`.
  ##
  ## ```nim
  ## let x = mkBitVecVar[8]("x")    # Z3BitVec[8]
  ## let y = ctx.mkBitVecVar[16]("y")
  ## ```
  static: assert W > 0, "BitVec width must be positive"
  let s = ctx.checkErr Z3_mk_bv_sort(ctx.raw, cuint(W))
  let sym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)
  wrap[Z3BitVec[W]](ctx, ctx.checkErr Z3_mk_const(ctx.raw, sym, s))
proc mkBitVecVar*[W: static int](name: string): Z3BitVec[W] =
  mkBitVecVar[W](requireCurrentContext(), name)

proc mkBitVec*[W: static int](
    ctx: Z3Context, v: SomeInteger): Z3BitVec[W] =
  ## Bit-vector literal of width `W` carrying the unsigned (mod 2^W)
  ## interpretation of `v`. Width is a bracket-position generic so the
  ## call site matches the rest of the BV surface (`mkBitVecVar[W]`,
  ## `mkBigBitVec[W]`).
  ##
  ## ```nim
  ## let a = mkBitVec[8](5'u32)     # Z3BitVec[8] with value 5
  ## let b = mkBitVec[8](-1'i8)     # Z3BitVec[8] = 0xFF
  ## let c = ctx.mkBitVec[16](7'u)  # explicit context
  ## ```
  ##
  ## Width is unrestricted — `mkBitVec[128](5'u)` produces a 128-bit
  ## BV with low 5. The Nim source value is `uint64`-bounded since
  ## `T: SomeInteger` only ranges over Nim's primitive integer types;
  ## for values exceeding that range use `mkBigBitVec[W](numeralString)`.
  static: assert W > 0, "BitVec width must be positive"
  let s = ctx.checkErr Z3_mk_bv_sort(ctx.raw, cuint(W))
  wrap[Z3BitVec[W]](ctx, ctx.checkErr Z3_mk_unsigned_int64(ctx.raw, uint64(v), s))
proc mkBitVec*[W: static int](v: SomeInteger): Z3BitVec[W] =
  mkBitVec[W](requireCurrentContext(), v)

proc mkBigBitVec*[W: static int](
    ctx: Z3Context, numeral: string): Z3BitVec[W] =
  ## Arbitrary-precision bit-vector literal of width `W` from a
  ## decimal string. Use when the value exceeds `uint64` range.
  ##
  ## ```nim
  ## let big = mkBigBitVec[128]("12345678901234567890")
  ## let huge = mkBigBitVec[256](
  ##   "115792089237316195423570985008687907853269984665640564039457")
  ## ```
  ##
  ## The numeral is interpreted mod 2^W (consistent with `mkBitVec`),
  ## so passing a value beyond the BV's range silently truncates —
  ## same semantics SMT-LIB itself uses.
  static: assert W > 0, "BitVec width must be positive"
  let s = ctx.checkErr Z3_mk_bv_sort(ctx.raw, cuint(W))
  wrap[Z3BitVec[W]](ctx, ctx.checkErr Z3_mk_numeral(ctx.raw, numeral.cstring, s))
proc mkBigBitVec*[W: static int](numeral: string): Z3BitVec[W] =
  mkBigBitVec[W](requireCurrentContext(), numeral)

# ============================================================================
# Arithmetic (sign-independent: result bit-pattern is the same under either
# 2's-complement or unsigned interpretation, so no signed/unsigned split)
# ============================================================================
#
# We collapse the boilerplate (ctx-extract, wrap, error-discipline) into a
# small template so individual ops are one-liners. Same idiom as
# `binaryOp` in arith.nim, specialised for the BV phantom shape.

template binBv(name: untyped, ffi: untyped) =
  proc name*[W: static int](a, b: Z3BitVec[W]): Z3BitVec[W] =
    wrap[Z3BitVec[W]](a.ctx, a.ctx.checkErr ffi(a.ctx.raw, a.raw, b.raw))

binBv(`+`, Z3_mk_bvadd)
binBv(`-`, Z3_mk_bvsub)
binBv(`*`, Z3_mk_bvmul)

# Sign-dependent division and remainder. Explicit names; we do NOT
# overload `div`/`mod` on BVs — picking unsigned or signed by default
# would silently bury a semantic choice that the user should make.
#
# - `bvudiv` / `bvurem` interpret operands as unsigned.
# - `bvsdiv` / `bvsrem` interpret as signed, with the sign of the
#   remainder matching the dividend (truncated division).
# - `bvsmod` interprets as signed with the sign of the remainder
#   matching the divisor (Euclidean-style modulo, matches SMT-LIB
#   `bvsmod`).
binBv(bvudiv, Z3_mk_bvudiv)
binBv(bvsdiv, Z3_mk_bvsdiv)
binBv(bvurem, Z3_mk_bvurem)
binBv(bvsrem, Z3_mk_bvsrem)
binBv(bvsmod, Z3_mk_bvsmod)

proc `-`*[W: static int](a: Z3BitVec[W]): Z3BitVec[W] =
  ## Unary negation — `0 - a` under modular arithmetic. Same bit pattern
  ## under either sign interpretation; for unsigned this is the additive
  ## inverse mod 2^W, for signed it's the 2's-complement negation
  ## (with the documented `-INT_MIN == INT_MIN` quirk for the minimum
  ## signed value).
  wrap[Z3BitVec[W]](a.ctx, a.ctx.checkErr Z3_mk_bvneg(a.ctx.raw, a.raw))

# ============================================================================
# Bitwise — overloaded normally (sign-independent at the bit level)
# ============================================================================

binBv(`and`, Z3_mk_bvand)
binBv(`or`, Z3_mk_bvor)
binBv(`xor`, Z3_mk_bvxor)

proc `not`*[W: static int](a: Z3BitVec[W]): Z3BitVec[W] =
  ## Bitwise complement — flips every bit. Unlike `not` on `Z3Bool`,
  ## this is the bitwise operator, not boolean negation.
  wrap[Z3BitVec[W]](a.ctx, a.ctx.checkErr Z3_mk_bvnot(a.ctx.raw, a.raw))

# ============================================================================
# Shifts — `shl` is sign-independent; right shifts split explicitly
# ============================================================================

binBv(`shl`, Z3_mk_bvshl)
binBv(lshr, Z3_mk_bvlshr)
binBv(ashr, Z3_mk_bvashr)

# ============================================================================
# Comparisons — Z3Bool-yielding; explicit signed/unsigned
# ============================================================================
#
# We deliberately don't overload `<`, `<=`, `>`, `>=`. Comparing
# fixed-width BVs is sign-dependent (0xFF on BV[8] is either -1 or 255),
# and silently picking one would invite bugs. SMT-LIB itself splits the
# operators (`bvult` vs `bvslt`); we mirror that. `==` / `!=` are
# sign-independent and *do* overload — they care only about bit equality.

template cmpBv(name: untyped, ffi: untyped) =
  proc name*[W: static int](a, b: Z3BitVec[W]): Z3Bool =
    wrap[Z3Bool](a.ctx, a.ctx.checkErr ffi(a.ctx.raw, a.raw, b.raw))

cmpBv(bvult, Z3_mk_bvult)
cmpBv(bvule, Z3_mk_bvule)
cmpBv(bvugt, Z3_mk_bvugt)
cmpBv(bvuge, Z3_mk_bvuge)
cmpBv(bvslt, Z3_mk_bvslt)
cmpBv(bvsle, Z3_mk_bvsle)
cmpBv(bvsgt, Z3_mk_bvsgt)
cmpBv(bvsge, Z3_mk_bvsge)

# ============================================================================
# Equality (returns Z3Bool)
# ============================================================================

proc `==`*[W: static int](a, b: Z3BitVec[W]): Z3Bool =
  ## SMT equality on same-width BVs. Returns a `Z3Bool` AST `(= a b)`.
  ## Different widths are a compile error (W must match).
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_eq(a.ctx.raw, a.raw, b.raw))

proc `!=`*[W: static int](a, b: Z3BitVec[W]): Z3Bool =
  ## Negation of `==`. Same width discipline.
  let eq = a == b
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_not(a.ctx.raw, eq.raw))

# ============================================================================
# Width manipulation — extract, concat, zeroExtend, signExtend, repeat
# ============================================================================
#
# Width arithmetic lifted to the type system. `extract[hi, lo]` returns
# a Z3BitVec whose width is `hi - lo + 1`, statically computed; the
# bounds are static-asserted so out-of-range slices fail at compile
# time. `concat` adds widths. `zeroExtend[N]` and `signExtend[N]` add N.
# `repeat[N]` multiplies.

proc extractImpl*[hi, lo: static int; W: static int](
    a: Z3BitVec[W]): Z3BitVec[hi - lo + 1] =
  ## Implementation backing `extract` — exposed publicly so the
  ## `extract` template can resolve it across module boundaries, but
  ## callers should use the `extract` template form.
  static:
    assert hi < W, "extract: hi must be < W"
    assert lo <= hi, "extract: lo must be <= hi"
    assert lo >= 0, "extract: lo must be >= 0"
  wrap[Z3BitVec[hi - lo + 1]](a.ctx,
    a.ctx.checkErr Z3_mk_extract(a.ctx.raw, cuint(hi), cuint(lo), a.raw))

proc concatImpl*[W1, W2: static int](
    a: Z3BitVec[W1], b: Z3BitVec[W2]): Z3BitVec[W1 + W2] =
  ## Implementation for `concat`. `a` becomes the high-order bits.
  wrap[Z3BitVec[W1 + W2]](a.ctx,
    a.ctx.checkErr Z3_mk_concat(a.ctx.raw, a.raw, b.raw))

proc concat*[W1, W2: static int](
    a: Z3BitVec[W1], b: Z3BitVec[W2]): Z3BitVec[W1 + W2] {.inline.} =
  ## Concatenate two BVs. `a` provides the high-order bits, `b` the low.
  ## Result width is `W1 + W2`, statically computed.
  concatImpl(a, b)

proc zeroExtendImpl*[N, W: static int](a: Z3BitVec[W]): Z3BitVec[W + N] =
  static: assert N >= 0, "zeroExtend: N must be >= 0"
  wrap[Z3BitVec[W + N]](a.ctx,
    a.ctx.checkErr Z3_mk_zero_ext(a.ctx.raw, cuint(N), a.raw))

template zeroExtend*(a: Z3BitVec, N: static int): untyped =
  ## Prepend `N` zero bits. Result width = `W + N`.
  ##
  ## ```nim
  ## let wide = bv8.zeroExtend(8)   # Z3BitVec[16], high byte zero
  ## ```
  zeroExtendImpl[N, a.W](a)

proc signExtendImpl*[N, W: static int](a: Z3BitVec[W]): Z3BitVec[W + N] =
  static: assert N >= 0, "signExtend: N must be >= 0"
  wrap[Z3BitVec[W + N]](a.ctx,
    a.ctx.checkErr Z3_mk_sign_ext(a.ctx.raw, cuint(N), a.raw))

template signExtend*(a: Z3BitVec, N: static int): untyped =
  ## Prepend `N` copies of the sign bit (MSB). Result width = `W + N`.
  signExtendImpl[N, a.W](a)

proc repeatImpl*[N, W: static int](a: Z3BitVec[W]): Z3BitVec[W * N] =
  static: assert N >= 1, "repeat: N must be >= 1"
  wrap[Z3BitVec[W * N]](a.ctx,
    a.ctx.checkErr Z3_mk_repeat(a.ctx.raw, cuint(N), a.raw))

template repeat*(a: Z3BitVec, N: static int): untyped =
  ## Tile `a` `N` times. Result width = `W * N`. Identity at `N = 1`.
  repeatImpl[N, a.W](a)

template extract*(a: Z3BitVec, hi, lo: static int): untyped =
  ## Bit slice `[hi..lo]` inclusive (Z3's `(_ extract hi lo)`).
  ## Result width is `hi - lo + 1`, known at compile time:
  ##
  ## ```nim
  ## let lo4 = bv.extract(3, 0)   # low nibble of an 8-bit BV → Z3BitVec[4]
  ## let hi4 = bv.extract(7, 4)
  ## ```
  ##
  ## Implementation: a template forwarding to `extractImpl` with the
  ## width pulled off the input type via `a.W`. Direct partial-explicit
  ## generic binding (`extract[hi, lo](bv)`) isn't supported by Nim 2.2,
  ## so we inject the width through the type witness rather than asking
  ## the caller for it.
  extractImpl[hi, lo, a.W](a)

# ============================================================================
# ite / mkDistinct — polymorphic over BV the same way they're polymorphic
# over Z3Ast[S]. Parallel overloads here because Z3BitVec[W] is a distinct
# type family.
# ============================================================================

proc ite*[W: static int](cond: Z3Bool, t, e: Z3BitVec[W]): Z3BitVec[W] =
  ## If-then-else on bit-vectors. Same-width branches enforced at the
  ## type level; cross-width is a compile error.
  wrap[Z3BitVec[W]](cond.ctx,
    cond.ctx.checkErr Z3_mk_ite(cond.ctx.raw, cond.raw, t.raw, e.raw))

# `mkDistinct` — all-pairs-distinct constraint on a sequence of
# same-width BVs. Returns a `Z3Bool`. Empty / singleton inputs are
# trivially true. (The pre-v0.5 version indexed `xs[0]` on empty
# input — a bug fixed by the unified `emitVarargsDistinctW` helper.)
emitVarargsDistinctW(mkDistinct, Z3BitVec[W])

# ============================================================================
# Literal lifts — `bv + 3'u32`, `3'u32 + bv`, `bv == 5'u32`, etc.
# Width inferred from the BV side; the integer literal is lifted to a
# BV of matching width via `mkBitVec[W](lit)`.
# ============================================================================

template liftBin(op: untyped) =
  proc op*[W: static int, T: SomeInteger](a: Z3BitVec[W], b: T): Z3BitVec[W] {.inline.} =
    op(a, mkBitVec[W](b))
  proc op*[W: static int, T: SomeInteger](a: T, b: Z3BitVec[W]): Z3BitVec[W] {.inline.} =
    op(mkBitVec[W](a), b)

liftBin(`+`)
liftBin(`-`)
liftBin(`*`)
liftBin(`and`)
liftBin(`or`)
liftBin(`xor`)

template liftCmp(op: untyped) =
  proc op*[W: static int, T: SomeInteger](a: Z3BitVec[W], b: T): Z3Bool {.inline.} =
    op(a, mkBitVec[W](b))
  proc op*[W: static int, T: SomeInteger](a: T, b: Z3BitVec[W]): Z3Bool {.inline.} =
    op(mkBitVec[W](a), b)

liftCmp(`==`)
liftCmp(`!=`)
liftCmp(bvult)
liftCmp(bvule)
liftCmp(bvugt)
liftCmp(bvuge)
liftCmp(bvslt)
liftCmp(bvsle)
liftCmp(bvsgt)
liftCmp(bvsge)

# ============================================================================
# Model extraction
# ============================================================================

proc toUint*[W: static int](a: Z3BitVec[W]): uint64 =
  ## Unsigned 64-bit extraction. Requires `W <= 64`. Internally calls
  ## `Z3_simplify` first, so concrete expression trees
  ## (`mkBitVec[8](0xFF'u8) + mkBitVec[8](1'u8)`) extract their folded
  ## value directly without the caller wrapping them in a solver or
  ## calling `simplify` themselves.
  ##
  ## Raises `Z3Error` if the AST still doesn't reduce to a literal
  ## numeral (i.e. it references a free variable).
  static: assert W <= 64,
    "toUint requires W <= 64; use `toBigUintStr` for wider BVs"
  let folded = a.ctx.checkErr Z3_simplify(a.ctx.raw, a.raw)
  var v: uint64
  if not Z3_get_numeral_uint64(a.ctx.raw, folded, addr v):
    var e = newException(Z3InvalidUsageError,
      "Z3BitVec.toUint: AST `" & $Z3_ast_to_string(a.ctx.raw, a.raw) &
      "` does not reduce to a literal BV numeral.")
    e.code = Z3_INVALID_USAGE
    raise e
  v

proc toBigIntStr*[W: static int](a: Z3BitVec[W]): string =
  ## Signed-2's-complement decimal string of an arbitrary-width BV
  ## numeral. Works for any `W`; for `W <= 64` `toInt` is the typed-
  ## return alternative.
  ##
  ## ```nim
  ## let allOnes = mkBigBitVec[128]("340282366920938463463374607431768211455")
  ## doAssert allOnes.toBigIntStr == "-1"
  ## ```
  ##
  ## Implementation: builds `Z3_mk_bv2int(bv, signed=true)` to obtain
  ## an Int-sorted AST whose value is the signed interpretation
  ## (Z3 does the `v - 2^W` transform internally with arbitrary
  ## precision), simplifies it, then reads off `Z3_get_numeral_string`.
  ## One FFI call beyond the FFI for `toBigUintStr`, no Nim-side
  ## arbitrary-precision arithmetic needed.
  ##
  ## Raises `Z3Error` if the AST isn't a literal numeral.
  let asInt = a.ctx.checkErr Z3_mk_bv2int(a.ctx.raw, a.raw, true)
  let simplified = a.ctx.checkErr Z3_simplify(a.ctx.raw, asInt)
  let s = Z3_get_numeral_string(a.ctx.raw, simplified)
  if s.isNil:
    var e = newException(Z3InvalidUsageError,
      "Z3BitVec.toBigIntStr: AST `" & $Z3_ast_to_string(a.ctx.raw, a.raw) &
      "` is not a literal BV numeral.")
    e.code = Z3_INVALID_USAGE
    raise e
  $s

proc toBigUintStr*[W: static int](a: Z3BitVec[W]): string =
  ## Unsigned-interpretation decimal string of an arbitrary-width BV.
  ## Internally `Z3_simplify`s first, so concrete expression trees
  ## fold to their literal value before extraction. Works for any `W`;
  ## for `W <= 64` `toUint` is the typed-return alternative.
  ##
  ## ```nim
  ## let big = mkBigBitVec[128]("12345678901234567890")
  ## doAssert big.toBigUintStr == "12345678901234567890"
  ## ```
  ##
  ## Raises `Z3Error` if the AST doesn't reduce to a literal numeral
  ## (i.e. it references a free variable).
  let folded = a.ctx.checkErr Z3_simplify(a.ctx.raw, a.raw)
  let s = Z3_get_numeral_string(a.ctx.raw, folded)
  if s.isNil:
    var e = newException(Z3InvalidUsageError,
      "Z3BitVec.toBigUintStr: AST `" & $Z3_ast_to_string(a.ctx.raw, a.raw) &
      "` does not reduce to a literal BV numeral.")
    e.code = Z3_INVALID_USAGE
    raise e
  $s

proc toInt*[W: static int](a: Z3BitVec[W]): int64 =
  ## Signed-2's-complement interpretation. Requires `W <= 64`.
  ## Internally calls `Z3_simplify` first, so concrete expression
  ## trees fold to their literal value before extraction.
  ##
  ## Implementation note: Z3 stores BV numerals as unsigned magnitudes
  ## even when the user intended a signed value (the BV theory itself
  ## doesn't carry a sign attribute — sign is purely an interpretation
  ## chosen by the operator). `Z3_get_numeral_uint64` returns the
  ## unsigned magnitude; we apply the 2's-complement transform
  ## (`v - 2^W` when the MSB is set) here.
  static: assert W <= 64,
    "toInt requires W <= 64; use `toBigIntStr` for wider BVs"
  let folded = a.ctx.checkErr Z3_simplify(a.ctx.raw, a.raw)
  var v: uint64
  if not Z3_get_numeral_uint64(a.ctx.raw, folded, addr v):
    var e = newException(Z3InvalidUsageError,
      "Z3BitVec.toInt: AST `" & $Z3_ast_to_string(a.ctx.raw, a.raw) &
      "` does not reduce to a literal BV numeral.")
    e.code = Z3_INVALID_USAGE
    raise e
  when W == 64:
    # No room above the MSB; reinterpret the bit pattern as int64.
    cast[int64](v)
  else:
    # MSB is bit (W-1). If set, subtract 2^W.
    const signBit = 1'u64 shl (W - 1)
    const modulus = 1'i64 shl W
    if (v and signBit) != 0:
      int64(v) - modulus
    else:
      int64(v)

# The BV-specific `eval[W]` / `[][W]` overloads lived here in v0.2;
# v0.3 step 2 absorbed them into the single generic `eval[T]` / `[][T]`
# in `z3/model` — works for every typed family automatically now that
# `wrap[T]` is unified.

# ============================================================================
# eval shortcuts (v0.5 step 3)
# ============================================================================
#
# The `evalXxx` convention: `evalXxx(m, a)` is shorthand for
# `m.eval(a).toXxx`. Defined here for the `Z3BitVec[W]` family to
# complete the model-extraction parity with `Z3Int.evalInt` /
# `Z3Bool.evalBool` etc.

proc evalUint*[W: static int](m: Z3Model, a: Z3BitVec[W],
                              modelCompletion = true): uint64 {.inline.} =
  ## Shorthand for `m.eval(a, modelCompletion).toUint` — extract the
  ## unsigned BV value at `a` under the model. Requires `W <= 64`.
  m.eval(a, modelCompletion).toUint

proc evalInt*[W: static int](m: Z3Model, a: Z3BitVec[W],
                             modelCompletion = true): int64 {.inline.} =
  ## Shorthand for `m.eval(a, modelCompletion).toInt` — extract the
  ## signed BV value at `a` under the model. Requires `W <= 64`.
  m.eval(a, modelCompletion).toInt

# ============================================================================
# Pretty-print
# ============================================================================

proc `$`*[W: static int](a: Z3BitVec[W]): string = termToSmt2(a)
  ## SMT-LIB rendering of the BV AST. Mirrors `$` on `Z3Ast[S]`.

# The BV-specific `smtEquiv` overload lived here in v0.2; v0.3 step 2
# absorbed it into the generic `smtEquiv[T]` in `z3/semantics`.

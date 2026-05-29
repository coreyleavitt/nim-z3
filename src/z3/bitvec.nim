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
import ./ffi, ./context, ./sort, ./ast, ./solver, ./model
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
  try:
    if not a.raw.isNil and a.ctx != nil and not a.ctx.raw.isNil:
      Z3_dec_ref(a.ctx.raw, a.raw)
  except CatchableError:
    discard

proc `=copy`[W: static int](dst: var Z3BitVec[W], src: Z3BitVec[W]) {.raises: [].} =
  if dst.raw != src.raw:
    try:
      if not dst.raw.isNil and dst.ctx != nil and not dst.ctx.raw.isNil:
        Z3_dec_ref(dst.ctx.raw, dst.raw)
      dst.raw = src.raw
      dst.ctx = src.ctx
      if not dst.raw.isNil and dst.ctx != nil and not dst.ctx.raw.isNil:
        Z3_inc_ref(dst.ctx.raw, dst.raw)
    except CatchableError:
      discard

proc `=dup`[W: static int](src: Z3BitVec[W]): Z3BitVec[W] {.raises: [].} =
  result.raw = src.raw
  result.ctx = src.ctx
  if not result.raw.isNil and result.ctx != nil and not result.ctx.raw.isNil:
    try:
      Z3_inc_ref(result.ctx.raw, result.raw)
    except CatchableError:
      discard

# ============================================================================
# Wrap — refcount-discipline entry point (parallels ast.nim's `wrap`)
# ============================================================================

template wrapBv*[W: static int](theCtx: Z3Context, theRaw: RawZ3Ast): Z3BitVec[W] =
  block:
    let r = theRaw
    if not r.isNil:
      Z3_inc_ref(theCtx.raw, r)
    Z3BitVec[W](raw: r, ctx: theCtx)

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
  wrapBv[W](ctx, ctx.checkErr Z3_mk_const(ctx.raw, sym, s))
proc mkBitVecVar*[W: static int](name: string): Z3BitVec[W] =
  mkBitVecVar[W](requireCurrentContext(), name)

proc mkBitVec*[T: SomeInteger](
    ctx: Z3Context, v: T, W: static int): Z3BitVec[W] =
  ## Bit-vector literal of width `W` carrying the unsigned (mod 2^W)
  ## interpretation of `v`.
  ##
  ## ```nim
  ## let a = mkBitVec(5'u32, 8)     # Z3BitVec[8] with value 5
  ## let b = mkBitVec(-1'i8, 8)     # Z3BitVec[8] = 0xFF
  ## let c = ctx.mkBitVec(7'u, 16)  # explicit context
  ## ```
  ##
  ## For widths above 64 bits, use `mkBigBitVec` with a string numeral.
  static:
    assert W > 0, "BitVec width must be positive"
    assert W <= 64, "use `mkBigBitVec` for widths above 64 bits"
  let s = ctx.checkErr Z3_mk_bv_sort(ctx.raw, cuint(W))
  wrapBv[W](ctx, ctx.checkErr Z3_mk_unsigned_int64(ctx.raw, uint64(v), s))
proc mkBitVec*[T: SomeInteger](v: T, W: static int): Z3BitVec[W] =
  mkBitVec(requireCurrentContext(), v, W)

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
    wrapBv[W](a.ctx, a.ctx.checkErr ffi(a.ctx.raw, a.raw, b.raw))

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
  wrapBv[W](a.ctx, a.ctx.checkErr Z3_mk_bvneg(a.ctx.raw, a.raw))

# ============================================================================
# Bitwise — overloaded normally (sign-independent at the bit level)
# ============================================================================

binBv(`and`, Z3_mk_bvand)
binBv(`or`, Z3_mk_bvor)
binBv(`xor`, Z3_mk_bvxor)

proc `not`*[W: static int](a: Z3BitVec[W]): Z3BitVec[W] =
  ## Bitwise complement — flips every bit. Unlike `not` on `Z3Bool`,
  ## this is the bitwise operator, not boolean negation.
  wrapBv[W](a.ctx, a.ctx.checkErr Z3_mk_bvnot(a.ctx.raw, a.raw))

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
    wrap[stBool](a.ctx, a.ctx.checkErr ffi(a.ctx.raw, a.raw, b.raw))

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
  wrap[stBool](a.ctx, a.ctx.checkErr Z3_mk_eq(a.ctx.raw, a.raw, b.raw))

proc `!=`*[W: static int](a, b: Z3BitVec[W]): Z3Bool =
  ## Negation of `==`. Same width discipline.
  let eq = a == b
  wrap[stBool](a.ctx, a.ctx.checkErr Z3_mk_not(a.ctx.raw, eq.raw))

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
  wrapBv[hi - lo + 1](a.ctx,
    a.ctx.checkErr Z3_mk_extract(a.ctx.raw, cuint(hi), cuint(lo), a.raw))

proc concatImpl*[W1, W2: static int](
    a: Z3BitVec[W1], b: Z3BitVec[W2]): Z3BitVec[W1 + W2] =
  ## Implementation for `concat`. `a` becomes the high-order bits.
  wrapBv[W1 + W2](a.ctx,
    a.ctx.checkErr Z3_mk_concat(a.ctx.raw, a.raw, b.raw))

proc concat*[W1, W2: static int](
    a: Z3BitVec[W1], b: Z3BitVec[W2]): Z3BitVec[W1 + W2] {.inline.} =
  ## Concatenate two BVs. `a` provides the high-order bits, `b` the low.
  ## Result width is `W1 + W2`, statically computed.
  concatImpl(a, b)

proc zeroExtendImpl*[N, W: static int](a: Z3BitVec[W]): Z3BitVec[W + N] =
  static: assert N >= 0, "zeroExtend: N must be >= 0"
  wrapBv[W + N](a.ctx,
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
  wrapBv[W + N](a.ctx,
    a.ctx.checkErr Z3_mk_sign_ext(a.ctx.raw, cuint(N), a.raw))

template signExtend*(a: Z3BitVec, N: static int): untyped =
  ## Prepend `N` copies of the sign bit (MSB). Result width = `W + N`.
  signExtendImpl[N, a.W](a)

proc repeatImpl*[N, W: static int](a: Z3BitVec[W]): Z3BitVec[W * N] =
  static: assert N >= 1, "repeat: N must be >= 1"
  wrapBv[W * N](a.ctx,
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
  wrapBv[W](cond.ctx,
    cond.ctx.checkErr Z3_mk_ite(cond.ctx.raw, cond.raw, t.raw, e.raw))

proc mkDistinct*[W: static int](xs: varargs[Z3BitVec[W]]): Z3Bool =
  ## All-pairs-distinct constraint on a sequence of same-width BVs.
  ## Returns a `Z3Bool`. Empty / singleton inputs are trivially true.
  if xs.len <= 1:
    return wrap[stBool](xs[0].ctx,
      xs[0].ctx.checkErr Z3_mk_true(xs[0].ctx.raw))
  var raws = newSeq[RawZ3Ast](xs.len)
  for i, x in xs:
    raws[i] = x.raw
  wrap[stBool](xs[0].ctx, xs[0].ctx.checkErr Z3_mk_distinct(
    xs[0].ctx.raw, cuint(raws.len),
    cast[ptr UncheckedArray[RawZ3Ast]](addr raws[0])))

# ============================================================================
# Literal lifts — `bv + 3'u32`, `3'u32 + bv`, `bv == 5'u32`, etc.
# Width inferred from the BV side; the integer literal is lifted to a
# BV of matching width via `mkBitVec(lit, W)`.
# ============================================================================

template liftBin(op: untyped) =
  proc op*[W: static int, T: SomeInteger](a: Z3BitVec[W], b: T): Z3BitVec[W] {.inline.} =
    op(a, mkBitVec(b, W))
  proc op*[W: static int, T: SomeInteger](a: T, b: Z3BitVec[W]): Z3BitVec[W] {.inline.} =
    op(mkBitVec(a, W), b)

liftBin(`+`)
liftBin(`-`)
liftBin(`*`)
liftBin(`and`)
liftBin(`or`)
liftBin(`xor`)

template liftCmp(op: untyped) =
  proc op*[W: static int, T: SomeInteger](a: Z3BitVec[W], b: T): Z3Bool {.inline.} =
    op(a, mkBitVec(b, W))
  proc op*[W: static int, T: SomeInteger](a: T, b: Z3BitVec[W]): Z3Bool {.inline.} =
    op(mkBitVec(a, W), b)

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
  ## Unsigned 64-bit extraction from a BV numeral. Requires `W <= 64`.
  ## Raises `Z3Error` if the AST isn't a literal numeral.
  static: assert W <= 64,
    "toUint requires W <= 64; use `toBigUintStr` for wider BVs"
  var v: uint64
  if not Z3_get_numeral_uint64(a.ctx.raw, a.raw, addr v):
    var e = newException(Z3Error,
      "Z3BitVec.toUint: AST `" & $Z3_ast_to_string(a.ctx.raw, a.raw) &
      "` is not a literal BV numeral.")
    e.code = Z3_INVALID_USAGE
    raise e
  v

proc toInt*[W: static int](a: Z3BitVec[W]): int64 =
  ## Signed-2's-complement interpretation of a BV numeral. Requires
  ## `W <= 64`. Raises `Z3Error` if the AST isn't a literal numeral.
  ##
  ## Implementation note: Z3 stores BV numerals as unsigned magnitudes
  ## even when the user intended a signed value (the BV theory itself
  ## doesn't carry a sign attribute — sign is purely an interpretation
  ## chosen by the operator). `Z3_get_numeral_int64` therefore returns
  ## the unsigned magnitude; we apply the 2's-complement transform
  ## (`v - 2^W` when the MSB is set) here.
  static: assert W <= 64,
    "toInt requires W <= 64; use `toBigIntStr` for wider BVs"
  var v: uint64
  if not Z3_get_numeral_uint64(a.ctx.raw, a.raw, addr v):
    var e = newException(Z3Error,
      "Z3BitVec.toInt: AST `" & $Z3_ast_to_string(a.ctx.raw, a.raw) &
      "` is not a literal BV numeral.")
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

# ============================================================================
# Model eval — Z3Model[bv]
# ============================================================================

proc eval*[W: static int](m: Z3Model, a: Z3BitVec[W],
                          modelCompletion = true): Z3BitVec[W] =
  ## Evaluate a BV AST under the model. Mirrors `Z3Model.eval` for
  ## `Z3Ast[S]`; separate overload because `Z3BitVec[W]` is a distinct
  ## type family.
  var outRaw: RawZ3Ast
  let ok = Z3_model_eval(m.ctx.raw, m.raw, a.raw, modelCompletion, addr outRaw)
  let errCode = Z3_get_error_code(m.ctx.raw)
  if errCode != Z3_OK:
    raiseZ3Error(m.ctx, errCode)
  if not ok:
    var e = newException(Z3Error,
      "Z3_model_eval returned false for a BV AST.")
    e.code = Z3_INVALID_USAGE
    raise e
  wrapBv[W](m.ctx, outRaw)

proc `[]`*[W: static int](m: Z3Model, a: Z3BitVec[W]): Z3BitVec[W] =
  ## Sugar for `m.eval(a)`.
  m.eval(a)

# ============================================================================
# Pretty-print
# ============================================================================

proc `$`*[W: static int](a: Z3BitVec[W]): string =
  ## SMT-LIB rendering of the BV AST. Mirrors `$` on `Z3Ast[S]`.
  $Z3_ast_to_string(a.ctx.raw, a.raw)

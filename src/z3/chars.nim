## `z3/chars` — SMT-LIB Char sort (Unicode codepoint).
##
## Z3's `Char` is a Unicode codepoint type — the basis alphabet
## underneath the String and Regex theories (`String = (Seq Char)`,
## `RegEx String` ranges over the char alphabet). It's surfaced as a
## phantom-typed value family parallel to `Z3String`, slotting into the
## `Z3Term` concept so lifecycle / `==` / `!=` / `eval` / `smtEquiv` /
## etc. fall out automatically.
##
## ## When you reach for `Z3Char`
##
## - **Char-level predicates** Z3 ships — `<=` / `<` codepoint ordering
##   (`char.<=`), `isDigit` (`char.is_digit`), and `toInt`
##   (`char.to_int`) for the codepoint extractor.
## - **Future BV interop** — `Z3_mk_char_to_bv` / `_from_bv` are real
##   Z3 entry points; surfaced in a follow-up once the
##   `:char-width` runtime parameter is wired through.
##
## Note: `Z3Regex.range` is `Z3String`-typed (Z3's polymorphic sort
## checker enforces `(re.range String String)`, not Char-typed
## operands), so building char ranges does NOT go through `Z3Char` —
## it goes through one-codepoint `Z3String` values.

import ./ffi, ./context, ./error, ./ast, ./model, ./simplify, ./bitvec

# ============================================================================
# Z3Char — phantom-typed value family
# ============================================================================

type
  Z3Char* = object
    ## A single Unicode codepoint as a Z3 AST. Non-generic; lifecycle
    ## via `emitTermLifecycle`.
    raw*: RawZ3Ast
    ctx*: Z3Context

emitTermLifecycle(Z3Char, Z3_dec_ref, Z3_inc_ref)

# Step 9 sortOf overload — participates in z3/sortdispatch's resolution.
proc sortOf*(_: typedesc[Z3Char], ctx: Z3Context): RawZ3Sort {.inline.} =
  ctx.checkErr Z3_mk_char_sort(ctx.raw)

# ============================================================================
# Construction
# ============================================================================

proc mkChar*(ctx: Z3Context, codepoint: int): Z3Char =
  ## Build a `Z3Char` carrying Unicode codepoint `codepoint`. Negative
  ## or out-of-Unicode values are rejected at the boundary.
  doAssert codepoint >= 0 and codepoint <= 0x10FFFF,
    "Z3Char codepoint must be in [0, 0x10FFFF]"
  wrap[Z3Char](ctx, ctx.checkErr Z3_mk_char(ctx.raw, cuint(codepoint)))
proc mkChar*(codepoint: int): Z3Char =
  mkChar(requireCurrentContext(), codepoint)

proc mkChar*(ctx: Z3Context, ch: char): Z3Char {.inline.} =
  ## ASCII-friendly overload — `mkChar(ctx, 'a')`. For any non-ASCII
  ## codepoint, pass the `int` codepoint directly.
  mkChar(ctx, int(ch))
proc mkChar*(ch: char): Z3Char {.inline.} =
  mkChar(requireCurrentContext(), ch)

proc mkCharVar*(ctx: Z3Context, name: string): Z3Char =
  ## Free Z3Char variable — usable as a bound var under `forall` /
  ## `exists` for quantified character properties, or as an
  ## unknown to be pinned by the solver. **v0.5 step 3.**
  let sort = ctx.checkErr Z3_mk_char_sort(ctx.raw)
  let sym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)
  wrap[Z3Char](ctx, ctx.checkErr Z3_mk_const(ctx.raw, sym, sort))
proc mkCharVar*(name: string): Z3Char =
  mkCharVar(requireCurrentContext(), name)

# ============================================================================
# Equality + comparison + predicates
# ============================================================================

proc `==`*(a, b: Z3Char): Z3Bool =
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_eq(a.ctx.raw, a.raw, b.raw))

proc `!=`*(a, b: Z3Char): Z3Bool =
  let eq = a == b
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_not(a.ctx.raw, eq.raw))

proc `<=`*(a, b: Z3Char): Z3Bool =
  ## Codepoint ordering — SMT `(char.<= a b)`.
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_char_le(a.ctx.raw, a.raw, b.raw))

proc `<`*(a, b: Z3Char): Z3Bool =
  ## Strict codepoint ordering — `a <= b and a != b`. Z3 doesn't ship
  ## a primitive for strict-less-than; this composes the two it has.
  let leq = a <= b
  let ne = a != b
  var raws = [leq.raw, ne.raw]
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_and(a.ctx.raw, 2,
    cast[ptr UncheckedArray[RawZ3Ast]](addr raws[0])))

proc isDigit*(a: Z3Char): Z3Bool =
  ## SMT `(char.is_digit a)` — true iff `a` is an ASCII digit `'0'..'9'`.
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_char_is_digit(a.ctx.raw, a.raw))

# ============================================================================
# Int / BV interop
# ============================================================================

proc toInt*(a: Z3Char): Z3Int =
  ## SMT `(char.to_int a)` — codepoint as a `Z3Int`. Distinct from
  ## `model.toInt64` (extracts a Nim `int64` from a numeral AST); this is
  ## the AST-level codepoint extractor.
  wrap[Z3Int](a.ctx, a.ctx.checkErr Z3_mk_char_to_int(a.ctx.raw, a.raw))

proc `$`*(a: Z3Char): string = termToSmt2(a)
  ## SMT-LIB rendering: e.g. `(_ Char 97)` for ASCII `'a'`.

proc evalChar*(m: Z3Model, a: Z3Char, modelCompletion = true): int64 {.inline.} =
  ## Shorthand for "extract the Unicode codepoint of `a` under the
  ## model as a Nim `int64`." **v0.5 step 3.** Composes the AST-level
  ## codepoint extractor (`toInt(a: Z3Char)`) with the model-level
  ## numeral extractor (`toInt64(a: Z3Int)`); `simplify` folds the
  ## `(char.to_int (_ Char N))` wrapper to the literal `N`, which
  ## Z3's evaluator doesn't do automatically.
  simplify(m.eval(a, modelCompletion).toInt).toInt64

# ============================================================================
# Z3Char <-> Z3BitVec interop (v0.5 step 6C)
# ============================================================================
#
# Z3 represents a `Z3Char` internally as a bit-vector whose width is
# determined by the global `encoding` parameter:
#
#   - `unicode` (default): 18 bits (the full Unicode-21 code-point
#     space rounded up to a power-of-two-shaped width)
#   - `bmp`: 16 bits (Basic Multilingual Plane only)
#   - `ascii`: 8 bits
#
# The wrapper commits to the **Unicode default** (`Z3BitVec[18]`).
# If a user changes Z3's `encoding` global param to `bmp` or
# `ascii`, the runtime BV width changes and these procs will
# produce ASTs of the wrong width — Z3 will raise a sort mismatch
# at solver time. That's advanced usage; users in that territory
# should call `Z3_mk_char_to_bv` / `Z3_mk_char_from_bv` directly.

const UnicodeCharWidth* = 18
  ## Z3's `Z3Char` width when `encoding = unicode` (the default).
  ## Locked at compile time on the wrapper's `toBitVec` /
  ## `mkChar(bv: Z3BitVec[18])` overloads.

proc toBitVec*(c: Z3Char): Z3BitVec[UnicodeCharWidth] =
  ## Convert `c` to its underlying bit-vector representation. The
  ## returned BV has width `UnicodeCharWidth` (18 bits) assuming
  ## Z3's default `encoding = unicode` global param.
  ##
  ## ```nim
  ## let codepoint = evalUint(m, mkChar('a').toBitVec)
  ## # codepoint == 97
  ## ```
  wrap[Z3BitVec[UnicodeCharWidth]](c.ctx,
    c.ctx.checkErr Z3_mk_char_to_bv(c.ctx.raw, c.raw))

proc mkChar*(bv: Z3BitVec[UnicodeCharWidth]): Z3Char =
  ## Build a `Z3Char` from a BV of width `UnicodeCharWidth`. Inverse
  ## of `toBitVec`. The BV's value must be a valid Unicode codepoint
  ## ([0, 0x10FFFF]); Z3 doesn't validate this in this builder, but
  ## the value will be silently masked or rejected at consumer
  ## boundaries (e.g. `Z3_mk_string_from_char` validates).
  wrap[Z3Char](bv.ctx,
    bv.ctx.checkErr Z3_mk_char_from_bv(bv.ctx.raw, bv.raw))

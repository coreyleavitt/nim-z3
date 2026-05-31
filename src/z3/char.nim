## `z3/char` — SMT-LIB Char sort (Unicode codepoint).
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

import ./ffi, ./context, ./error, ./ast

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
  ## `model.toInt` (extracts a Nim `int` from a numeral AST); this is
  ## the AST-level codepoint extractor.
  wrap[Z3Int](a.ctx, a.ctx.checkErr Z3_mk_char_to_int(a.ctx.raw, a.raw))

# ============================================================================
# BV interop — deferred to a focused follow-up
# ============================================================================
#
# Z3 ships `Z3_mk_char_to_bv` / `Z3_mk_char_from_bv`. The encoded BV
# width matches Z3's runtime `:char-width` param (default 18 bits).
# Surfacing them well needs:
#   - deciding whether to lock to `Z3BitVec[18]` (the default and what
#     ~everyone uses) or surface a `--char-width` setting too, and
#   - resolving the bidirectional import between `z3/char` and
#     `z3/bitvec` (currently bitvec doesn't import char).
# Logged for v0.3 step 5+ work or a follow-up; not blocking step 4.

## `z3/string` — SMT-LIB String theory.
##
## Strings in SMT-LIB are `(Seq Char)`: finite sequences of Unicode
## characters. Z3 exposes them via a first-class String sort plus the
## `seq_*` builders. This module surfaces them as `Z3String`, a
## phantom-typed value family parallel to `Z3Array[K, V]` and
## `Z3DatatypeValue[T]` — slots into the `Z3Term` concept, gets generic
## `eval` / `smtEquiv` / `==` automatically through `z3/lifecycle` and
## `z3/semantics`.
##
## ## Decidability caveat
##
## Z3's string solver is **incomplete in general**. Concrete-string
## queries (no free variables) decide reliably; queries combining string
## constraints with arithmetic, regex membership, and free string
## variables may return `zsUnknown` or run for a long time. Treat
## `zsUnknown` as a possible outcome for any non-trivial string proof
## obligation.

import ./ffi, ./context, ./ast, ./builder, ./model

# ============================================================================
# Z3String — phantom-typed value family
# ============================================================================

type
  Z3String* = object
    ## SMT-LIB string value or expression. Non-generic; lifecycle hooks
    ## are stamped out by `emitTermLifecycle`.
    raw*: RawZ3Ast
    ctx*: Z3Context

emitTermLifecycle(Z3String, Z3_dec_ref, Z3_inc_ref)

# ============================================================================
# Literals + variables
# ============================================================================

proc mkString*(ctx: Z3Context, s: string): Z3String =
  ## String literal carrying the bytes of `s`. Uses `Z3_mk_lstring` so
  ## embedded NULs are preserved.
  wrap[Z3String](ctx,
    ctx.checkErr Z3_mk_lstring(ctx.raw, cuint(s.len), s.cstring))
proc mkString*(s: string): Z3String =
  mkString(requireCurrentContext(), s)

proc mkStringVar*(ctx: Z3Context, name: string): Z3String =
  ## Free string variable. The Z3 solver decides its value (if any)
  ## that satisfies the asserted constraints.
  let sort = ctx.checkErr Z3_mk_string_sort(ctx.raw)
  let sym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)
  wrap[Z3String](ctx, ctx.checkErr Z3_mk_const(ctx.raw, sym, sort))
proc mkStringVar*(name: string): Z3String =
  mkStringVar(requireCurrentContext(), name)

# ============================================================================
# Model extraction
# ============================================================================

proc toStr*(a: Z3String): string =
  ## Extract the Nim `string` from a Z3 string literal AST. Uses
  ## `Z3_get_lstring` so embedded NULs are preserved. Raises `Z3Error`
  ## if the AST isn't a concrete string literal.
  var length: cuint
  let raw = Z3_get_lstring(a.ctx.raw, a.raw, addr length)
  let errCode = Z3_get_error_code(a.ctx.raw)
  if errCode != Z3_OK:
    raiseZ3Error(a.ctx, errCode)
  if raw.isNil:
    var e = newException(Z3Error,
      "Z3String.toStr: AST `" & $Z3_ast_to_string(a.ctx.raw, a.raw) &
      "` is not a literal string.")
    e.code = Z3_INVALID_USAGE
    raise e
  # Z3 owns the cstring; copy into a Nim string of the right length.
  var s = newString(int(length))
  if length > 0'u32:
    copyMem(addr s[0], raw, int(length))
  s

proc evalStr*(m: Z3Model, a: Z3String, modelCompletion = true): string {.inline.} =
  ## `m.eval(a, modelCompletion).toStr` in one call.
  m.eval(a, modelCompletion).toStr

# ============================================================================
# Equality — Z3Bool-yielding semantic equality
# ============================================================================
#
# Mirrors the per-family `==` defined on Z3Ast[S], Z3BitVec[W],
# Z3Array[K,V], Z3DatatypeValue[T]. Returns a Z3Bool AST `(= a b)`.

proc `==`*(a, b: Z3String): Z3Bool =
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_eq(a.ctx.raw, a.raw, b.raw))

proc `!=`*(a, b: Z3String): Z3Bool =
  let eq = a == b
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_not(a.ctx.raw, eq.raw))

# ============================================================================
# Primitive ops
# ============================================================================

proc len*(a: Z3String): Z3Int =
  ## SMT `(seq.len a)`. Result is a `Z3Int` counting Unicode
  ## *codepoints* (matches the input's `.len` only for pure-ASCII
  ## literals).
  wrap[Z3Int](a.ctx, a.ctx.checkErr Z3_mk_seq_length(a.ctx.raw, a.raw))

proc concat*(xs: varargs[Z3String]): Z3String =
  ## SMT `(seq.++ x1 x2 ...)`. Requires at least one argument; for
  ## ergonomic two-arg use, see the `&` operator below.
  doAssert xs.len >= 1,
    "Z3String.concat requires at least one argument"
  if xs.len == 1:
    return xs[0]
  var raws = newSeq[RawZ3Ast](xs.len)
  for i, x in xs:
    raws[i] = x.raw
  wrap[Z3String](xs[0].ctx, xs[0].ctx.checkErr Z3_mk_seq_concat(
    xs[0].ctx.raw, cuint(raws.len),
    cast[ptr UncheckedArray[RawZ3Ast]](addr raws[0])))

proc `&`*(a, b: Z3String): Z3String {.inline.} =
  ## Two-arg concat sugar mirroring Nim's `string` concat operator.
  concat(a, b)

proc contains*(a, sub: Z3String): Z3Bool =
  ## SMT `(seq.contains a sub)`. True iff `sub` occurs as a substring
  ## of `a` (including `sub = ""` and `sub = a`).
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_seq_contains(a.ctx.raw, a.raw, sub.raw))

proc substr*(a: Z3String, offset, length: Z3Int): Z3String =
  ## SMT `(seq.extract a offset length)`. Substring of `a` starting at
  ## `offset` (0-based), `length` codepoints long. Out-of-range
  ## offsets / lengths produce the empty string per SMT-LIB semantics.
  let raw = a.ctx.checkErr Z3_mk_seq_extract(a.ctx.raw, a.raw, offset.raw, length.raw)
  wrap[Z3String](a.ctx, raw)

proc at*(a: Z3String, index: Z3Int): Z3String =
  ## SMT `(seq.at a index)`. Single-codepoint substring at `index`
  ## (still a `Z3String`, not a hypothetical `Z3Char`). Out-of-range
  ## indices yield the empty string.
  let raw = a.ctx.checkErr Z3_mk_seq_at(a.ctx.raw, a.raw, index.raw)
  wrap[Z3String](a.ctx, raw)

proc startsWith*(s, prefix: Z3String): Z3Bool =
  ## SMT `(seq.prefixof prefix s)`. Argument order matches Nim's
  ## `strutils.startsWith(s, prefix)`, not SMT-LIB's `(prefix s)`.
  wrap[Z3Bool](s.ctx, s.ctx.checkErr Z3_mk_seq_prefix(s.ctx.raw, prefix.raw, s.raw))

proc endsWith*(s, suffix: Z3String): Z3Bool =
  ## SMT `(seq.suffixof suffix s)`. Argument order matches Nim's
  ## `strutils.endsWith(s, suffix)`.
  wrap[Z3Bool](s.ctx, s.ctx.checkErr Z3_mk_seq_suffix(s.ctx.raw, suffix.raw, s.raw))

proc indexOf*(s, sub: Z3String, start: Z3Int): Z3Int =
  ## SMT `(seq.indexof s sub start)`. Returns the 0-based index of the
  ## first occurrence of `sub` in `s` starting from `start`, or `-1` if
  ## not found.
  let raw = s.ctx.checkErr Z3_mk_seq_index(s.ctx.raw, s.raw, sub.raw, start.raw)
  wrap[Z3Int](s.ctx, raw)

proc indexOf*(s, sub: Z3String): Z3Int {.inline.} =
  ## `indexOf(s, sub, mkInt(0))` — find from the start.
  indexOf(s, sub, mkInt(s.ctx, 0))

proc replace*(s, old, new: Z3String): Z3String =
  ## SMT `(seq.replace s src dst)`. Replaces the **first** occurrence
  ## of `old` in `s` with `new`. (For replace-all, the user composes
  ## via regex `replace_all` — landing in a later step if Z3 exposes
  ## it; currently a manual fold.)
  let raw = s.ctx.checkErr Z3_mk_seq_replace(s.ctx.raw, s.raw, old.raw, new.raw)
  wrap[Z3String](s.ctx, raw)

# ============================================================================
# Int interop
# ============================================================================

proc strToInt*(s: Z3String): Z3Int =
  ## SMT `(str.to.int s)`. Returns the non-negative integer the digits
  ## of `s` represent, or `-1` if `s` isn't a non-empty digit string.
  ## Z3 follows the SMT-LIB convention of leading-zero acceptance.
  wrap[Z3Int](s.ctx, s.ctx.checkErr Z3_mk_str_to_int(s.ctx.raw, s.raw))

proc intToStr*(i: Z3Int): Z3String =
  ## SMT `(str.from.int i)`. Returns the decimal representation of `i`
  ## as a string, or the empty string if `i` is negative.
  wrap[Z3String](i.ctx, i.ctx.checkErr Z3_mk_int_to_str(i.ctx.raw, i.raw))

# ============================================================================
# Nim-`string`-literal lifts
# ============================================================================
#
# Mirrors the integer-lit lifts on Z3BitVec — the user writes
# `x == "literal"` / `"prefix" & x` and the Nim string is lifted to a
# `Z3String` via `mkString` on the same context.

template liftBinString(op: untyped, ret: typedesc) =
  proc op*(a: Z3String, b: string): ret {.inline.} =
    op(a, mkString(a.ctx, b))
  proc op*(a: string, b: Z3String): ret {.inline.} =
    op(mkString(b.ctx, a), b)

liftBinString(`==`, Z3Bool)
liftBinString(`!=`, Z3Bool)
liftBinString(`&`, Z3String)
liftBinString(contains, Z3Bool)
liftBinString(startsWith, Z3Bool)
liftBinString(endsWith, Z3Bool)

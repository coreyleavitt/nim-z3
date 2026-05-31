## `z3/string` — SMT-LIB String theory.
##
## Strings in SMT-LIB are `(Seq Char)`: finite sequences of Unicode
## characters. Z3 reflects this in its C API; the wrapper makes it
## explicit at the Nim type level:
##
## ```nim
## type Z3String* = Z3Seq[Z3Char]
## ```
##
## **All the generic sequence ops** (`len`, varargs `concat`, `&`,
## `nth`, `at`, `substr`, `contains`, `startsWith` / `endsWith`,
## `indexOf`, `replace`, `==`, `!=`) live in `z3/seq` and apply to
## `Z3String` automatically through this alias. This module ships
## **only the string-specific** surface:
##
## - `mkString(s: string)` — string literal carrying the bytes of `s`,
##   built via `Z3_mk_lstring` so embedded NULs are preserved.
## - `mkStringVar(name)` — free string variable.
## - `toStr` / `evalStr` — `Z3_get_lstring`-backed model extraction.
## - `strToInt` / `intToStr` — int interop unique to strings.
## - Nim-`string`-literal lifts on `==` / `!=` / `&` / `contains` /
##   `startsWith` / `endsWith` so `x == "hello"`, `"prefix" & x`, etc.
##   Just Work for the `Z3Seq[Z3Char]` instantiation only.
##
## ## Decidability caveat
##
## Z3's string solver is **incomplete in general**. Concrete-string
## queries decide reliably; queries combining string constraints with
## arithmetic, regex membership, and free string variables may return
## `zsUnknown` or run for a long time.

import ./ffi, ./context, ./error, ./ast, ./builder, ./model, ./char, ./seq
export seq
  # Re-export so `import z3/string` users get the generic Z3Seq surface
  # for free — that's where `len`, `concat`, `nth`, etc. now live.

# ============================================================================
# Z3String — alias for Z3Seq[Z3Char]
# ============================================================================

type
  Z3String* = Z3Seq[Z3Char]
    ## SMT-LIB string = sequence of Unicode codepoints. Every generic
    ## op on `Z3Seq[E]` is available here automatically — see
    ## `z3/seq` for the full surface.

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
    raiseZ3Error(a.ctx.raw, errCode)
  if raw.isNil:
    var e = newException(Z3Error,
      "Z3String.toStr: AST `" & $Z3_ast_to_string(a.ctx.raw, a.raw) &
      "` is not a literal string.")
    e.code = Z3_INVALID_USAGE
    raise e
  var s = newString(int(length))
  if length > 0'u32:
    copyMem(addr s[0], raw, int(length))
  s

proc evalStr*(m: Z3Model, a: Z3String, modelCompletion = true): string {.inline.} =
  ## `m.eval(a, modelCompletion).toStr` in one call.
  m.eval(a, modelCompletion).toStr

# ============================================================================
# Int interop — string-specific (no generic Z3Seq equivalent)
# ============================================================================

proc strToInt*(s: Z3String): Z3Int =
  ## SMT `(str.to.int s)`. Non-negative integer the digits of `s`
  ## represent, or `-1` if `s` isn't a non-empty digit string.
  wrap[Z3Int](s.ctx, s.ctx.checkErr Z3_mk_str_to_int(s.ctx.raw, s.raw))

proc intToStr*(i: Z3Int): Z3String =
  ## SMT `(str.from.int i)`. Decimal representation of `i`; empty
  ## string for negative `i`.
  wrap[Z3String](i.ctx, i.ctx.checkErr Z3_mk_int_to_str(i.ctx.raw, i.raw))

# ============================================================================
# Nim-`string`-literal lifts — Z3String-specific (not generic to Z3Seq[E])
# ============================================================================
#
# Mirrors the integer-lit lifts on Z3BitVec. The user writes
# `x == "literal"` / `"prefix" & x` and the Nim string is lifted to a
# `Z3String` via `mkString` on the same context. These overloads are
# specific to `Z3Seq[Z3Char]` (= `Z3String`) — generic `Z3Seq[E]`
# can't lift a Nim primitive without a per-E lifter.

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

## Boolean operators on `Z3Bool` and the generic `ite` builder.
##
## ## What's exposed
##
## - Binary operators usable with the Nim spellings: `and`, `or`,
##   `xor`. Each has overloads accepting a Nim `bool` on either side
##   that auto-lift to a `Z3Bool` literal — so `p and true`, `false or
##   q`, `p xor true` all compile and produce a `Z3Bool` AST.
## - Unary `not`. No lift overload needed (no scalar form).
## - `implies(p, q)` and `iff(p, q)`. Z3-named; Nim has no infix
##   spellings for these.
## - `ite[S](cond, t, e)` — if-then-else, generic over sort: `ite(p,
##   x, y)` works whether x and y are both Int, both Bool, both Real,
##   etc. — the type system enforces same-sort branches.
## - Varargs `mkAnd(args)`, `mkOr(args)` — builder-friendly for
##   accumulated constraint lists.
## - `mkDistinct(args)` — pairwise-distinct, generic over sort.
##
## ## Auto-lift overloads
##
## `p and true` would be ambiguous if Nim's stdlib `and(bool, bool)
## bool` were the best match — Nim's overload resolution prefers
## *the more specific* match, and `and(Z3Bool, bool): Z3Bool` is the
## more specific binding when `p: Z3Bool`. The lift then calls
## `mkBool(p.ctx, true)` to construct the Z3Bool literal and recurses
## into the all-Z3Bool overload.

import ./ffi, ./context, ./error, ./ast, ./builder
export builder

# ----------------------------------------------------------------------------
# `and`
# ----------------------------------------------------------------------------

proc `and`*(a, b: Z3Bool): Z3Bool =
  var args = [a.raw, b.raw]
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_and(
    a.ctx.raw, 2.cuint,
    cast[ptr UncheckedArray[RawZ3Ast]](addr args[0])))

proc `and`*(a: Z3Bool, b: bool): Z3Bool {.inline.} = a and mkBool(a.ctx, b)
proc `and`*(a: bool, b: Z3Bool): Z3Bool {.inline.} = mkBool(b.ctx, a) and b

# ----------------------------------------------------------------------------
# `or`
# ----------------------------------------------------------------------------

proc `or`*(a, b: Z3Bool): Z3Bool =
  var args = [a.raw, b.raw]
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_or(
    a.ctx.raw, 2.cuint,
    cast[ptr UncheckedArray[RawZ3Ast]](addr args[0])))

proc `or`*(a: Z3Bool, b: bool): Z3Bool {.inline.} = a or mkBool(a.ctx, b)
proc `or`*(a: bool, b: Z3Bool): Z3Bool {.inline.} = mkBool(b.ctx, a) or b

# ----------------------------------------------------------------------------
# `not`
# ----------------------------------------------------------------------------

proc `not`*(a: Z3Bool): Z3Bool =
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_not(a.ctx.raw, a.raw))

# ----------------------------------------------------------------------------
# `xor`
# ----------------------------------------------------------------------------

proc `xor`*(a, b: Z3Bool): Z3Bool =
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_xor(a.ctx.raw, a.raw, b.raw))

proc `xor`*(a: Z3Bool, b: bool): Z3Bool {.inline.} = a xor mkBool(a.ctx, b)
proc `xor`*(a: bool, b: Z3Bool): Z3Bool {.inline.} = mkBool(b.ctx, a) xor b

# ----------------------------------------------------------------------------
# `implies` / `iff`
# ----------------------------------------------------------------------------
#
# Z3-named because Nim has no infix spellings. `iff` (logical
# biconditional) is semantically equivalent to `==` on Z3Bool — both
# produce `(= p q)`/`(<=> p q)` at the SMT level; we expose both so
# the user can choose readability per context.

proc implies*(a, b: Z3Bool): Z3Bool =
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_implies(a.ctx.raw, a.raw, b.raw))

proc implies*(a: Z3Bool, b: bool): Z3Bool {.inline.} = implies(a, mkBool(a.ctx, b))
proc implies*(a: bool, b: Z3Bool): Z3Bool {.inline.} = implies(mkBool(b.ctx, a), b)

proc iff*(a, b: Z3Bool): Z3Bool =
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_iff(a.ctx.raw, a.raw, b.raw))

proc iff*(a: Z3Bool, b: bool): Z3Bool {.inline.} = iff(a, mkBool(a.ctx, b))
proc iff*(a: bool, b: Z3Bool): Z3Bool {.inline.} = iff(mkBool(b.ctx, a), b)

# ----------------------------------------------------------------------------
# `==` literal lift for Z3Bool
# ----------------------------------------------------------------------------
#
# Same-sort `Z3Bool == Z3Bool` is the generic `==` in ast.nim. These
# overloads add the Nim-bool literal lifts so `p == true` works.

proc `==`*(a: Z3Bool, b: bool): Z3Bool {.inline.} = a == mkBool(a.ctx, b)
proc `==`*(a: bool, b: Z3Bool): Z3Bool {.inline.} = mkBool(b.ctx, a) == b
proc `!=`*(a: Z3Bool, b: bool): Z3Bool {.inline.} = a != mkBool(a.ctx, b)
proc `!=`*(a: bool, b: Z3Bool): Z3Bool {.inline.} = mkBool(b.ctx, a) != b

# ----------------------------------------------------------------------------
# If-then-else (generic over sort)
# ----------------------------------------------------------------------------

proc ite*[T: Z3Term](cond: Z3Bool, t, e: T): T =
  ## `if cond then t else e`. Both branches must have the same Z3
  ## sort — enforced statically via the shared `T` typed-AST family
  ## parameter (`Z3Int`, `Z3Real`, `Z3Bool`, `Z3BitVec[W]`,
  ## `Z3Array[K, V]`, `Z3Seq[E]`, `Z3Char`, `Z3Fp[E, S]`,
  ## `Z3DatatypeValue[T]`, etc.).
  ##
  ## v0.5.0 medium-audit B4 collapsed the per-family `ite` overloads
  ## (originally `[Z3Ast[S]]` + `[Z3BitVec[W]]`) into one generic.
  ##
  ## ```nim
  ## let r = ite(p, mkInt(1), mkInt(0))          # Z3Int
  ## let q = ite(p, mkBool(true), mkBool(false)) # Z3Bool
  ## let bv = ite(p, mkBitVec[8](1), mkBitVec[8](0))
  ## ```
  wrap[T](cond.ctx, cond.ctx.checkErr Z3_mk_ite(
    cond.ctx.raw, cond.raw, t.raw, e.raw))

# ----------------------------------------------------------------------------
# Varargs and/or
# ----------------------------------------------------------------------------

# `mkAnd` — N-ary conjunction. Empty input returns `mkTrue()`
# (identity). One input returns the singleton unchanged. Otherwise
# builds an n-ary `(and ...)` AST.
#
# ```nim
# let constraints = @[x > mkInt(0), y > mkInt(0), x + y < mkInt(100)]
# let composite = mkAnd(constraints)
# ```
emitVarargsMonoid(mkAnd, Z3_mk_and, mkTrue)

# `mkOr` — N-ary disjunction. Empty input returns `mkFalse()`
# (identity).
emitVarargsMonoid(mkOr, Z3_mk_or, mkFalse)

# ----------------------------------------------------------------------------
# `distinct` — pairwise-distinct, generic over sort
# ----------------------------------------------------------------------------

proc mkDistinct*[T: Z3Term](xs: varargs[T]): Z3Bool =
  ## `(distinct x_1 ... x_n)` — true iff every pair `(x_i, x_j)` with
  ## `i != j` is unequal. Generic across every typed-AST family
  ## (`Z3Int`, `Z3Real`, `Z3Bool`, `Z3BitVec[W]`, `Z3Seq[E]`,
  ## `Z3Array[K, V]`, `Z3Char`, `Z3Fp[E, S]`, …). `varargs[T]`
  ## enforces same-T (hence same-sort) inputs; cross-sort
  ## `mkDistinct(intAst, boolAst)` is a compile error.
  ##
  ## Empty / singleton inputs are trivially true (returns `mkTrue`).
  ##
  ## v0.5.0 medium-audit B5 collapsed the per-family
  ## `emitVarargsDistinctS` + `emitVarargsDistinctW` templates into
  ## this single generic; Z3Seq / Z3Array / Z3Fp / Z3Char / etc.
  ## inherit `mkDistinct` automatically.
  if xs.len <= 1:
    let ctx = if xs.len == 1: xs[0].ctx else: requireCurrentContext()
    return wrap[Z3Bool](ctx, ctx.checkErr Z3_mk_true(ctx.raw))
  let ctx = xs[0].ctx
  var raws = newSeq[RawZ3Ast](xs.len)
  for i, x in xs:
    raws[i] = x.raw
  wrap[Z3Bool](ctx, naryFFICall(ctx, raws, Z3_mk_distinct))

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

import ./ffi, ./context, ./sort, ./ast, ./builder
export builder

# ----------------------------------------------------------------------------
# `and`
# ----------------------------------------------------------------------------

proc `and`*(a, b: Z3Bool): Z3Bool =
  var args = [a.raw, b.raw]
  wrap[stBool](a.ctx, a.ctx.checkErr Z3_mk_and(
    a.ctx.raw, 2.cuint,
    cast[ptr UncheckedArray[RawZ3Ast]](addr args[0])))

proc `and`*(a: Z3Bool, b: bool): Z3Bool {.inline.} = a and mkBool(a.ctx, b)
proc `and`*(a: bool, b: Z3Bool): Z3Bool {.inline.} = mkBool(b.ctx, a) and b

# ----------------------------------------------------------------------------
# `or`
# ----------------------------------------------------------------------------

proc `or`*(a, b: Z3Bool): Z3Bool =
  var args = [a.raw, b.raw]
  wrap[stBool](a.ctx, a.ctx.checkErr Z3_mk_or(
    a.ctx.raw, 2.cuint,
    cast[ptr UncheckedArray[RawZ3Ast]](addr args[0])))

proc `or`*(a: Z3Bool, b: bool): Z3Bool {.inline.} = a or mkBool(a.ctx, b)
proc `or`*(a: bool, b: Z3Bool): Z3Bool {.inline.} = mkBool(b.ctx, a) or b

# ----------------------------------------------------------------------------
# `not`
# ----------------------------------------------------------------------------

proc `not`*(a: Z3Bool): Z3Bool =
  wrap[stBool](a.ctx, a.ctx.checkErr Z3_mk_not(a.ctx.raw, a.raw))

# ----------------------------------------------------------------------------
# `xor`
# ----------------------------------------------------------------------------

proc `xor`*(a, b: Z3Bool): Z3Bool =
  wrap[stBool](a.ctx, a.ctx.checkErr Z3_mk_xor(a.ctx.raw, a.raw, b.raw))

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
  wrap[stBool](a.ctx, a.ctx.checkErr Z3_mk_implies(a.ctx.raw, a.raw, b.raw))

proc implies*(a: Z3Bool, b: bool): Z3Bool {.inline.} = implies(a, mkBool(a.ctx, b))
proc implies*(a: bool, b: Z3Bool): Z3Bool {.inline.} = implies(mkBool(b.ctx, a), b)

proc iff*(a, b: Z3Bool): Z3Bool =
  wrap[stBool](a.ctx, a.ctx.checkErr Z3_mk_iff(a.ctx.raw, a.raw, b.raw))

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

proc ite*[S: static SortTag](cond: Z3Bool, t, e: Z3Ast[S]): Z3Ast[S] =
  ## `if cond then t else e`. Both branches must have the same sort
  ## (enforced by the phantom-type parameter).
  ##
  ## ```nim
  ## let r = ite(p, mkInt(1), mkInt(0))          # Z3Int
  ## let q = ite(p, mkBool(true), mkBool(false)) # Z3Bool
  ## ```
  wrap[S](cond.ctx, cond.ctx.checkErr Z3_mk_ite(
    cond.ctx.raw, cond.raw, t.raw, e.raw))

# ----------------------------------------------------------------------------
# Varargs and/or
# ----------------------------------------------------------------------------

proc mkAnd*(args: varargs[Z3Bool]): Z3Bool =
  ## N-ary conjunction. Empty input returns `mkTrue()` (identity).
  ## One input returns the singleton unchanged. Otherwise builds an
  ## n-ary `(and ...)` AST.
  ##
  ## ```nim
  ## let constraints = @[x > mkInt(0), y > mkInt(0), x + y < mkInt(100)]
  ## let composite = mkAnd(constraints)
  ## ```
  if args.len == 0:
    return mkTrue(requireCurrentContext())
  if args.len == 1:
    return args[0]
  let ctx = args[0].ctx
  var raws = newSeq[RawZ3Ast](args.len)
  for i, a in args:
    raws[i] = a.raw
  wrap[stBool](ctx, ctx.checkErr Z3_mk_and(
    ctx.raw, cuint(args.len),
    cast[ptr UncheckedArray[RawZ3Ast]](addr raws[0])))

proc mkOr*(args: varargs[Z3Bool]): Z3Bool =
  ## N-ary disjunction. Empty input returns `mkFalse()` (identity).
  if args.len == 0:
    return mkFalse(requireCurrentContext())
  if args.len == 1:
    return args[0]
  let ctx = args[0].ctx
  var raws = newSeq[RawZ3Ast](args.len)
  for i, a in args:
    raws[i] = a.raw
  wrap[stBool](ctx, ctx.checkErr Z3_mk_or(
    ctx.raw, cuint(args.len),
    cast[ptr UncheckedArray[RawZ3Ast]](addr raws[0])))

# ----------------------------------------------------------------------------
# `distinct` — pairwise-distinct, generic over sort
# ----------------------------------------------------------------------------

proc mkDistinct*[S: static SortTag](args: varargs[Z3Ast[S]]): Z3Bool =
  ## Pairwise-distinct constraint: `mkDistinct(a, b, c)` is true iff
  ## `a != b && b != c && a != c`. Cheaper at the SMT level than the
  ## equivalent quadratic conjunction of `!=` because Z3 has a
  ## dedicated rewrite for this term.
  ##
  ## Generic over sort — works on `Z3Int`, `Z3Real`, `Z3Bool`, etc.
  if args.len <= 1:
    # `distinct` over fewer than 2 args is vacuously true.
    return mkTrue(requireCurrentContext())
  let ctx = args[0].ctx
  var raws = newSeq[RawZ3Ast](args.len)
  for i, a in args:
    raws[i] = a.raw
  wrap[stBool](ctx, ctx.checkErr Z3_mk_distinct(
    ctx.raw, cuint(args.len),
    cast[ptr UncheckedArray[RawZ3Ast]](addr raws[0])))

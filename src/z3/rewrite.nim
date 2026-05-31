## `z3/rewrite` — term rewriting.
##
## Two C entry points:
##
## - **`Z3_substitute`** — by-term substitution. Each `(from, to)` pair
##   replaces matching subterms of `a` with `to`. Multiple pairs can
##   target different sorts simultaneously; Z3 dispatches by structural
##   match.
##
## - **`Z3_substitute_vars`** — de-Bruijn-indexed substitution. The
##   `replacements[i]` argument replaces the `i`-th bound variable in
##   `a` counted from innermost. Used for quantifier-body rewriting.
##
## ## Sort safety
##
## `substitute` and `substituteVars` both take `Z3AnyAst` for the
## replacement terms because pairs across a single call may target
## different sorts — Z3 dispatches dynamically. The wrapper's typed
## return is preserved (`substitute[T: Z3Term](a: T, ...): T`) so
## callers don't lose the AST's typed family when the rewrite
## doesn't change its sort, but each individual replacement IS
## untyped at the call site. Use `toAnyAst[T: Z3Term]` to lift typed
## values for the general-form `substitute(a, openArray[(Z3AnyAst,
## Z3AnyAst)])`. The single-pair convenience handles the conversion
## automatically.

import ./ffi, ./context, ./error, ./ast, ./introspect

# ============================================================================
# substitute — by-term substitution
# ============================================================================

proc substitute*[T: Z3Term](
    a: T,
    replacements: openArray[(Z3AnyAst, Z3AnyAst)]): T =
  ## Replace each `from` subterm by the matching `to` term. Multi-pair
  ## form for when a single call needs to rewrite multiple sorts at
  ## once.
  ##
  ## ```nim
  ## let result = substitute(expr,
  ##   [(toAnyAst(x), toAnyAst(mkInt(3))),
  ##    (toAnyAst(p), toAnyAst(mkBool(true)))])
  ## ```
  if replacements.len == 0:
    return wrap[T](a.ctx, a.raw)
  var fromArr = newSeq[RawZ3Ast](replacements.len)
  var toArr = newSeq[RawZ3Ast](replacements.len)
  for i, (f, t) in replacements:
    fromArr[i] = f.raw
    toArr[i] = t.raw
  let raw = a.ctx.checkErr Z3_substitute(a.ctx.raw, a.raw,
    cuint(replacements.len),
    cast[ptr UncheckedArray[RawZ3Ast]](addr fromArr[0]),
    cast[ptr UncheckedArray[RawZ3Ast]](addr toArr[0]))
  wrap[T](a.ctx, raw)

proc substitute*[T, F, To: Z3Term](a: T, fromTerm: F, toTerm: To): T =
  ## Single-pair convenience — the common case. Auto-lifts the
  ## typed `from` / `to` to `Z3AnyAst`.
  ##
  ## ```nim
  ## let result = substitute(x + y, x, mkInt(3))
  ## ```
  substitute(a, [(toAnyAst(fromTerm), toAnyAst(toTerm))])

# ============================================================================
# substituteVars — de-Bruijn-indexed bound-variable substitution
# ============================================================================

proc substituteVars*[T: Z3Term](
    a: T, replacements: openArray[Z3AnyAst]): T =
  ## Replace de-Bruijn-indexed bound variables. `replacements[i]`
  ## replaces the `i`-th bound variable in `a` counted from innermost
  ## (the same convention Z3 itself uses). Typically used to
  ## instantiate a quantifier body with concrete terms.
  ##
  ## ```nim
  ## # body : p(bound 0)
  ## let instantiated = substituteVars(body, [toAnyAst(mkInt(5))])
  ## # instantiated : p(5)
  ## ```
  if replacements.len == 0:
    return wrap[T](a.ctx, a.raw)
  var toArr = newSeq[RawZ3Ast](replacements.len)
  for i, r in replacements:
    toArr[i] = r.raw
  let raw = a.ctx.checkErr Z3_substitute_vars(a.ctx.raw, a.raw,
    cuint(replacements.len),
    cast[ptr UncheckedArray[RawZ3Ast]](addr toArr[0]))
  wrap[T](a.ctx, raw)

# ============================================================================
# mkBound — typed bound-variable constructor
# ============================================================================

proc mkBound*(ctx: Z3Context, index: int, sort: RawZ3Sort): Z3AnyAst =
  ## Construct a de-Bruijn-indexed bound variable. The result is a
  ## `Z3AnyAst` because the sort is supplied at runtime; users with a
  ## known sort can lift via `asZ3Int` / `asZ3Bool` / etc.
  ##
  ## This is the constructor used for manually building quantifier
  ## bodies; required to test `substituteVars` and useful for any
  ## user doing quantifier-body programming.
  doAssert index >= 0
  let raw = ctx.checkErr Z3_mk_bound(ctx.raw, cuint(index), sort)
  wrap[Z3AnyAst](ctx, raw)

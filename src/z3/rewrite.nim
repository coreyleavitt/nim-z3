## `z3/rewrite` — term rewriting.
##
## Three C entry points:
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
## - **`Z3_substitute_funs`** — function-application substitution. Each
##   application of `fromFuncs[i]` in `a` is replaced by `toExprs[i]`,
##   which may contain de-Bruijn free variables (index 0 = first argument
##   of the replaced function, index 1 = second argument, etc.).
##
## Fresh-name constructors (typed wrappers over `Z3_mk_fresh_const` and
## `Z3_mk_fresh_func_decl`) also live here because they parallel the
## rewriting surface (generate structurally-distinct terms for safe
## substitution targets).
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
##
## `substituteFuns` takes `openArray[RawZ3FuncDecl]` for the from-side
## (unwrapped from `Z3FuncDecl[ArgsTup, Ret]` via `.raw`) and
## `openArray[Z3AnyAst]` for the to-side (sort-erased because the
## replacement expressions may not share the overall AST's sort).
## The typed return is preserved by the same phantom-preserving
## `wrap[T]` trick.

import ./ffi, ./context, ./error, ./ast, ./introspect, ./sortdispatch

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

# ============================================================================
# substituteFuns — function-application substitution (N9.4)
# ============================================================================

proc substituteFuns*[T: Z3Term](
    a: T,
    fromFuncs: openArray[RawZ3FuncDecl],
    toExprs: openArray[Z3AnyAst]): T =
  ## Replace function applications in `a`. Each application of
  ## `fromFuncs[i]` is replaced by `toExprs[i]`, which may contain
  ## de-Bruijn free variables: index 0 refers to the first argument of
  ## the replaced function, index 1 to the second argument, etc.
  ##
  ## `fromFuncs` and `toExprs` must have equal length.
  ##
  ## ```nim
  ## # Replace f-applications with g-applications:
  ## let intSort = sortOf(Z3Int, ctx)
  ## let bound0  = asZ3Int(mkBound(ctx, 0, intSort))
  ## let result  = substituteFuns(expr, @[f.raw], @[toAnyAst(g(bound0))])
  ## ```
  doAssert fromFuncs.len == toExprs.len,
    "substituteFuns: fromFuncs and toExprs must have the same length"
  if fromFuncs.len == 0:
    return wrap[T](a.ctx, a.raw)
  var fromArr = newSeq[RawZ3FuncDecl](fromFuncs.len)
  var toArr   = newSeq[RawZ3Ast](toExprs.len)
  for i in 0 ..< fromFuncs.len:
    fromArr[i] = fromFuncs[i]
    toArr[i]   = toExprs[i].raw
  let raw = a.ctx.checkErr Z3_substitute_funs(a.ctx.raw, a.raw,
    cuint(fromArr.len),
    cast[ptr UncheckedArray[RawZ3FuncDecl]](addr fromArr[0]),
    cast[ptr UncheckedArray[RawZ3Ast]](addr toArr[0]))
  wrap[T](a.ctx, raw)

# ============================================================================
# freshConst — typed fresh constant (N9.4)
# ============================================================================

proc freshConst*[T: Z3Term](ctx: Z3Context, prefix: string): T =
  ## Create a fresh constant of the sort corresponding to `T`, with a
  ## unique name derived from `prefix`. Unlike `mkIntVar` / `mkBoolVar` /
  ## etc., two calls with the same `prefix` produce structurally distinct
  ## constants — safe to use where name-collision would cause Z3 to treat
  ## them as the same term.
  ##
  ## ```nim
  ## let x = freshConst[Z3Int](ctx, "x")
  ## let y = freshConst[Z3Int](ctx, "x")   # distinct from x
  ## ```
  let sort = sortOfType[T](ctx)
  let raw = ctx.checkErr Z3_mk_fresh_const(ctx.raw, prefix.cstring, sort)
  wrap[T](ctx, raw)

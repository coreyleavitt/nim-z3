## `forall` / `exists` quantifier surface with optional pattern triggers.
##
## ## Phantom design
##
## Bound variables can be any typed AST family — `Z3Int`, `Z3Real`,
## `Z3Bool`, `Z3BitVec[W]`, `Z3DatatypeValue[T]`, etc. Each must be a
## free constant (built via `mkIntVar`, `mkBitVecVar`, `mkDatatypeVar`,
## …); `Z3_mk_forall_const` re-binds these constants as bound vars
## within the quantifier scope.
##
## Per-arity templates cover 1–5 bound variables, mirroring the same
## technique step 4 used for constructor `apply`. Heterogeneous-sort
## quantifiers (`forall(x: Int, p: Bool, …)`) work for free because
## each generic position binds independently.
##
## v0.2 plan §7 Q2 suggested a `Z3BoundVar` typeclass with
## `mkBoundVar[S]()`. We diverged: the only thing `forall_const`
## needs from each bound var is `.raw`, so the per-arity-template
## approach is simpler and stays consistent with the rest of the
## library's "build-by-arity" pattern.
##
## ## Patterns — instantiation triggers
##
## A quantifier without good patterns is the most common cause of "my
## SMT problem ran forever." Z3 only instantiates a quantified body
## when it finds ground terms in the context matching the patterns;
## without patterns Z3 picks heuristically, often picking poorly.
## `forall`/`exists` accept an optional `patterns: openArray[Z3Pattern]`
## last argument exactly to make the choice visible.
##
## A pattern is a *conjunction* of trigger terms; supply multiple
## patterns (each itself a pattern object) to encode disjunction.
##
## ## What's not here
##
## `Z3BoundVar`-style explicit boxing helpers — see the §7 Q2
## divergence above.

import ./ffi, ./context, ./sort, ./ast

# ============================================================================
# Z3Pattern — refcount-managed quantifier trigger
# ============================================================================

type
  Z3Pattern* = object
    raw*: RawZ3Pattern
    ctx*: Z3Context

proc decRefPattern(ctx: Z3Context, raw: RawZ3Pattern) {.raises: [].} =
  try:
    if not raw.isNil and ctx != nil and not ctx.raw.isNil:
      let asAst = Z3_pattern_to_ast(ctx.raw, raw)
      Z3_dec_ref(ctx.raw, asAst)
  except CatchableError:
    discard

proc incRefPattern(ctx: Z3Context, raw: RawZ3Pattern) {.raises: [].} =
  try:
    if not raw.isNil and ctx != nil and not ctx.raw.isNil:
      let asAst = Z3_pattern_to_ast(ctx.raw, raw)
      Z3_inc_ref(ctx.raw, asAst)
  except CatchableError:
    discard

proc `=destroy`(p: Z3Pattern) {.raises: [].} =
  decRefPattern(p.ctx, p.raw)

proc `=copy`(dst: var Z3Pattern, src: Z3Pattern) {.raises: [].} =
  if dst.raw != src.raw:
    decRefPattern(dst.ctx, dst.raw)
    dst.raw = src.raw
    dst.ctx = src.ctx
    incRefPattern(dst.ctx, dst.raw)

proc `=dup`(src: Z3Pattern): Z3Pattern {.raises: [].} =
  result.raw = src.raw
  result.ctx = src.ctx
  incRefPattern(result.ctx, result.raw)

# ============================================================================
# mkPattern — per-arity construction
# ============================================================================

proc mkPatternImpl(ctx: Z3Context,
                   terms: openArray[RawZ3Ast]): Z3Pattern =
  let termsPtr =
    if terms.len > 0:
      cast[ptr UncheckedArray[RawZ3Ast]](unsafeAddr terms[0])
    else: nil
  let raw = ctx.checkErr Z3_mk_pattern(ctx.raw, cuint(terms.len), termsPtr)
  result.raw = raw
  result.ctx = ctx
  incRefPattern(ctx, raw)

template mkPattern*(t1: typed): Z3Pattern =
  ## Build a single-trigger pattern.
  ##
  ## ```nim
  ## let p = mkPattern(selectExpr)
  ## let q = forall(x, body, patterns = [p])
  ## ```
  ##
  ## **Z3 constraint**: each trigger term must contain at least one
  ## function application — bare variables are rejected. Common valid
  ## triggers: arithmetic ops (`x + 1`), array reads (`select(a, i)`),
  ## datatype constructor / accessor calls (`head(l)`). Building a
  ## pattern with only a variable raises `Z3Error`.
  mkPatternImpl(t1.ctx, [t1.raw])

template mkPattern*(t1, t2: typed): Z3Pattern =
  ## Multi-trigger pattern: both terms must match for Z3 to instantiate.
  mkPatternImpl(t1.ctx, [t1.raw, t2.raw])

template mkPattern*(t1, t2, t3: typed): Z3Pattern =
  mkPatternImpl(t1.ctx, [t1.raw, t2.raw, t3.raw])

template mkPattern*(t1, t2, t3, t4: typed): Z3Pattern =
  mkPatternImpl(t1.ctx, [t1.raw, t2.raw, t3.raw, t4.raw])

template mkPattern*(t1, t2, t3, t4, t5: typed): Z3Pattern =
  mkPatternImpl(t1.ctx, [t1.raw, t2.raw, t3.raw, t4.raw, t5.raw])

# ============================================================================
# forall / exists impl + per-arity templates
# ============================================================================

proc patternsToRaw(patterns: openArray[Z3Pattern]): seq[RawZ3Pattern] =
  result = newSeq[RawZ3Pattern](patterns.len)
  for i, p in patterns:
    result[i] = p.raw

proc quantifierImpl(ctx: Z3Context, isForall: bool,
                    bound: openArray[RawZ3Ast],
                    body: RawZ3Ast,
                    patterns: openArray[Z3Pattern]): Z3Bool =
  ## Shared core for forall / exists. Converts bound `RawZ3Ast` constants
  ## to `RawZ3App` (`Z3_mk_forall_const` requires the App form), threads
  ## the optional patterns through, and wraps the resulting body as
  ## `Z3Bool`.
  var bounds = newSeq[RawZ3App](bound.len)
  for i, b in bound:
    bounds[i] = Z3_to_app(ctx.raw, b)
  let boundsPtr =
    if bounds.len > 0:
      cast[ptr UncheckedArray[RawZ3App]](addr bounds[0])
    else: nil

  var rawPatterns = patternsToRaw(patterns)
  let patternsPtr =
    if rawPatterns.len > 0:
      cast[ptr UncheckedArray[RawZ3Pattern]](addr rawPatterns[0])
    else: nil

  let raw =
    if isForall:
      ctx.checkErr Z3_mk_forall_const(ctx.raw, 0, cuint(bounds.len),
        boundsPtr, cuint(rawPatterns.len), patternsPtr, body)
    else:
      ctx.checkErr Z3_mk_exists_const(ctx.raw, 0, cuint(bounds.len),
        boundsPtr, cuint(rawPatterns.len), patternsPtr, body)
  wrap[Z3Bool](ctx, raw)

template forall*[B1](b1: B1, body: Z3Bool,
                     patterns: openArray[Z3Pattern] = []): Z3Bool =
  ## Universal quantifier with one bound variable. The bound variable
  ## must be a free constant (`mkIntVar(...)`, `mkBitVecVar[W](...)`,
  ## `mkDatatypeVar(...)`); Z3 re-binds it as a bound variable inside
  ## `body`.
  ##
  ## Pass `patterns = [mkPattern(...)]` to control instantiation —
  ## without patterns Z3 picks heuristically, often poorly. Skipping
  ## patterns is fine for simple arithmetic; supply them for anything
  ## involving uninterpreted functions, arrays, or datatypes.
  quantifierImpl(body.ctx, true, [b1.raw], body.raw, patterns)

template forall*[B1, B2](b1: B1, b2: B2, body: Z3Bool,
                         patterns: openArray[Z3Pattern] = []): Z3Bool =
  quantifierImpl(body.ctx, true, [b1.raw, b2.raw], body.raw, patterns)

template forall*[B1, B2, B3](b1: B1, b2: B2, b3: B3, body: Z3Bool,
                             patterns: openArray[Z3Pattern] = []): Z3Bool =
  quantifierImpl(body.ctx, true, [b1.raw, b2.raw, b3.raw], body.raw, patterns)

template forall*[B1, B2, B3, B4](b1: B1, b2: B2, b3: B3, b4: B4,
                                 body: Z3Bool,
                                 patterns: openArray[Z3Pattern] = []): Z3Bool =
  quantifierImpl(body.ctx, true, [b1.raw, b2.raw, b3.raw, b4.raw],
                 body.raw, patterns)

template forall*[B1, B2, B3, B4, B5](
    b1: B1, b2: B2, b3: B3, b4: B4, b5: B5, body: Z3Bool,
    patterns: openArray[Z3Pattern] = []): Z3Bool =
  quantifierImpl(body.ctx, true,
    [b1.raw, b2.raw, b3.raw, b4.raw, b5.raw], body.raw, patterns)

template exists*[B1](b1: B1, body: Z3Bool,
                     patterns: openArray[Z3Pattern] = []): Z3Bool =
  ## Existential quantifier with one bound variable. Same shape as
  ## `forall` — see that proc's docstring for the pattern story.
  quantifierImpl(body.ctx, false, [b1.raw], body.raw, patterns)

template exists*[B1, B2](b1: B1, b2: B2, body: Z3Bool,
                         patterns: openArray[Z3Pattern] = []): Z3Bool =
  quantifierImpl(body.ctx, false, [b1.raw, b2.raw], body.raw, patterns)

template exists*[B1, B2, B3](b1: B1, b2: B2, b3: B3, body: Z3Bool,
                             patterns: openArray[Z3Pattern] = []): Z3Bool =
  quantifierImpl(body.ctx, false, [b1.raw, b2.raw, b3.raw], body.raw, patterns)

template exists*[B1, B2, B3, B4](b1: B1, b2: B2, b3: B3, b4: B4,
                                 body: Z3Bool,
                                 patterns: openArray[Z3Pattern] = []): Z3Bool =
  quantifierImpl(body.ctx, false, [b1.raw, b2.raw, b3.raw, b4.raw],
                 body.raw, patterns)

template exists*[B1, B2, B3, B4, B5](
    b1: B1, b2: B2, b3: B3, b4: B4, b5: B5, body: Z3Bool,
    patterns: openArray[Z3Pattern] = []): Z3Bool =
  quantifierImpl(body.ctx, false,
    [b1.raw, b2.raw, b3.raw, b4.raw, b5.raw], body.raw, patterns)

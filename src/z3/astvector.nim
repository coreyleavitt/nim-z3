## `z3/astvector` — typed ref-handle for Z3's `Z3_ast_vector` C type.
##
## A `Z3AstVector` is a heterogeneous-sort sequence of AST handles
## managed by Z3. The most common way to encounter one is as a return
## value from solver / parser operations that produce multiple ASTs
## without knowing their typed family up front:
##
## - `Z3Solver.getUnsatCore` — returns a vector of `Z3Bool` tracker
##   propositions
## - `Z3Solver.getConsequences` — returns a vector of implied
##   `Z3Bool` literals
## - `Z3ParserContext.parseFromString` — returns a vector of parsed
##   assertions
##
## The vector itself is sort-agnostic: you can put a `Z3Int` next to a
## `Z3Bool` and Z3 won't complain. The wrapper preserves that — `add`
## is generic over `Z3Term`, indexed access returns `RawZ3Ast` because
## the typed family isn't compile-time known.
##
## ## Typed extraction
##
## `toSeq[T: Z3Term](v): seq[T]` converts to a typed sequence using
## the unified `wrap[T]` template. The user is responsible for
## asserting the right element type — the conversion does no runtime
## sort check. For paranoid callers, `getSortKind` verifies each
## element before extraction:
##
## ```nim
## for raw in v:
##   doAssert getSortKind(Z3_get_sort(ctx.raw, raw)) == skBool
## let cores = v.toSeq[Z3Bool]
## ```
##
## ## Refcount discipline
##
## `Z3_ast_vector_push` inc_refs the pushed AST internally; the
## wrapper does not double-inc_ref. The vector's `=destroy` dec_refs
## the vector itself, which releases all element refs in one shot.
## `toSeq[T]` extracts raws and calls `wrap[T](ctx, raw)` — each
## output element holds an independent ref surviving the vector's
## destruction.

import ./ffi, ./context, ./error, ./ast

# ============================================================================
# Z3AstVector — typed ref-handle
# ============================================================================

type
  Z3AstVectorOwn = object
    raw: RawZ3AstVector
    ctx: Z3Context
    borrowed: bool
      ## When true, Z3 owns this vector and frees it at `Z3_del_context`;
      ## our `=destroy` must skip the `Z3_ast_vector_dec_ref` (see
      ## `wrapAstVectorBorrowed`). Mirrors `Z3ContextOwn.borrowed`.
  Z3AstVector* = ref Z3AstVectorOwn

emitRefcountLifecycle(Z3AstVectorOwn, Z3_ast_vector_dec_ref)

proc wrapAstVector*(ctx: Z3Context, raw: RawZ3AstVector): Z3AstVector =
  ## Adopt a freshly-returned raw vector handle. Public so sibling
  ## modules (`z3/solver` for `getUnsatCore` / `getConsequences`,
  ## `z3/io` for `Z3ParserContext.parseFromString`) can wrap vectors
  ## obtained from their own FFI paths. Parallel to `wrapModel` /
  ## `wrapSolver` from prior steps. Raises `Z3Error` if `raw` is nil.
  if raw.isNil:
    var e = newException(Z3InvalidUsageError, "Z3 returned a nil ast-vector handle.")
    e.code = Z3_INVALID_USAGE
    raise e
  Z3_ast_vector_inc_ref(ctx.raw, raw)
  Z3AstVector(raw: raw, ctx: ctx)

proc wrapAstVectorBorrowed*(ctx: Z3Context, raw: RawZ3AstVector): Z3AstVector =
  ## Wrap a vector whose lifetime Z3 secretly couples to the originating
  ## context/model: Z3 registers it in the context's managed-object list
  ## AND retains an internal (non-refcounted) alias to it, then frees it
  ## itself at `Z3_del_context`. Such a vector must **not** be released
  ## by us — dec_ref'ing it to zero frees the block while Z3's alias and
  ## `~context()` still point at it → use-after-free (valgrind
  ## Invalid-read; reproduced on Z3 4.13.4 AND 4.15.0).
  ##
  ## So, unlike `wrapAstVector`, this issues **no** `inc_ref` (we borrow
  ## the context's ref) and marks the handle `borrowed` so its `=destroy`
  ## issues **no** `dec_ref`. It still holds — and releases — the `ctx`
  ## ARC ref, so the owning context (and hence this vector) stays alive
  ## for at least as long as the handle. The one net leaked Z3-side ref
  ## is reclaimed deterministically when `Z3_del_context` runs.
  ##
  ## Sole current use: `model.sortUniverse`
  ## (`Z3_model_get_sort_universe`). See ADR-FC-0012 / slice D3.
  if raw.isNil:
    var e = newException(Z3InvalidUsageError, "Z3 returned a nil ast-vector handle.")
    e.code = Z3_INVALID_USAGE
    raise e
  Z3AstVector(raw: raw, ctx: ctx, borrowed: true)

proc newAstVector*(ctx: Z3Context): Z3AstVector =
  ## Fresh empty vector bound to `ctx`.
  wrapAstVector(ctx, ctx.checkErr Z3_mk_ast_vector(ctx.raw))

proc newAstVector*(): Z3AstVector =
  ## Fresh empty vector bound to the current context. Raises `Z3Error`
  ## with `Z3_INVALID_USAGE` if no current context is set.
  newAstVector(requireCurrentContext())

proc raw*(v: Z3AstVector): RawZ3AstVector {.inline.} = v.raw
proc ctx*(v: Z3AstVector): Z3Context {.inline.} = v.ctx
  ## Underlying-handle accessors — used by sibling modules that need
  ## to thread the raw handle into Z3 calls beyond what this module
  ## wraps directly.

# ============================================================================
# Length + indexed access
# ============================================================================

proc len*(v: Z3AstVector): int {.inline.} =
  ## Element count. SMT `(ast-vector-size v)`.
  int(Z3_ast_vector_size(v.ctx.raw, v.raw))

proc `[]`*(v: Z3AstVector, i: int): RawZ3Ast =
  ## Raw AST handle at index `i`. The wrapper returns the raw because
  ## the vector is heterogeneous — typed family isn't compile-time
  ## known. For typed access, use `toSeq[T]` for whole-vector
  ## conversion, or pair this with `getSortKind` for per-element
  ## runtime dispatch.
  doAssert i >= 0 and i < v.len,
    "Z3AstVector[]: index " & $i & " out of bounds [0, " & $v.len & ")"
  v.ctx.checkErr Z3_ast_vector_get(v.ctx.raw, v.raw, cuint(i))

proc `[]=`*[T: Z3Term](v: Z3AstVector, i: int, x: T) =
  ## Replace the entry at `i` with `x.raw`. Generic over any typed
  ## family.
  doAssert i >= 0 and i < v.len,
    "Z3AstVector[]=: index " & $i & " out of bounds [0, " & $v.len & ")"
  v.ctx.checkErrVoid Z3_ast_vector_set(v.ctx.raw, v.raw, cuint(i), x.raw)

# ============================================================================
# Mutation
# ============================================================================

proc add*[T: Z3Term](v: Z3AstVector, x: T) =
  ## Append `x`. Z3 internally inc_refs the pushed AST; the wrapper
  ## does NOT inc_ref a second time (would be a leak). The vector's
  ## `=destroy` releases all element refs in one shot.
  v.ctx.checkErrVoid Z3_ast_vector_push(v.ctx.raw, v.raw, x.raw)

proc resize*(v: Z3AstVector, n: int) =
  ## Resize to `n` elements. Growing inserts nil-AST entries that the
  ## caller is responsible for populating before reading; shrinking
  ## releases trailing entries.
  doAssert n >= 0, "Z3AstVector.resize: negative length " & $n
  v.ctx.checkErrVoid Z3_ast_vector_resize(v.ctx.raw, v.raw, cuint(n))

# ============================================================================
# Iteration
# ============================================================================

iterator items*(v: Z3AstVector): RawZ3Ast =
  ## Yield each raw AST in order. Use `toSeq[T]` for typed conversion.
  let n = v.len
  for i in 0 ..< n:
    yield v[i]

iterator pairs*(v: Z3AstVector): (int, RawZ3Ast) =
  ## Yield `(index, raw)` pairs in order.
  let n = v.len
  for i in 0 ..< n:
    yield (i, v[i])

# ============================================================================
# Typed conversion
# ============================================================================

proc toSeq*[T: Z3Term](v: Z3AstVector, _: typedesc[T]): seq[T] =
  ## Materialise the vector as a typed sequence via the unified
  ## `wrap[T]` template. The caller asserts the right element type —
  ## the conversion does no runtime sort check. Use `getSortKind` per
  ## element for paranoid verification when the element sort isn't
  ## compile-time known.
  ##
  ## Each output element holds an independent inc_ref, so the seq
  ## survives the vector's destruction.
  ##
  ## ```nim
  ## let cores = solver.getUnsatCore()  # returns Z3AstVector
  ## let bools = cores.toSeq(Z3Bool)    # typed Z3Bool sequence
  ## ```
  result = newSeq[T](v.len)
  for i, raw in v:
    result[i] = wrap[T](v.ctx, raw)

# ============================================================================
# Cross-context transfer
# ============================================================================

proc translate*(v: Z3AstVector, target: Z3Context): Z3AstVector =
  ## Transfer every AST in `v` from its owning context into `target`.
  ## Returns a fresh vector owned by `target`; the source vector is
  ## not modified.
  ##
  ## Raises `Z3Error` if `target` can't accept the ASTs — most commonly
  ## because the two contexts were configured with incompatible parameters.
  wrapAstVector(target,
    target.checkErr Z3_ast_vector_translate(v.ctx.raw, v.raw, target.raw))

# ============================================================================
# Pretty-print
# ============================================================================

proc `$`*(v: Z3AstVector): string =
  ## SMT-LIB rendering. Z3 returns a parenthesised list of the
  ## vector's elements.
  $Z3_ast_vector_to_string(v.ctx.raw, v.raw)


## `Z3Set[E]` — phantom-typed SMT set theory over `Z3Array[E, Z3Bool]`.
##
## ## Design
##
## `Z3Set[E] = distinct Z3Array[E, Z3Bool]` enforces set-vs-array
## semantic distinction at the type level while re-using the array
## module's sort dispatch and lifecycle machinery. The `distinct`
## barrier means:
##
##   - Array ops (`store`, `select`, `mkConstArray`) are not available
##     directly on `Z3Set` — callers go through `toArray` for raw
##     access.
##   - Set ops (`add`, `del`, `member`, `union`, `intersect`, …) are
##     available only on `Z3Set`.
##   - Casting between the two representations is zero-cost via
##     `toArray` / `toSet`.
##
## ## Lifecycle
##
## Nim's `distinct` does **not** propagate `=destroy` / `=copy` /
## `=dup` from the base type. Without explicit delegation, every copy
## of a `Z3Set[E]` silently double-dec_refs both the original and the
## copy on destruction. The three hooks are explicitly delegated here:
##
##   `=destroy` → `=destroy` of `Z3Array[E, Z3Bool]`
##   `=copy`    → `=copy`    of `Z3Array[E, Z3Bool]`
##   `=dup`     → `=dup`     of `Z3Array[E, Z3Bool]`, re-wrapped
##
## ## Equality
##
## `==` and `!=` delegate via `toArray`, which calls `Z3_mk_eq` on
## the underlying array ASTs — the standard extensional array equality.
## Without this explicit delegation Nim's generic `==` for distinct
## types would attempt a field-by-field comparison of the opaque raw
## struct, always returning `true` regardless of the actual pointer
## identity (same bug that bit the raw handle types in N0.1).
##
## ## Build gate
##
## Gated on `-d:z3WithoutSets`. When built with that flag, this file
## imports cleanly but exports nothing.

when not defined(z3WithoutSets):

  import ./ffi, ./context, ./error, ./ast, ./lifecycle, ./arrays, ./builder

  # ============================================================================
  # Type
  # ============================================================================

  type
    Z3Set*[E] = distinct Z3Array[E, Z3Bool]
      ## SMT set-theory set whose elements are Z3-typed as `E`.
      ## Represented as `(Array E Bool)` inside Z3.
      ## Element type `E` must support `sortOf(_: typedesc[E], ctx)` —
      ## i.e. it must be one of the typed AST families (Z3Int, Z3Real,
      ## Z3Bool, Z3BitVec[W], Z3Char, …).

  # ============================================================================
  # Lifecycle hooks — explicit delegation (Nim distinct doesn't propagate)
  #
  # Nim's `distinct` does NOT propagate =destroy / =copy / =dup from the
  # base type. Without explicit delegation every copy of a Z3Set[E] silently
  # double-dec_refs on destruction. We delegate using the same body-extraction
  # templates that Z3Array uses (`termDestroy` / `termCopy` / `termDup` from
  # z3/lifecycle), treating the set value as a raw+ctx pair directly.
  #
  # We cannot call `=destroy(Z3Array[E,Z3Bool](s))` directly because the
  # cast produces a temporary (rvalue) and =destroy hooks require var. Instead
  # we reach through to the underlying `termDestroy` / `termCopy` / `termDup`
  # templates which operate on the value directly, reading `.raw` and `.ctx`
  # from the reinterpreted object.
  # ============================================================================

  proc `=destroy`*[E](s: Z3Set[E]) {.raises: [].} =
    termDestroy(Z3Array[E, Z3Bool](s), Z3_dec_ref)

  proc `=copy`*[E](dst: var Z3Set[E], src: Z3Set[E]) {.raises: [].} =
    # Cannot call termCopy with `Z3Array[E,Z3Bool](dst)` because the cast
    # produces an rvalue — writes through the cast don't land on `dst`.
    # Instead, reach through to the underlying fields directly using a
    # pointer cast that gives us a mutable alias to the same memory.
    # Z3Set[E] and Z3Array[E,Z3Bool] share identical memory layout (distinct
    # types with the same underlying struct), so this is safe and zero-cost.
    let dstArr = cast[ptr Z3Array[E, Z3Bool]](addr dst)
    termCopy(dstArr[], Z3Array[E, Z3Bool](src), Z3_dec_ref, Z3_inc_ref)

  proc `=dup`*[E](src: Z3Set[E]): Z3Set[E] {.raises: [].} =
    var arr: Z3Array[E, Z3Bool]
    termDup(arr, Z3Array[E, Z3Bool](src), Z3_inc_ref)
    Z3Set[E](arr)

  # ============================================================================
  # Conversions (zero-cost casts)
  # ============================================================================

  proc toArray*[E](s: Z3Set[E]): Z3Array[E, Z3Bool] {.inline.} =
    ## Cast a Z3Set to its underlying Z3Array representation.
    ## Zero-cost (no Z3 API call).
    Z3Array[E, Z3Bool](s)

  proc toSet*[E](a: Z3Array[E, Z3Bool]): Z3Set[E] {.inline.} =
    ## Wrap a Z3Array[E, Z3Bool] as a Z3Set.
    ## Zero-cost (no Z3 API call).
    Z3Set[E](a)

  # ============================================================================
  # Internal helper: extract ctx from a Z3Set
  # ============================================================================

  template setCtx[E](s: Z3Set[E]): Z3Context =
    ## Pull the context out of the underlying array (which has a `.ctx` field).
    (Z3Array[E, Z3Bool](s)).ctx

  template setRaw[E](s: Z3Set[E]): RawZ3Ast =
    ## Pull the raw handle out of the underlying array.
    (Z3Array[E, Z3Bool](s)).raw

  # ============================================================================
  # Constructors
  # ============================================================================

  proc mkEmptySet*[E](ctx: Z3Context): Z3Set[E] =
    ## The empty set over the sort of `E`.
    ##
    runnableExamples:
      import z3
      let ctx = newContext()
      let s = mkEmptySet[Z3Int](ctx)
      let x = mkInt(ctx, 42)
      # The empty set contains no elements — membership is always false.
      let isMember = member(x, s)
      let solver = newSolver(ctx)
      solver.add isMember
      doAssert solver.check() == zsUnsat
    let domSort = sortOfType[E](ctx)
    wrap[Z3Array[E, Z3Bool]](ctx,
      ctx.checkErr Z3_mk_empty_set(ctx.raw, domSort)).toSet

  proc mkEmptySet*[E](_: typedesc[E]): Z3Set[E] =
    ## Typedesc-form; uses the current context.
    mkEmptySet[E](requireCurrentContext())

  proc mkFullSet*[E](ctx: Z3Context): Z3Set[E] =
    ## The full set (universe) over the sort of `E`.
    ##
    runnableExamples:
      import z3
      let ctx = newContext()
      let full = mkFullSet[Z3Int](ctx)
      let x = mkInt(ctx, 7)
      # The full set contains every element — membership is always true.
      let solver = newSolver(ctx)
      solver.add(not member(x, full))
      doAssert solver.check() == zsUnsat
    let domSort = sortOfType[E](ctx)
    wrap[Z3Array[E, Z3Bool]](ctx,
      ctx.checkErr Z3_mk_full_set(ctx.raw, domSort)).toSet

  proc mkFullSet*[E](_: typedesc[E]): Z3Set[E] =
    ## Typedesc-form; uses the current context.
    mkFullSet[E](requireCurrentContext())

  # ============================================================================
  # Element operations
  # ============================================================================

  proc add*[E](s: Z3Set[E], e: E): Z3Set[E] =
    ## Functional add — returns a new set with `e` inserted.
    let ctx = setCtx(s)
    wrap[Z3Array[E, Z3Bool]](ctx,
      ctx.checkErr Z3_mk_set_add(ctx.raw, setRaw(s), e.raw)).toSet

  proc del*[E](s: Z3Set[E], e: E): Z3Set[E] =
    ## Functional delete — returns a new set with `e` removed.
    let ctx = setCtx(s)
    wrap[Z3Array[E, Z3Bool]](ctx,
      ctx.checkErr Z3_mk_set_del(ctx.raw, setRaw(s), e.raw)).toSet

  proc member*[E](e: E, s: Z3Set[E]): Z3Bool =
    ## Membership predicate: `e ∈ s`. Returns a Z3Bool AST.
    let ctx = setCtx(s)
    wrap[Z3Bool](ctx,
      ctx.checkErr Z3_mk_set_member(ctx.raw, e.raw, setRaw(s)))

  # ============================================================================
  # Set operations
  # ============================================================================

  proc union*[E](a, b: Z3Set[E]): Z3Set[E] =
    ## Binary union `a ∪ b`.
    ##
    runnableExamples:
      import z3
      let ctx = newContext()
      let x = mkInt(ctx, 1)
      let y = mkInt(ctx, 2)
      let sa = mkEmptySet[Z3Int](ctx).add(x)
      let sb = mkEmptySet[Z3Int](ctx).add(y)
      let u = union(sa, sb)
      # Both x and y are members of the union.
      let solver = newSolver(ctx)
      solver.add(not member(x, u))
      doAssert solver.check() == zsUnsat
    let ctx = setCtx(a)
    var args = [setRaw(a), setRaw(b)]
    wrap[Z3Array[E, Z3Bool]](ctx,
      ctx.checkErr Z3_mk_set_union(
        ctx.raw, 2.cuint,
        cast[ptr UncheckedArray[RawZ3Ast]](addr args[0]))).toSet

  proc union*[E](xs: varargs[Z3Set[E]]): Z3Set[E] =
    ## N-ary union. Requires at least one argument.
    doAssert xs.len >= 1, "union requires at least one argument"
    if xs.len == 1: return xs[0]
    let ctx = setCtx(xs[0])
    var raws = newSeq[RawZ3Ast](xs.len)
    for i, x in xs:
      raws[i] = setRaw(x)
    wrap[Z3Array[E, Z3Bool]](ctx,
      naryFFICall(ctx, raws, Z3_mk_set_union)).toSet

  proc intersect*[E](a, b: Z3Set[E]): Z3Set[E] =
    ## Binary intersection `a ∩ b`.
    let ctx = setCtx(a)
    var args = [setRaw(a), setRaw(b)]
    wrap[Z3Array[E, Z3Bool]](ctx,
      ctx.checkErr Z3_mk_set_intersect(
        ctx.raw, 2.cuint,
        cast[ptr UncheckedArray[RawZ3Ast]](addr args[0]))).toSet

  proc intersect*[E](xs: varargs[Z3Set[E]]): Z3Set[E] =
    ## N-ary intersection. Requires at least one argument.
    doAssert xs.len >= 1, "intersect requires at least one argument"
    if xs.len == 1: return xs[0]
    let ctx = setCtx(xs[0])
    var raws = newSeq[RawZ3Ast](xs.len)
    for i, x in xs:
      raws[i] = setRaw(x)
    wrap[Z3Array[E, Z3Bool]](ctx,
      naryFFICall(ctx, raws, Z3_mk_set_intersect)).toSet

  proc difference*[E](a, b: Z3Set[E]): Z3Set[E] =
    ## Set difference `a \ b`.
    let ctx = setCtx(a)
    wrap[Z3Array[E, Z3Bool]](ctx,
      ctx.checkErr Z3_mk_set_difference(ctx.raw, setRaw(a), setRaw(b))).toSet

  proc complement*[E](a: Z3Set[E]): Z3Set[E] =
    ## Complement of `a` (with respect to the full universe).
    let ctx = setCtx(a)
    wrap[Z3Array[E, Z3Bool]](ctx,
      ctx.checkErr Z3_mk_set_complement(ctx.raw, setRaw(a))).toSet

  proc subset*[E](a, b: Z3Set[E]): Z3Bool =
    ## Subset predicate: `a ⊆ b`. Returns a Z3Bool AST.
    let ctx = setCtx(a)
    wrap[Z3Bool](ctx,
      ctx.checkErr Z3_mk_set_subset(ctx.raw, setRaw(a), setRaw(b)))

  proc hasSize*[E](s: Z3Set[E], k: Z3Int): Z3Bool =
    ## Cardinality constraint: `|s| = k`. Returns a Z3Bool AST.
    ##
    ## Note: Z3's `Z3_mk_set_has_size` takes an `Int`-sorted `k` operand.
    let ctx = setCtx(s)
    wrap[Z3Bool](ctx,
      ctx.checkErr Z3_mk_set_has_size(ctx.raw, setRaw(s), k.raw))

  # ============================================================================
  # Equality + pretty
  # ============================================================================

  proc `==`*[E](a, b: Z3Set[E]): Z3Bool =
    ## SMT equality — delegates to `Z3Array[E, Z3Bool]`'s `==`.
    ## With Z3's array extensionality axiom, `a = b` iff they agree at
    ## every index (i.e. have the same members).
    toArray(a) == toArray(b)

  proc `!=`*[E](a, b: Z3Set[E]): Z3Bool =
    not (a == b)

  proc `$`*[E](s: Z3Set[E]): string =
    ## SMT-LIB rendering, delegated through the underlying array.
    $toArray(s)

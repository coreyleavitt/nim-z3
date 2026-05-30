## `Z3Array[Key, Val]` — phantom-typed arrays over the SMT array theory.
##
## ## Phantom design
##
## `Key` and `Val` are **typedescs of AST types** (`Z3Int`, `Z3Real`,
## `Z3Bool`, `Z3BitVec[W]`), not `static SortTag` values. v0.2's plan
## sketched `Z3Array[K, V: static SortTag]`, but that representation
## can't express `Z3Array[Z3BitVec[32], Z3BitVec[8]]` (the canonical
## memory model) because every BV width would collapse to the same
## `stBitVec` tag. Typedescs preserve the full sort identity —
## `select` returns the *actual* typed AST, not a `Z3Ast[stBitVec]`
## the user would have to re-cast.
##
## Dispatch happens through `sortOfType[T](ctx)` which pattern-matches
## the typedesc and extracts `T.W` for the `Z3BitVec` branch.
##
## ## Lifecycle
##
## Same refcount-discipline shape as `Z3Ast[S]`: value type carrying a
## `RawZ3Ast` + parent context, with `=destroy` / `=copy` / `=dup`
## calling Z3's `inc_ref` / `dec_ref` correctly. The `wrapArray`
## template is the centralised entry point for "freshly-returned raw
## handle → managed `Z3Array`".
##
## ## Not yet supported (deferred to v0.2 §8)
##
## - **Nested arrays** (`Z3Array[Z3Int, Z3Array[Z3Int, Z3Int]]`).
##   Nim 2.2's typedesc-generic-param reflection doesn't compose
##   cleanly across nesting — extracting `T.Key` and `T.Val` from a
##   `T: Z3Array` to recursively build the sort needs macro-level
##   introspection. Revisit if a user needs it before datatypes land.
## - **`Z3_mk_array_ext`** (extensionality witness). Niche; defer
##   until tactics or v0.3.

import ./ffi, ./context, ./sort, ./ast, ./bitvec

# ============================================================================
# sortOfType — typedesc → RawZ3Sort dispatch
# ============================================================================

proc sortOfType*[T](ctx: Z3Context): RawZ3Sort =
  ## Compile-time-resolved sort constructor for a typed AST family.
  ## Used by `Z3Array` and any other module needing to turn a typedesc
  ## into a raw Z3 sort. Public so future modules (datatypes, etc.)
  ## can dispatch the same way.
  when T is Z3Int:
    ctx.checkErr Z3_mk_int_sort(ctx.raw)
  elif T is Z3Real:
    ctx.checkErr Z3_mk_real_sort(ctx.raw)
  elif T is Z3Bool:
    ctx.checkErr Z3_mk_bool_sort(ctx.raw)
  elif T is Z3BitVec:
    # T.W extracts the static int generic param of Z3BitVec[W].
    ctx.checkErr Z3_mk_bv_sort(ctx.raw, cuint(T.W))
  else:
    {.error: "sortOfType: unsupported sort type. Supported: Z3Int, " &
             "Z3Real, Z3Bool, Z3BitVec[W]. Nested arrays / datatypes " &
             "land in later v0.2 steps.".}

# ============================================================================
# Z3Array — phantom-typed value type
# ============================================================================

type
  Z3Array*[Key, Val] = object
    ## Total function from `Key`-sorted values to `Val`-sorted values
    ## in Z3's array theory. Value-typed (cheap to pass); `=copy`
    ## handles refcounting.
    raw*: RawZ3Ast
    ctx*: Z3Context

# Lifecycle hooks parallel Z3Ast[S]; same body, two generic params.

proc `=destroy`[Key, Val](a: Z3Array[Key, Val]) {.raises: [].} =
  try:
    if not a.raw.isNil and a.ctx != nil and not a.ctx.raw.isNil:
      Z3_dec_ref(a.ctx.raw, a.raw)
  except CatchableError:
    discard

proc `=copy`[Key, Val](dst: var Z3Array[Key, Val],
                      src: Z3Array[Key, Val]) {.raises: [].} =
  if dst.raw != src.raw:
    try:
      if not dst.raw.isNil and dst.ctx != nil and not dst.ctx.raw.isNil:
        Z3_dec_ref(dst.ctx.raw, dst.raw)
      dst.raw = src.raw
      dst.ctx = src.ctx
      if not dst.raw.isNil and dst.ctx != nil and not dst.ctx.raw.isNil:
        Z3_inc_ref(dst.ctx.raw, dst.raw)
    except CatchableError:
      discard

proc `=dup`[Key, Val](src: Z3Array[Key, Val]): Z3Array[Key, Val] {.raises: [].} =
  result.raw = src.raw
  result.ctx = src.ctx
  if not result.raw.isNil and result.ctx != nil and not result.ctx.raw.isNil:
    try:
      Z3_inc_ref(result.ctx.raw, result.raw)
    except CatchableError:
      discard

template wrapArray*[Key, Val](theCtx: Z3Context,
                              theRaw: RawZ3Ast): Z3Array[Key, Val] =
  block:
    let r = theRaw
    if not r.isNil:
      Z3_inc_ref(theCtx.raw, r)
    Z3Array[Key, Val](raw: r, ctx: theCtx)

# ============================================================================
# Construction
# ============================================================================

proc mkConstArray*[Key, Val](
    ctx: Z3Context, default: Val): Z3Array[Key, Val] =
  ## Array whose value is `default` at every index. The key sort is
  ## inferred from `Key`; the range sort comes from `default`.
  ##
  ## ```nim
  ## let zeros = mkConstArray[Z3Int, Z3Int](ctx, mkInt(0))
  ## let blank = mkConstArray[Z3BitVec[32], Z3BitVec[8]](
  ##   ctx, mkBitVec(0'u8, 8))
  ## ```
  let kSort = sortOfType[Key](ctx)
  wrapArray[Key, Val](ctx,
    ctx.checkErr Z3_mk_const_array(ctx.raw, kSort, default.raw))

proc mkConstArray*[Key, Val](default: Val): Z3Array[Key, Val] =
  mkConstArray[Key, Val](requireCurrentContext(), default)

proc mkArrayVar*[Key, Val](
    ctx: Z3Context, name: string): Z3Array[Key, Val] =
  ## Free array variable.
  ##
  ## ```nim
  ## let mem = mkArrayVar[Z3BitVec[32], Z3BitVec[8]]("mem")
  ## ```
  let kSort = sortOfType[Key](ctx)
  let vSort = sortOfType[Val](ctx)
  let aSort = ctx.checkErr Z3_mk_array_sort(ctx.raw, kSort, vSort)
  let sym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)
  wrapArray[Key, Val](ctx,
    ctx.checkErr Z3_mk_const(ctx.raw, sym, aSort))

proc mkArrayVar*[Key, Val](name: string): Z3Array[Key, Val] =
  mkArrayVar[Key, Val](requireCurrentContext(), name)

# ============================================================================
# Operations
# ============================================================================

proc store*[Key, Val](
    a: Z3Array[Key, Val], i: Key, v: Val): Z3Array[Key, Val] =
  ## Functional update: `result[i] = v`, `result[j] = a[j]` for `j ≠ i`.
  ## Returns a new array; `a` is unchanged.
  wrapArray[Key, Val](a.ctx,
    a.ctx.checkErr Z3_mk_store(a.ctx.raw, a.raw, i.raw, v.raw))

proc select*[Key, Val](a: Z3Array[Key, Val], i: Key): Val =
  ## Read `a[i]`. Returns a `Val`-typed AST.
  # `Val` is a typedesc here, so the return type is computed; we
  # construct the value of that type via the same raw-wrap path each
  # typed-AST family uses.
  when Val is Z3Int:    wrap[stInt](a.ctx, a.ctx.checkErr Z3_mk_select(a.ctx.raw, a.raw, i.raw))
  elif Val is Z3Real:   wrap[stReal](a.ctx, a.ctx.checkErr Z3_mk_select(a.ctx.raw, a.raw, i.raw))
  elif Val is Z3Bool:   wrap[stBool](a.ctx, a.ctx.checkErr Z3_mk_select(a.ctx.raw, a.raw, i.raw))
  elif Val is Z3BitVec: wrapBv[Val.W](a.ctx, a.ctx.checkErr Z3_mk_select(a.ctx.raw, a.raw, i.raw))
  else:
    {.error: "select: unsupported Val type. Same set as sortOfType.".}

proc `[]`*[Key, Val](a: Z3Array[Key, Val], i: Key): Val {.inline.} =
  ## Sugar for `select(a, i)`.
  select(a, i)

# ============================================================================
# Equality + pretty
# ============================================================================

proc `==`*[Key, Val](a, b: Z3Array[Key, Val]): Z3Bool =
  ## SMT equality. Returns `(= a b)`. With Z3's array extensionality
  ## axiom, this is true iff `a` and `b` agree at every index.
  wrap[stBool](a.ctx, a.ctx.checkErr Z3_mk_eq(a.ctx.raw, a.raw, b.raw))

proc `!=`*[Key, Val](a, b: Z3Array[Key, Val]): Z3Bool =
  let eq = a == b
  wrap[stBool](a.ctx, a.ctx.checkErr Z3_mk_not(a.ctx.raw, eq.raw))

proc `$`*[Key, Val](a: Z3Array[Key, Val]): string =
  ## SMT-LIB rendering.
  $Z3_ast_to_string(a.ctx.raw, a.raw)

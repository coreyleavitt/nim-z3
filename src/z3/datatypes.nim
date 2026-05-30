## `Z3DatatypeDecl[T] / Z3DatatypeValue[T]` — inductive sums.
##
## Single (non-mutually-recursive) datatypes. Mutually recursive
## (e.g. `List ↔ Tree`) is v0.2 step 5; it will go through
## `Z3_mk_datatypes` (plural) instead of `Z3_mk_datatype`, but the
## user-facing surface and lifecycle discipline established here
## extends naturally.
##
## ## Phantom design — marker type as the phantom
##
## The user declares a marker Nim type per datatype and passes it as
## the `T` generic to `declareDatatype`:
##
## ```nim
## type IntList = object
## let listDt = declareDatatype[IntList](@[
##   constructor("nil"),
##   constructor("cons", @[
##     field("head", Z3Int),
##     selfField("tail")])])
## ```
##
## Different marker types produce *distinct Nim phantom types*, so
## `Z3DatatypeValue[IntList]` and `Z3DatatypeValue[Tree]` are
## non-interchangeable — passing one where the other is expected is a
## compile error, not a Z3 sort mismatch at check-sat time.
##
## The Z3 sort name (used for SMT-LIB rendering and `(declare-datatype
## IntList ...)` output) is derived from `$T` — i.e. the marker type's
## Nim name. So the marker type doubles as the human-readable
## identifier.
##
## v0.2 plan §7 Q1 leaned toward runtime decl-pointer comparison; the
## marker-type approach costs the user one `type X = object` per
## datatype but gives the same type-system guarantee the rest of the
## library leans on. (An earlier attempt with `static string` as the
## phantom hit a Nim 2.2 instantiation bug where `=destroy` couldn't
## be resolved for static-string-parameterised types; the marker type
## avoids that path.)
##
## ## Lifecycle for `RawZ3FuncDecl`
##
## v0.2 plan §6 flagged this as a step-4 risk. Z3 refcounts func_decls
## through the same `Z3_inc_ref` / `Z3_dec_ref` calls used for `Ast`,
## via `Z3_func_decl_to_ast` to get the underlying handle. The
## datatype decl holds strong references to every constructor /
## recognizer / accessor func_decl; they live as long as the decl.
## `=destroy` on the decl decrements them in bulk.

import std/[strformat]
import ./ffi, ./context, ./sort, ./ast, ./bitvec, ./array

# ============================================================================
# Field + constructor specs — user-facing builders
# ============================================================================

type
  FieldKind = enum fkSort, fkRecursive
  FieldSpec* = ref object
    fname*: string
    case kind*: FieldKind
    of fkSort: sortFn: proc (ctx: Z3Context): RawZ3Sort {.closure.}
    of fkRecursive: discard

  ConstructorSpec* = ref object
    cname*: string
    fields*: seq[FieldSpec]

proc field*[T](name: string, _: typedesc[T]): FieldSpec =
  ## Non-recursive field. Sort is derived from the typedesc `T` via
  ## `sortOfType` (the same dispatch used by `Z3Array`).
  result = FieldSpec(fname: name, kind: fkSort)
  result.sortFn = proc (ctx: Z3Context): RawZ3Sort = sortOfType[T](ctx)

proc selfField*(name: string): FieldSpec =
  ## Recursive field — references the datatype currently being declared.
  ## Resolved inside `declareDatatype` to the sort index.
  FieldSpec(fname: name, kind: fkRecursive)

proc constructor*(name: string,
                  fields: openArray[FieldSpec] = []): ConstructorSpec =
  ConstructorSpec(cname: name, fields: @fields)

# ============================================================================
# Decl + handle types
# ============================================================================

type
  Z3ConstructorDeclOwn[T] = object
    ctx: Z3Context
    cname: string
    constructorFD: RawZ3FuncDecl
    recognizerFD: RawZ3FuncDecl
    accessorsFD: seq[(string, RawZ3FuncDecl)]

  Z3ConstructorDeclRef[T] =
    ref Z3ConstructorDeclOwn[T]
    ## Internal — the constructor's three groups of func_decls plus
    ## name; held by the parent datatype decl. The public
    ## `Z3ConstructorDecl` / `Z3RecognizerDecl` / `Z3AccessorDecl`
    ## are thin lookups against this.

  Z3DatatypeDeclOwn[T] = object
    ctx: Z3Context
    sort: RawZ3Sort
    # constructors[i] mirrors the order passed to declareDatatype.
    cons: seq[Z3ConstructorDeclRef[T]]

  Z3DatatypeDecl*[T] = ref Z3DatatypeDeclOwn[T]
    ## Handle to a finalised inductive sum, name-tagged at the type
    ## level. Carries the underlying Z3 sort plus the per-constructor
    ## func_decls; lifetime owns refcounts on all of those.

  Z3DatatypeValue*[T] = object
    ## AST value of an inductive datatype, name-tagged.
    raw*: RawZ3Ast
    ctx*: Z3Context

  Z3ConstructorDecl*[T] = object
    inner: Z3ConstructorDeclRef[T]

  Z3RecognizerDecl*[T] = object
    inner: Z3ConstructorDeclRef[T]

  Z3AccessorDecl*[T, Ret] = object
    inner: Z3ConstructorDeclRef[T]
    fname: string

# ============================================================================
# Lifecycle hooks
# ============================================================================

proc decRefFuncDecl(ctx: Z3Context, fd: RawZ3FuncDecl) {.raises: [].} =
  try:
    if not fd.isNil and ctx != nil and not ctx.raw.isNil:
      let asAst = Z3_func_decl_to_ast(ctx.raw, fd)
      Z3_dec_ref(ctx.raw, asAst)
  except CatchableError:
    discard

proc incRefFuncDecl(ctx: Z3Context, fd: RawZ3FuncDecl) {.raises: [].} =
  try:
    if not fd.isNil and ctx != nil and not ctx.raw.isNil:
      let asAst = Z3_func_decl_to_ast(ctx.raw, fd)
      Z3_inc_ref(ctx.raw, asAst)
  except CatchableError:
    discard

proc `=destroy`[T](
    c: Z3ConstructorDeclOwn[T]) {.raises: [].} =
  decRefFuncDecl(c.ctx, c.constructorFD)
  decRefFuncDecl(c.ctx, c.recognizerFD)
  for (_, fd) in c.accessorsFD:
    decRefFuncDecl(c.ctx, fd)

# Z3DatatypeDeclOwn has no explicit =destroy — the default suffices.
# Its `cons` seq carries Z3ConstructorDeclRef[T] refs; ORC will
# tear them down automatically when the parent decl drops, and the
# per-constructor =destroy above fires to dec_ref each func_decl.
# Z3_mk_datatype's sort registers with the context and is freed when
# the context goes away, so no per-decl sort cleanup is needed.

proc `=destroy`[T](
    v: Z3DatatypeValue[T]) {.raises: [].} =
  try:
    if not v.raw.isNil and v.ctx != nil and not v.ctx.raw.isNil:
      Z3_dec_ref(v.ctx.raw, v.raw)
  except CatchableError:
    discard

proc `=copy`[T](
    dst: var Z3DatatypeValue[T],
    src: Z3DatatypeValue[T]) {.raises: [].} =
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

proc `=dup`[T](
    src: Z3DatatypeValue[T]): Z3DatatypeValue[T] {.raises: [].} =
  result.raw = src.raw
  result.ctx = src.ctx
  if not result.raw.isNil and result.ctx != nil and not result.ctx.raw.isNil:
    try:
      Z3_inc_ref(result.ctx.raw, result.raw)
    except CatchableError:
      discard

template wrapValue[T](
    theCtx: Z3Context, theRaw: RawZ3Ast): Z3DatatypeValue[T] =
  block:
    let r = theRaw
    if not r.isNil:
      Z3_inc_ref(theCtx.raw, r)
    Z3DatatypeValue[T](raw: r, ctx: theCtx)

# ============================================================================
# declareDatatype
# ============================================================================

proc declareDatatype*[T](
    ctx: Z3Context,
    cons: openArray[ConstructorSpec]): Z3DatatypeDecl[T] =
  ## Finalise an inductive datatype with the supplied constructors.
  ## The `T` generic is a Nim marker type — typically `type Maybe =
  ## object` declared above the call. Values are typed
  ## `Z3DatatypeValue[T]`; the Z3 sort name is `$T`.
  ##
  ## ```nim
  ## type Maybe = object
  ## let MaybeDt = declareDatatype[Maybe](@[
  ##   constructor("nothing"),
  ##   constructor("just", @[field("value", Z3Int)])
  ## ])
  ## ```
  let dtSym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T).cstring)

  # Build raw constructor descriptors in lockstep with `cons`.
  var rawCons = newSeq[RawZ3Constructor](cons.len)
  # We have to keep the per-constructor scratch arrays alive across the
  # Z3_mk_constructor call (it copies them but the GC scares me less
  # this way).
  var fieldNameSyms = newSeq[seq[RawZ3Symbol]](cons.len)
  var fieldSorts = newSeq[seq[RawZ3Sort]](cons.len)
  var fieldRefs = newSeq[seq[cuint]](cons.len)

  for ci, c in cons:
    let cnameSym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, c.cname.cstring)
    let recogName = "is-" & c.cname
    let recogSym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, recogName.cstring)

    fieldNameSyms[ci] = newSeq[RawZ3Symbol](c.fields.len)
    fieldSorts[ci] = newSeq[RawZ3Sort](c.fields.len)
    fieldRefs[ci] = newSeq[cuint](c.fields.len)

    for fi, f in c.fields:
      fieldNameSyms[ci][fi] =
        ctx.checkErr Z3_mk_string_symbol(ctx.raw, f.fname.cstring)
      case f.kind
      of fkSort:
        fieldSorts[ci][fi] = f.sortFn(ctx)
        fieldRefs[ci][fi] = 0
      of fkRecursive:
        # Sort field is nil; the index in `sort_refs` is the datatype
        # being declared. Single-datatype mode → index 0.
        fieldSorts[ci][fi] = RawZ3Sort()    # nil
        fieldRefs[ci][fi] = 0

    let fieldNamesPtr =
      if c.fields.len > 0:
        cast[ptr UncheckedArray[RawZ3Symbol]](addr fieldNameSyms[ci][0])
      else: nil
    let fieldSortsPtr =
      if c.fields.len > 0:
        cast[ptr UncheckedArray[RawZ3Sort]](addr fieldSorts[ci][0])
      else: nil
    let fieldRefsPtr =
      if c.fields.len > 0:
        cast[ptr UncheckedArray[cuint]](addr fieldRefs[ci][0])
      else: nil

    rawCons[ci] = ctx.checkErr Z3_mk_constructor(ctx.raw,
      cnameSym, recogSym, cuint(c.fields.len),
      fieldNamesPtr, fieldSortsPtr, fieldRefsPtr)

  let consPtr =
    if rawCons.len > 0:
      cast[ptr UncheckedArray[RawZ3Constructor]](addr rawCons[0])
    else: nil
  let dtSort = ctx.checkErr Z3_mk_datatype(ctx.raw, dtSym,
    cuint(rawCons.len), consPtr)

  # Query the func_decls for each constructor.
  var conRefs = newSeq[Z3ConstructorDeclRef[T]](cons.len)
  for ci, c in cons:
    var conFD, recogFD: RawZ3FuncDecl
    var accFDs = newSeq[RawZ3FuncDecl](c.fields.len)
    let accFDsPtr =
      if c.fields.len > 0:
        cast[ptr UncheckedArray[RawZ3FuncDecl]](addr accFDs[0])
      else: nil
    ctx.checkErrVoid Z3_query_constructor(ctx.raw, rawCons[ci],
      cuint(c.fields.len), addr conFD, addr recogFD, accFDsPtr)

    incRefFuncDecl(ctx, conFD)
    incRefFuncDecl(ctx, recogFD)
    var accs = newSeq[(string, RawZ3FuncDecl)](c.fields.len)
    for fi, f in c.fields:
      incRefFuncDecl(ctx, accFDs[fi])
      accs[fi] = (f.fname, accFDs[fi])

    conRefs[ci] = Z3ConstructorDeclRef[T](
      ctx: ctx, cname: c.cname,
      constructorFD: conFD, recognizerFD: recogFD, accessorsFD: accs)

  # Delete the descriptors — Z3 has consumed them.
  for con in rawCons:
    Z3_del_constructor(ctx.raw, con)

  Z3DatatypeDecl[T](ctx: ctx, sort: dtSort, cons: conRefs)

proc declareDatatype*[T](
    cons: openArray[ConstructorSpec]): Z3DatatypeDecl[T] =
  declareDatatype[T](requireCurrentContext(), cons)

# ============================================================================
# Lookup — con, recognizer, accessor
# ============================================================================

proc findCon[T](
    dt: Z3DatatypeDecl[T], cname: string): Z3ConstructorDeclRef[T] =
  for c in dt.cons:
    if c.cname == cname:
      return c
  raise newException(Z3Error,
    &"datatype {$T}: no constructor named '{cname}'")

proc con*[T](
    dt: Z3DatatypeDecl[T], cname: string): Z3ConstructorDecl[T] =
  ## Look up a constructor by name. Apply it via `c.apply(args…)` to
  ## build a `Z3DatatypeValue[T]`.
  Z3ConstructorDecl[T](inner: findCon(dt, cname))

proc recognizer*[T](
    dt: Z3DatatypeDecl[T], cname: string): Z3RecognizerDecl[T] =
  ## Look up the `is-<cname>` recognizer. Apply via `r.test(value)`.
  Z3RecognizerDecl[T](inner: findCon(dt, cname))

proc accessor*[T, Ret](
    dt: Z3DatatypeDecl[T], cname, fname: string,
    _: typedesc[Ret] = Z3DatatypeValue[T]): Z3AccessorDecl[T, Ret] =
  ## Look up a field accessor. `Ret` is the declared field type; passing
  ## it explicitly at the lookup site (rather than per-read) keeps the
  ## `read` call site clean.
  ##
  ## ```nim
  ## let head = Maybe.accessor("just", "value", Z3Int)
  ## let v = head.read(myValue)   # Z3Int, statically known
  ## ```
  let inner = findCon(dt, cname)
  var found = false
  for (fname2, _) in inner.accessorsFD:
    if fname2 == fname:
      found = true
      break
  if not found:
    raise newException(Z3Error,
      &"datatype {$T}: constructor '{cname}' has no field '{fname}'")
  Z3AccessorDecl[T, Ret](inner: inner, fname: fname)

# ============================================================================
# Apply constructor (per-arity templates)
# ============================================================================
#
# Templates rather than a single varargs proc — explicit args propagate
# the `T` phantom through more cleanly, and the `.raw` access on
# each arg is type-checked at the call site by the compiler. Arity 5
# covers ~every realistic constructor; raise the ceiling here if a
# user needs more.

proc applyImpl[T](
    c: Z3ConstructorDecl[T],
    args: openArray[RawZ3Ast]): Z3DatatypeValue[T] =
  let ctx = c.inner.ctx
  let argsPtr =
    if args.len > 0:
      cast[ptr UncheckedArray[RawZ3Ast]](unsafeAddr args[0])
    else: nil
  wrapValue[T](ctx, ctx.checkErr Z3_mk_app(ctx.raw,
    c.inner.constructorFD, cuint(args.len), argsPtr))

template apply*[T](
    c: Z3ConstructorDecl[T]): Z3DatatypeValue[T] =
  applyImpl(c, [])
template apply*[T](
    c: Z3ConstructorDecl[T], a: typed): Z3DatatypeValue[T] =
  applyImpl(c, [a.raw])
template apply*[T](
    c: Z3ConstructorDecl[T], a, b: typed): Z3DatatypeValue[T] =
  applyImpl(c, [a.raw, b.raw])
template apply*[T](
    c: Z3ConstructorDecl[T], a, b, c2: typed): Z3DatatypeValue[T] =
  applyImpl(c, [a.raw, b.raw, c2.raw])
template apply*[T](
    c: Z3ConstructorDecl[T], a, b, c2, d: typed): Z3DatatypeValue[T] =
  applyImpl(c, [a.raw, b.raw, c2.raw, d.raw])
template apply*[T](
    c: Z3ConstructorDecl[T], a, b, c2, d, e: typed): Z3DatatypeValue[T] =
  applyImpl(c, [a.raw, b.raw, c2.raw, d.raw, e.raw])

# ============================================================================
# test (recognizer) + read (accessor)
# ============================================================================

proc test*[T](
    r: Z3RecognizerDecl[T], v: Z3DatatypeValue[T]): Z3Bool =
  ## `(is-<cname> v)` — true iff `v` was built with this constructor.
  let ctx = r.inner.ctx
  var arg = v.raw
  let raw = ctx.checkErr Z3_mk_app(ctx.raw,
    r.inner.recognizerFD, 1, cast[ptr UncheckedArray[RawZ3Ast]](addr arg))
  wrap[stBool](ctx, raw)

proc readRawAccessor[T, Ret](
    a: Z3AccessorDecl[T, Ret], v: Z3DatatypeValue[T]): RawZ3Ast =
  let ctx = a.inner.ctx
  var fd: RawZ3FuncDecl
  for (fname2, decl) in a.inner.accessorsFD:
    if fname2 == a.fname:
      fd = decl
      break
  var arg = v.raw
  ctx.checkErr Z3_mk_app(ctx.raw, fd, 1,
    cast[ptr UncheckedArray[RawZ3Ast]](addr arg))

proc read*[T, Ret](
    a: Z3AccessorDecl[T, Ret], v: Z3DatatypeValue[T]): Ret =
  ## Read a field. Return type is the `Ret` declared at the accessor
  ## lookup; dispatches on it via `sortOfType`-style branches.
  let ctx = a.inner.ctx
  let raw = readRawAccessor(a, v)
  when Ret is Z3Int:    wrap[stInt](ctx, raw)
  elif Ret is Z3Real:   wrap[stReal](ctx, raw)
  elif Ret is Z3Bool:   wrap[stBool](ctx, raw)
  elif Ret is Z3BitVec: wrapBv[Ret.W](ctx, raw)
  elif Ret is Z3DatatypeValue[T]:
    # Recursive reference. Just wrap as the same-name value.
    wrapValue[T](ctx, raw)
  else:
    {.error: "accessor read: unsupported Ret type for datatype field.".}

# ============================================================================
# Equality + pretty
# ============================================================================

proc `==`*[T](
    a, b: Z3DatatypeValue[T]): Z3Bool =
  wrap[stBool](a.ctx, a.ctx.checkErr Z3_mk_eq(a.ctx.raw, a.raw, b.raw))

proc `!=`*[T](
    a, b: Z3DatatypeValue[T]): Z3Bool =
  let eq = a == b
  wrap[stBool](a.ctx, a.ctx.checkErr Z3_mk_not(a.ctx.raw, eq.raw))

proc `$`*[T](v: Z3DatatypeValue[T]): string =
  $Z3_ast_to_string(v.ctx.raw, v.raw)

# ============================================================================
# Datatype-sorted variables
# ============================================================================

proc mkDatatypeVar*[T](
    dt: Z3DatatypeDecl[T], name: string): Z3DatatypeValue[T] =
  ## Free variable of the datatype sort.
  let sym = dt.ctx.checkErr Z3_mk_string_symbol(dt.ctx.raw, name.cstring)
  wrapValue[T](dt.ctx, dt.ctx.checkErr Z3_mk_const(dt.ctx.raw, sym, dt.sort))

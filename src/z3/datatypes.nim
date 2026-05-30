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

import std/[strformat, tables]
import ./ffi, ./context, ./sort, ./ast, ./bitvec, ./array

# ============================================================================
# Field + constructor specs — user-facing builders
# ============================================================================

type
  FieldKind = enum fkSort, fkRecursive, fkCross
  FieldSpec* = ref object
    fname*: string
    case kind*: FieldKind
    of fkSort: sortFn: proc (ctx: Z3Context): RawZ3Sort {.closure.}
    of fkRecursive: discard
    of fkCross: crossTypeName*: string
      ## Marker-type name (`$T2`) of the other datatype this field
      ## references. Resolved against the sibling specs at
      ## `declareDatatypes` call time.

  ConstructorSpec* = ref object
    cname*: string
    fields*: seq[FieldSpec]

  DatatypeSpec*[T] = object
    ## Per-datatype spec used by `declareDatatypes`. Carries the
    ## marker type `T` as a phantom plus the constructor list. Built
    ## via `forDatatype[T](cons)`.
    cons*: seq[ConstructorSpec]

proc field*[T](name: string, _: typedesc[T]): FieldSpec =
  ## Non-recursive field. Sort is derived from the typedesc `T` via
  ## `sortOfType` (the same dispatch used by `Z3Array`).
  result = FieldSpec(fname: name, kind: fkSort)
  result.sortFn = proc (ctx: Z3Context): RawZ3Sort = sortOfType[T](ctx)

proc selfField*(name: string): FieldSpec =
  ## Recursive field — references the datatype currently being declared.
  ## In a `forDatatype[T]` group, "self" is the datatype tagged with `T`.
  FieldSpec(fname: name, kind: fkRecursive)

proc crossField*[T2](name: string, _: typedesc[T2] = T2): FieldSpec =
  ## Cross-reference field — references another datatype `T2` in the
  ## same `declareDatatypes` batch. Resolved by marker-type name (`$T2`)
  ## at declaration time. Using `crossField` outside `declareDatatypes`
  ## (in single-datatype `declareDatatype`) raises `Z3Error` because
  ## there's no sibling to resolve against.
  FieldSpec(fname: name, kind: fkCross, crossTypeName: $T2)

proc constructor*(name: string,
                  fields: openArray[FieldSpec] = []): ConstructorSpec =
  ConstructorSpec(cname: name, fields: @fields)

proc forDatatype*[T](cons: openArray[ConstructorSpec]): DatatypeSpec[T] =
  ## Bundle a constructor list with its marker type, ready for
  ## `declareDatatypes`.
  DatatypeSpec[T](cons: @cons)

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

proc `=destroy`[T](v: Z3DatatypeValue[T]) {.raises: [].} =
  termDestroy(v, Z3_dec_ref)

proc `=copy`[T](dst: var Z3DatatypeValue[T],
                src: Z3DatatypeValue[T]) {.raises: [].} =
  termCopy(dst, src, Z3_dec_ref, Z3_inc_ref)

proc `=dup`[T](src: Z3DatatypeValue[T]): Z3DatatypeValue[T] {.raises: [].} =
  termDup(result, src, Z3_inc_ref)

# `wrapValue` removed v0.3 step 1 — call sites use the unified
# `wrap[Z3DatatypeValue[T]](ctx, raw)` from `z3/lifecycle` directly.

# ============================================================================
# declareDatatype
# ============================================================================

type
  RawConsWork = object
    ## Per-datatype scratch carrying everything that has to outlive the
    ## `Z3_mk_constructor` calls until `Z3_mk_datatype(s)` has consumed
    ## the descriptors. Owned by the caller — kept on the stack frame
    ## across the entire build.
    rawCons: seq[RawZ3Constructor]
    fieldNameSyms: seq[seq[RawZ3Symbol]]
    fieldSorts: seq[seq[RawZ3Sort]]
    fieldRefs: seq[seq[cuint]]

proc buildRawConstructors(
    ctx: Z3Context,
    cons: openArray[ConstructorSpec],
    selfIdx: int,
    nameToIdx: Table[string, int]): RawConsWork =
  ## Build raw constructor descriptors for one datatype. `selfIdx` is
  ## the datatype's own index in the surrounding `Z3_mk_datatypes`
  ## batch (always 0 for single-datatype). `nameToIdx` maps marker-
  ## type names (`$T2`) to indices for cross-references; empty in the
  ## single-datatype path.
  result.rawCons = newSeq[RawZ3Constructor](cons.len)
  result.fieldNameSyms = newSeq[seq[RawZ3Symbol]](cons.len)
  result.fieldSorts = newSeq[seq[RawZ3Sort]](cons.len)
  result.fieldRefs = newSeq[seq[cuint]](cons.len)

  for ci, c in cons:
    let cnameSym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, c.cname.cstring)
    let recogName = "is-" & c.cname
    let recogSym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, recogName.cstring)

    result.fieldNameSyms[ci] = newSeq[RawZ3Symbol](c.fields.len)
    result.fieldSorts[ci] = newSeq[RawZ3Sort](c.fields.len)
    result.fieldRefs[ci] = newSeq[cuint](c.fields.len)

    for fi, f in c.fields:
      result.fieldNameSyms[ci][fi] =
        ctx.checkErr Z3_mk_string_symbol(ctx.raw, f.fname.cstring)
      case f.kind
      of fkSort:
        result.fieldSorts[ci][fi] = f.sortFn(ctx)
        result.fieldRefs[ci][fi] = 0
      of fkRecursive:
        result.fieldSorts[ci][fi] = RawZ3Sort()    # nil
        result.fieldRefs[ci][fi] = cuint(selfIdx)
      of fkCross:
        if not nameToIdx.hasKey(f.crossTypeName):
          raise newException(Z3Error,
            &"datatype build: crossField references '{f.crossTypeName}' " &
            "which is not among the sibling datatypes in this batch. " &
            "Use `selfField` for self-references; use `declareDatatypes` " &
            "with all involved datatypes in one call for cross-references.")
        result.fieldSorts[ci][fi] = RawZ3Sort()
        result.fieldRefs[ci][fi] = cuint(nameToIdx[f.crossTypeName])

    let fieldNamesPtr =
      if c.fields.len > 0:
        cast[ptr UncheckedArray[RawZ3Symbol]](addr result.fieldNameSyms[ci][0])
      else: nil
    let fieldSortsPtr =
      if c.fields.len > 0:
        cast[ptr UncheckedArray[RawZ3Sort]](addr result.fieldSorts[ci][0])
      else: nil
    let fieldRefsPtr =
      if c.fields.len > 0:
        cast[ptr UncheckedArray[cuint]](addr result.fieldRefs[ci][0])
      else: nil

    result.rawCons[ci] = ctx.checkErr Z3_mk_constructor(ctx.raw,
      cnameSym, recogSym, cuint(c.fields.len),
      fieldNamesPtr, fieldSortsPtr, fieldRefsPtr)

proc queryConstructorsInto[T](
    ctx: Z3Context,
    cons: openArray[ConstructorSpec],
    rawCons: openArray[RawZ3Constructor]): seq[Z3ConstructorDeclRef[T]] =
  ## After `Z3_mk_datatype(s)` has finalised the sort, extract per-
  ## constructor `func_decl`s and wrap them as managed refs.
  result = newSeq[Z3ConstructorDeclRef[T]](cons.len)
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

    result[ci] = Z3ConstructorDeclRef[T](
      ctx: ctx, cname: c.cname,
      constructorFD: conFD, recognizerFD: recogFD, accessorsFD: accs)

proc declareDatatype*[T](
    ctx: Z3Context,
    cons: openArray[ConstructorSpec]): Z3DatatypeDecl[T] =
  ## Finalise an inductive datatype with the supplied constructors.
  ## The `T` generic is a Nim marker type — typically `type Maybe =
  ## object` declared above the call. Values are typed
  ## `Z3DatatypeValue[T]`; the Z3 sort name is `$T`.
  ##
  ## For mutually-recursive datatypes (cross-references via
  ## `crossField`) use `declareDatatypes` instead.
  let dtSym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T).cstring)
  let emptyMap = initTable[string, int]()
  var work = buildRawConstructors(ctx, cons, selfIdx = 0,
                                  nameToIdx = emptyMap)
  let consPtr =
    if work.rawCons.len > 0:
      cast[ptr UncheckedArray[RawZ3Constructor]](addr work.rawCons[0])
    else: nil
  let dtSort = ctx.checkErr Z3_mk_datatype(ctx.raw, dtSym,
    cuint(work.rawCons.len), consPtr)

  let conRefs = queryConstructorsInto[T](ctx, cons, work.rawCons)
  for con in work.rawCons:
    Z3_del_constructor(ctx.raw, con)

  Z3DatatypeDecl[T](ctx: ctx, sort: dtSort, cons: conRefs)

proc declareDatatype*[T](
    cons: openArray[ConstructorSpec]): Z3DatatypeDecl[T] =
  declareDatatype[T](requireCurrentContext(), cons)

# ============================================================================
# declareDatatypes — mutually recursive
# ============================================================================

proc declareDatatypes*[T1, T2](
    ctx: Z3Context, d1: DatatypeSpec[T1], d2: DatatypeSpec[T2]):
    (Z3DatatypeDecl[T1], Z3DatatypeDecl[T2]) =
  ## Finalise two mutually-recursive datatypes simultaneously. Cross-
  ## references (via `crossField[T2]`) resolve against the sibling
  ## marker types in this batch; self-references continue to use
  ## `selfField`.
  ##
  ## ```nim
  ## type Tree = object
  ## type Forest = object
  ## let (treeDt, forestDt) = declareDatatypes(
  ##   forDatatype[Tree](@[
  ##     constructor("leaf"),
  ##     constructor("node", @[
  ##       field("value", Z3Int),
  ##       crossField[Forest]("children")])]),
  ##   forDatatype[Forest](@[
  ##     constructor("empty"),
  ##     constructor("conscell", @[
  ##       crossField[Tree]("head"),
  ##       selfField("tail")])]))
  ## ```
  var nameToIdx = initTable[string, int]()
  nameToIdx[$T1] = 0
  nameToIdx[$T2] = 1

  var work1 = buildRawConstructors(ctx, d1.cons,
    selfIdx = 0, nameToIdx = nameToIdx)
  var work2 = buildRawConstructors(ctx, d2.cons,
    selfIdx = 1, nameToIdx = nameToIdx)

  # Bundle into per-datatype constructor lists.
  let list1 = ctx.checkErr Z3_mk_constructor_list(ctx.raw,
    cuint(work1.rawCons.len),
    cast[ptr UncheckedArray[RawZ3Constructor]](addr work1.rawCons[0]))
  let list2 = ctx.checkErr Z3_mk_constructor_list(ctx.raw,
    cuint(work2.rawCons.len),
    cast[ptr UncheckedArray[RawZ3Constructor]](addr work2.rawCons[0]))

  var sortNames = @[
    ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T1).cstring),
    ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T2).cstring),
  ]
  var sortsOut = newSeq[RawZ3Sort](2)
  var lists = @[list1, list2]

  ctx.checkErrVoid Z3_mk_datatypes(ctx.raw, 2,
    cast[ptr UncheckedArray[RawZ3Symbol]](addr sortNames[0]),
    cast[ptr UncheckedArray[RawZ3Sort]](addr sortsOut[0]),
    cast[ptr UncheckedArray[RawZ3ConstructorList]](addr lists[0]))

  let conRefs1 = queryConstructorsInto[T1](ctx, d1.cons, work1.rawCons)
  let conRefs2 = queryConstructorsInto[T2](ctx, d2.cons, work2.rawCons)

  # Z3 owns the descriptors via the lists; deleting the lists releases
  # the individual constructors too.
  Z3_del_constructor_list(ctx.raw, list1)
  Z3_del_constructor_list(ctx.raw, list2)

  let dt1 = Z3DatatypeDecl[T1](ctx: ctx, sort: sortsOut[0], cons: conRefs1)
  let dt2 = Z3DatatypeDecl[T2](ctx: ctx, sort: sortsOut[1], cons: conRefs2)
  (dt1, dt2)

proc declareDatatypes*[T1, T2](
    d1: DatatypeSpec[T1], d2: DatatypeSpec[T2]):
    (Z3DatatypeDecl[T1], Z3DatatypeDecl[T2]) =
  declareDatatypes(requireCurrentContext(), d1, d2)

proc declareDatatypes*[T1, T2, T3](
    ctx: Z3Context,
    d1: DatatypeSpec[T1], d2: DatatypeSpec[T2], d3: DatatypeSpec[T3]):
    (Z3DatatypeDecl[T1], Z3DatatypeDecl[T2], Z3DatatypeDecl[T3]) =
  ## 3-tuple variant. Same shape as the 2-arity overload — bump if a
  ## consumer needs N >= 4.
  var nameToIdx = initTable[string, int]()
  nameToIdx[$T1] = 0
  nameToIdx[$T2] = 1
  nameToIdx[$T3] = 2

  var work1 = buildRawConstructors(ctx, d1.cons, 0, nameToIdx)
  var work2 = buildRawConstructors(ctx, d2.cons, 1, nameToIdx)
  var work3 = buildRawConstructors(ctx, d3.cons, 2, nameToIdx)

  let list1 = ctx.checkErr Z3_mk_constructor_list(ctx.raw,
    cuint(work1.rawCons.len),
    cast[ptr UncheckedArray[RawZ3Constructor]](addr work1.rawCons[0]))
  let list2 = ctx.checkErr Z3_mk_constructor_list(ctx.raw,
    cuint(work2.rawCons.len),
    cast[ptr UncheckedArray[RawZ3Constructor]](addr work2.rawCons[0]))
  let list3 = ctx.checkErr Z3_mk_constructor_list(ctx.raw,
    cuint(work3.rawCons.len),
    cast[ptr UncheckedArray[RawZ3Constructor]](addr work3.rawCons[0]))

  var sortNames = @[
    ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T1).cstring),
    ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T2).cstring),
    ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T3).cstring),
  ]
  var sortsOut = newSeq[RawZ3Sort](3)
  var lists = @[list1, list2, list3]

  ctx.checkErrVoid Z3_mk_datatypes(ctx.raw, 3,
    cast[ptr UncheckedArray[RawZ3Symbol]](addr sortNames[0]),
    cast[ptr UncheckedArray[RawZ3Sort]](addr sortsOut[0]),
    cast[ptr UncheckedArray[RawZ3ConstructorList]](addr lists[0]))

  let conRefs1 = queryConstructorsInto[T1](ctx, d1.cons, work1.rawCons)
  let conRefs2 = queryConstructorsInto[T2](ctx, d2.cons, work2.rawCons)
  let conRefs3 = queryConstructorsInto[T3](ctx, d3.cons, work3.rawCons)

  Z3_del_constructor_list(ctx.raw, list1)
  Z3_del_constructor_list(ctx.raw, list2)
  Z3_del_constructor_list(ctx.raw, list3)

  let dt1 = Z3DatatypeDecl[T1](ctx: ctx, sort: sortsOut[0], cons: conRefs1)
  let dt2 = Z3DatatypeDecl[T2](ctx: ctx, sort: sortsOut[1], cons: conRefs2)
  let dt3 = Z3DatatypeDecl[T3](ctx: ctx, sort: sortsOut[2], cons: conRefs3)
  (dt1, dt2, dt3)

proc declareDatatypes*[T1, T2, T3](
    d1: DatatypeSpec[T1], d2: DatatypeSpec[T2], d3: DatatypeSpec[T3]):
    (Z3DatatypeDecl[T1], Z3DatatypeDecl[T2], Z3DatatypeDecl[T3]) =
  declareDatatypes(requireCurrentContext(), d1, d2, d3)

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
  wrap[Z3DatatypeValue[T]](ctx, ctx.checkErr Z3_mk_app(ctx.raw,
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
  wrap[Z3Bool](ctx, raw)

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
  ## lookup.
  ##
  ## v0.3 step 1: the previous five-branch `when Ret is X` dispatch
  ## collapsed to one call to the unified `wrap[T]` template from
  ## `z3/lifecycle`. Self-references and cross-references both fall
  ## out: `Ret` is `Z3DatatypeValue[X]` for some marker X, and the
  ## constructor inside `wrap[Ret]` propagates X through.
  wrap[Ret](a.inner.ctx, readRawAccessor(a, v))

# ============================================================================
# Equality + pretty
# ============================================================================

proc `==`*[T](
    a, b: Z3DatatypeValue[T]): Z3Bool =
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_eq(a.ctx.raw, a.raw, b.raw))

proc `!=`*[T](
    a, b: Z3DatatypeValue[T]): Z3Bool =
  let eq = a == b
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_not(a.ctx.raw, eq.raw))

proc `$`*[T](v: Z3DatatypeValue[T]): string =
  $Z3_ast_to_string(v.ctx.raw, v.raw)

# ============================================================================
# Datatype-sorted variables
# ============================================================================

proc mkDatatypeVar*[T](
    dt: Z3DatatypeDecl[T], name: string): Z3DatatypeValue[T] =
  ## Free variable of the datatype sort.
  let sym = dt.ctx.checkErr Z3_mk_string_symbol(dt.ctx.raw, name.cstring)
  wrap[Z3DatatypeValue[T]](dt.ctx, dt.ctx.checkErr Z3_mk_const(dt.ctx.raw, sym, dt.sort))

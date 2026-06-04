## `Z3DatatypeDecl[T] / Z3DatatypeValue[T]` — inductive sums.
##
## Single (non-mutually-recursive) datatypes go via
## `declareDatatype[T]`; mutually recursive groups (e.g.
## `List ↔ Tree`) via `declareDatatypes[T1, T2]` /
## `declareDatatypes[T1, T2, T3]` (both shipped in v0.2). The user-
## facing surface (`con` / `recognizer` / `accessor` / `apply` /
## `test` / `read`) is uniform across both paths.
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
import ./ffi, ./context, ./error, ./sort, ./ast, ./bitvec, ./arrays, ./sortdispatch

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
# sortOf overload (v0.4 step 3 — closes v0.3 §8 carryover)
# ============================================================================
#
# Datatype sorts are built at runtime by `declareDatatype` / `declareDatatypes`,
# which register the produced sort under `$T` in the context's
# datatypeRegistry. The sortOf overload does the lookup; raises if the
# user references Z3DatatypeValue[T] before `declareDatatype[T]` ran.
#
# This is the only `sortOf` overload in the wrapper that does runtime
# table lookup — every other overload is purely compile-time. The
# departure is justified because datatype sort identity literally
# cannot be encoded at compile time (the sort's Z3 handle is dynamic).

proc sortOf*[T](_: typedesc[Z3DatatypeValue[T]],
                ctx: Z3Context): RawZ3Sort =
  ## Per-context lookup of `T`'s registered datatype sort. Raises
  ## `Z3Error` (`Z3_INVALID_USAGE`) if the datatype hasn't been
  ## declared in this context — call `declareDatatype[T](...)` (or
  ## `declareDatatypes(...)` if mutually-recursive) before any code
  ## path that builds `Z3DatatypeValue[T]` as an element of another
  ## family (`Z3Array[K, Z3DatatypeValue[T]]`, `Z3Seq[Z3DatatypeValue[T]]`,
  ## `Z3FuncDecl[..., Z3DatatypeValue[T]]`, …).
  let name = $T
  if not ctx.datatypeRegistry.hasKey(name):
    var e = newException(Z3InvalidUsageError,
      "Z3DatatypeValue[" & name & "] is not registered in this context " &
      "— call `declareDatatype[" & name & "](...)` first (or " &
      "`declareDatatypes(...)` if mutually-recursive). " &
      "Datatype sorts are tracked per-context, keyed by marker-type " &
      "name; only the `declare*` APIs populate the table.")
    e.code = Z3_INVALID_USAGE
    raise e
  ctx.datatypeRegistry[name]

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
          raise newException(Z3InvalidUsageError,
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

  # v0.4 step 3: register the produced sort for sortdispatch lookup by
  # marker-type name. Re-registering the same T overwrites — Z3 would
  # build a fresh sort anyway; we just track the most recent.
  ctx.datatypeRegistry[$T] = dtSort

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

  # Bundle into per-datatype constructor lists. `addr seq[0]` requires
  # a non-empty seq; a zero-constructor datatype is invalid at the
  # theory level anyway.
  doAssert work1.rawCons.len > 0,
    "declareDatatypes: " & $T1 & " has zero constructors"
  doAssert work2.rawCons.len > 0,
    "declareDatatypes: " & $T2 & " has zero constructors"
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
  # v0.4 step 3: sortdispatch registry — both sides land in one batch.
  ctx.datatypeRegistry[$T1] = sortsOut[0]
  ctx.datatypeRegistry[$T2] = sortsOut[1]
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

  doAssert work1.rawCons.len > 0,
    "declareDatatypes: " & $T1 & " has zero constructors"
  doAssert work2.rawCons.len > 0,
    "declareDatatypes: " & $T2 & " has zero constructors"
  doAssert work3.rawCons.len > 0,
    "declareDatatypes: " & $T3 & " has zero constructors"
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
  # v0.4 step 3: sortdispatch registry — all three sides land in one batch.
  ctx.datatypeRegistry[$T1] = sortsOut[0]
  ctx.datatypeRegistry[$T2] = sortsOut[1]
  ctx.datatypeRegistry[$T3] = sortsOut[2]
  (dt1, dt2, dt3)

proc declareDatatypes*[T1, T2, T3](
    d1: DatatypeSpec[T1], d2: DatatypeSpec[T2], d3: DatatypeSpec[T3]):
    (Z3DatatypeDecl[T1], Z3DatatypeDecl[T2], Z3DatatypeDecl[T3]) =
  declareDatatypes(requireCurrentContext(), d1, d2, d3)

# declareDatatypes — arities 4-8 (generated via the same pattern as 2-3)

proc declareDatatypes*[T1, T2, T3, T4](
    ctx: Z3Context,
    d1: DatatypeSpec[T1], d2: DatatypeSpec[T2],
    d3: DatatypeSpec[T3], d4: DatatypeSpec[T4]):
    (Z3DatatypeDecl[T1], Z3DatatypeDecl[T2],
     Z3DatatypeDecl[T3], Z3DatatypeDecl[T4]) =
  var nameToIdx = initTable[string, int]()
  nameToIdx[$T1] = 0; nameToIdx[$T2] = 1
  nameToIdx[$T3] = 2; nameToIdx[$T4] = 3
  var w1 = buildRawConstructors(ctx, d1.cons, 0, nameToIdx)
  var w2 = buildRawConstructors(ctx, d2.cons, 1, nameToIdx)
  var w3 = buildRawConstructors(ctx, d3.cons, 2, nameToIdx)
  var w4 = buildRawConstructors(ctx, d4.cons, 3, nameToIdx)
  doAssert w1.rawCons.len > 0, "declareDatatypes: " & $T1 & " has zero constructors"
  doAssert w2.rawCons.len > 0, "declareDatatypes: " & $T2 & " has zero constructors"
  doAssert w3.rawCons.len > 0, "declareDatatypes: " & $T3 & " has zero constructors"
  doAssert w4.rawCons.len > 0, "declareDatatypes: " & $T4 & " has zero constructors"
  let l1 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w1.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w1.rawCons[0]))
  let l2 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w2.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w2.rawCons[0]))
  let l3 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w3.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w3.rawCons[0]))
  let l4 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w4.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w4.rawCons[0]))
  var sortNames = @[ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T1).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T2).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T3).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T4).cstring)]
  var sortsOut = newSeq[RawZ3Sort](4)
  var lists = @[l1, l2, l3, l4]
  ctx.checkErrVoid Z3_mk_datatypes(ctx.raw, 4, cast[ptr UncheckedArray[RawZ3Symbol]](addr sortNames[0]), cast[ptr UncheckedArray[RawZ3Sort]](addr sortsOut[0]), cast[ptr UncheckedArray[RawZ3ConstructorList]](addr lists[0]))
  let c1 = queryConstructorsInto[T1](ctx, d1.cons, w1.rawCons)
  let c2 = queryConstructorsInto[T2](ctx, d2.cons, w2.rawCons)
  let c3 = queryConstructorsInto[T3](ctx, d3.cons, w3.rawCons)
  let c4 = queryConstructorsInto[T4](ctx, d4.cons, w4.rawCons)
  Z3_del_constructor_list(ctx.raw, l1); Z3_del_constructor_list(ctx.raw, l2)
  Z3_del_constructor_list(ctx.raw, l3); Z3_del_constructor_list(ctx.raw, l4)
  ctx.datatypeRegistry[$T1] = sortsOut[0]; ctx.datatypeRegistry[$T2] = sortsOut[1]
  ctx.datatypeRegistry[$T3] = sortsOut[2]; ctx.datatypeRegistry[$T4] = sortsOut[3]
  (Z3DatatypeDecl[T1](ctx: ctx, sort: sortsOut[0], cons: c1),
   Z3DatatypeDecl[T2](ctx: ctx, sort: sortsOut[1], cons: c2),
   Z3DatatypeDecl[T3](ctx: ctx, sort: sortsOut[2], cons: c3),
   Z3DatatypeDecl[T4](ctx: ctx, sort: sortsOut[3], cons: c4))

proc declareDatatypes*[T1, T2, T3, T4](
    d1: DatatypeSpec[T1], d2: DatatypeSpec[T2],
    d3: DatatypeSpec[T3], d4: DatatypeSpec[T4]):
    (Z3DatatypeDecl[T1], Z3DatatypeDecl[T2],
     Z3DatatypeDecl[T3], Z3DatatypeDecl[T4]) =
  declareDatatypes(requireCurrentContext(), d1, d2, d3, d4)

proc declareDatatypes*[T1, T2, T3, T4, T5](
    ctx: Z3Context,
    d1: DatatypeSpec[T1], d2: DatatypeSpec[T2], d3: DatatypeSpec[T3],
    d4: DatatypeSpec[T4], d5: DatatypeSpec[T5]):
    (Z3DatatypeDecl[T1], Z3DatatypeDecl[T2], Z3DatatypeDecl[T3],
     Z3DatatypeDecl[T4], Z3DatatypeDecl[T5]) =
  var nameToIdx = initTable[string, int]()
  nameToIdx[$T1] = 0; nameToIdx[$T2] = 1; nameToIdx[$T3] = 2
  nameToIdx[$T4] = 3; nameToIdx[$T5] = 4
  var w1 = buildRawConstructors(ctx, d1.cons, 0, nameToIdx)
  var w2 = buildRawConstructors(ctx, d2.cons, 1, nameToIdx)
  var w3 = buildRawConstructors(ctx, d3.cons, 2, nameToIdx)
  var w4 = buildRawConstructors(ctx, d4.cons, 3, nameToIdx)
  var w5 = buildRawConstructors(ctx, d5.cons, 4, nameToIdx)
  doAssert w1.rawCons.len > 0, "declareDatatypes: " & $T1 & " has zero constructors"
  doAssert w2.rawCons.len > 0, "declareDatatypes: " & $T2 & " has zero constructors"
  doAssert w3.rawCons.len > 0, "declareDatatypes: " & $T3 & " has zero constructors"
  doAssert w4.rawCons.len > 0, "declareDatatypes: " & $T4 & " has zero constructors"
  doAssert w5.rawCons.len > 0, "declareDatatypes: " & $T5 & " has zero constructors"
  let l1 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w1.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w1.rawCons[0]))
  let l2 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w2.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w2.rawCons[0]))
  let l3 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w3.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w3.rawCons[0]))
  let l4 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w4.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w4.rawCons[0]))
  let l5 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w5.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w5.rawCons[0]))
  var sortNames = @[ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T1).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T2).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T3).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T4).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T5).cstring)]
  var sortsOut = newSeq[RawZ3Sort](5)
  var lists = @[l1, l2, l3, l4, l5]
  ctx.checkErrVoid Z3_mk_datatypes(ctx.raw, 5, cast[ptr UncheckedArray[RawZ3Symbol]](addr sortNames[0]), cast[ptr UncheckedArray[RawZ3Sort]](addr sortsOut[0]), cast[ptr UncheckedArray[RawZ3ConstructorList]](addr lists[0]))
  let c1 = queryConstructorsInto[T1](ctx, d1.cons, w1.rawCons)
  let c2 = queryConstructorsInto[T2](ctx, d2.cons, w2.rawCons)
  let c3 = queryConstructorsInto[T3](ctx, d3.cons, w3.rawCons)
  let c4 = queryConstructorsInto[T4](ctx, d4.cons, w4.rawCons)
  let c5 = queryConstructorsInto[T5](ctx, d5.cons, w5.rawCons)
  Z3_del_constructor_list(ctx.raw, l1); Z3_del_constructor_list(ctx.raw, l2)
  Z3_del_constructor_list(ctx.raw, l3); Z3_del_constructor_list(ctx.raw, l4)
  Z3_del_constructor_list(ctx.raw, l5)
  ctx.datatypeRegistry[$T1] = sortsOut[0]; ctx.datatypeRegistry[$T2] = sortsOut[1]
  ctx.datatypeRegistry[$T3] = sortsOut[2]; ctx.datatypeRegistry[$T4] = sortsOut[3]
  ctx.datatypeRegistry[$T5] = sortsOut[4]
  (Z3DatatypeDecl[T1](ctx: ctx, sort: sortsOut[0], cons: c1),
   Z3DatatypeDecl[T2](ctx: ctx, sort: sortsOut[1], cons: c2),
   Z3DatatypeDecl[T3](ctx: ctx, sort: sortsOut[2], cons: c3),
   Z3DatatypeDecl[T4](ctx: ctx, sort: sortsOut[3], cons: c4),
   Z3DatatypeDecl[T5](ctx: ctx, sort: sortsOut[4], cons: c5))

proc declareDatatypes*[T1, T2, T3, T4, T5](
    d1: DatatypeSpec[T1], d2: DatatypeSpec[T2], d3: DatatypeSpec[T3],
    d4: DatatypeSpec[T4], d5: DatatypeSpec[T5]):
    (Z3DatatypeDecl[T1], Z3DatatypeDecl[T2], Z3DatatypeDecl[T3],
     Z3DatatypeDecl[T4], Z3DatatypeDecl[T5]) =
  declareDatatypes(requireCurrentContext(), d1, d2, d3, d4, d5)

proc declareDatatypes*[T1, T2, T3, T4, T5, T6](
    ctx: Z3Context,
    d1: DatatypeSpec[T1], d2: DatatypeSpec[T2], d3: DatatypeSpec[T3],
    d4: DatatypeSpec[T4], d5: DatatypeSpec[T5], d6: DatatypeSpec[T6]):
    (Z3DatatypeDecl[T1], Z3DatatypeDecl[T2], Z3DatatypeDecl[T3],
     Z3DatatypeDecl[T4], Z3DatatypeDecl[T5], Z3DatatypeDecl[T6]) =
  var nameToIdx = initTable[string, int]()
  nameToIdx[$T1] = 0; nameToIdx[$T2] = 1; nameToIdx[$T3] = 2
  nameToIdx[$T4] = 3; nameToIdx[$T5] = 4; nameToIdx[$T6] = 5
  var w1 = buildRawConstructors(ctx, d1.cons, 0, nameToIdx)
  var w2 = buildRawConstructors(ctx, d2.cons, 1, nameToIdx)
  var w3 = buildRawConstructors(ctx, d3.cons, 2, nameToIdx)
  var w4 = buildRawConstructors(ctx, d4.cons, 3, nameToIdx)
  var w5 = buildRawConstructors(ctx, d5.cons, 4, nameToIdx)
  var w6 = buildRawConstructors(ctx, d6.cons, 5, nameToIdx)
  doAssert w1.rawCons.len > 0, "declareDatatypes: " & $T1 & " has zero constructors"
  doAssert w2.rawCons.len > 0, "declareDatatypes: " & $T2 & " has zero constructors"
  doAssert w3.rawCons.len > 0, "declareDatatypes: " & $T3 & " has zero constructors"
  doAssert w4.rawCons.len > 0, "declareDatatypes: " & $T4 & " has zero constructors"
  doAssert w5.rawCons.len > 0, "declareDatatypes: " & $T5 & " has zero constructors"
  doAssert w6.rawCons.len > 0, "declareDatatypes: " & $T6 & " has zero constructors"
  let l1 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w1.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w1.rawCons[0]))
  let l2 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w2.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w2.rawCons[0]))
  let l3 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w3.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w3.rawCons[0]))
  let l4 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w4.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w4.rawCons[0]))
  let l5 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w5.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w5.rawCons[0]))
  let l6 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w6.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w6.rawCons[0]))
  var sortNames = @[ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T1).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T2).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T3).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T4).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T5).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T6).cstring)]
  var sortsOut = newSeq[RawZ3Sort](6)
  var lists = @[l1, l2, l3, l4, l5, l6]
  ctx.checkErrVoid Z3_mk_datatypes(ctx.raw, 6, cast[ptr UncheckedArray[RawZ3Symbol]](addr sortNames[0]), cast[ptr UncheckedArray[RawZ3Sort]](addr sortsOut[0]), cast[ptr UncheckedArray[RawZ3ConstructorList]](addr lists[0]))
  let c1 = queryConstructorsInto[T1](ctx, d1.cons, w1.rawCons)
  let c2 = queryConstructorsInto[T2](ctx, d2.cons, w2.rawCons)
  let c3 = queryConstructorsInto[T3](ctx, d3.cons, w3.rawCons)
  let c4 = queryConstructorsInto[T4](ctx, d4.cons, w4.rawCons)
  let c5 = queryConstructorsInto[T5](ctx, d5.cons, w5.rawCons)
  let c6 = queryConstructorsInto[T6](ctx, d6.cons, w6.rawCons)
  Z3_del_constructor_list(ctx.raw, l1); Z3_del_constructor_list(ctx.raw, l2)
  Z3_del_constructor_list(ctx.raw, l3); Z3_del_constructor_list(ctx.raw, l4)
  Z3_del_constructor_list(ctx.raw, l5); Z3_del_constructor_list(ctx.raw, l6)
  ctx.datatypeRegistry[$T1] = sortsOut[0]; ctx.datatypeRegistry[$T2] = sortsOut[1]
  ctx.datatypeRegistry[$T3] = sortsOut[2]; ctx.datatypeRegistry[$T4] = sortsOut[3]
  ctx.datatypeRegistry[$T5] = sortsOut[4]; ctx.datatypeRegistry[$T6] = sortsOut[5]
  (Z3DatatypeDecl[T1](ctx: ctx, sort: sortsOut[0], cons: c1),
   Z3DatatypeDecl[T2](ctx: ctx, sort: sortsOut[1], cons: c2),
   Z3DatatypeDecl[T3](ctx: ctx, sort: sortsOut[2], cons: c3),
   Z3DatatypeDecl[T4](ctx: ctx, sort: sortsOut[3], cons: c4),
   Z3DatatypeDecl[T5](ctx: ctx, sort: sortsOut[4], cons: c5),
   Z3DatatypeDecl[T6](ctx: ctx, sort: sortsOut[5], cons: c6))

proc declareDatatypes*[T1, T2, T3, T4, T5, T6](
    d1: DatatypeSpec[T1], d2: DatatypeSpec[T2], d3: DatatypeSpec[T3],
    d4: DatatypeSpec[T4], d5: DatatypeSpec[T5], d6: DatatypeSpec[T6]):
    (Z3DatatypeDecl[T1], Z3DatatypeDecl[T2], Z3DatatypeDecl[T3],
     Z3DatatypeDecl[T4], Z3DatatypeDecl[T5], Z3DatatypeDecl[T6]) =
  declareDatatypes(requireCurrentContext(), d1, d2, d3, d4, d5, d6)

proc declareDatatypes*[T1, T2, T3, T4, T5, T6, T7](
    ctx: Z3Context,
    d1: DatatypeSpec[T1], d2: DatatypeSpec[T2], d3: DatatypeSpec[T3],
    d4: DatatypeSpec[T4], d5: DatatypeSpec[T5], d6: DatatypeSpec[T6],
    d7: DatatypeSpec[T7]):
    (Z3DatatypeDecl[T1], Z3DatatypeDecl[T2], Z3DatatypeDecl[T3],
     Z3DatatypeDecl[T4], Z3DatatypeDecl[T5], Z3DatatypeDecl[T6],
     Z3DatatypeDecl[T7]) =
  var nameToIdx = initTable[string, int]()
  nameToIdx[$T1] = 0; nameToIdx[$T2] = 1; nameToIdx[$T3] = 2
  nameToIdx[$T4] = 3; nameToIdx[$T5] = 4; nameToIdx[$T6] = 5
  nameToIdx[$T7] = 6
  var w1 = buildRawConstructors(ctx, d1.cons, 0, nameToIdx)
  var w2 = buildRawConstructors(ctx, d2.cons, 1, nameToIdx)
  var w3 = buildRawConstructors(ctx, d3.cons, 2, nameToIdx)
  var w4 = buildRawConstructors(ctx, d4.cons, 3, nameToIdx)
  var w5 = buildRawConstructors(ctx, d5.cons, 4, nameToIdx)
  var w6 = buildRawConstructors(ctx, d6.cons, 5, nameToIdx)
  var w7 = buildRawConstructors(ctx, d7.cons, 6, nameToIdx)
  doAssert w1.rawCons.len > 0, "declareDatatypes: " & $T1 & " has zero constructors"
  doAssert w2.rawCons.len > 0, "declareDatatypes: " & $T2 & " has zero constructors"
  doAssert w3.rawCons.len > 0, "declareDatatypes: " & $T3 & " has zero constructors"
  doAssert w4.rawCons.len > 0, "declareDatatypes: " & $T4 & " has zero constructors"
  doAssert w5.rawCons.len > 0, "declareDatatypes: " & $T5 & " has zero constructors"
  doAssert w6.rawCons.len > 0, "declareDatatypes: " & $T6 & " has zero constructors"
  doAssert w7.rawCons.len > 0, "declareDatatypes: " & $T7 & " has zero constructors"
  let l1 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w1.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w1.rawCons[0]))
  let l2 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w2.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w2.rawCons[0]))
  let l3 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w3.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w3.rawCons[0]))
  let l4 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w4.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w4.rawCons[0]))
  let l5 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w5.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w5.rawCons[0]))
  let l6 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w6.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w6.rawCons[0]))
  let l7 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w7.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w7.rawCons[0]))
  var sortNames = @[ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T1).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T2).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T3).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T4).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T5).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T6).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T7).cstring)]
  var sortsOut = newSeq[RawZ3Sort](7)
  var lists = @[l1, l2, l3, l4, l5, l6, l7]
  ctx.checkErrVoid Z3_mk_datatypes(ctx.raw, 7, cast[ptr UncheckedArray[RawZ3Symbol]](addr sortNames[0]), cast[ptr UncheckedArray[RawZ3Sort]](addr sortsOut[0]), cast[ptr UncheckedArray[RawZ3ConstructorList]](addr lists[0]))
  let c1 = queryConstructorsInto[T1](ctx, d1.cons, w1.rawCons)
  let c2 = queryConstructorsInto[T2](ctx, d2.cons, w2.rawCons)
  let c3 = queryConstructorsInto[T3](ctx, d3.cons, w3.rawCons)
  let c4 = queryConstructorsInto[T4](ctx, d4.cons, w4.rawCons)
  let c5 = queryConstructorsInto[T5](ctx, d5.cons, w5.rawCons)
  let c6 = queryConstructorsInto[T6](ctx, d6.cons, w6.rawCons)
  let c7 = queryConstructorsInto[T7](ctx, d7.cons, w7.rawCons)
  Z3_del_constructor_list(ctx.raw, l1); Z3_del_constructor_list(ctx.raw, l2)
  Z3_del_constructor_list(ctx.raw, l3); Z3_del_constructor_list(ctx.raw, l4)
  Z3_del_constructor_list(ctx.raw, l5); Z3_del_constructor_list(ctx.raw, l6)
  Z3_del_constructor_list(ctx.raw, l7)
  ctx.datatypeRegistry[$T1] = sortsOut[0]; ctx.datatypeRegistry[$T2] = sortsOut[1]
  ctx.datatypeRegistry[$T3] = sortsOut[2]; ctx.datatypeRegistry[$T4] = sortsOut[3]
  ctx.datatypeRegistry[$T5] = sortsOut[4]; ctx.datatypeRegistry[$T6] = sortsOut[5]
  ctx.datatypeRegistry[$T7] = sortsOut[6]
  (Z3DatatypeDecl[T1](ctx: ctx, sort: sortsOut[0], cons: c1),
   Z3DatatypeDecl[T2](ctx: ctx, sort: sortsOut[1], cons: c2),
   Z3DatatypeDecl[T3](ctx: ctx, sort: sortsOut[2], cons: c3),
   Z3DatatypeDecl[T4](ctx: ctx, sort: sortsOut[3], cons: c4),
   Z3DatatypeDecl[T5](ctx: ctx, sort: sortsOut[4], cons: c5),
   Z3DatatypeDecl[T6](ctx: ctx, sort: sortsOut[5], cons: c6),
   Z3DatatypeDecl[T7](ctx: ctx, sort: sortsOut[6], cons: c7))

proc declareDatatypes*[T1, T2, T3, T4, T5, T6, T7](
    d1: DatatypeSpec[T1], d2: DatatypeSpec[T2], d3: DatatypeSpec[T3],
    d4: DatatypeSpec[T4], d5: DatatypeSpec[T5], d6: DatatypeSpec[T6],
    d7: DatatypeSpec[T7]):
    (Z3DatatypeDecl[T1], Z3DatatypeDecl[T2], Z3DatatypeDecl[T3],
     Z3DatatypeDecl[T4], Z3DatatypeDecl[T5], Z3DatatypeDecl[T6],
     Z3DatatypeDecl[T7]) =
  declareDatatypes(requireCurrentContext(), d1, d2, d3, d4, d5, d6, d7)

proc declareDatatypes*[T1, T2, T3, T4, T5, T6, T7, T8](
    ctx: Z3Context,
    d1: DatatypeSpec[T1], d2: DatatypeSpec[T2], d3: DatatypeSpec[T3],
    d4: DatatypeSpec[T4], d5: DatatypeSpec[T5], d6: DatatypeSpec[T6],
    d7: DatatypeSpec[T7], d8: DatatypeSpec[T8]):
    (Z3DatatypeDecl[T1], Z3DatatypeDecl[T2], Z3DatatypeDecl[T3],
     Z3DatatypeDecl[T4], Z3DatatypeDecl[T5], Z3DatatypeDecl[T6],
     Z3DatatypeDecl[T7], Z3DatatypeDecl[T8]) =
  var nameToIdx = initTable[string, int]()
  nameToIdx[$T1] = 0; nameToIdx[$T2] = 1; nameToIdx[$T3] = 2
  nameToIdx[$T4] = 3; nameToIdx[$T5] = 4; nameToIdx[$T6] = 5
  nameToIdx[$T7] = 6; nameToIdx[$T8] = 7
  var w1 = buildRawConstructors(ctx, d1.cons, 0, nameToIdx)
  var w2 = buildRawConstructors(ctx, d2.cons, 1, nameToIdx)
  var w3 = buildRawConstructors(ctx, d3.cons, 2, nameToIdx)
  var w4 = buildRawConstructors(ctx, d4.cons, 3, nameToIdx)
  var w5 = buildRawConstructors(ctx, d5.cons, 4, nameToIdx)
  var w6 = buildRawConstructors(ctx, d6.cons, 5, nameToIdx)
  var w7 = buildRawConstructors(ctx, d7.cons, 6, nameToIdx)
  var w8 = buildRawConstructors(ctx, d8.cons, 7, nameToIdx)
  doAssert w1.rawCons.len > 0, "declareDatatypes: " & $T1 & " has zero constructors"
  doAssert w2.rawCons.len > 0, "declareDatatypes: " & $T2 & " has zero constructors"
  doAssert w3.rawCons.len > 0, "declareDatatypes: " & $T3 & " has zero constructors"
  doAssert w4.rawCons.len > 0, "declareDatatypes: " & $T4 & " has zero constructors"
  doAssert w5.rawCons.len > 0, "declareDatatypes: " & $T5 & " has zero constructors"
  doAssert w6.rawCons.len > 0, "declareDatatypes: " & $T6 & " has zero constructors"
  doAssert w7.rawCons.len > 0, "declareDatatypes: " & $T7 & " has zero constructors"
  doAssert w8.rawCons.len > 0, "declareDatatypes: " & $T8 & " has zero constructors"
  let l1 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w1.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w1.rawCons[0]))
  let l2 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w2.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w2.rawCons[0]))
  let l3 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w3.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w3.rawCons[0]))
  let l4 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w4.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w4.rawCons[0]))
  let l5 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w5.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w5.rawCons[0]))
  let l6 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w6.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w6.rawCons[0]))
  let l7 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w7.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w7.rawCons[0]))
  let l8 = ctx.checkErr Z3_mk_constructor_list(ctx.raw, cuint(w8.rawCons.len), cast[ptr UncheckedArray[RawZ3Constructor]](addr w8.rawCons[0]))
  var sortNames = @[ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T1).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T2).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T3).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T4).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T5).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T6).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T7).cstring), ctx.checkErr Z3_mk_string_symbol(ctx.raw, ($T8).cstring)]
  var sortsOut = newSeq[RawZ3Sort](8)
  var lists = @[l1, l2, l3, l4, l5, l6, l7, l8]
  ctx.checkErrVoid Z3_mk_datatypes(ctx.raw, 8, cast[ptr UncheckedArray[RawZ3Symbol]](addr sortNames[0]), cast[ptr UncheckedArray[RawZ3Sort]](addr sortsOut[0]), cast[ptr UncheckedArray[RawZ3ConstructorList]](addr lists[0]))
  let c1 = queryConstructorsInto[T1](ctx, d1.cons, w1.rawCons)
  let c2 = queryConstructorsInto[T2](ctx, d2.cons, w2.rawCons)
  let c3 = queryConstructorsInto[T3](ctx, d3.cons, w3.rawCons)
  let c4 = queryConstructorsInto[T4](ctx, d4.cons, w4.rawCons)
  let c5 = queryConstructorsInto[T5](ctx, d5.cons, w5.rawCons)
  let c6 = queryConstructorsInto[T6](ctx, d6.cons, w6.rawCons)
  let c7 = queryConstructorsInto[T7](ctx, d7.cons, w7.rawCons)
  let c8 = queryConstructorsInto[T8](ctx, d8.cons, w8.rawCons)
  Z3_del_constructor_list(ctx.raw, l1); Z3_del_constructor_list(ctx.raw, l2)
  Z3_del_constructor_list(ctx.raw, l3); Z3_del_constructor_list(ctx.raw, l4)
  Z3_del_constructor_list(ctx.raw, l5); Z3_del_constructor_list(ctx.raw, l6)
  Z3_del_constructor_list(ctx.raw, l7); Z3_del_constructor_list(ctx.raw, l8)
  ctx.datatypeRegistry[$T1] = sortsOut[0]; ctx.datatypeRegistry[$T2] = sortsOut[1]
  ctx.datatypeRegistry[$T3] = sortsOut[2]; ctx.datatypeRegistry[$T4] = sortsOut[3]
  ctx.datatypeRegistry[$T5] = sortsOut[4]; ctx.datatypeRegistry[$T6] = sortsOut[5]
  ctx.datatypeRegistry[$T7] = sortsOut[6]; ctx.datatypeRegistry[$T8] = sortsOut[7]
  (Z3DatatypeDecl[T1](ctx: ctx, sort: sortsOut[0], cons: c1),
   Z3DatatypeDecl[T2](ctx: ctx, sort: sortsOut[1], cons: c2),
   Z3DatatypeDecl[T3](ctx: ctx, sort: sortsOut[2], cons: c3),
   Z3DatatypeDecl[T4](ctx: ctx, sort: sortsOut[3], cons: c4),
   Z3DatatypeDecl[T5](ctx: ctx, sort: sortsOut[4], cons: c5),
   Z3DatatypeDecl[T6](ctx: ctx, sort: sortsOut[5], cons: c6),
   Z3DatatypeDecl[T7](ctx: ctx, sort: sortsOut[6], cons: c7),
   Z3DatatypeDecl[T8](ctx: ctx, sort: sortsOut[7], cons: c8))

proc declareDatatypes*[T1, T2, T3, T4, T5, T6, T7, T8](
    d1: DatatypeSpec[T1], d2: DatatypeSpec[T2], d3: DatatypeSpec[T3],
    d4: DatatypeSpec[T4], d5: DatatypeSpec[T5], d6: DatatypeSpec[T6],
    d7: DatatypeSpec[T7], d8: DatatypeSpec[T8]):
    (Z3DatatypeDecl[T1], Z3DatatypeDecl[T2], Z3DatatypeDecl[T3],
     Z3DatatypeDecl[T4], Z3DatatypeDecl[T5], Z3DatatypeDecl[T6],
     Z3DatatypeDecl[T7], Z3DatatypeDecl[T8]) =
  declareDatatypes(requireCurrentContext(), d1, d2, d3, d4, d5, d6, d7, d8)

# declareDatatypesN — runtime-N seq-form escape hatch.
# Uses `void` as the phantom type; all constructors are accessible via
# `con`, `recognizer`, `accessor` with no compile-time sort guarantees.
# This is useful for dynamically-built datatype families where the number
# of sorts isn't known at compile time.

proc declareDatatypesN*(
    ctx: Z3Context,
    specs: openArray[(string, seq[ConstructorSpec])]): seq[Z3DatatypeDecl[void]] =
  ## Declare N mutually-recursive datatypes given as `(sortName, constructors)`
  ## pairs. Returns a `seq[Z3DatatypeDecl[void]]` of the same length.
  ##
  ## This is the escape hatch when the number of datatypes isn't known at
  ## compile time. The `void` phantom provides no type-level sort tracking;
  ## use the typed `declareDatatypes` overloads when possible.
  let n = specs.len
  doAssert n >= 1, "declareDatatypesN: must have at least one datatype"
  # Build nameToIdx from the sort names
  var nameToIdx = initTable[string, int]()
  for i, (sname, _) in specs:
    nameToIdx[sname] = i
  # Build raw constructors for each spec
  var works = newSeq[RawConsWork](n)
  for i, (_, cons) in specs:
    works[i] = buildRawConstructors(ctx, cons, i, nameToIdx)
    doAssert works[i].rawCons.len > 0,
      "declareDatatypesN: spec[" & $i & "] has zero constructors"
  # Build constructor lists
  var lists = newSeq[RawZ3ConstructorList](n)
  for i in 0 ..< n:
    lists[i] = ctx.checkErr Z3_mk_constructor_list(ctx.raw,
      cuint(works[i].rawCons.len),
      cast[ptr UncheckedArray[RawZ3Constructor]](addr works[i].rawCons[0]))
  # Build sort name symbols
  var sortNames = newSeq[RawZ3Symbol](n)
  for i, (sname, _) in specs:
    sortNames[i] = ctx.checkErr Z3_mk_string_symbol(ctx.raw, sname.cstring)
  var sortsOut = newSeq[RawZ3Sort](n)
  ctx.checkErrVoid Z3_mk_datatypes(ctx.raw, cuint(n),
    cast[ptr UncheckedArray[RawZ3Symbol]](addr sortNames[0]),
    cast[ptr UncheckedArray[RawZ3Sort]](addr sortsOut[0]),
    cast[ptr UncheckedArray[RawZ3ConstructorList]](addr lists[0]))
  # Extract constructor func_decls and build results
  result = newSeq[Z3DatatypeDecl[void]](n)
  for i, (sname, cons) in specs:
    let conRefs = queryConstructorsInto[void](ctx, cons, works[i].rawCons)
    result[i] = Z3DatatypeDecl[void](ctx: ctx, sort: sortsOut[i], cons: conRefs)
    ctx.datatypeRegistry[sname] = sortsOut[i]
  # Clean up constructor lists
  for i in 0 ..< n:
    Z3_del_constructor_list(ctx.raw, lists[i])

# ============================================================================
# Lookup — con, recognizer, accessor
# ============================================================================

proc findCon[T](
    dt: Z3DatatypeDecl[T], cname: string): Z3ConstructorDeclRef[T] =
  for c in dt.cons:
    if c.cname == cname:
      return c
  raise newException(Z3InvalidUsageError,
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
    raise newException(Z3InvalidUsageError,
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
# updateField — functional record update (N7.4)
# ============================================================================
#
# `Z3_datatype_update_field(c, field_access, t, value)` returns a copy of
# the datatype value `t` in which the field identified by the accessor
# func_decl `field_access` has been replaced by `value`; all other fields
# are unchanged.  The Z3 SMT-LIB encoding is
#   `((_ update-field <accessor>) <record> <newval>)`.
#
# We resolve the accessor func_decl from the `Z3AccessorDecl[T, Ret]` using
# the same linear walk as `readRawAccessor`, keeping implementation flat.

proc updateField*[T, Ret](
    a: Z3AccessorDecl[T, Ret],
    record: Z3DatatypeValue[T],
    newVal: Ret): Z3DatatypeValue[T] =
  ## Functional record update: return `{record with <field> = newVal}`.
  ##
  ## `a` is the accessor for the field to update; `Ret` is the field's
  ## sort (same type as `a.read(record)` returns).  All other fields of
  ## `record` are preserved unchanged in the result.
  ##
  ## Wraps `Z3_datatype_update_field`.
  let ctx = a.inner.ctx
  var fd: RawZ3FuncDecl
  for (fname2, decl) in a.inner.accessorsFD:
    if fname2 == a.fname:
      fd = decl
      break
  let raw = ctx.checkErr Z3_datatype_update_field(ctx.raw, fd,
                                                   record.raw, newVal.raw)
  wrap[Z3DatatypeValue[T]](ctx, raw)

# ============================================================================
# Datatype sort introspection (N2.3)
# ============================================================================
#
# These four procs expose the Z3 "sort-level" view of a declared
# datatype: how many constructors it has, and what func_decl Z3 assigned
# to each constructor / recognizer / accessor slot.  The returned
# `RawZ3FuncDecl` handles are borrowed — Z3 owns them through the sort's
# lifetime — so callers must not store them beyond the `Z3DatatypeDecl`.
#
# These complement the *name-keyed* `con` / `recognizer` / `accessor`
# procs above (which walk the Nim-side func_decl cache). The index-keyed
# introspection surface goes directly to Z3's sort-level API, which is
# the ground truth for what the solver actually resolved.

proc numConstructors*[T](dt: Z3DatatypeDecl[T]): int =
  ## Number of constructors in the datatype sort as reported by Z3.
  ## For a type declared with N `ConstructorSpec` entries this is always N;
  ## the proc is useful when operating on a `Z3DatatypeDecl[void]` from
  ## `declareDatatypesN`, where the count isn't statically known.
  int(Z3_get_datatype_sort_num_constructors(dt.ctx.raw, dt.sort))

proc constructor*[T](dt: Z3DatatypeDecl[T], i: int): RawZ3FuncDecl =
  ## Return the `i`-th constructor func_decl (0-based).
  ## Raises `Z3Error` if `i` is out of range.
  let n = numConstructors(dt)
  if i < 0 or i >= n:
    raise newException(Z3InvalidUsageError,
      "constructor: index " & $i & " out of range [0, " & $n & ")")
  Z3_get_datatype_sort_constructor(dt.ctx.raw, dt.sort, cuint(i))

proc recognizer*[T](dt: Z3DatatypeDecl[T], i: int): RawZ3FuncDecl =
  ## Return the `i`-th recognizer func_decl (0-based).
  ## Overloads the existing `recognizer(dt, cname)` name; the int
  ## vs string argument disambiguates.
  let n = numConstructors(dt)
  if i < 0 or i >= n:
    raise newException(Z3InvalidUsageError,
      "recognizer: index " & $i & " out of range [0, " & $n & ")")
  Z3_get_datatype_sort_recognizer(dt.ctx.raw, dt.sort, cuint(i))

proc constructorAccessor*[T](dt: Z3DatatypeDecl[T], ctor: int,
                              accessor: int): RawZ3FuncDecl =
  ## Return the `accessor`-th accessor of the `ctor`-th constructor.
  ## Both indices are 0-based. Raises `Z3Error` if either is out of range.
  let n = numConstructors(dt)
  if ctor < 0 or ctor >= n:
    raise newException(Z3InvalidUsageError,
      "constructorAccessor: ctor index " & $ctor & " out of range [0, " & $n & ")")
  # No Nim-side bound check on `accessor` — Z3's own pre-condition fires
  # (the arity of constructor `ctor` isn't easily accessible from the decl
  # without an extra Z3 call); an out-of-range `accessor` will trip Z3's
  # internal assert via the error handler in checkErr.
  Z3_get_datatype_sort_constructor_accessor(dt.ctx.raw, dt.sort,
                                            cuint(ctor), cuint(accessor))

# ============================================================================
# mkEnumerationSort — Z3_mk_enumeration_sort convenience wrapper (N7.1)
# ============================================================================
#
# `Z3_mk_enumeration_sort` is a Z3 convenience that builds a single-level
# enumeration datatype (no accessor fields, all constructors nullary) in one
# call, without going through the full `mk_constructor` / `mk_datatype`
# machinery.  It returns the sort directly and fills two caller-allocated
# output arrays: one of nullary constructor func_decls and one of unary
# tester (recognizer) func_decls.
#
# We expose this at the raw level — same policy as the rest of `datatypes.nim`
# for its low-level surface — returning a named tuple so callers can
# destructure with `let (sort, consts, testers) = mkEnumerationSort(...)`.

proc mkEnumerationSort*(
    ctx: Z3Context,
    name: string,
    members: openArray[string]
): tuple[sort: RawZ3Sort,
         consts: seq[RawZ3FuncDecl],
         testers: seq[RawZ3FuncDecl]] =
  ## Build a named enumeration sort from `members`.
  ##
  ## Returns the Z3 sort, a seq of nullary constructor func_decls (one per
  ## member, in order), and a seq of unary tester (recognizer) func_decls.
  ## All func_decls are owned by Z3 through the sort's (context's) lifetime;
  ## callers must not `Z3_dec_ref` them independently.
  ##
  ## Example:
  ## ```nim
  ## let (colorSort, consts, testers) =
  ##   mkEnumerationSort(ctx, "Color", @["Red", "Green", "Blue"])
  ## ```
  let n = members.len
  doAssert n >= 1, "mkEnumerationSort: must have at least one member"

  # Build symbol array for member names
  var nameSyms = newSeq[RawZ3Symbol](n)
  for i, m in members:
    nameSyms[i] = ctx.checkErr Z3_mk_string_symbol(ctx.raw, m.cstring)

  # Pre-allocate output arrays — Z3 fills these in place
  var constsOut = newSeq[RawZ3FuncDecl](n)
  var testersOut = newSeq[RawZ3FuncDecl](n)

  let sortSym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)
  let sort = ctx.checkErr Z3_mk_enumeration_sort(ctx.raw, sortSym, cuint(n),
    cast[ptr UncheckedArray[RawZ3Symbol]](addr nameSyms[0]),
    cast[ptr UncheckedArray[RawZ3FuncDecl]](addr constsOut[0]),
    cast[ptr UncheckedArray[RawZ3FuncDecl]](addr testersOut[0]))

  # Z3 starts the returned func_decls at refcount 0; inc_ref them now so
  # they survive until the caller is done. The caller holds them as plain
  # `RawZ3FuncDecl` values — no destructor fires on the seq elements —
  # so we do a single balanced inc_ref here. The func_decls remain live
  # as long as the sort/context is alive, which is the expected contract.
  for fd in constsOut:
    incRefFuncDecl(ctx, fd)
  for fd in testersOut:
    incRefFuncDecl(ctx, fd)

  (sort: sort, consts: constsOut, testers: testersOut)

proc mkEnumerationSort*(
    name: string,
    members: openArray[string]
): tuple[sort: RawZ3Sort,
         consts: seq[RawZ3FuncDecl],
         testers: seq[RawZ3FuncDecl]] =
  ## Context-free overload; uses `requireCurrentContext()`.
  mkEnumerationSort(requireCurrentContext(), name, members)

# ============================================================================
# mkTupleSort — Z3_mk_tuple_sort convenience wrapper (N7.2)
# ============================================================================
#
# `Z3_mk_tuple_sort` is a Z3 convenience that builds a product (tuple) sort
# in one call, without going through the full `mk_constructor` / `mk_datatype`
# machinery. It returns the sort directly and fills two caller-allocated
# output args: the constructor func_decl and an array of projection func_decls.
#
# Lifecycle: same as N7.1. Z3 emits the constructor and all projection
# func_decls at refcount 0; we `incRefFuncDecl` each one before returning so
# they stay live for as long as the caller holds the returned seqs.

proc mkTupleSort*(
    ctx: Z3Context,
    name: string,
    fields: openArray[(string, RawZ3Sort)]
): tuple[sort: RawZ3Sort, ctor: RawZ3FuncDecl, projs: seq[RawZ3FuncDecl]] =
  ## Build a named tuple sort with the given `(fieldName, fieldSort)` pairs.
  ##
  ## Returns the Z3 sort, the constructor func_decl, and a seq of projection
  ## func_decls in field order. All func_decls are `inc_ref`'d before return
  ## so they live as long as the caller holds the returned values.
  ##
  ## Example:
  ## ```nim
  ## let intS = ctx.checkErr Z3_mk_int_sort(ctx.raw)
  ## let (sort, ctor, projs) =
  ##   mkTupleSort(ctx, "Point", [("x", intS), ("y", intS)])
  ## ```
  let n = fields.len

  # Build symbol array for field names
  var fieldNameSyms = newSeq[RawZ3Symbol](n)
  var fieldSorts = newSeq[RawZ3Sort](n)
  for i, (fname, fsort) in fields:
    fieldNameSyms[i] = ctx.checkErr Z3_mk_string_symbol(ctx.raw, fname.cstring)
    fieldSorts[i] = fsort

  # Pre-allocate output for the constructor and projection func_decls
  var ctorOut: RawZ3FuncDecl
  var projsOut = newSeq[RawZ3FuncDecl](n)

  let nameSym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)

  let fieldNamesPtr =
    if n > 0: cast[ptr UncheckedArray[RawZ3Symbol]](addr fieldNameSyms[0])
    else: nil
  let fieldSortsPtr =
    if n > 0: cast[ptr UncheckedArray[RawZ3Sort]](addr fieldSorts[0])
    else: nil
  let projsPtr =
    if n > 0: cast[ptr UncheckedArray[RawZ3FuncDecl]](addr projsOut[0])
    else: nil

  let sort = ctx.checkErr Z3_mk_tuple_sort(ctx.raw, nameSym, cuint(n),
    fieldNamesPtr, fieldSortsPtr, addr ctorOut, projsPtr)

  # Z3 emits func_decls at refcount 0; inc_ref them now.
  incRefFuncDecl(ctx, ctorOut)
  for fd in projsOut:
    incRefFuncDecl(ctx, fd)

  (sort: sort, ctor: ctorOut, projs: projsOut)

proc mkTupleSort*(
    name: string,
    fields: openArray[(string, RawZ3Sort)]
): tuple[sort: RawZ3Sort, ctor: RawZ3FuncDecl, projs: seq[RawZ3FuncDecl]] =
  ## Context-free overload; uses `requireCurrentContext()`.
  mkTupleSort(requireCurrentContext(), name, fields)

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

proc `$`*[T](v: Z3DatatypeValue[T]): string = termToSmt2(v)
  ## SMT-LIB rendering of the datatype value AST.

# ============================================================================
# Datatype-sorted variables
# ============================================================================

proc mkDatatypeVar*[T](
    dt: Z3DatatypeDecl[T], name: string): Z3DatatypeValue[T] =
  ## Free variable of the datatype sort.
  let sym = dt.ctx.checkErr Z3_mk_string_symbol(dt.ctx.raw, name.cstring)
  wrap[Z3DatatypeValue[T]](dt.ctx, dt.ctx.checkErr Z3_mk_const(dt.ctx.raw, sym, dt.sort))

proc mkDatatypeVar*[T](name: string): Z3DatatypeValue[T] =
  ## Registry-based overload (N7.5). Mirrors `mkUninterpretedVar[T](name)` from
  ## N1.3. Uses `requireCurrentContext()` and looks up the sort via
  ## `ctx.datatypeRegistry[$T]`. The datatype must have been declared in the
  ## current context before calling this.
  let ctx = requireCurrentContext()
  let sort = sortOf(Z3DatatypeValue[T], ctx)
  let sym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)
  wrap[Z3DatatypeValue[T]](ctx, ctx.checkErr Z3_mk_const(ctx.raw, sym, sort))

proc readRaw*[T](
    dt: Z3DatatypeDecl[T], cname, fname: string,
    v: Z3DatatypeValue[T]): RawZ3Ast =
  ## Raw-handle escape hatch (N7.5). Applies the accessor for field `fname`
  ## of constructor `cname` to `v`, returning the result as a `RawZ3Ast`.
  ##
  ## Useful when the `Ret` type cannot be inferred statically (e.g. in
  ## generic dispatch or dynamic tooling). The caller is responsible for
  ## wrapping the result with the appropriate typed wrapper (`wrap[Z3Int]`,
  ## etc.).
  ##
  ## Raises `Z3InvalidUsageError` if `cname` or `fname` is not found.
  let inner = findCon(dt, cname)
  var fd: RawZ3FuncDecl
  for (fname2, decl) in inner.accessorsFD:
    if fname2 == fname:
      fd = decl
      break
  if fd.isNil:
    raise newException(Z3InvalidUsageError,
      "readRaw: datatype " & $T & ": constructor '" & cname &
      "' has no field '" & fname & "'")
  var arg = v.raw
  dt.ctx.checkErr Z3_mk_app(dt.ctx.raw, fd, 1,
    cast[ptr UncheckedArray[RawZ3Ast]](addr arg))

## `z3/funcdecl` — uninterpreted function declarations.
##
## `Z3FuncDecl[ArgsTup, Ret]` is a phantom-typed handle to an
## uninterpreted function. The `ArgsTup` tuple captures arity + per-
## position element type; `Ret` captures the return type. The wrapper
## generates per-arity `apply` overloads and `()` callable hooks so
## users can write `f(x, y)` naturally:
##
## ```nim
## let f = mkFuncDecl[(Z3Int, Z3Int), Z3Bool]("f")
## let g = mkFuncDecl[(Z3Int,), Z3Int]("g")
## let h = mkFuncDecl[(), Z3Int]("h")    # constant (nullary)
##
## s.add f(g(mkInt(0)), mkInt(1))         # binary application
## s.add g(h()) == mkInt(42)              # composed; nullary call
## ```
##
## ## Model extraction
##
## For "what value does f take at this specific argument?" use
## `evalAt(m, f, args)` — it composes `f.apply(args)` and
## `m.eval(...)`. The full tabular-interpretation surface
## (`Z3FuncInterp[ArgsTup, Ret]` with explicit `(args, value)`
## entries plus an `elseValue`) lives in the same module — see
## `getFuncInterp(m, f)` below and `tests/tfuncinterp.nim` for
## the working pattern. v0.5 step 6A.
##
## ## Arity
##
## Per-arity overloads ship for **0 through 6 arguments**. Larger
## arities are rare in practice; bumping the ceiling is one macro
## line per new arity if a user needs it.

{.experimental: "callOperator".}

import std/[macros]
import ./ffi, ./context, ./error, ./ast, ./sortdispatch, ./arrays, ./bitvec, ./chars,
       ./sequence, ./strings, ./fp, ./model
# The leaf-family imports are intentional: funcdecl's domainSorts
# iterates an arbitrary tuple at compile time, and `sortOfType[FieldT]`
# resolves through `mixin sortOf` at the iteration site (which is
# inside this module). So every family whose `sortOf` overload we want
# reachable from a `Z3FuncDecl[…]` signature must be imported here.

# v0.3 step 9 dropped the local `sortOfType` cascade — every typed
# family now owns its `sortOf` overload via `z3/sortdispatch`.

# ============================================================================
# Z3FuncDecl[ArgsTup, Ret] — phantom-typed function declaration
# ============================================================================

type
  Z3FuncDeclOwn[ArgsTup: tuple, Ret] = object
    raw: RawZ3FuncDecl
    ctx: Z3Context
  Z3FuncDecl*[ArgsTup: tuple, Ret] = ref Z3FuncDeclOwn[ArgsTup, Ret]
    ## Ref-typed handle (parallel to `Z3Solver`, `Z3Model`, etc.).
    ## The phantom tuple `ArgsTup` captures the domain element types
    ## positionally; `Ret` is the codomain.

proc raw*[ArgsTup: tuple, Ret](
    f: Z3FuncDecl[ArgsTup, Ret]): RawZ3FuncDecl {.inline.} = f.raw
proc ctx*[ArgsTup: tuple, Ret](
    f: Z3FuncDecl[ArgsTup, Ret]): Z3Context {.inline.} = f.ctx
  ## Underlying-handle accessors — used by sibling modules (notably
  ## `z3/fixedpoint` for `registerRelation` / `addFact` / cover ops)
  ## that need to thread the raw func_decl into Z3 calls.

# ----------------------------------------------------------------------------
# Refcount discipline
# ----------------------------------------------------------------------------
# Z3 refcounts func_decls through `Z3_func_decl_to_ast` + the AST
# refcount pair, same pattern datatypes.nim already uses. We don't go
# through the lifecycle stampers because the dec_ref needs the
# `_to_ast` round-trip.

proc decRefFD(ctx: Z3Context, fd: RawZ3FuncDecl) {.raises: [].} =
  if fd.isNil or ctx == nil or ctx.raw.isNil: return
  try:
    let asAst = Z3_func_decl_to_ast(ctx.raw, fd)
    if not asAst.isNil:
      Z3_dec_ref(ctx.raw, asAst)
  except CatchableError:
    discard

proc incRefFD(ctx: Z3Context, fd: RawZ3FuncDecl) {.raises: [].} =
  if fd.isNil or ctx == nil or ctx.raw.isNil: return
  try:
    let asAst = Z3_func_decl_to_ast(ctx.raw, fd)
    if not asAst.isNil:
      Z3_inc_ref(ctx.raw, asAst)
  except CatchableError:
    discard

proc `=destroy`[ArgsTup: tuple, Ret](v: Z3FuncDeclOwn[ArgsTup, Ret])
    {.raises: [].} =
  decRefFD(v.ctx, v.raw)

# ============================================================================
# Construction
# ============================================================================

proc domainSorts[ArgsTup: tuple](ctx: Z3Context): system.seq[RawZ3Sort] =
  ## Walk the tuple's field types at compile time, collecting their
  ## Z3 sort handles. Uses `default(T)` zero-init + `fields()` macro
  ## for static iteration. Qualified `system.seq` to avoid shadowing
  ## by the `z3/sequence` module import.
  result = newSeq[RawZ3Sort]()
  var t: ArgsTup
  for field in fields(t):
    result.add sortOfType[typeof(field)](ctx)

proc mkFuncDecl*[ArgsTup: tuple, Ret](
    ctx: Z3Context, name: string): Z3FuncDecl[ArgsTup, Ret] =
  ## Declare an uninterpreted function `name : ArgsTup → Ret`.
  var domain = domainSorts[ArgsTup](ctx)
  let domainPtr =
    if domain.len == 0: nil
    else: cast[ptr UncheckedArray[RawZ3Sort]](addr domain[0])
  let sym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)
  let rangeSort = sortOfType[Ret](ctx)
  let raw = ctx.checkErr Z3_mk_func_decl(
    ctx.raw, sym, cuint(domain.len), domainPtr, rangeSort)
  result = Z3FuncDecl[ArgsTup, Ret](raw: raw, ctx: ctx)
  incRefFD(ctx, raw)

proc mkFuncDecl*[ArgsTup: tuple, Ret](name: string): Z3FuncDecl[ArgsTup, Ret] =
  mkFuncDecl[ArgsTup, Ret](requireCurrentContext(), name)

# ============================================================================
# defineFun — define a recursive (non-uninterpreted) function. N5.5.
# ============================================================================
#
# `defineFun[A1, Ret](name, body)` creates a `Z3FuncDecl` whose
# interpretation is fixed by the supplied body proc. Internally calls
# `Z3_mk_rec_func_decl` + `Z3_add_rec_def`. The body receives fresh
# typed Z3 constants as its parameters; those constants appear free in
# the returned body AST.
#
# Per-arity overloads for 1..3 arguments (covers all N5.5 tests).
# Body proc type has no explicit CC annotation so Nim's implicit coercion
# from nimcall → closure applies at the call site (works for non-capturing
# and capturing lambdas alike).

proc defineFun*[A1, Ret](
    ctx: Z3Context, name: string,
    body: proc(a1: A1): Ret): Z3FuncDecl[(A1,), Ret] =
  ## Define a unary recursive function `name(a1) = body(a1)`.
  ##
  ## Implementation note: argument constants are created using the same
  ## inline pattern as `mkIntVar` (direct `wrap(ctx, Z3_mk_const(...))`)
  ## to avoid a Nim 2.2 ORC bug where a stored `RawZ3Ast` let-binding is
  ## treated as "moved" and zeroed when passed to a subsequent `wrap` call.
  let domain = [sortOfType[A1](ctx)]
  let domainPtr = cast[ptr UncheckedArray[RawZ3Sort]](unsafeAddr domain[0])
  let rangeSort = sortOfType[Ret](ctx)
  let sym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)
  let raw = ctx.checkErr Z3_mk_rec_func_decl(
    ctx.raw, sym, 1'u32, domainPtr, rangeSort)
  incRefFD(ctx, raw)
  let a1 = wrap[A1](ctx, ctx.checkErr Z3_mk_const(ctx.raw,
    ctx.checkErr Z3_mk_string_symbol(ctx.raw, (name & "_arg0").cstring),
    sortOfType[A1](ctx)))
  let bodyExpr = body(a1)
  var argsArr = [a1.raw]
  Z3_add_rec_def(ctx.raw, raw, 1'u32,
    cast[ptr UncheckedArray[RawZ3Ast]](addr argsArr[0]), bodyExpr.raw)
  Z3FuncDecl[(A1,), Ret](raw: raw, ctx: ctx)

proc defineFun*[A1, Ret](name: string,
    body: proc(a1: A1): Ret): Z3FuncDecl[(A1,), Ret] {.inline.} =
  defineFun[A1, Ret](requireCurrentContext(), name, body)

proc defineFun*[A1, A2, Ret](
    ctx: Z3Context, name: string,
    body: proc(a1: A1, a2: A2): Ret): Z3FuncDecl[(A1, A2), Ret] =
  ## Define a binary recursive function `name(a1, a2) = body(a1, a2)`.
  var domain = [sortOfType[A1](ctx), sortOfType[A2](ctx)]
  let domainPtr = cast[ptr UncheckedArray[RawZ3Sort]](addr domain[0])
  let rangeSort = sortOfType[Ret](ctx)
  let sym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)
  let raw = ctx.checkErr Z3_mk_rec_func_decl(
    ctx.raw, sym, 2'u32, domainPtr, rangeSort)
  incRefFD(ctx, raw)
  # Inline wrap pattern (avoids Nim 2.2 ORC bycopy-move bug — see unary note).
  let a1 = wrap[A1](ctx, ctx.checkErr Z3_mk_const(ctx.raw,
    ctx.checkErr Z3_mk_string_symbol(ctx.raw, (name & "_arg0").cstring),
    sortOfType[A1](ctx)))
  let a2 = wrap[A2](ctx, ctx.checkErr Z3_mk_const(ctx.raw,
    ctx.checkErr Z3_mk_string_symbol(ctx.raw, (name & "_arg1").cstring),
    sortOfType[A2](ctx)))
  let bodyExpr = body(a1, a2)
  var argsArr = [a1.raw, a2.raw]
  Z3_add_rec_def(ctx.raw, raw, 2'u32,
    cast[ptr UncheckedArray[RawZ3Ast]](addr argsArr[0]), bodyExpr.raw)
  Z3FuncDecl[(A1, A2), Ret](raw: raw, ctx: ctx)

proc defineFun*[A1, A2, Ret](name: string,
    body: proc(a1: A1, a2: A2): Ret): Z3FuncDecl[(A1, A2), Ret] {.inline.} =
  defineFun[A1, A2, Ret](requireCurrentContext(), name, body)

proc defineFun*[A1, A2, A3, Ret](
    ctx: Z3Context, name: string,
    body: proc(a1: A1, a2: A2, a3: A3): Ret): Z3FuncDecl[(A1, A2, A3), Ret] =
  ## Define a ternary recursive function `name(a1, a2, a3) = body(...)`.
  var domain = [sortOfType[A1](ctx), sortOfType[A2](ctx),
                sortOfType[A3](ctx)]
  let domainPtr = cast[ptr UncheckedArray[RawZ3Sort]](addr domain[0])
  let rangeSort = sortOfType[Ret](ctx)
  let sym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)
  let raw = ctx.checkErr Z3_mk_rec_func_decl(
    ctx.raw, sym, 3'u32, domainPtr, rangeSort)
  incRefFD(ctx, raw)
  # Inline wrap pattern (avoids Nim 2.2 ORC bycopy-move bug — see unary note).
  let a1 = wrap[A1](ctx, ctx.checkErr Z3_mk_const(ctx.raw,
    ctx.checkErr Z3_mk_string_symbol(ctx.raw, (name & "_arg0").cstring),
    sortOfType[A1](ctx)))
  let a2 = wrap[A2](ctx, ctx.checkErr Z3_mk_const(ctx.raw,
    ctx.checkErr Z3_mk_string_symbol(ctx.raw, (name & "_arg1").cstring),
    sortOfType[A2](ctx)))
  let a3 = wrap[A3](ctx, ctx.checkErr Z3_mk_const(ctx.raw,
    ctx.checkErr Z3_mk_string_symbol(ctx.raw, (name & "_arg2").cstring),
    sortOfType[A3](ctx)))
  let bodyExpr = body(a1, a2, a3)
  var argsArr = [a1.raw, a2.raw, a3.raw]
  Z3_add_rec_def(ctx.raw, raw, 3'u32,
    cast[ptr UncheckedArray[RawZ3Ast]](addr argsArr[0]), bodyExpr.raw)
  Z3FuncDecl[(A1, A2, A3), Ret](raw: raw, ctx: ctx)

proc defineFun*[A1, A2, A3, Ret](name: string,
    body: proc(a1: A1, a2: A2, a3: A3): Ret
    ): Z3FuncDecl[(A1, A2, A3), Ret] {.inline.} =
  defineFun[A1, A2, A3, Ret](requireCurrentContext(), name, body)

# ============================================================================
# Application — per-arity overloads + `()` callable hooks for 0..6 args
# ============================================================================
#
# A small macro generates the per-arity bodies. Each emits both
# `apply` and `()` so users get UFCS form (`f.apply(x, y)`) and
# natural call form (`f(x, y)`).

macro emitApplyArity(n: static int): untyped =
  result = newStmtList()
  let argTypes = nnkPar.newTree()
  let argParams = nnkIdentDefs.newTree()
  var argNames: seq[NimNode] = @[]
  var typeNames: seq[NimNode] = @[]
  for i in 0 ..< n:
    let tn = ident("A" & $(i + 1))
    typeNames.add tn
    argTypes.add tn
    argNames.add ident("a" & $(i + 1))
  if n == 1:
    # Single-element tuple needs trailing comma syntax: (T,)
    argTypes.add newEmptyNode()  # placeholder; rebuild below
  let argsTupType =
    if n == 0:
      nnkPar.newTree()  # ()
    elif n == 1:
      # Build (T,) — Nim's single-element tuple
      nnkTupleConstr.newTree(typeNames[0])
    else:
      var t = nnkTupleConstr.newTree()
      for tn in typeNames: t.add tn
      t
  let genericParams = nnkGenericParams.newTree()
  for tn in typeNames:
    genericParams.add nnkIdentDefs.newTree(tn, newEmptyNode(), newEmptyNode())
  genericParams.add nnkIdentDefs.newTree(ident"Ret", newEmptyNode(), newEmptyNode())

  let fParam = nnkIdentDefs.newTree(
    ident"f",
    nnkBracketExpr.newTree(ident"Z3FuncDecl", argsTupType, ident"Ret"),
    newEmptyNode())

  # Build the body: collect arg.raw into a seq, call Z3_mk_app, wrap.
  let body = newStmtList()
  if n == 0:
    body.add quote do:
      let raw = f.ctx.checkErr Z3_mk_app(f.ctx.raw, f.raw, 0'u32, nil)
      wrap[Ret](f.ctx, raw)
  else:
    let rawsId = ident"raws"
    var arr = nnkBracket.newTree()
    for an in argNames:
      arr.add nnkDotExpr.newTree(an, ident"raw")
    body.add nnkVarSection.newTree(
      nnkIdentDefs.newTree(rawsId, newEmptyNode(), arr))
    body.add quote do:
      let raw = f.ctx.checkErr Z3_mk_app(f.ctx.raw, f.raw, uint32(`rawsId`.len),
        cast[ptr UncheckedArray[RawZ3Ast]](addr `rawsId`[0]))
      wrap[Ret](f.ctx, raw)

  # apply proc
  let applyFormals = nnkFormalParams.newTree(ident"Ret", fParam)
  for i in 0 ..< n:
    applyFormals.add nnkIdentDefs.newTree(argNames[i], typeNames[i], newEmptyNode())
  let applyProc = nnkProcDef.newTree(
    nnkPostfix.newTree(ident"*", ident"apply"),
    newEmptyNode(), newEmptyNode(),
    applyFormals,
    newEmptyNode(), newEmptyNode(),
    body)
  applyProc[2] = genericParams.copy
  result.add applyProc

  # () callable proc — same params, same body
  let callFormals = nnkFormalParams.newTree(ident"Ret", fParam.copy)
  for i in 0 ..< n:
    callFormals.add nnkIdentDefs.newTree(argNames[i], typeNames[i], newEmptyNode())
  let callProc = nnkProcDef.newTree(
    nnkPostfix.newTree(ident"*", ident"()"),
    newEmptyNode(), newEmptyNode(),
    callFormals,
    newEmptyNode(), newEmptyNode(),
    body.copy)
  callProc[2] = genericParams.copy
  result.add callProc

emitApplyArity(0)
emitApplyArity(1)
emitApplyArity(2)
emitApplyArity(3)
emitApplyArity(4)
emitApplyArity(5)
emitApplyArity(6)

# ============================================================================
# Model extraction at a specific argument tuple
# ============================================================================

proc evalAt*[ArgsTup: tuple, Ret](m: Z3Model,
                                  f: Z3FuncDecl[ArgsTup, Ret],
                                  args: ArgsTup,
                                  modelCompletion = true): Ret =
  ## Evaluate `f` at the argument tuple under the given model.
  ## Internally builds the application via `Z3_mk_app` and then
  ## evaluates the resulting AST.
  when ArgsTup is tuple[]:
    m.eval(f.apply(), modelCompletion)
  else:
    var raws = newSeq[RawZ3Ast]()
    for field in fields(args):
      raws.add field.raw
    let raw = f.ctx.checkErr Z3_mk_app(f.ctx.raw, f.raw, cuint(raws.len),
      cast[ptr UncheckedArray[RawZ3Ast]](addr raws[0]))
    m.eval(wrap[Ret](f.ctx, raw), modelCompletion)

# ============================================================================
# Pretty-print (v0.5 step 3D)
# ============================================================================

proc `$`*[ArgsTup: tuple, Ret](f: Z3FuncDecl[ArgsTup, Ret]): string =
  ## SMT-LIB rendering of the function declaration:
  ## `(declare-fun f (Int Int) Bool)`-shaped. `Z3FuncDecl` doesn't
  ## match `Z3Term` (it carries `RawZ3FuncDecl`, not `RawZ3Ast`),
  ## so this overload sits alongside the per-handle `$` on
  ## `Z3Sort` / `Z3Solver` / etc. rather than being absorbed by
  ## the generic `$[T: Z3Term]` in `z3/ast`.
  $Z3_ast_to_string(f.ctx.raw,
    Z3_func_decl_to_ast(f.ctx.raw, f.raw))

# ============================================================================
# Z3FuncInterp[ArgsTup, Ret] — tabular UF model interpretation (v0.5 step 6A)
# ============================================================================
#
# After a satisfiable `check()`, Z3's model carries an interpretation
# for each uninterpreted function. The interpretation is a finite
# table mapping `(args, value)` tuples plus an else-value that
# applies to all other arg tuples — exactly the structure a user
# wants for "show me everywhere the solver pinned `f`."

type
  Z3FuncInterpOwn[ArgsTup: tuple, Ret] = object
    raw: RawZ3FuncInterp
    ctx: Z3Context
  Z3FuncInterp*[ArgsTup: tuple, Ret] = ref Z3FuncInterpOwn[ArgsTup, Ret]
    ## Phantom-typed handle to a `Z3_func_interp`. Phantom parameters
    ## mirror the corresponding `Z3FuncDecl` so entry tuples deserialise
    ## to the right typed family without runtime sort dispatch.

# `emitRefcountLifecycle` doesn't unify across the two phantom
# parameters, so spell the lifecycle hooks out per-instantiation.
proc `=destroy`[ArgsTup: tuple, Ret](v: Z3FuncInterpOwn[ArgsTup, Ret])
    {.raises: [].} =
  if not v.raw.isNil and v.ctx != nil:
    Z3_func_interp_dec_ref(v.ctx.raw, v.raw)

proc raw*[ArgsTup: tuple, Ret](fi: Z3FuncInterp[ArgsTup, Ret]):
    RawZ3FuncInterp {.inline.} = fi.raw
proc ctx*[ArgsTup: tuple, Ret](fi: Z3FuncInterp[ArgsTup, Ret]):
    Z3Context {.inline.} = fi.ctx

proc getFuncInterp*[ArgsTup: tuple, Ret](m: Z3Model,
    f: Z3FuncDecl[ArgsTup, Ret]): Z3FuncInterp[ArgsTup, Ret] =
  ## Extract the tabular interpretation of `f` under model `m`.
  ## Returns a refcounted handle whose `len` / `arity` /
  ## `elseValue` / `[i]` surfaces decompose the table.
  ##
  ## Z3 may return `nil` for functions the model didn't constrain
  ## (the solver picked a sat assignment without ever pinning `f`);
  ## in that case this raises `Z3InvalidUsageError`.
  let ctx = f.ctx
  let raw = ctx.checkErr Z3_model_get_func_interp(ctx.raw, m.raw, f.raw)
  if raw.isNil:
    var e = newException(Z3InvalidUsageError,
      "Z3 returned a nil func-interp — the model didn't constrain " &
      "this function. (Check that the function is used in an asserted " &
      "constraint and that `check()` returned `zsSat`.)")
    e.code = Z3_INVALID_USAGE
    raise e
  Z3_func_interp_inc_ref(ctx.raw, raw)
  Z3FuncInterp[ArgsTup, Ret](raw: raw, ctx: ctx)

proc len*[ArgsTup: tuple, Ret](fi: Z3FuncInterp[ArgsTup, Ret]): int =
  ## Number of explicit `(args, value)` entries. The else-value
  ## (accessible via `elseValue`) covers all other arg tuples and
  ## is *not* counted in `len`.
  int(Z3_func_interp_get_num_entries(fi.ctx.raw, fi.raw))

proc arity*[ArgsTup: tuple, Ret](fi: Z3FuncInterp[ArgsTup, Ret]): int =
  ## Function arity. Matches the number of fields in `ArgsTup`.
  int(Z3_func_interp_get_arity(fi.ctx.raw, fi.raw))

proc elseValue*[ArgsTup: tuple, Ret](fi: Z3FuncInterp[ArgsTup, Ret]): Ret =
  ## The default value `f` takes on any arg tuple not explicitly
  ## listed in the entry table.
  let raw = fi.ctx.checkErr Z3_func_interp_get_else(fi.ctx.raw, fi.raw)
  wrap[Ret](fi.ctx, raw)

proc `[]`*[ArgsTup: tuple, Ret](fi: Z3FuncInterp[ArgsTup, Ret],
    i: int): tuple[args: ArgsTup, value: Ret] =
  ## `i`-th `(args, value)` entry, decomposed into typed families
  ## via the phantom parameters. `i` is 0-based; bounds-checked.
  doAssert i >= 0 and i < fi.len,
    "Z3FuncInterp[]: index " & $i & " out of bounds [0, " & $fi.len & ")"
  let entry = fi.ctx.checkErr Z3_func_interp_get_entry(
    fi.ctx.raw, fi.raw, cuint(i))
  Z3_func_entry_inc_ref(fi.ctx.raw, entry)
  try:
    # Walk the `ArgsTup` fields and lift each `Z3_func_entry`'s
    # i-th arg into the corresponding typed family.
    var argsTuple: ArgsTup
    var k = cuint(0)
    for fieldVal in fields(argsTuple):
      let raw = fi.ctx.checkErr Z3_func_entry_get_arg(
        fi.ctx.raw, entry, k)
      fieldVal = wrap[typeof(fieldVal)](fi.ctx, raw)
      inc k
    let valRaw = fi.ctx.checkErr Z3_func_entry_get_value(
      fi.ctx.raw, entry)
    result.args = argsTuple
    result.value = wrap[Ret](fi.ctx, valRaw)
  finally:
    Z3_func_entry_dec_ref(fi.ctx.raw, entry)

# ============================================================================
# Sequence HOF — seqMap / seqMapi / seqFoldl / seqFoldli. N5.5.
# ============================================================================
#
# Z3's seq HOF API (`Z3_mk_seq_map` etc.) takes the function as a `Z3_ast`
# obtained from `Z3_func_decl_to_ast`. The typed Nim surface accepts a
# `Z3FuncDecl` and converts it internally. Lives here (rather than in
# `z3/sequence`) because `sequence.nim` is imported by this module — the
# reverse import would create a cycle.
#
# Phantom-type constraints encode the expected arities:
#
#   seqMap   : f : (E) → F,           s : Seq[E]           → Seq[F]
#   seqMapi  : f : (Z3Int, E) → F,    startIdx, s           → Seq[F]
#   seqFoldl : f : (A, E) → A,        init : A, s : Seq[E]  → A
#   seqFoldli: f : (Z3Int, A, E) → A, startIdx, init, s     → A

proc seqMap*[E, F](f: Z3FuncDecl[(E,), F],
                   s: Z3Seq[E]): Z3Seq[F] =
  ## SMT `(seq.map f s)`. Applies unary `f` to every element of `s`,
  ## yielding a new sequence of the same length with return type `F`.
  ##
  ## Z3's `Z3_mk_seq_map` requires a lambda expression. We build
  ## `(lambda ((x E)) (f x))` via `Z3_mk_lambda_const` and pass it.
  let ctx = f.ctx
  # Inline wrap — avoids Nim 2.2 ORC bycopy-move bug (see defineFun note).
  let x = wrap[E](ctx, ctx.checkErr Z3_mk_const(ctx.raw,
    ctx.checkErr Z3_mk_string_symbol(ctx.raw, "seqmap_x".cstring),
    sortOfType[E](ctx)))
  let bodyRaw = f(x).raw
  var xApp = ctx.checkErr Z3_to_app(ctx.raw, x.raw)
  let lambdaRaw = ctx.checkErr Z3_mk_lambda_const(ctx.raw, 1'u32,
    cast[ptr UncheckedArray[RawZ3App]](addr xApp), bodyRaw)
  wrap[Z3Seq[F]](ctx, ctx.checkErr Z3_mk_seq_map(ctx.raw, lambdaRaw, s.raw))

proc seqMapi*[E, F](f: Z3FuncDecl[(Z3Int, E), F],
                    startIdx: Z3Int,
                    s: Z3Seq[E]): Z3Seq[F] =
  ## SMT `(seq.mapi f startIdx s)`. Like `seqMap` but `f` also receives
  ## the 0-based index offset by `startIdx` as its first argument.
  let ctx = f.ctx
  let wIdx  = wrap[Z3Int](ctx, ctx.checkErr Z3_mk_const(ctx.raw,
    ctx.checkErr Z3_mk_string_symbol(ctx.raw, "seqmapi_i".cstring),
    sortOfType[Z3Int](ctx)))
  let wElem = wrap[E](ctx, ctx.checkErr Z3_mk_const(ctx.raw,
    ctx.checkErr Z3_mk_string_symbol(ctx.raw, "seqmapi_e".cstring),
    sortOfType[E](ctx)))
  let bodyRaw = f(wIdx, wElem).raw
  var apps = [ctx.checkErr Z3_to_app(ctx.raw, wIdx.raw),
              ctx.checkErr Z3_to_app(ctx.raw, wElem.raw)]
  let lambdaRaw = ctx.checkErr Z3_mk_lambda_const(ctx.raw, 2'u32,
    cast[ptr UncheckedArray[RawZ3App]](addr apps[0]), bodyRaw)
  wrap[Z3Seq[F]](ctx,
    ctx.checkErr Z3_mk_seq_mapi(ctx.raw, lambdaRaw, startIdx.raw, s.raw))

proc seqFoldl*[E, A](f: Z3FuncDecl[(A, E), A],
                     init: A,
                     s: Z3Seq[E]): A =
  ## SMT `(seq.foldl f init s)`. Left-fold `f(acc, elem)` over `s`
  ## starting from `init`.
  let ctx = f.ctx
  let wAcc  = wrap[A](ctx, ctx.checkErr Z3_mk_const(ctx.raw,
    ctx.checkErr Z3_mk_string_symbol(ctx.raw, "seqfoldl_a".cstring),
    sortOfType[A](ctx)))
  let wElem = wrap[E](ctx, ctx.checkErr Z3_mk_const(ctx.raw,
    ctx.checkErr Z3_mk_string_symbol(ctx.raw, "seqfoldl_e".cstring),
    sortOfType[E](ctx)))
  let bodyRaw = f(wAcc, wElem).raw
  var apps = [ctx.checkErr Z3_to_app(ctx.raw, wAcc.raw),
              ctx.checkErr Z3_to_app(ctx.raw, wElem.raw)]
  let lambdaRaw = ctx.checkErr Z3_mk_lambda_const(ctx.raw, 2'u32,
    cast[ptr UncheckedArray[RawZ3App]](addr apps[0]), bodyRaw)
  wrap[A](ctx, ctx.checkErr Z3_mk_seq_foldl(ctx.raw, lambdaRaw, init.raw, s.raw))

proc seqFoldli*[E, A](f: Z3FuncDecl[(Z3Int, A, E), A],
                      startIdx: Z3Int,
                      init: A,
                      s: Z3Seq[E]): A =
  ## SMT `(seq.foldli f startIdx init s)`. Like `seqFoldl` but `f` also
  ## receives the element index (offset by `startIdx`) as its first arg.
  let ctx = f.ctx
  let wIdx  = wrap[Z3Int](ctx, ctx.checkErr Z3_mk_const(ctx.raw,
    ctx.checkErr Z3_mk_string_symbol(ctx.raw, "seqfoldli_i".cstring),
    sortOfType[Z3Int](ctx)))
  let wAcc  = wrap[A](ctx, ctx.checkErr Z3_mk_const(ctx.raw,
    ctx.checkErr Z3_mk_string_symbol(ctx.raw, "seqfoldli_a".cstring),
    sortOfType[A](ctx)))
  let wElem = wrap[E](ctx, ctx.checkErr Z3_mk_const(ctx.raw,
    ctx.checkErr Z3_mk_string_symbol(ctx.raw, "seqfoldli_e".cstring),
    sortOfType[E](ctx)))
  let bodyRaw = f(wIdx, wAcc, wElem).raw
  var apps = [ctx.checkErr Z3_to_app(ctx.raw, wIdx.raw),
              ctx.checkErr Z3_to_app(ctx.raw, wAcc.raw),
              ctx.checkErr Z3_to_app(ctx.raw, wElem.raw)]
  let lambdaRaw = ctx.checkErr Z3_mk_lambda_const(ctx.raw, 3'u32,
    cast[ptr UncheckedArray[RawZ3App]](addr apps[0]), bodyRaw)
  wrap[A](ctx,
    ctx.checkErr Z3_mk_seq_foldli(ctx.raw, lambdaRaw, startIdx.raw,
      init.raw, s.raw))

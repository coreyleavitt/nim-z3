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
## `m.eval(...)`. The full `Z3_func_interp` surface (tabular
## interpretation: explicit entries + else value) is a richer
## feature; deferred from v0.3 (see plan §8).
##
## ## Arity
##
## Per-arity overloads ship for **0 through 6 arguments**. Larger
## arities are rare in practice; bumping the ceiling is one macro
## line per new arity if a user needs it.

{.experimental: "callOperator".}

import std/[macros]
import ./ffi, ./context, ./error, ./ast, ./sortdispatch, ./array, ./bitvec, ./char,
       ./sequence, ./string, ./fp, ./model
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

## `z3/funcdecl_types` — type declarations for `Z3FuncDecl[ArgsTup, Ret]`.
##
## This module exists solely to break the `funcdecl → model → funcdecl`
## circular import. It holds the type definition and the minimal lifecycle
## machinery (`incRefFD` / `decRefFD` / `=destroy` / `wrapFuncDecl`) so
## that `model.nim` can import only this module and use
## `Z3FuncDecl[tuple[], Z3AnyAst]` on its enumeration surface without
## pulling in the full `funcdecl.nim` (which in turn imports `model.nim`).
##
## All functional surface (apply, mkFuncDecl, defineFun, defineRecFun,
## Z3FuncInterp, seqMap, …) lives in `z3/funcdecl`.
##
## This module is **not** part of the public `import z3` surface on its
## own — users reach it transitively through `z3/funcdecl` or `z3/model`.

import ./ffi, ./context, ./error

# ============================================================================
# Z3FuncDecl[ArgsTup, Ret] — phantom-typed function declaration
# ============================================================================

type
  Z3FuncDeclOwn*[ArgsTup: tuple, Ret] = object
    raw*: RawZ3FuncDecl
    ctx*: Z3Context
  Z3FuncDecl*[ArgsTup: tuple, Ret] = ref Z3FuncDeclOwn[ArgsTup, Ret]
    ## Ref-typed handle (parallel to `Z3Solver`, `Z3Model`, etc.).
    ## The phantom tuple `ArgsTup` captures the domain element types
    ## positionally; `Ret` is the codomain.

# ----------------------------------------------------------------------------
# Refcount discipline
# ----------------------------------------------------------------------------
# Z3 refcounts func_decls through `Z3_func_decl_to_ast` + the AST
# refcount pair, same pattern datatypes.nim already uses.

proc decRefFD*(ctx: Z3Context, fd: RawZ3FuncDecl) {.raises: [].} =
  if fd.isNil or ctx == nil or ctx.raw.isNil: return
  try:
    let asAst = Z3_func_decl_to_ast(ctx.raw, fd)
    if not asAst.isNil:
      Z3_dec_ref(ctx.raw, asAst)
  except CatchableError:
    discard

proc incRefFD*(ctx: Z3Context, fd: RawZ3FuncDecl) {.raises: [].} =
  if fd.isNil or ctx == nil or ctx.raw.isNil: return
  try:
    let asAst = Z3_func_decl_to_ast(ctx.raw, fd)
    if not asAst.isNil:
      Z3_inc_ref(ctx.raw, asAst)
  except CatchableError:
    discard

proc `=destroy`*[ArgsTup: tuple, Ret](v: Z3FuncDeclOwn[ArgsTup, Ret])
    {.raises: [].} =
  decRefFD(v.ctx, v.raw)

# ============================================================================
# wrapFuncDecl — typed constructor for externally-created raw handles
# ============================================================================

proc wrapFuncDecl*[ArgsTup: tuple, Ret](
    ctx: Z3Context, raw: RawZ3FuncDecl): Z3FuncDecl[ArgsTup, Ret] =
  ## Wrap a raw `Z3_func_decl` into a typed `Z3FuncDecl[ArgsTup, Ret]`,
  ## incrementing its refcount. Used by sibling modules (e.g. `z3/order`,
  ## `z3/model`) that create func_decls via Z3 C-API calls and need to
  ## lift them into the typed surface without access to `Z3FuncDeclOwn`'s
  ## private fields.
  if raw.isNil:
    var e = newException(Z3InvalidUsageError,
      "wrapFuncDecl: Z3 returned a nil func_decl")
    e.code = Z3_INVALID_USAGE
    raise e
  incRefFD(ctx, raw)
  Z3FuncDecl[ArgsTup, Ret](raw: raw, ctx: ctx)

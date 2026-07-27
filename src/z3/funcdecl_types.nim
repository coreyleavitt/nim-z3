## `z3/funcdecl_types` — type declarations for `Z3FuncDecl[ArgsTup, Ret]`.
##
## This module exists solely to break the `funcdecl → model → funcdecl`
## circular import. It holds the type definition and the minimal lifecycle
## machinery (`incRefFD` / `decRefFD` / `=destroy` / `wrapFuncDecl`) so
## that `z3/model.nim` can import only this module and use
## `Z3FuncDecl[tuple[], Z3AnyAst]` on its enumeration surface without
## pulling in the full `z3/funcdecl.nim` (which in turn imports `z3/model.nim`).
##
## All functional surface (apply, mkFuncDecl, defineFun, defineRecFun,
## Z3FuncInterp, seqMap, …) lives in `z3/funcdecl`.
##
## **Public reach**: users reach this module transitively via `z3/funcdecl`
## (the primary typed surface, re-exported by `import z3`) or via
## `z3/model` (which exports it so callers of the model-enumeration
## surface — `constDecl`, `funcDecl` — get the `Z3FuncDecl` type without
## a separate import). Direct `import z3/funcdecl_types` is not needed
## in normal usage.

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

proc incRefFD*(ctx: Z3Context, fd: RawZ3FuncDecl) =
  ## Increment the Z3 refcount for `fd`. Errors propagate — this proc runs
  ## on the construction path where an error indicates a real problem and
  ## should not be silenced. (Compare `decRefFD`, which swallows errors
  ## because it runs from `=destroy` and cannot propagate.)
  if fd.isNil or ctx == nil or ctx.raw.isNil: return
  let asAst = Z3_func_decl_to_ast(ctx.raw, fd)
  if not asAst.isNil:
    Z3_inc_ref(ctx.raw, asAst)

proc `=destroy`*[ArgsTup: tuple, Ret](v: Z3FuncDeclOwn[ArgsTup, Ret])
    {.raises: [].} =
  decRefFD(v.ctx, v.raw)

# ============================================================================
# wrapFuncDecl — typed constructor for externally-created raw handles
# ============================================================================

proc wrapFuncDecl*[ArgsTup: tuple, Ret](
    ctx: Z3Context, raw: RawZ3FuncDecl): Z3FuncDecl[ArgsTup, Ret] =
  ## Wrap a raw `Z3_func_decl` into a typed `Z3FuncDecl[ArgsTup, Ret]`,
  ## incrementing its refcount.
  ##
  ## Primary consumer: `z3/model` (`constDecl` / `funcDecl`), which wraps
  ## raw handles it obtains from `Z3_model_get_const_decl` /
  ## `Z3_model_get_func_decl`. Secondary consumers include `z3/order`,
  ## `z3/fixedpoint`, and any external module that obtains a `RawZ3FuncDecl`
  ## from a Z3 C-API call and needs to lift it into the typed surface
  ## without direct access to `Z3FuncDeclOwn`'s fields.
  if raw.isNil:
    var e = newException(Z3InvalidUsageError,
      "wrapFuncDecl: Z3 returned a nil func_decl")
    e.code = Z3_INVALID_USAGE
    raise e
  incRefFD(ctx, raw)
  Z3FuncDecl[ArgsTup, Ret](raw: raw, ctx: ctx)

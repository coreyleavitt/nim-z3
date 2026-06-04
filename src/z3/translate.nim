## `z3/translate` — cross-context AST transfer.
##
## Z3 supports moving ASTs between contexts. The wrapper exposes:
##
## - **`translate[T: Z3Term](t, targetCtx)`** — generic over every
##   typed family. Sort is preserved; refcount discipline is honest
##   (`wrap[T]` inc_refs in the target context).
## - **`compatibleWith(ctxA, ctxB)`** — predicate for whether
##   subsequent `translate` calls between the two contexts will
##   succeed. Z3 has no direct compatibility predicate; the wrapper
##   smoke-tests with a trivial AST under exception capture.
##
## ## When to reach for this
##
## Cross-context transfer matters for:
##
## - **Multi-threaded solving**: each thread owns a context; results
##   transfer across them. Z3 contexts aren't thread-safe; one context
##   per thread is the canonical pattern.
## - **Solver delegation**: build a constraint in one context, hand
##   off to a specialised solver in another.
## - **Long-running services**: periodically rebuild a "clean"
##   context, translating just the assertions you care about.
##
## Stick to one context per user-facing task when you can. Cross-
## context translation is a real Z3 capability but it's a sharp tool.

import ./ffi, ./context, ./error, ./ast, ./sort, ./funcdecl

# ============================================================================
# translate — typed cross-context transfer
# ============================================================================

proc translate*[T: Z3Term](t: T, targetCtx: Z3Context): T {.inline.} =
  ## Transfer `t` from its owning context to `targetCtx`. The returned
  ## handle is owned by `targetCtx`; the source handle is independent.
  ## Sort is preserved (typed family round-trips).
  ##
  ## Raises `Z3Error` if `targetCtx` can't accept the AST — most
  ## commonly because the two contexts were configured with
  ## incompatible parameters. Use `compatibleWith(srcCtx, targetCtx)`
  ## up front to test.
  let raw = targetCtx.checkErr Z3_translate(
    t.ctx.raw, t.raw, targetCtx.raw)
  wrap[T](targetCtx, raw)

# ============================================================================
# compatibleWith — smoke-test predicate
# ============================================================================

proc translate*[ArgsTup: tuple, Ret](
    f: Z3FuncDecl[ArgsTup, Ret], target: Z3Context): Z3FuncDecl[ArgsTup, Ret] =
  ## Transfer `f` from its owning context to `target`. The returned handle is
  ## owned by `target`; the source handle is independent. Phantom types
  ## `ArgsTup` and `Ret` are preserved — the translated decl has the same
  ## arity and sort signature.
  ##
  ## Implementation: Z3 has no dedicated `Z3_translate_func_decl`; instead,
  ## `Z3_sort` and `Z3_func_decl` are sub-types of `Z3_ast` in Z3's C API.
  ## We cast the func_decl to its underlying AST via `Z3_func_decl_to_ast`,
  ## run it through `Z3_translate`, then cast back with `Z3_to_func_decl`.
  let asAst = f.ctx.checkErr Z3_func_decl_to_ast(f.ctx.raw, f.raw)
  let translatedAst = target.checkErr Z3_translate(f.ctx.raw, asAst, target.raw)
  let rawFd = target.checkErr Z3_to_func_decl(target.raw, translatedAst)
  wrapFuncDecl[ArgsTup, Ret](target, rawFd)

proc translate*[S: static SortTag](
    s: Z3Sort[S], target: Z3Context): Z3Sort[S] =
  ## Transfer `s` from its owning context to `target`. The phantom sort tag `S`
  ## is preserved.
  ##
  ## Implementation: `Z3_sort` is a sub-type of `Z3_ast` in Z3's C API.
  ## We upcast via `Z3_sort_to_ast`, run through `Z3_translate` for the
  ## context transfer, then downcast the returned `Z3_ast` back to
  ## `RawZ3Sort` with a plain Nim `cast` — valid because Z3's memory model
  ## guarantees the pointer identity is preserved through the upcast/translate
  ## round-trip. (The C API has no dedicated `Z3_to_sort` downcast function.)
  let asAst = s.ctx.checkErr Z3_sort_to_ast(s.ctx.raw, s.raw)
  let translatedAst = target.checkErr Z3_translate(s.ctx.raw, asAst, target.raw)
  Z3Sort[S](raw: cast[RawZ3Sort](translatedAst), ctx: target)

proc compatibleWith*(ctxA, ctxB: Z3Context): bool =
  ## True iff ASTs from `ctxA` can be translated to `ctxB` (and vice
  ## versa — Z3 compatibility is symmetric in practice). No direct
  ## Z3 predicate exists; the wrapper smoke-tests via a trivial
  ## `Z3_mk_true → Z3_translate` round-trip under exception capture.
  ##
  ## Conservative: returns `false` if anything raises. Side-effect
  ## note: the smoke-test allocates a transient AST in each context
  ## (released immediately via the wrapper's refcount discipline);
  ## one round-trip per call.
  try:
    let trueA = Z3_mk_true(ctxA.raw)
    let errA = Z3_get_error_code(ctxA.raw)
    if errA != Z3_OK: return false
    Z3_inc_ref(ctxA.raw, trueA)
    defer: Z3_dec_ref(ctxA.raw, trueA)
    let translated = Z3_translate(ctxA.raw, trueA, ctxB.raw)
    let errB = Z3_get_error_code(ctxB.raw)
    if errB != Z3_OK: return false
    if translated.isNil: return false
    # Z3_translate does not inc_ref the result; we acquire then
    # release immediately. This is a zero-net refcount round-trip
    # whose purpose is just to verify the translation produced a
    # well-formed handle — we don't keep the handle past this point.
    Z3_inc_ref(ctxB.raw, translated)
    Z3_dec_ref(ctxB.raw, translated)
    true
  except CatchableError:
    false

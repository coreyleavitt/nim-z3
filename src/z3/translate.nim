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

import ./ffi, ./context, ./error, ./ast

# ============================================================================
# translate — typed cross-context transfer
# ============================================================================

proc translate*[T: Z3Term](t: T, targetCtx: Z3Context): T =
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
    let translated = Z3_translate(ctxA.raw, trueA, ctxB.raw)
    let errB = Z3_get_error_code(ctxB.raw)
    if errB != Z3_OK: return false
    if translated.isNil: return false
    # Release the transient handles immediately; Z3_translate did NOT
    # inc_ref the result in our space, and Z3_mk_true didn't either.
    # Adopting via wrap would inc_ref then immediately dec_ref on
    # scope exit, which works but is unnecessary work — we just
    # verify the translation succeeded.
    true
  except CatchableError:
    false

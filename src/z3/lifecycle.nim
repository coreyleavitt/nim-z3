## `z3/lifecycle` — refcount-discipline generators and unified wrap.
##
## v0.3 step 1's architectural unification. v0.2 had 22 verbatim copies
## of `=destroy` / `=copy` / `=dup` across five value families (Z3Ast,
## Z3BitVec, Z3Array, Z3DatatypeValue, Z3Pattern), five separately-named
## `wrap*` helpers (`wrap[S]`, `wrapBv[W]`, `wrapArray[K,V]`,
## `wrapValue[T]`, `wrapModel`), and 6+ inline `when T is X` dispatch
## blocks scattered across `array.select`, `datatypes.read`,
## `optimize.upper`/`lower`, and (incoming) `model.eval` overloads.
##
## This module replaces all of that with three primitives:
##
## 1. **Body-extraction templates** (`termDestroy`, `termCopy`, `termDup`)
##    that emit the *bodies* of the three hooks. Each generic value family
##    still declares its own `=destroy[S](v: Z3Ast[S])` proc signature
##    (the signature is where the meaningful generic-type discipline
##    lives), but the body shrinks to a single template invocation.
##    Hand-written body duplication drops from ~10 lines × 22 instances
##    to 1 line × 22 instances.
##
## 2. **Whole-hook stampers** (`emitTermLifecycle` for value types,
##    `emitRefcountLifecycle` for ref-typed handles) that emit all three
##    hooks for non-generic types. `Z3Pattern` (no phantom), `Z3Solver` /
##    `Z3Model` / `Z3Optimize` / `Z3Goal` / `Z3Tactic` / `Z3ApplyResult` /
##    `Z3Params` (all ref-typed, single dec_ref symbol per type) all use
##    the stampers and become one-liners at the family-declaration site.
##
## 3. **Unified `wrap[T]` template** that replaces the five separate
##    `wrap*` helpers and every inline `when T is X` dispatch. Works
##    because every member of every typed family has the same shape:
##    `T(raw: r, ctx: c)`. Inside a generic template, `T` is substituted
##    at expansion, so the constructor call sees the concrete type.
##
## ## What this module does NOT replace
##
## Two genuine exceptions to the generator pattern:
##
## - **`Z3ConstructorDeclOwn[T]`** in `z3/datatypes`. Its `=destroy`
##   dec_refs a *list* of `RawZ3FuncDecl` (constructor + recognizer + N
##   accessors), not a single raw handle. Stays hand-written with a
##   "list-of-handles exception" comment. Logged as the resolution of
##   the v0.3 plan §7 Q1.
## - **`Z3ContextOwn`** in `z3/context`. Calls `Z3_del_context` +
##   `Z3_del_config` directly, not a refcount pair. Stays hand-written.
## - **`Z3Pattern`** value lifecycle goes through `Z3_pattern_to_ast`
##   before issuing the dec_ref/inc_ref. The templates accept a custom
##   `decRefSym` / `incRefSym` so `quantifier.nim`'s
##   `decRefPattern` / `incRefPattern` helpers can plug in.

import ./ffi, ./context

# ============================================================================
# Body-extraction templates — for generic types that need explicit
# per-family proc declarations (Z3Ast[S], Z3BitVec[W], Z3Array[K,V],
# Z3DatatypeValue[T]).
#
# Each emits ONLY the body. Callers wrap them in concrete
# `proc =destroy[…](v: …)` declarations whose signatures carry the
# meaningful generic-type discipline.
# ============================================================================

template termDestroy*(v: untyped, decRefSym: untyped) =
  ## Body of `=destroy` for a Z3-Term-shaped value. `decRefSym` is the
  ## Z3 dec_ref proc that releases the underlying raw handle (e.g.
  ## `Z3_dec_ref` for ASTs).
  try:
    if not v.raw.isNil and v.ctx != nil and not v.ctx.raw.isNil:
      decRefSym(v.ctx.raw, v.raw)
  except CatchableError:
    discard

template termCopy*(dst: untyped, src: untyped,
                   decRefSym: untyped, incRefSym: untyped) =
  ## Body of `=copy`. Decrements the destination's old handle (if any)
  ## before adopting the source's, then increments the new reference.
  if dst.raw != src.raw:
    try:
      if not dst.raw.isNil and dst.ctx != nil and not dst.ctx.raw.isNil:
        decRefSym(dst.ctx.raw, dst.raw)
      dst.raw = src.raw
      dst.ctx = src.ctx
      if not dst.raw.isNil and dst.ctx != nil and not dst.ctx.raw.isNil:
        incRefSym(dst.ctx.raw, dst.raw)
    except CatchableError:
      discard

template termDup*(result: untyped, src: untyped, incRefSym: untyped) =
  ## Body of `=dup`. Copies the source's fields into `result` and
  ## inc_refs the underlying handle.
  result.raw = src.raw
  result.ctx = src.ctx
  if not result.raw.isNil and result.ctx != nil and not result.ctx.raw.isNil:
    try:
      incRefSym(result.ctx.raw, result.raw)
    except CatchableError:
      discard

# ============================================================================
# Whole-hook stampers — for non-generic value types and ref-typed handles
# whose hook signatures don't carry useful generic info.
# ============================================================================

template emitTermLifecycle*(T: typedesc,
                            decRefSym: untyped,
                            incRefSym: untyped) =
  ## Emit `=destroy` / `=copy` / `=dup` for a non-generic value type `T`
  ## whose lifecycle follows the standard inc_ref / dec_ref pair.
  proc `=destroy`(v: T) {.raises: [].} =
    termDestroy(v, decRefSym)
  proc `=copy`(dst: var T, src: T) {.raises: [].} =
    termCopy(dst, src, decRefSym, incRefSym)
  proc `=dup`(src: T): T {.raises: [].} =
    termDup(result, src, incRefSym)

template emitRefcountLifecycle*(OwnT: typedesc, decRefSym: untyped) =
  ## Emit `=destroy` for a ref-typed handle's owned-object type (e.g.
  ## `Z3SolverOwn`). Ref types only need `=destroy`; Nim's ref machinery
  ## handles `=copy` / `=dup`.
  proc `=destroy`(v: OwnT) {.raises: [].} =
    try:
      if not v.raw.isNil and v.ctx != nil and not v.ctx.raw.isNil:
        decRefSym(v.ctx.raw, v.raw)
    except CatchableError:
      discard

# ============================================================================
# Unified `wrap[T]` — single dispatch surface
# ============================================================================
#
# Replaces `wrap[S]` (ast.nim), `wrapBv[W]` (bitvec.nim),
# `wrapArray[K,V]` (array.nim), `wrapValue[T]` (datatypes.nim, private)
# and every inline `when T is X` dispatch block.
#
# Works because every typed family's constructor has the same shape:
# `T(raw: r, ctx: c)`. Inside a generic template `T` is substituted at
# expansion, so the constructor call sees the concrete instantiation.

template wrap*[T](theCtx: Z3Context, theRaw: RawZ3Ast): T =
  ## Construct a value of typed family `T` from a freshly-returned raw
  ## Z3 handle. Takes responsibility for the initial inc_ref. Subsequent
  ## copies go through the family's `=copy` hook.
  ##
  ## ```nim
  ## let i = wrap[Z3Int](ctx, raw)
  ## let b = wrap[Z3BitVec[8]](ctx, raw)
  ## let a = wrap[Z3Array[Z3Int, Z3Bool]](ctx, raw)
  ## ```
  ##
  ## All families backed by `RawZ3Ast` refcount through the same
  ## `Z3_inc_ref` symbol; that's the only refcount type the template
  ## handles directly. Families with custom refcount paths (e.g.
  ## `Z3Pattern` via `Z3_pattern_to_ast`) keep their own bespoke
  ## constructor outside this template.
  block:
    let r = theRaw
    if not r.isNil:
      Z3_inc_ref(theCtx.raw, r)
    T(raw: r, ctx: theCtx)

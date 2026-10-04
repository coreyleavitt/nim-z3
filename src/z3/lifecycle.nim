## `z3/lifecycle` — refcount-discipline generators and unified wrap.
##
## See [docs/PARITY.md](../docs/PARITY.md) for the cross-family contract
## (what every new typed family must implement) and
## [docs/INTERNAL_API.md](../docs/INTERNAL_API.md) for the seam policy
## (when the `wrap*` / `emit*` helpers exported here are appropriate
## cross-module surfaces vs. when they signal a missing public surface).
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
##   `decRefSym` / `incRefSym` so `z3/quantifier.nim`'s
##   `decRefPattern` / `incRefPattern` helpers can plug in.

import ./ffi, ./context

# ============================================================================
# Z3Term — the structural concept binding every typed value family
# ============================================================================
#
# v0.3 step 1's plan documented this concept; the unification *machinery*
# (`wrap[T]`, `emitTermLifecycle`, `emitRefcountLifecycle`) shipped but
# the concept itself was left implicit. v0.4 step 1 lands the concept as
# real Nim code so downstream generics (`Z3AstVector.add[T: Z3Term]`,
# `Z3AstVector.toSeq[T: Z3Term]`, the v0.4-step-2 introspection generics)
# can constrain on it properly.
#
# Every typed family ships with `raw: RawZ3Ast` + `ctx: Z3Context` — that
# IS the concept. Structural-typing means we don't need to update the
# families; they satisfy `Z3Term` automatically.
#
# v0.5 step 2 retroactively constrains v0.3's unconstrained generics
# (`wrap[T]`, `==`, `eval`, etc.) to `[T: Z3Term]` — that's the
# "make Z3Term load-bearing" cycle. v0.4 step 1 just adds the machinery.

type Z3Term* = concept x
  ## Structural concept satisfied by every typed value family. Any type
  ## with `raw: RawZ3Ast` and `ctx: Z3Context` fields qualifies — that
  ## includes `Z3Ast[S]`, `Z3BitVec[W]`, `Z3Array[K, V]`, `Z3Seq[E]`,
  ## `Z3Char`, `Z3String` (= `Z3Seq[Z3Char]`), `Z3Regex[Basis]`,
  ## `Z3Fp[E, S]`, `Z3DatatypeValue[T]`, `Z3RoundingMode`,
  ## `Z3AnyAst` (v0.4 step 2), and `Z3Proof` (v0.4 step 4).
  ##
  ## `Z3Pattern` is **not** a `Z3Term`. Its `raw` field is
  ## `RawZ3Pattern` (it round-trips through `Z3_pattern_to_ast` for
  ## refcounting; see §51 below for the lifecycle exception). Patterns
  ## are quantifier-trigger annotations, not first-class ASTs;
  ## generic ops (`eval`, `astEqual`, `pretty`, `$`) don't apply to
  ## them. If you find yourself wanting a generic-`Z3Term` operation
  ## on a `Z3Pattern`, the right move is to extract the underlying AST
  ## via `Z3_pattern_to_ast` and wrap it explicitly.
  x.raw is RawZ3Ast
  x.ctx is Z3Context

# ============================================================================
# Body-extraction templates — for generic types that need explicit
# per-family proc declarations (Z3Ast[S], Z3BitVec[W], Z3Array[K,V],
# Z3DatatypeValue[T]).
#
# Each emits ONLY the body. Callers wrap them in concrete
# `proc =destroy[…](v: …)` declarations whose signatures carry the
# meaningful generic-type discipline.
# ============================================================================

# ----------------------------------------------------------------------------
# Hook discipline: raise-free by construction
# ----------------------------------------------------------------------------
#
# Nim 2.2's C backend (goto exceptions) runs a destructor on the raise path
# with the error flag still set, and saves and clears the flag around it
# only when it takes the destructor as able to raise. A `{.raises: [].}`
# hook, or a generated seq / ref hook over one, therefore runs with an
# exception IN FLIGHT: a call's result temporary (`T = f(); if (*nimErr_)
# { eqdestroy(T); goto ...; }`) and a local's destroy at its scope's merge
# label alike. Two consequences shape every hook in this package:
#
# - **No `try`.** A `try` entered with the flag set cannot tell the
#   in-flight exception from one of its own: its first checked call jumps
#   to its handler, which matches the in-flight exception, clears the flag
#   and pops it, so the caller returns as if nothing had been raised. The
#   hooks used to wrap their bodies in `try: ... except CatchableError:
#   discard`, which lost any raise unwinding through a frame that destroyed
#   a Z3 value (C only; C++ exceptions are native and unaffected).
# - **`quirky`.** Without `--panics:on` the compiler checks the flag after
#   every call and leaves the routine when it is set, so even a try-free
#   hook entered on the raise path would stop at its first call and leak
#   the rest of its body (the dec_ref, the context release). `{.quirky.}`
#   (the pragma `system/arc`'s `nimDestroyAndDispose` uses for the same
#   reason) drops those checks: the whole body runs, and the in-flight
#   exception is untouched.
#
# A hook body therefore calls nothing that can raise: the raw C entry point
# through softlink's `<sym>Ptr()` accessor (`{.cdecl, raises: [].}`, nil
# when libz3 is not loaded), never the `<sym>` wrapper, which raises
# `SoftlinkError` on a nil entry; nil handles are checked first; and
# `{.raises: [].}` makes the compiler prove it. Every hook is declared
# `{.raises: [], quirky.}`; `tests/thook_raise_path.nim` pins both the
# propagation and the whole-body run, and audits the declarations.

template rawEntry*(sym: untyped): untyped =
  ## softlink's raw C entry point for the Z3 function `sym`: typed
  ## `{.cdecl, raises: [].}`, nil when libz3 is not loaded. For lifecycle
  ## hooks only (see the hook discipline above).
  `sym Ptr`()

template termDestroy*(v: untyped, decRefSym: untyped) =
  ## Body of `=destroy` for a Z3-Term-shaped value. `decRefSym` is the
  ## Z3 dec_ref function that releases the underlying raw handle (e.g.
  ## `Z3_dec_ref` for ASTs), called through its raw entry point. The
  ## enclosing hook must be `{.raises: [], quirky.}`.
  if v.ctx != nil:
    let decRef = rawEntry(decRefSym)
    if not v.raw.isNil and not v.ctx.raw.isNil and decRef != nil:
      decRef(v.ctx.raw, v.raw)
    # v.ctx must stay alive through the dec_ref above (it needs
    # v.ctx.raw); only release it after. Slice D3 (ADR-FC-0012): same
    # ADR-FC-0011 omission as `emitRefcountLifecycle` below, but for
    # every value-typed family (Z3Ast, Z3BitVec, Z3Fp, Z3Array, Z3Seq,
    # Z3Set, Z3Regex, Z3UninterpretedVal, ...) that shares this body.
    # Without this, every value teardown leaks its `ctx` ref.
    `=destroy`(v.ctx)

template termCopy*(dst: untyped, src: untyped,
                   decRefSym: untyped, incRefSym: untyped) =
  ## Body of `=copy`. Decrements the destination's old handle (if any)
  ## before adopting the source's, then increments the new reference.
  ## The enclosing hook must be `{.raises: [], quirky.}`.
  if dst.raw != src.raw:
    let decRef = rawEntry(decRefSym)
    let incRef = rawEntry(incRefSym)
    if not dst.raw.isNil and dst.ctx != nil and not dst.ctx.raw.isNil and
        decRef != nil:
      decRef(dst.ctx.raw, dst.raw)
    dst.raw = src.raw
    dst.ctx = src.ctx
    if not dst.raw.isNil and dst.ctx != nil and not dst.ctx.raw.isNil and
        incRef != nil:
      incRef(dst.ctx.raw, dst.raw)

template termDup*(result: untyped, src: untyped, incRefSym: untyped) =
  ## Body of `=dup`. Copies the source's fields into `result` and
  ## inc_refs the underlying handle. The enclosing hook must be
  ## `{.raises: [], quirky.}`.
  result.raw = src.raw
  result.ctx = src.ctx
  let incRef = rawEntry(incRefSym)
  if not result.raw.isNil and result.ctx != nil and
      not result.ctx.raw.isNil and incRef != nil:
    incRef(result.ctx.raw, result.raw)

# ============================================================================
# Whole-hook stampers — for non-generic value types and ref-typed handles
# whose hook signatures don't carry useful generic info.
# ============================================================================

template emitTermLifecycle*(T: typedesc,
                            decRefSym: untyped,
                            incRefSym: untyped) =
  ## Emit `=destroy` / `=copy` / `=dup` for a non-generic value type `T`
  ## whose lifecycle follows the standard inc_ref / dec_ref pair.
  proc `=destroy`(v: T) {.raises: [], quirky.} =
    termDestroy(v, decRefSym)
  proc `=copy`(dst: var T, src: T) {.raises: [], quirky.} =
    termCopy(dst, src, decRefSym, incRefSym)
  proc `=dup`(src: T): T {.raises: [], quirky.} =
    termDup(result, src, incRefSym)

template emitRefcountLifecycle*(OwnT: typedesc, decRefSym: untyped) =
  ## Emit `=destroy` for a ref-typed handle's owned-object type (e.g.
  ## `Z3SolverOwn`). Ref types only need `=destroy`; Nim's ref machinery
  ## handles `=copy` / `=dup`.
  ##
  ## **WARNING (ADR-FC-0011):** a custom `=destroy` — whether emitted
  ## here or hand-written, as `Z3ContextOwn` and `Z3ConstructorDeclOwn`
  ## are — *replaces* Nim's field-wise destruction under `--mm:orc`
  ## entirely; it does not run alongside it. If `OwnT` grows a
  ## GC-managed field (`Table`, `seq`, `string`, another `ref`, …)
  ## after adopting a custom `=destroy`, that field silently stops
  ## being released unless the hook explicitly destroys it too. See
  ## `src/z3/context.nim`'s `=destroy` for the fix pattern
  ## (`` `=destroy`(c.someTableField) `` called unconditionally,
  ## before any early return). The systemic template-level fix
  ## (teaching `emitRefcountLifecycle` to hand-release arbitrary
  ## extra fields automatically) is a separate, later slice — this is
  ## a discipline reminder, not a guarantee this template enforces.
  proc `=destroy`(v: OwnT) {.raises: [], quirky.} =
    # Borrowed handles (opt-in via a `borrowed: bool` field on `OwnT`)
    # are owned by Z3 itself — the originating context frees them at
    # `Z3_del_context`, so we must NOT dec_ref the raw handle or we race
    # Z3's own teardown into a use-after-free. This is the ref-handle
    # analogue of `Z3ContextOwn.borrowed`; see `wrapAstVectorBorrowed`
    # in `z3/astvector` and the upstream Z3 `Z3_model_get_sort_universe`
    # lifetime-coupling bug that mandates it (ADR-FC-0012, slice D3).
    if v.ctx != nil:
      when compiles(v.borrowed):
        let skipRaw = v.borrowed
      else:
        const skipRaw = false
      let decRef = rawEntry(decRefSym)
      if not skipRaw and not v.raw.isNil and not v.ctx.raw.isNil and
          decRef != nil:
        decRef(v.ctx.raw, v.raw)
      # D3 (ADR-FC-0012): release the `ctx: Z3Context` ARC ref AFTER the
      # raw dec_ref above (which needs `v.ctx.raw` live) — the ref-handle
      # analogue of the value-type release in `termDestroy`. Without it,
      # every ref-handle teardown leaks one strong ref to the owning
      # context (and its config + registry tables). The raw dec_ref keeps
      # the context alive until this point; only then may we drop it.
      `=destroy`(v.ctx)

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

# ============================================================================
# N-ary FFI helper (v0.5 step 2D)
# ============================================================================
#
# Every typed family with a varargs op (`mkAnd` / `mkOr` / `mkDistinct` on
# `Z3Bool`, `mkDistinct` on `Z3BitVec[W]` / `Z3Ast[S]`, `concat` on
# `Z3Seq[E]`, `concat` / `union` / `intersect` on `Z3Regex[Basis]`) shares
# the same four-line core:
#
#   1. Walk the input collecting `.raw` handles into a `seq[RawZ3Ast]`.
#   2. Call the n-ary Z3 FFI builder with `(ctx, len, ptr)`.
#   3. Wrap the returned raw handle as the result family.
#
# The variants differ only in **early-return policy** (required ≥1 vs
# monoid-with-identity vs distinct-≤1-trivially-true). `naryFFICore` is the
# shared core; the three `emitVarargs*` templates wrap it with the
# appropriate guard.

template naryFFICall*(ctx: untyped, raws: untyped, ffi: untyped): RawZ3Ast =
  ## Internal helper template: hand off the `raws` array (already
  ## populated by the caller) to the variadic Z3 FFI builder `ffi`,
  ## guarded by `checkErr`. Expands to the inline call so the FFI
  ## proc's `header: "z3.h"` binding stays at the syntactic call
  ## site rather than passing through a proc-value indirection.
  ctx.checkErr ffi(
    ctx.raw, cuint(raws.len),
    cast[ptr UncheckedArray[RawZ3Ast]](addr raws[0]))

template emitVarargsRequired1Basis*(name, family, ffi: untyped) =
  ## Define `name[Basis](xs: varargs[family]): family` — the
  ## phantom-basis-parameterised variant. Used for `Z3Regex.concat`
  ## / `union` / `intersect` where `family = Z3Regex[Basis]`.
  proc name*[Basis](xs: varargs[family]): family =
    doAssert xs.len >= 1,
      astToStr(name) & " requires at least one argument"
    if xs.len == 1:
      return xs[0]
    var raws = newSeq[RawZ3Ast](xs.len)
    for i, x in xs:
      raws[i] = x.raw
    wrap[family](xs[0].ctx, naryFFICall(xs[0].ctx, raws, ffi))

template emitVarargsRequired1E*(name, family, ffi: untyped) =
  ## Define `name[E](xs: varargs[family]): family` — the
  ## element-parameterised variant. Used for `Z3Seq.concat` where
  ## `family = Z3Seq[E]`.
  proc name*[E](xs: varargs[family]): family =
    doAssert xs.len >= 1,
      astToStr(name) & " requires at least one argument"
    if xs.len == 1:
      return xs[0]
    var raws = newSeq[RawZ3Ast](xs.len)
    for i, x in xs:
      raws[i] = x.raw
    wrap[family](xs[0].ctx, naryFFICall(xs[0].ctx, raws, ffi))

template emitVarargsMonoid*(name, ffi, identityProc: untyped) =
  ## Define `name(args: varargs[Z3Bool]): Z3Bool` with the "monoid
  ## with identity" policy — empty input returns `identityProc(ctx)`,
  ## singleton returns itself, otherwise n-ary FFI. Used for
  ## `Z3Bool.mkAnd` (identity `mkTrue`) and `Z3Bool.mkOr` (identity
  ## `mkFalse`). No generic spec because `Z3Bool` isn't parameterised.
  proc name*(args: varargs[Z3Bool]): Z3Bool =
    if args.len == 0:
      return identityProc(requireCurrentContext())
    if args.len == 1:
      return args[0]
    let ctx = args[0].ctx
    var raws = newSeq[RawZ3Ast](args.len)
    for i, a in args:
      raws[i] = a.raw
    wrap[Z3Bool](ctx, naryFFICall(ctx, raws, ffi))

# `mkDistinct[T: Z3Term]` lives in z3/boolean (cannot live here
# because Z3Bool — the return type — is defined in z3/ast which
# imports z3/lifecycle, not the other way around). v0.5.0
# medium-audit B5 collapsed `emitVarargsDistinctS` +
# `emitVarargsDistinctW` into the single boolean.nim definition.

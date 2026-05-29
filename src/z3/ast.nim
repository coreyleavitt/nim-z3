## `Z3Ast[S]` — phantom-typed AST node.
##
## The core value type for everything you build with Z3. Carries the
## raw Z3 AST handle, a reference to its parent context, and a static
## sort tag (`stInt`, `stReal`, `stBool`, …) that lifts Z3's runtime
## sort discipline into Nim's type system.
##
## ## Lifecycle
##
## Z3's API is reference-counted: every AST returned from a builder
## must be `Z3_inc_ref`'d when stored and `Z3_dec_ref`'d when no longer
## referenced. The spike validated that Nim 2's `=destroy[S]` /
## `=copy[S]` hooks handle this correctly:
##
## - `=copy` decrements the destination's old ref (if any), copies
##   the source's raw pointer + context, increments the new ref.
## - `=destroy` decrements the ref. If the parent context has already
##   been finalised (defensive nil checks), the dec_ref is skipped.
## - Hooks operate on the underlying object type. For phantom-typed
##   `Z3Ast[S]`, the underlying object type IS `Z3Ast[S]` (value type,
##   not `ref`), so the hook signature is `[S: static SortTag](a: Z3Ast[S])`.
##
## All hooks carry `{.raises: [].}` plus a `try/except CatchableError`
## guard because softlink-wrapped FFI procs can raise `SoftlinkError`
## (e.g. if libz3 was unloaded mid-program); destructors can't
## propagate exceptions.
##
## ## `wrap` helper
##
## Every AST builder calls `wrap[S](ctx, raw)` to construct a `Z3Ast[S]`
## with the inc_ref bookkeeping correctly performed. This is the single
## centralised refcount-discipline point — every place we create a new
## Nim handle to a Z3 AST goes through here.

import ./ffi, ./context, ./sort
export sort   # so users get Z3Sort + SortTag from `import z3/ast`

type
  Z3Ast*[S: static SortTag] = object
    ## Value-typed phantom-tagged AST. Cheap to pass around; `=copy`
    ## handles refcounting transparently. Two `Z3Ast` values can refer
    ## to the same underlying Z3 AST; the refcount is correct in either
    ## case.
    raw*: RawZ3Ast
    ctx*: Z3Context

# ============================================================================
# Lifecycle hooks
# ============================================================================

proc `=destroy`[S: static SortTag](a: Z3Ast[S]) {.raises: [].} =
  try:
    if not a.raw.isNil and a.ctx != nil and not a.ctx.raw.isNil:
      Z3_dec_ref(a.ctx.raw, a.raw)
  except CatchableError:
    discard

proc `=copy`[S: static SortTag](dst: var Z3Ast[S], src: Z3Ast[S]) {.raises: [].} =
  if dst.raw != src.raw:
    try:
      # Drop the destination's old reference (if any) before adopting
      # the source's. Order matters: if dst and src share a parent
      # context, decrementing first then re-incrementing is correct
      # net (and goes through the same refcount path).
      if not dst.raw.isNil and dst.ctx != nil and not dst.ctx.raw.isNil:
        Z3_dec_ref(dst.ctx.raw, dst.raw)
      dst.raw = src.raw
      dst.ctx = src.ctx
      if not dst.raw.isNil and dst.ctx != nil and not dst.ctx.raw.isNil:
        Z3_inc_ref(dst.ctx.raw, dst.raw)
    except CatchableError:
      discard

proc `=dup`[S: static SortTag](src: Z3Ast[S]): Z3Ast[S] {.raises: [].} =
  ## Nim 2's preferred copy hook (used for `let y = expr`-style
  ## bindings and return-value paths where `=copy` would otherwise
  ## require an out-param). If only `=copy` is defined, modern Nim
  ## sometimes elides the call entirely and produces a bitwise copy
  ## that breaks our refcount discipline — see
  ## https://nim-lang.org/docs/destructors.html#move-semantics on
  ## `=dup` vs `=copy`. Defining both is the safe story.
  result.raw = src.raw
  result.ctx = src.ctx
  if not result.raw.isNil and result.ctx != nil and not result.ctx.raw.isNil:
    try:
      Z3_inc_ref(result.ctx.raw, result.raw)
    except CatchableError:
      discard

# ============================================================================
# `wrap` — the refcount-discipline entry point
# ============================================================================

template wrap*[S: static SortTag](theCtx: Z3Context, theRaw: RawZ3Ast): Z3Ast[S] =
  ## Construct a `Z3Ast[S]` from a freshly-returned `RawZ3Ast`, taking
  ## responsibility for the inc_ref. Z3 returns ASTs with refcount 0
  ## initially; this template owns the first inc_ref. Subsequent copies
  ## are handled by the `=copy` hook.
  ##
  ## Template (not proc) so the inc_ref happens at the call site and
  ## the result is constructed in-place; otherwise =copy/=sink would
  ## fire spuriously on the proc return value.
  block:
    let r = theRaw
    if not r.isNil:
      Z3_inc_ref(theCtx.raw, r)
    Z3Ast[S](raw: r, ctx: theCtx)

# ============================================================================
# Identity check (not value equality — that's a Z3 operator producing an AST)
# ============================================================================

proc astEqual*[S: static SortTag](a, b: Z3Ast[S]): bool {.inline.} =
  ## Pointer-level identity check: are `a` and `b` the same underlying
  ## Z3 AST? Distinct from semantic equality (which is the `==`
  ## operator on Z3Ast[S] returning a `Z3Ast[stBool]`, defined in
  ## the boolean ops module).
  ##
  ## Two equivalently-built ASTs may or may not be identity-equal
  ## depending on Z3's internal hash-consing. The right tool for
  ## "are these the same Z3 term?" is this proc; the right tool for
  ## "do these terms reduce to the same value?" is the operator `==`.
  cast[pointer](a.raw) == cast[pointer](b.raw)

# ============================================================================
# Pretty-print
# ============================================================================

proc `$`*[S: static SortTag](a: Z3Ast[S]): string =
  ## SMT-LIB rendering of the AST. Useful for debugging:
  ##
  ## ```nim
  ## let x = mkIntVar("x")
  ## echo x          # "x"
  ## let y = mkIntVar("y")
  ## echo (x + y)    # "(+ x y)"
  ## ```
  ##
  ## The string is generated fresh by Z3 on each call; if you need it
  ## hot in a tight loop, cache it yourself.
  $Z3_ast_to_string(a.ctx.raw, a.raw)

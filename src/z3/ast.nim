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

import ./ffi, ./context, ./sort, ./lifecycle
# Re-export so users get Z3Sort + SortTag and the unified `wrap[T]`
# + lifecycle generators from `import z3/ast`. Every downstream module
# already imports ast; piggy-backing the lifecycle surface here avoids
# touching every import site.
export sort, lifecycle

type
  Z3Ast*[S: static SortTag] = object
    ## Value-typed phantom-tagged AST. Cheap to pass around; `=copy`
    ## handles refcounting transparently. Two `Z3Ast` values can refer
    ## to the same underlying Z3 AST; the refcount is correct in either
    ## case.
    raw*: RawZ3Ast
    ctx*: Z3Context

  Z3Int*  = Z3Ast[stInt]
    ## Convenience alias for `Z3Ast[stInt]`. Aliases live here so the
    ## type system + the operator overload modules (`arith.nim`,
    ## `boolean.nim`) can reference them without depending on
    ## `builder.nim`.
  Z3Real* = Z3Ast[stReal]
  Z3Bool* = Z3Ast[stBool]

# ============================================================================
# Lifecycle hooks
# ============================================================================

proc `=destroy`[S: static SortTag](a: Z3Ast[S]) {.raises: [].} =
  termDestroy(a, Z3_dec_ref)

proc `=copy`[S: static SortTag](dst: var Z3Ast[S], src: Z3Ast[S]) {.raises: [].} =
  termCopy(dst, src, Z3_dec_ref, Z3_inc_ref)

proc `=dup`[S: static SortTag](src: Z3Ast[S]): Z3Ast[S] {.raises: [].} =
  ## Nim 2's preferred copy hook (used for `let y = expr`-style
  ## bindings and return-value paths where `=copy` would otherwise
  ## require an out-param). If only `=copy` is defined, modern Nim
  ## sometimes elides the call entirely and produces a bitwise copy
  ## that breaks our refcount discipline — see
  ## https://nim-lang.org/docs/destructors.html#move-semantics on
  ## `=dup` vs `=copy`. Defining both is the safe story.
  termDup(result, src, Z3_inc_ref)

# ============================================================================
# `wrap` — the refcount-discipline entry point now lives in z3/lifecycle
# ============================================================================
#
# Pre-v0.3 this module exposed `wrap*[S: static SortTag](ctx, raw): Z3Ast[S]`.
# v0.3 step 1 unified that and the parallel `wrapBv` / `wrapArray` /
# `wrapValue` helpers into a single `wrap*[T](ctx, raw): T` in
# `z3/lifecycle`, dispatched via the typedesc rather than a SortTag
# value. Existing call sites migrated to the typedesc form
# (`wrap[Z3Int](...)` instead of `wrap[stInt](...)`).

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

# ============================================================================
# Generic same-sort equality
# ============================================================================
#
# `==` returns a Z3Bool — it's the SMT semantic-equality operator,
# not Nim value equality. (For pointer-level identity use `astEqual`.)
# Type-checked at compile time to require both sides have the same
# sort, so `x: Z3Int; p: Z3Bool; x == p` is a compile error.
#
# Literal-lift overloads (`x == 5` for `x: Z3Int`) live in the
# type-specific operator modules (`arith.nim`, `boolean.nim`)
# alongside the matching `<`, `and`, etc. overloads — that's where
# users will look for them.

proc `==`*[S: static SortTag](a, b: Z3Ast[S]): Z3Bool =
  ## SMT equality. Returns a `Z3Bool` AST `(= a b)`.
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_eq(a.ctx.raw, a.raw, b.raw))

proc `!=`*[S: static SortTag](a, b: Z3Ast[S]): Z3Bool =
  ## SMT non-equality. Equivalent to `not (a == b)`.
  let eq = a == b
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_not(a.ctx.raw, eq.raw))

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

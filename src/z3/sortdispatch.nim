## `z3/sortdispatch` — typedesc → `RawZ3Sort` dispatch (the v0.3 step 9
## consolidation).
##
## v0.2 + v0.3-steps-1..8 had **three near-duplicate cascades** turning
## a typedesc into a `RawZ3Sort`:
##
## - `z3/arrays.sortOfType[T]` — Int / Real / Bool / BV[W]
## - `z3/sequence.sortOfTypeSeq[E]` — adds Char / Seq[E']
## - `z3/funcdecl.sortOfTypeFD[T]` — adds Fp[E, S]
##
## Each one had to grow whenever a new typed family landed, and the
## three cascades disagreed on coverage (no cascade handled
## `Z3Array[K, V]` as an element type — so `Z3FuncDecl[(Z3Array[…],),
## Ret]` failed to compile).
##
## Step 9 replaces the three cascades with **`mixin`-based per-family
## overloads** of a single `sortOf*(_: typedesc[X], ctx)` proc. Each
## typed-family module owns its own `sortOf` overload at the
## declaration site; `sortOfType[T](ctx)` is a one-line template that
## dispatches via Nim's normal overload resolution with `mixin sortOf`.
##
## This is the deep-module move: the central dispatcher disappears,
## every family owns its construction step, and adding a new family is
## one `sortOf` overload in that family's module — no edits anywhere
## else.
##
## ## Bonus capability
##
## The redesign closes the v0.2 §8 "nested arrays deferred — typedesc-
## reflection limit" gap: `Z3Array[Z3Int, Z3Array[Z3Int, Z3Bool]]` works
## because array's own `sortOf[K, V]` overload recurses through
## `sortOfType[V](ctx)` and `mixin` defers resolution to instantiation
## time. Same reason `Z3FuncDecl[(Z3Array[Z3Int, Z3Int],), Z3Bool]`
## now constructs.

import ./ffi, ./context, ./error, ./ast

# ============================================================================
# sortOf overloads for the base typed families (Z3Int / Z3Real / Z3Bool)
# ============================================================================
#
# These live here because the base types are declared in z3/sort + z3/ast,
# which are foundation modules with no downstream cycles. Every other
# family (BV, Char, Seq, Array, Fp) declares its `sortOf` overload at the
# end of its own module, after the type definition.

proc sortOf*(_: typedesc[Z3Int], ctx: Z3Context): RawZ3Sort {.inline.} =
  ctx.checkErr Z3_mk_int_sort(ctx.raw)

proc sortOf*(_: typedesc[Z3Real], ctx: Z3Context): RawZ3Sort {.inline.} =
  ctx.checkErr Z3_mk_real_sort(ctx.raw)

proc sortOf*(_: typedesc[Z3Bool], ctx: Z3Context): RawZ3Sort {.inline.} =
  ctx.checkErr Z3_mk_bool_sort(ctx.raw)

# ============================================================================
# sortOfType — the public dispatch entry point
# ============================================================================

template sortOfType*[T](ctx: Z3Context): RawZ3Sort =
  ## Dispatch a typedesc to its `RawZ3Sort` via Nim overload resolution.
  ## Generic instantiation site needs the relevant family's `sortOf`
  ## overload in scope — `mixin sortOf` defers the name lookup to the
  ## instantiation point so any imported family contributes.
  ##
  ## Replaces the v0.2 `array.sortOfType[T]` cascade. Every typed family
  ## that ships in `nim-z3` provides its own `sortOf` overload in its
  ## own module, so `sortOfType[T]` resolves for every member of the
  ## family set without needing this module to know about them.
  mixin sortOf
  sortOf(T, ctx)

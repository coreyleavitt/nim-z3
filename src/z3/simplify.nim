## `simplify` — Z3's term simplifier wrapped with phantom-type
## preservation.
##
## Z3's `Z3_simplify` folds constants, applies known algebraic
## identities (`x + 0 ⇒ x`, `not (not p) ⇒ p`, `x * 0 ⇒ 0`, …),
## and normalises forms — but doesn't run the full decision procedure.
## The returned AST is semantically equivalent to the input and has
## the same sort.
##
## ## One generic, every family
##
## `simplify[T: Z3Term]` is generic over the entire typed-AST family
## set (`Z3Int`, `Z3Real`, `Z3Bool`, `Z3BitVec[W]`, `Z3Array[K, V]`,
## `Z3Seq[E]`, `Z3Char`, `Z3String`, `Z3Regex[B]`, `Z3Fp[E, S]`,
## `Z3DatatypeValue[T]`, `Z3RoundingMode`, `Z3AnyAst`). Pre-v0.5.0
## the per-family overload set was incomplete (no `Z3Fp` /
## `Z3Seq` / `Z3Char` simplify); v0.5.0 medium-audit B1 closed that
## gap by collapsing all per-family overloads into the single
## `[T: Z3Term]` generic. The phantom-type guarantee survives because
## `wrap[T]` returns the same `T` it was instantiated with.
##
## ## Params-customised variant
##
## `simplify[T: Z3Term](a, p)` routes through `Z3_simplify_ex` for
## per-call tuning (`flat`, `som`, `arith_lhs`, …). Param keys are
## documented under `Z3_simplify_ex` in the Z3 C API.

import ./ffi, ./context, ./error, ./lifecycle, ./params

proc simplify*[T: Z3Term](a: T): T =
  ## Apply Z3's default simplifier to `a`. Result has the same sort
  ## and is semantically equivalent under every interpretation.
  ## Generic across every typed-AST family — see module docstring.
  wrap[T](a.ctx, a.ctx.checkErr Z3_simplify(a.ctx.raw, a.raw))

proc simplify*[T: Z3Term](a: T, p: Z3Params): T =
  ## Params-customised simplifier. See `Z3_simplify_ex` in the Z3
  ## C API for the param keys that affect normalisation behaviour
  ## (`arith_lhs`, `som`, `flat`, `elim_and`, …). Result has the
  ## same sort and is semantically equivalent.
  wrap[T](a.ctx, a.ctx.checkErr Z3_simplify_ex(a.ctx.raw, a.raw, p.raw))

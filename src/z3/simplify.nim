## `simplify` — Z3's term simplifier wrapped with phantom-type
## preservation.
##
## Z3's `Z3_simplify` folds constants, applies known algebraic
## identities (`x + 0 ⇒ x`, `not (not p) ⇒ p`, `x * 0 ⇒ 0`, …),
## and normalises forms — but doesn't run the full decision procedure.
## The returned AST is semantically equivalent to the input and has
## the same sort.
##
## ## Why phantom-typed overloads
##
## v0.1 settled on two phantom type families: `Z3Ast[S: static SortTag]`
## (Int / Real / Bool) and `Z3BitVec[W: static int]`. `simplify` has a
## separate overload for each so the result preserves the caller's
## type-level guarantee:
##
## - `simplify(x: Z3Int)` → `Z3Int`
## - `simplify(p: Z3Bool)` → `Z3Bool`
## - `simplify(b: Z3BitVec[8])` → `Z3BitVec[8]`
##
## Without the overload, every caller would have to re-assert the
## phantom — defeating the type discipline the rest of the library is
## built on.
##
## ## What we don't expose (yet)
##
## `Z3_simplify_ex` takes a `Z3_params` object for per-call tuning
## (`flat`, `som`, `arith_lhs`, …). That's deferred until the tactics
## module lands — `Z3Params` is a refcounted entity in its own right
## and deserves a full typed wrapper, not a one-off lifecycle hack in
## this module. The default-params form covers the overwhelming
## majority of user calls anyway.

import ./ffi, ./context, ./sort, ./ast, ./bitvec, ./params

proc simplify*[S: static SortTag](a: Z3Ast[S]): Z3Ast[S] =
  ## Apply Z3's default simplifier to `a`. Result has the same sort
  ## and is semantically equivalent under every interpretation.
  wrap[Z3Ast[S]](a.ctx, a.ctx.checkErr Z3_simplify(a.ctx.raw, a.raw))

proc simplify*[W: static int](a: Z3BitVec[W]): Z3BitVec[W] =
  ## BV overload — preserves width. `simplify(bv: Z3BitVec[8])` stays
  ## `Z3BitVec[8]`; the simplifier folds constant BV expressions
  ## (`bvadd(0x10, 0x01) ⇒ 0x11`) and rewrites obvious identities
  ## (`bvxor(x, x) ⇒ 0`) but doesn't change the width.
  wrap[Z3BitVec[W]](a.ctx, a.ctx.checkErr Z3_simplify(a.ctx.raw, a.raw))

# ============================================================================
# Params-customised overloads (Z3_simplify_ex)
# ============================================================================
#
# The carryover from v0.2 step 1's §8 deferral. Now that step 8 has
# landed `Z3Params`, we can take a params arg cleanly. Both overloads
# preserve the phantom type the same way the default-params forms do.

proc simplify*[S: static SortTag](a: Z3Ast[S], p: Z3Params): Z3Ast[S] =
  ## Params-customised simplifier. See `Z3_simplify_ex` for the param
  ## keys that affect normalisation behaviour (`arith_lhs`, `som`,
  ## `flat`, `elim_and`, …). Result has the same sort and is
  ## semantically equivalent.
  wrap[Z3Ast[S]](a.ctx, a.ctx.checkErr Z3_simplify_ex(a.ctx.raw, a.raw, p.raw))

proc simplify*[W: static int](a: Z3BitVec[W], p: Z3Params): Z3BitVec[W] =
  ## Params-customised BV simplifier. Width-preserving like its
  ## default-params sibling.
  wrap[Z3BitVec[W]](a.ctx, a.ctx.checkErr Z3_simplify_ex(a.ctx.raw, a.raw, p.raw))

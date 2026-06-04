## `z3/order` — order theory + transitive closure (N9.2).
##
## Provides typed wrappers for Z3's built-in order-theory constructors:
##
## - `mkLinearOrder[E](ctx, id)` — strict total (linear) order on sort `E`.
##   Z3 injects irreflexivity, transitivity, and totality axioms.
## - `mkPartialOrder[E](ctx, id)` — non-strict partial order (≤).
##   Z3 injects reflexivity, antisymmetry, and transitivity axioms.
## - `mkPiecewiseLinearOrder[E](ctx, id)` — forest of linear chains.
## - `mkTreeOrder[E](ctx, id)` — tree (forest) order on sort `E`.
## - `mkTransitiveClosure(f)` — transitive closure of a binary relation `f`.
##
## All five constructors return a `Z3FuncDecl[tuple[a, b: E], Z3Bool]`
## (binary predicate over the element sort). The `id` parameter
## distinguishes multiple independent orders over the same sort within a
## single context.
##
## ## Design
##
## `sortOf[E](ctx)` (via `sortOfType[E](ctx)` from `z3/sortdispatch`)
## resolves the element sort at compile time, parallel to the pattern used
## by `z3/arrays`. The returned `Z3FuncDecl` is refcounted via the same
## `incRefFD` / `decRefFD` discipline as `z3/funcdecl`.
##
## ## Gate flag
##
## The entire module body is guarded by `when not defined(z3WithoutOrder):`.
## When compiled with `-d:z3WithoutOrder`, this file imports cleanly but
## exports nothing. The umbrella `z3` module gates its import the same way.

when not defined(z3WithoutOrder):
  import ./ffi, ./context, ./error, ./ast, ./sortdispatch, ./funcdecl

  # --------------------------------------------------------------------------
  # mkLinearOrder
  # --------------------------------------------------------------------------

  proc mkLinearOrder*[E](ctx: Z3Context, id: int): Z3FuncDecl[tuple[a, b: E], Z3Bool] =
    ## Declare a strict total (linear) order on the sort of `E`, identified
    ## by `id`. Z3 automatically injects irreflexivity, transitivity, and
    ## totality axioms into the context.
    ##
    ## Multiple independent linear orders on the same sort are supported by
    ## using distinct `id` values.
    ##
    runnableExamples:
      import z3
      let ctx = newContext()
      let lt = mkLinearOrder[Z3Int](ctx, 0)
      let a = mkIntVar(ctx, "a")
      let b = mkIntVar(ctx, "b")
      let s = newSolver(ctx)
      s.add lt(a, b)
      # The ordering is satisfiable — a < b has solutions.
      doAssert s.check() == zsSat
    let s = sortOfType[E](ctx)
    let raw = ctx.checkErr Z3_mk_linear_order(ctx.raw, s, cuint(id))
    wrapFuncDecl[tuple[a, b: E], Z3Bool](ctx, raw)

  proc mkLinearOrder*[E](id: int): Z3FuncDecl[tuple[a, b: E], Z3Bool] {.inline.} =
    ## Current-context form of `mkLinearOrder[E]`.
    mkLinearOrder[E](requireCurrentContext(), id)

  # --------------------------------------------------------------------------
  # mkPartialOrder
  # --------------------------------------------------------------------------

  proc mkPartialOrder*[E](ctx: Z3Context, id: int): Z3FuncDecl[tuple[a, b: E], Z3Bool] =
    ## Declare a non-strict partial order (reflexive, antisymmetric,
    ## transitive) on the sort of `E`.
    ##
    ## ```nim
    ## let leq = mkPartialOrder[Z3Int](ctx, 0)
    ## s.add leq(a, b)  # a ≤ b
    ## ```
    let s = sortOfType[E](ctx)
    let raw = ctx.checkErr Z3_mk_partial_order(ctx.raw, s, cuint(id))
    wrapFuncDecl[tuple[a, b: E], Z3Bool](ctx, raw)

  proc mkPartialOrder*[E](id: int): Z3FuncDecl[tuple[a, b: E], Z3Bool] {.inline.} =
    ## Current-context form of `mkPartialOrder[E]`.
    mkPartialOrder[E](requireCurrentContext(), id)

  # --------------------------------------------------------------------------
  # mkPiecewiseLinearOrder
  # --------------------------------------------------------------------------

  proc mkPiecewiseLinearOrder*[E](ctx: Z3Context,
      id: int): Z3FuncDecl[tuple[a, b: E], Z3Bool] =
    ## Declare a piecewise linear order (disjoint union of linear chains)
    ## on the sort of `E`.
    let s = sortOfType[E](ctx)
    let raw = ctx.checkErr Z3_mk_piecewise_linear_order(ctx.raw, s, cuint(id))
    wrapFuncDecl[tuple[a, b: E], Z3Bool](ctx, raw)

  proc mkPiecewiseLinearOrder*[E](id: int): Z3FuncDecl[tuple[a, b: E], Z3Bool]
      {.inline.} =
    ## Current-context form of `mkPiecewiseLinearOrder[E]`.
    mkPiecewiseLinearOrder[E](requireCurrentContext(), id)

  # --------------------------------------------------------------------------
  # mkTreeOrder
  # --------------------------------------------------------------------------

  proc mkTreeOrder*[E](ctx: Z3Context, id: int): Z3FuncDecl[tuple[a, b: E], Z3Bool] =
    ## Declare a tree order on the sort of `E`. In a tree order every
    ## element has at most one predecessor; Z3 injects the tree axioms.
    let s = sortOfType[E](ctx)
    let raw = ctx.checkErr Z3_mk_tree_order(ctx.raw, s, cuint(id))
    wrapFuncDecl[tuple[a, b: E], Z3Bool](ctx, raw)

  proc mkTreeOrder*[E](id: int): Z3FuncDecl[tuple[a, b: E], Z3Bool] {.inline.} =
    ## Current-context form of `mkTreeOrder[E]`.
    mkTreeOrder[E](requireCurrentContext(), id)

  # --------------------------------------------------------------------------
  # mkTransitiveClosure
  # --------------------------------------------------------------------------

  proc mkTransitiveClosure*[ArgsTup, Ret](
      f: Z3FuncDecl[ArgsTup, Ret]): Z3FuncDecl[ArgsTup, Ret] =
    ## Return the transitive closure of the binary relation `f`.
    ## The result has the same domain and codomain as `f`; Z3 constrains it to
    ## be the smallest relation containing `f` that is transitively closed.
    ##
    ## `f` must be a binary relation (arity 2); Z3 raises an error otherwise.
    ##
    runnableExamples:
      import z3
      let ctx = newContext()
      let edge = mkFuncDecl[(Z3Int, Z3Int), Z3Bool](ctx, "edge")
      let tc   = mkTransitiveClosure(edge)
      let s = newSolver(ctx)
      s.add edge(mkInt(ctx, 1), mkInt(ctx, 2))
      s.add edge(mkInt(ctx, 2), mkInt(ctx, 3))
      # tc(1, 3) is derivable by transitivity.
      s.add tc(mkInt(ctx, 1), mkInt(ctx, 3))
      doAssert s.check() == zsSat
    let ctx = f.ctx
    let raw = ctx.checkErr Z3_mk_transitive_closure(ctx.raw, f.raw)
    wrapFuncDecl[ArgsTup, Ret](ctx, raw)

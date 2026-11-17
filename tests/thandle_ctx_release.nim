## Every owning handle releases the `ctx: Z3Context` it holds.
##
## A custom `=destroy` replaces Nim's field-wise destruction under
## `--mm:orc` (ADR-FC-0011), so a hook that releases its raw handle but
## not its `ctx` field leaks one strong reference to the owning context,
## and with it the native Z3 context, its config and its registries.
## `tests/td3_ctx_release.nim` pins this for the two lifecycle
## generators (`emitRefcountLifecycle`, `termDestroy`); this file pins it
## for every hand-written hook outside them: `Z3FuncDeclOwn`,
## `Z3FuncInterpOwn`, `Z3RcfNum` and `Z3Pattern`.
##
## Needs `-d:z3CtxDestroyCount` (`run-tests.sh counting`); without it the
## suite is skipped.
## Uses `td3_ctx_release`'s threadvar-swap idiom: each iteration makes a
## context, builds one handle of the family under test on it, then evicts
## the context from the current-context threadvar with a throwaway
## `newContext()`, so the local bindings are its only owners. At block
## exit the context must be destroyed; the previous iteration's
## throwaway is destroyed by this iteration's eviction. Every iteration
## therefore fires `Z3ContextOwn.=destroy` exactly twice when the family
## releases `ctx`, and once when it leaks it.

import std/unittest
import z3

when not defined(z3CtxDestroyCount):
  suite "hand-written hooks release ctx":
    test "needs -d:z3CtxDestroyCount":
      skip()
else:
  const N = 10

  template countDrops(body: untyped): int =
    ## Context destroys over N iterations of `body`, each with its own
    ## fresh context bound as `ctx` (injected). The leading
    ## `newContext()` puts a throwaway in the threadvar, so the first
    ## iteration's eviction counts like every later one. It sits in its
    ## own block because a `discard`ed temporary lives to the end of its
    ## scope, and here that would hold the throwaway past its eviction.
    block:
      discard newContext()
    let before = z3CtxDestroyCounter
    for i in 0 ..< N:
      block:
        let ctx {.inject.} = newContext()
        body
        discard newContext()
    z3CtxDestroyCounter - before

  suite "hand-written hooks release ctx":
    test "Z3FuncDecl":
      let drops = countDrops:
        let f = mkFuncDecl[(Z3Int,), Z3Int](ctx, "f")
        check f.ctx == ctx
      check drops == 2 * N

    test "Z3FuncDecl from model enumeration":
      let drops = countDrops:
        let s = newSolver(ctx)
        s.add mkIntVar(ctx, "x") == mkInt(ctx, 3)
        check s.check() == zsSat
        let m = s.model()
        check m.numConsts == 1
        let d = m.constDecl(0)
        check d.ctx == ctx
      check drops == 2 * N

    test "Z3FuncInterp":
      let drops = countDrops:
        let f = mkFuncDecl[(Z3Int,), Z3Int](ctx, "f")
        let s = newSolver(ctx)
        s.add f(mkInt(ctx, 0)) == mkInt(ctx, 42)
        check s.check() == zsSat
        let fi = getFuncInterp(s.model(), f)
        check fi.ctx == ctx
      check drops == 2 * N

    when not defined(z3WithoutRcf):
      test "Z3RcfNum":
        let drops = countDrops:
          let a = mkSmallInt(ctx, 2) + mkPi(ctx)
          check a.ctx == ctx
        check drops == 2 * N

    test "Z3Pattern":
      let drops = countDrops:
        let f = mkFuncDecl[(Z3Int,), Z3Int](ctx, "f")
        let x = mkIntVar(ctx, "x")
        let p = mkPattern(f(x))
        check p.ctx == ctx
      check drops == 2 * N

## `z3/semantics` — validity / equivalence oracles.
##
## Up through v0.2 these primitives lived in `z3/solver` (`smtValid`
## and the `smtEquiv` overload for `Z3Ast[S]`) and `z3/bitvec` (the
## `smtEquiv` overload for `Z3BitVec[W]`). v0.3 step 2 relocates them
## into this single module — closes the v0.2 audit's discoverability
## finding (one search location for "is this SMT-valid?" rather than
## three) and adds the missing overloads for `Z3Array[K, V]` and
## `Z3DatatypeValue[T]` that v0.1 §18 had promised "in v0.2 alongside
## those sort modules" but never landed.
##
## ## Generic `smtEquiv[T]`
##
## Post-step-1 unification, `smtEquiv` is a single generic over any
## typed family. The constraint on `T` is duck-typed through Nim's
## generic-proc resolution: any type with an `==(a, b: T): Z3Bool`
## operator works. Every typed AST family satisfies it — `Z3Ast[S]`,
## `Z3BitVec[W]`, `Z3Array[K, V]`, `Z3DatatypeValue[T]`, `Z3String`,
## `Z3Seq[E]`, `Z3Char`, `Z3Regex[B]`, `Z3Fp[E, S]`, `Z3RoundingMode`,
## `Z3FuncDecl[...]`.
##
## The implementation is `smtValid(a == b)` — same as the v0.2
## per-family overloads. The win is one definition instead of N.

import ./ffi, ./context, ./error, ./ast, ./solver

proc smtValid*(p: Z3Bool): bool =
  ## True iff `p` is valid — i.e. `(not p)` is unsatisfiable. Uses a
  ## fresh throwaway solver bound to `p`'s context.
  ##
  ## Returns `false` for both falsified and unknown — strict validity
  ## requires Z3 prove unsat. If you need to distinguish "definitely
  ## not valid" from "couldn't decide", use a solver manually and case
  ## on `Z3Status`.
  let s = newSolver(p.ctx)
  s.add wrap[Z3Bool](p.ctx,
    p.ctx.checkErr Z3_mk_not(p.ctx.raw, p.raw))
  s.check() == zsUnsat

proc smtEquiv*[T](a, b: T): bool {.inline.} =
  ## True iff `a` and `b` are SMT-level equal under every
  ## interpretation. Sugar over `smtValid(a == b)`.
  ##
  ## Generic over any typed family that has an `==(a, b: T): Z3Bool`
  ## operator — covers every typed family (`Z3Ast[S]`, `Z3BitVec[W]`,
  ## `Z3Array[K, V]`, `Z3DatatypeValue[T]`, `Z3String`, `Z3Seq[E]`,
  ## `Z3Char`, `Z3Regex[B]`, `Z3Fp[E, S]`, `Z3RoundingMode`,
  ## `Z3FuncDecl[...]`) automatically.
  smtValid(a == b)

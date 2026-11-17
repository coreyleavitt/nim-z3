## Every value family's declared hooks are bound to every instantiation.
##
## Nim binds a generic `=destroy` / `=copy` / `=dup` only to
## instantiations made after the hook is declared. An instantiation made
## earlier, such as an alias `Z3Int* = Z3Ast[stInt]` in the type section
## that declares `Z3Ast`, silently gets compiler-generated field-wise
## hooks instead: its destroy never dec_refs and its copies never
## inc_ref, so every AST of that type leaks one Z3 refcount.
##
## `termDestroy` / `termCopy` / `termDup` (`z3/lifecycle`) bump a counter
## under `-d:z3TermHookCount` (`run-tests.sh counting`); a generated hook
## does not. For each family this explicitly destroys one value, copies
## one and dups one, and checks each counter moved. Values are built with
## `wrap[T]` over one Int AST: refcounting does not look at the sort, and
## the same construction then reaches every family. (`Z3Set`'s hooks
## delegate to these bodies too.)

import std/unittest
import z3

when not defined(z3TermHookCount):
  suite "declared term hooks are bound":
    test "needs -d:z3TermHookCount":
      skip()
else:
  type Marker = object

  proc mk[T](ctx: Z3Context, raw: RawZ3Ast): T =
    when T is Z3Set:
      # A distinct type has no object constructor; build its base.
      T(wrap[Z3Array[Z3Int, Z3Bool]](ctx, raw))
    else:
      wrap[T](ctx, raw)

  proc probe[T](ctx: Z3Context, raw: RawZ3Ast): (int, int) =
    ## Destroy count of one explicit `=destroy`, and copy count of one
    ## `=copy` plus one `=dup`.
    var v = mk[T](ctx, raw)
    var w = mk[T](ctx, raw)
    let d0 = z3TermDestroyCounter
    let c0 = z3TermCopyCounter
    `=copy`(w, v)
    let u = `=dup`(v)
    let copies = z3TermCopyCounter - c0
    `=destroy`(v)
    `=wasMoved`(v)
    result = (z3TermDestroyCounter - d0, copies)
    discard u

  template bound(T: typedesc) =
    test $T:
      let ctx = newContext()
      let base = mkIntVar(ctx, "x")
      let (destroys, copies) = probe[T](ctx, base.raw)
      check destroys == 1
      check copies == 2

  suite "declared term hooks are bound":
    bound(Z3Int)
    bound(Z3Real)
    bound(Z3Bool)
    bound(Z3Ast[stUninterpreted])
    bound(Z3AnyAst)
    bound(Z3BitVec[8])
    bound(Z3Float16)
    bound(Z3Float32)
    bound(Z3Float64)
    bound(Z3Float128)
    bound(Z3Fp[3, 5])
    bound(Z3RoundingMode)
    bound(Z3Char)
    bound(Z3String)
    bound(Z3Seq[Z3Int])
    bound(Z3Regex[Z3String])
    bound(Z3Array[Z3Int, Z3Bool])
    bound(Z3Set[Z3Int])
    bound(Z3DatatypeValue[Marker])
    bound(Z3UninterpretedVal[Marker])
    bound(Z3Proof)

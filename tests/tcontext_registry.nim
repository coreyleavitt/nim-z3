## `Z3Context` registry-teardown regression test — ADR-FC-0011 / slice D2.
##
## `Z3ContextOwn`'s hand-written `=destroy` (see `src/z3/context.nim`)
## replaces Nim's field-wise destruction under `--mm:orc`. Before this
## slice it touched only `raw`/`cfg`, so the GC-managed `Table` fields
## `datatypeRegistry` and `uninterpretedRegistry` were never released —
## a leak on every context teardown once those tables were populated.
##
## `tests/tcontext.nim`'s fixture never populates either registry, so
## it can't catch this. This test populates BOTH (via `declareDatatype`
## and `declareUninterpretedSort`, the real public API) and exercises
## the resulting values enough to prove the registries actually did
## their job. The functional checks below prove no crash/regression
## from the new destructor; the leak proof itself is
## `nimz3.sh valgrind tests/tcontext_registry.nim`.
##
## ## Why two contexts, both torn down in-process
##
## `newContext()` installs its result as the per-thread current context
## (a `{.threadvar.}`), so a naive "let it fall out of scope" doesn't
## actually drop the refcount to zero before process exit — the
## threadvar keeps it alive, and valgrind reports the memory "still
## reachable" rather than "definitely lost"/"possibly lost", hiding
## the bug entirely. Replacing the current context with a fresh
## throwaway one leaves the local `ctx` (or `dtCtx`) as sole owner, so
## its `=destroy` fires deterministically (ARC/ORC) at scope exit —
## while the process is still running, where valgrind can observe the
## registry tables as genuinely unreachable.
##
## Originally the *datatype* side (`dtCtx`) could not use this trick.
## Investigation surfaced a separate, pre-existing bug sitting one
## layer down: `Z3ConstructorDeclOwn[T]`'s hand-written `=destroy`
## (`src/z3/datatypes.nim`) — same ADR-FC-0011 bug class, a custom
## `=destroy` that doesn't release every GC-managed field it owns —
## never released its own `ctx: Z3Context` field (nor its `cname`
## string / `accessorsFD` seq). That leaked one strong reference to
## the context for every constructor of every
## `declareDatatype`/`declareDatatypes` call, for the life of the
## process — a context that had ever had `declareDatatype` called on
## it could never reach refcount zero while the process ran. Slice D4
## fixed `Z3ConstructorDeclOwn[T].=destroy` to release `ctx`, `cname`,
## and `accessorsFD` explicitly, which unblocks the same
## threadvar-swap trick for `dtCtx` below: once the last
## `Z3ConstructorDeclRef` backing `BoxDt` drops (via `BoxDt`'s own
## scope exit), its `ctx` ref finally releases, `dtCtx`'s refcount
## hits zero, and `=destroy` runs in-process where valgrind can see
## the `datatypeRegistry` table become genuinely unreachable — giving
## both registries the same clean, direct before/after signal. Both
## registries share the exact same fix (two adjacent, symmetric
## `` `=destroy`(Table[string, RawZ3Sort]) `` calls in
## `Z3ContextOwn`'s `=destroy` — see `src/z3/context.nim`).

import std/unittest
import z3

type
  Box = object       # marker for declareDatatype — populates datatypeRegistry
  ColorSort = distinct void   # marker for declareUninterpretedSort — populates uninterpretedRegistry

suite "Z3Context — registry teardown (ADR-FC-0011)":
  test "datatypeRegistry populated via declareDatatype and exercised":
    block:
      let dtCtx = newContext()
      let BoxDt = declareDatatype[Box](dtCtx, @[
        constructor("box", @[field("value", Z3Int)])
      ])
      let box = BoxDt.con("box")
      let isBox = BoxDt.recognizer("box")
      let v = box.apply(mkInt(7))
      check smtValid(isBox.test(v))

      # Drop the threadvar's reference so `dtCtx` is the sole owner;
      # when it (and BoxDt/box/isBox/v, all of which hold `ctx` refs)
      # fall out of scope below, refcount hits zero and `=destroy`
      # runs now, not at process exit. See module doc.
      discard newContext()
    # If the datatypes.nim ctx-release fix (slice D4) regressed —
    # e.g. a double-free on the shared ctx ref — we'd see a crash
    # here rather than a clean fall-through.
    check true

  test "uninterpretedRegistry populated then context drops without crashing":
    block:
      let ctx = newContext()

      let colorSort = declareUninterpretedSort[ColorSort](ctx, "Color")
      check colorSort is Z3Sort[stUninterpreted]
      let c = mkUninterpretedVar[ColorSort]("c", ctx)
      let s = newSolver(ctx)
      s.add(c == c)
      check s.check() == zsSat

      # Drop the threadvar's reference so `ctx` is the sole owner;
      # when it falls out of scope below, refcount hits zero and
      # `=destroy` runs now, not at process exit. See module doc.
      discard newContext()
    # If the new =destroy double-freed or otherwise corrupted state,
    # we'd see a crash here rather than a clean fall-through.
    check true

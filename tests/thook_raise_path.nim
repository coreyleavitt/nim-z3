## Lifecycle hooks run on the raise path: an exception in flight must
## survive them.
##
## Nim 2.2's C backend (goto exceptions) runs a destructor on the raise path
## with the error flag still set, and saves and clears the flag around it
## only when it takes the destructor as able to raise. A `{.raises: [].}`
## hook, or a generated seq / ref hook over one, therefore runs with the
## flag set: a reassignment's result temporary
## (`T = f(); if (*nimErr_) { eqdestroy(T); goto ...; }`) and a local's
## destroy at its scope's merge label alike. A `try` inside such a hook
## cannot tell the in-flight exception from one of its own: its first
## checked call jumps to its handler, which matches the in-flight exception,
## clears the flag and pops it, and the caller returns as if nothing had
## been raised. The hooks used to wrap their bodies in `try: ... except
## CatchableError: discard` (`except Exception` for the context release),
## so on the C backend a raise unwinding through any frame that destroyed a
## Z3 value was lost. C++ exceptions are native and unaffected.
##
## The hooks are now raise-free by construction (no `try`, no checked call:
## the raw C entry points through softlink's `*Ptr` accessors), so the raise
## reaches the outer `except`. One case per distinct hook body; each raises
## out of a call whose result holds the value, reassigned and initialised.
## Under `-d:z3CtxDestroyCount` a further suite checks that a hook entered
## with the flag set runs its WHOLE body: the trailing context release
## still fires. A source audit pins the discipline on every hook in
## `src/z3`: declared `{.raises: [], quirky.}`, with no `try` in its body.

import std/[os, strutils, unittest]
import z3
import z3/fixedpoint_callbacks

type HookFault = object of CatchableError

proc fault() =
  raise newException(HookFault, "in-flight raise")

proc reaches(body: proc ()): bool =
  ## True when the raise reaches this outer `except`.
  try:
    body()
    false
  except HookFault:
    true

proc soleCtx(): Z3Context =
  ## A fresh context that is not this thread's current one, so the values
  ## built over it hold its only references.
  let prev = currentContext()
  result = newContext()
  setCurrentContext(prev)

type Maybe = object

template shape(name: string; T: typedesc; build: untyped) =
  ## `build` evaluates to a `T` over `ctx`. Raise out of a call returning
  ## it, once reassigning an existing variable and once initialising one.
  test name & " (reassigned)":
    proc thenRaise(ctx {.inject.}: Z3Context; n: int): T =
      result = build
      if n >= 0: fault()
    proc caller(ctx {.inject.}: Z3Context) =
      var r = build
      r = thenRaise(ctx, 1)
      discard r
    let c = soleCtx()
    check reaches(proc () = caller(c))
  test name & " (initialised)":
    proc thenRaise(ctx {.inject.}: Z3Context; n: int): T =
      result = build
      if n >= 0: fault()
    proc caller(ctx {.inject.}: Z3Context) =
      let r = thenRaise(ctx, 1)
      discard r
    let c = soleCtx()
    check reaches(proc () = caller(c))

suite "a raise survives each lifecycle hook on the raise path":
  # `termDestroy` (generic value families).
  shape("Z3BitVec terms (termDestroy)", seq[Z3BitVec[8]]):
    @[mkBitVec[8](ctx, 1), mkBitVec[8](ctx, 2)]
  # `emitTermLifecycle` (non-generic value families).
  shape("Z3Char terms (emitTermLifecycle)", seq[Z3Char]):
    @[mkChar(ctx, 'a')]
  # `emitRefcountLifecycle` (ref handles).
  shape("a solver (emitRefcountLifecycle)", Z3Solver):
    newSolver(ctx)
  # `Z3ContextOwn.=destroy`: the last reference dropped on the raise path,
  # from a value whose own hook is field-wise.
  shape("the context's own destroy", seq[Z3AnyAst]):
    @[toAnyAst(mkInt(ctx, 1))]
  # `Z3Pattern` (`decRefPattern`).
  shape("patterns (decRefPattern)", seq[Z3Pattern]):
    @[mkPattern(mkIntVar(ctx, "p") + mkInt(ctx, 1))]
  # `Z3ConstructorDeclOwn` (`decRefFuncDecl`), through the datatype decl.
  shape("a datatype declaration (Z3ConstructorDeclOwn)", Z3DatatypeDecl[Maybe]):
    declareDatatype[Maybe](ctx, @[
      constructor("nothing"),
      constructor("just", @[field("value", Z3Int)])])
  # `Z3FuncDeclOwn` (`decRefFD`).
  shape("a function declaration (decRefFD)", Z3FuncDecl[(Z3Int, ), Z3Int]):
    mkFuncDecl[(Z3Int, ), Z3Int](ctx, "f")
  # `Z3FuncInterpOwn`.
  shape("a function interpretation (Z3FuncInterpOwn)",
        Z3FuncInterp[(Z3Int, ), Z3Int]):
    (block:
      let f = mkFuncDecl[(Z3Int, ), Z3Int](ctx, "g")
      let s = newSolver(ctx)
      s.add(f.apply(mkInt(ctx, 1)) == mkInt(ctx, 7))
      doAssert s.check() == zsSat
      s.model().getFuncInterp(f))
  # `Z3FixedpointOwn` (and the callback box it roots).
  shape("a fixedpoint with a rooted box (Z3FixedpointOwn)", Z3Fixedpoint):
    (block:
      let fp = newFixedpoint(ctx)
      fp.cbBoxRef = cast[RootRef](FixedpointCtxBox(ctx: ctx))
      fp)
  # `FixedpointCtxBoxObj` on its own.
  shape("a fixedpoint callback box (FixedpointCtxBoxObj)", FixedpointCtxBox):
    FixedpointCtxBox(ctx: ctx)
  when not defined(z3WithoutRcf):
    # `Z3RcfNum` (`Z3_rcf_del`).
    shape("RCF numerals (Z3RcfNum)", seq[Z3RcfNum]):
      @[mkSmallInt(ctx, 3)]

  test "control: a call that does not raise returns normally":
    proc noRaise(ctx: Z3Context; n: int): seq[Z3BitVec[8]] =
      result = @[mkBitVec[8](ctx, n)]
      if n < 0: fault()
    let c = soleCtx()
    check not reaches(proc () =
      var r = @[mkBitVec[8](c, 0)]
      r = noRaise(c, 1)
      doAssert r.len == 1)

when defined(z3CtxDestroyCount):
  suite "a hook entered with the flag set runs its whole body":
    # The context release is each hook's LAST statement. A hook that bailed
    # out at its first checked call (the flag is set) would skip it and leak
    # the context; this counts its `=destroy` firing on the raise path. The
    # value is `run`'s only local, destroyed at its scope's merge label by a
    # later raise: a generated seq hook, so unsaved on C, and an unwinding
    # destroy on C++. (It is built in a helper: a context temporary in `run`
    # itself would make the compiler save the flag around the whole group.)
    proc bvsOnSoleCtx(): seq[Z3BitVec[8]] = @[mkBitVec[8](soleCtx(), 0)]
    proc solversOnSoleCtx(): seq[Z3Solver] = @[newSolver(soleCtx())]

    test "termDestroy releases the last context reference":
      let before = z3CtxDestroyCounter
      proc run() =
        let r = bvsOnSoleCtx()
        if r.len > 0: fault()
      check reaches(run)
      check z3CtxDestroyCounter - before == 1

    test "emitRefcountLifecycle releases the last context reference":
      let before = z3CtxDestroyCounter
      proc run() =
        let r = solversOnSoleCtx()
        if r.len > 0: fault()
      check reaches(run)
      check z3CtxDestroyCounter - before == 1

# ----------------------------------------------------------------------------
# Source audit: every hook, and every helper a hook calls, follows the
# discipline. A body is the declaration's following lines indented deeper
# than it.
# ----------------------------------------------------------------------------

const hookHelpers = ["decRefPattern", "incRefPattern", "decRefFuncDecl",
                     "incRefFuncDecl", "decRefFD"]
const hookTemplates = ["termDestroy", "termCopy", "termDup",
                       "emitTermLifecycle", "emitRefcountLifecycle"]

proc indentOf(line: string): int =
  while result < line.len and line[result] == ' ': inc result

proc declBlock(lines: seq[string]; i: int): (string, seq[string]) =
  ## The declaration starting at line `i` (up to its `=`) and its body.
  var header = lines[i]
  var j = i
  while not header.strip.endsWith("=") and j + 1 < lines.len:
    inc j
    header.add " " & lines[j].strip
  let ind = indentOf(lines[i])
  var body: seq[string]
  inc j
  while j < lines.len:
    let l = lines[j]
    if l.strip.len > 0 and indentOf(l) <= ind: break
    body.add l
    inc j
  (header, body)

proc codeLines(body: seq[string]): seq[string] =
  for l in body:
    let t = l.strip
    if t.len > 0 and not t.startsWith("#"): result.add t

suite "source audit: every lifecycle hook is raise-free by construction":
  let srcDir = currentSourcePath().parentDir.parentDir / "src" / "z3"

  test "each =destroy / =copy / =dup is {.raises: [], quirky.} with no try":
    var seen = 0
    for path in walkFiles(srcDir / "*.nim"):
      let lines = readFile(path).splitLines
      for i, l in lines:
        let t = l.strip
        if not (t.startsWith("proc `=destroy`") or
                t.startsWith("proc `=copy`") or
                t.startsWith("proc `=dup`")): continue
        let (header, body) = declBlock(lines, i)
        if "error:" in header: continue   # a forbidden hook has no body
        inc seen
        checkpoint path.extractFilename & ": " & t
        check "raises: []" in header
        check "quirky" in header
        for c in codeLines(body):
          check not c.startsWith("try")
          check not c.startsWith("except")
    check seen >= 30

  test "each hook helper and hook-body template has no try":
    var seen = 0
    for path in walkFiles(srcDir / "*.nim"):
      let lines = readFile(path).splitLines
      for i, l in lines:
        let t = l.strip
        var hit = ""
        for h in hookHelpers:
          if t.startsWith("proc " & h & "(") or t.startsWith("proc " & h & "*("):
            hit = h
        for h in hookTemplates:
          if t.startsWith("template " & h & "*("): hit = h
        if hit.len == 0: continue
        let (header, body) = declBlock(lines, i)
        inc seen
        checkpoint path.extractFilename & ": " & hit
        if header.startsWith("proc"):
          check "raises: []" in header
          check "quirky" in header
        for c in codeLines(body):
          check not c.startsWith("try")
          check not c.startsWith("except")
    check seen == hookHelpers.len + hookTemplates.len

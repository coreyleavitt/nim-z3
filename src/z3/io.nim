## `z3/io` — SMT-LIB2 input / output.
##
## This module hosts the wrapper's complete SMT-LIB2 surface:
##
## - **Emission.** `smt2Script(solver)` and `writeSmt2(solver, path)`
##   produce a self-contained SMT2 script — declarations + assertions
##   + a trailing `(check-sat)` — suitable for piping to the `z3` CLI
##   for ablation, minimisation, or sharing as a bug report.
##   `toSmt2Benchmark(formula)` does the same for a single formula
##   (plus optional assumption set).
## - **Parsing.** `parseSmt2String` / `parseSmt2File` parse a
##   self-contained SMT2 source into `seq[Z3Bool]` assertions. They
##   round-trip exactly with `smt2Script`.
## - **Direct-to-solver feeders.** `loadSmt2String` / `loadSmt2File`
##   parse and assert into a `Z3Solver` in one call, skipping the
##   intermediate AST-vector.
## - **Eval.** `evalSmt2` executes a script of SMT2 commands
##   (`assert`, `check-sat`, `get-model`, …) and returns Z3's text
##   response — handy for scripting and tests.
## - **Streaming parse.** `Z3ParserContext` is a stateful, refcounted
##   parser that retains pre-registered sorts / declarations *and*
##   any declarations it ingests across calls; ideal for large
##   incremental sources (REPLs, file-by-file ingestion).
##
## Everything in this module obeys the same `Z3Context` and error
## conventions as the rest of the wrapper: Z3 parser / FFI errors
## bubble out as `Z3Error`. The parser context is auto-managed via
## `emitRefcountLifecycle`.

import ./ffi, ./context, ./ast, ./solver, ./lifecycle, ./sort, ./funcdecl

# ============================================================================
# Helpers
# ============================================================================

template guardParse(ctx: Z3Context, body: untyped): untyped =
  ## Run an FFI parse call; if Z3's error state went non-OK, raise
  ## `Z3Error` so callers see a precise SMT2 syntax / lookup error
  ## rather than a stale `discard`'d return.
  let r = body
  let err = Z3_get_error_code(ctx.raw)
  if err != Z3_OK:
    raiseZ3Error(ctx, err)
  r

proc collectAsserts(ctx: Z3Context, vec: RawZ3AstVector): seq[Z3Bool] =
  ## Drain a (just-returned, owned-by-Z3) AST-vector into a typed
  ## seq of `Z3Bool`. Pins the vector with one extra refcount for
  ## the duration of the walk to defend against GC interference.
  Z3_ast_vector_inc_ref(ctx.raw, vec)
  try:
    let n = int(Z3_ast_vector_size(ctx.raw, vec))
    result = newSeqOfCap[Z3Bool](n)
    for i in 0 ..< n:
      let raw = Z3_ast_vector_get(ctx.raw, vec, cuint(i))
      result.add wrap[Z3Bool](ctx, raw)
  finally:
    Z3_ast_vector_dec_ref(ctx.raw, vec)

# ============================================================================
# SMT2 emission
# ============================================================================

proc smt2Script*(s: Z3Solver): string =
  ## Emit a self-contained SMT2 script for `s`: every free-constant
  ## declaration the solver has accumulated, every assertion, terminated
  ## by `(check-sat)`. The output can be piped to the `z3` CLI — useful
  ## for ablation / minimisation when a solver hangs or returns
  ## `unknown`.
  ##
  ## ```nim
  ## echo smt2Script(s)
  ## # (declare-fun x () Int)
  ## # (assert (> x 0))
  ## # (check-sat)
  ## ```
  result = $s
  if result.len == 0 or result[^1] != '\n':
    result.add '\n'
  result.add "(check-sat)\n"

proc writeSmt2*(s: Z3Solver, path: string) =
  ## Write `smt2Script(s)` to `path`. Pure convenience over
  ## `writeFile(path, smt2Script(s))`.
  writeFile(path, smt2Script(s))

proc toSmt2Benchmark*(formula: Z3Bool,
                      name = "", logic = "",
                      status = "unknown", attributes = "";
                      assumptions: openArray[Z3Bool] = @[]): string =
  ## Serialise `formula` as a self-contained SMT-LIB2 benchmark with
  ## optional `name` / `logic` / `status` / `attributes` metadata and
  ## `assumptions` (extra context formulas that are conjoined under
  ## the benchmark's `(assert ...)`). Wraps `Z3_benchmark_to_smtlib_string`.
  ##
  ## `status` defaults to `"unknown"` because Z3's serialiser
  ## unconditionally emits `(set-info :status <s>)` — passing an empty
  ## string produces malformed SMT2. The other three metadata strings
  ## are properly omitted when empty.
  ##
  ## ```nim
  ## echo toSmt2Benchmark(x > mkInt(0), name = "demo", logic = "QF_LIA")
  ## ```
  let ctx = formula.ctx
  if assumptions.len == 0:
    let s = ctx.checkErr Z3_benchmark_to_smtlib_string(
      ctx.raw, name.cstring, logic.cstring, status.cstring,
      attributes.cstring, 0, nil, formula.raw)
    $s
  else:
    var raws = newSeq[RawZ3Ast](assumptions.len)
    for i, a in assumptions:
      raws[i] = a.raw
    let s = ctx.checkErr Z3_benchmark_to_smtlib_string(
      ctx.raw, name.cstring, logic.cstring, status.cstring,
      attributes.cstring, cuint(raws.len),
      cast[ptr UncheckedArray[RawZ3Ast]](addr raws[0]),
      formula.raw)
    $s

# ============================================================================
# SMT2 parsing — stateless one-shot
# ============================================================================

proc parseSmt2String*(ctx: Z3Context, source: string): seq[Z3Bool] =
  ## Parse a self-contained SMT2 source into a `seq[Z3Bool]` of
  ## assertions. Every sort, declaration, and constant referenced
  ## must be `declare-`d in `source` itself — for pre-registered
  ## sorts / decls, use `Z3ParserContext`.
  ##
  ## ```nim
  ## let asserts = parseSmt2String(ctx,
  ##   "(declare-const x Int) (assert (> x 0))")
  ## for a in asserts:
  ##   s.add a
  ## ```
  ##
  ## Round-trips exactly with `smt2Script`. Raises `Z3Error` on parser
  ## error; Z3 silently ignores command forms it doesn't classify as
  ## assertions (e.g. `(check-sat)`), so feeding a full script is fine.
  let vec = guardParse(ctx,
    Z3_parse_smtlib2_string(ctx.raw, source.cstring,
                            0, nil, nil, 0, nil, nil))
  collectAsserts(ctx, vec)

proc parseSmt2File*(ctx: Z3Context, path: string): seq[Z3Bool] =
  ## File-input twin of `parseSmt2String`. Z3 reads the file with its
  ## own I/O layer; OS-level errors surface as `Z3Error`
  ## (`Z3_FILE_ACCESS_ERROR`).
  let vec = guardParse(ctx,
    Z3_parse_smtlib2_file(ctx.raw, path.cstring,
                          0, nil, nil, 0, nil, nil))
  collectAsserts(ctx, vec)

# ============================================================================
# Direct-to-solver feeders
# ============================================================================

proc loadSmt2String*(s: Z3Solver, source: string) =
  ## Parse `source` and assert each resulting formula directly into
  ## `s`. Skips the intermediate AST-vector — Z3 wires the parsed
  ## assertions into the solver internally. Most efficient way to
  ## ingest a long script. Raises `Z3Error` on parse failure.
  s.ctx.checkErrVoid Z3_solver_from_string(s.ctx.raw, s.raw, source.cstring)

proc loadSmt2File*(s: Z3Solver, path: string) =
  ## File-input twin of `loadSmt2String`.
  s.ctx.checkErrVoid Z3_solver_from_file(s.ctx.raw, s.raw, path.cstring)

# ============================================================================
# Eval
# ============================================================================

proc evalSmt2*(ctx: Z3Context, source: string): string =
  ## Execute an SMT2 command script (`assert`, `check-sat`,
  ## `get-model`, …) and return Z3's textual response. The
  ## response shape mirrors the `z3` CLI's output: e.g. `"sat\n"` /
  ## `"unsat\n"` from `(check-sat)`, an S-expression from
  ## `(get-model)`. Useful for tests and one-off scripting.
  let s = ctx.checkErr Z3_eval_smtlib2_string(ctx.raw, source.cstring)
  $s

# ============================================================================
# Z3ParserContext — stateful streaming parser
# ============================================================================

type
  Z3ParserContextOwn = object
    raw: RawZ3ParserContext
    ctx: Z3Context
  Z3ParserContext* = ref Z3ParserContextOwn

emitRefcountLifecycle(Z3ParserContextOwn, Z3_parser_context_dec_ref)

proc raw*(pc: Z3ParserContext): RawZ3ParserContext {.inline.} = pc.raw
proc ctx*(pc: Z3ParserContext): Z3Context {.inline.} = pc.ctx

proc newParserContext*(ctx: Z3Context): Z3ParserContext =
  ## Allocate a fresh parser context. Pre-register sorts / decls
  ## with `addSort` / `addDecl`, then call `parseFromString`
  ## repeatedly — all `declare-` / `define-` forms seen across
  ## parses accumulate on the same context, so the **n+1**th
  ## parse can reference identifiers introduced in the **n**th.
  ##
  ## ```nim
  ## let pc = newParserContext(ctx)
  ## discard pc.parseFromString("(declare-const x Int)")
  ## let asserts = pc.parseFromString("(assert (> x 0))")
  ## ```
  let raw = ctx.checkErr Z3_mk_parser_context(ctx.raw)
  Z3_parser_context_inc_ref(ctx.raw, raw)
  Z3ParserContext(raw: raw, ctx: ctx)

proc newParserContext*(): Z3ParserContext =
  newParserContext(requireCurrentContext())

proc addSort*[S](pc: Z3ParserContext, s: Z3Sort[S]) =
  ## Register a sort with the parser. Subsequent `parseFromString`
  ## calls can reference the sort by the name it was constructed
  ## with (`declareSort("Color")` → reference as `Color` in SMT2).
  pc.ctx.checkErrVoid Z3_parser_context_add_sort(
    pc.ctx.raw, pc.raw, s.raw)

proc addDecl*[A, R](pc: Z3ParserContext, f: Z3FuncDecl[A, R]) =
  ## Register a function declaration with the parser. Subsequent
  ## `parseFromString` calls can call the function by name without
  ## re-declaring it.
  pc.ctx.checkErrVoid Z3_parser_context_add_decl(
    pc.ctx.raw, pc.raw, f.raw)

proc parseFromString*(pc: Z3ParserContext, source: string): seq[Z3Bool] =
  ## Parse a fragment, resolving free identifiers against `pc`'s
  ## accumulated declarations. Any new `declare-` / `define-` forms
  ## in `source` persist on `pc` for the next call.
  let vec = guardParse(pc.ctx,
    Z3_parser_context_from_string(pc.ctx.raw, pc.raw, source.cstring))
  collectAsserts(pc.ctx, vec)

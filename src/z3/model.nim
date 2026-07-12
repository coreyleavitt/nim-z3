## `Z3Model` — witness extraction from a satisfied solver.
##
## After `s.check()` returns `zsSat`, `s.model()` produces a `Z3Model`
## — Z3's assignment of values to the free variables in the asserted
## constraints. The model can then be queried in two ways:
##
## 1. **Evaluate any AST**: `m[expr]` (sugar for `m.eval(expr)`)
##    substitutes the model's variable values into `expr` and returns
##    the simplified result — typically a numeral / literal AST.
##
## 2. **Extract a scalar**: `.toInt64`, `.toBool`, `.toBigIntStr`,
##    `.toBigRealStr` on the evaluated AST yield the raw Nim value.
##
## Convenience composers: `m.evalInt(x)` does both in one call.
##
## ## Model completion
##
## Z3 assigns values to *every* free variable, even those unconstrained
## by the assertions. This is "model completion" and is the default
## here because it matches user expectations ("give me concrete
## values"). Pass `modelCompletion = false` to leave unconstrained
## variables symbolic — useful for inspecting which variables Z3
## actually needed to constrain.

import std/options
import ./ffi, ./context, ./error, ./ast, ./builder, ./solver, ./astvector,
       ./funcdecl_types
export solver, funcdecl_types

type
  Z3ModelOwn = object
    raw: RawZ3Model
    ctx: Z3Context
  Z3Model* = ref Z3ModelOwn

# ============================================================================
# Lifecycle
# ============================================================================

emitRefcountLifecycle(Z3ModelOwn, Z3_model_dec_ref)

# Internal: wrap a freshly-returned Z3_model into a managed Z3Model.
proc wrapModel*(ctx: Z3Context, raw: RawZ3Model): Z3Model =
  ## Take ownership of a freshly-returned raw model handle. Public so
  ## sibling modules (`z3/optimize`, future tactics, …) can wrap
  ## models they obtain from their own FFI paths. Raises `Z3Error`
  ## if `raw` is nil.
  if raw.isNil:
    var e = newException(Z3InvalidUsageError,
      "Z3 returned a nil model. Most likely cause: `model()` was " &
      "called on a solver/optimiser whose last `check()` did not " &
      "return `zsSat`.")
    e.code = Z3_INVALID_USAGE
    raise e
  Z3_model_inc_ref(ctx.raw, raw)
  Z3Model(raw: raw, ctx: ctx)

proc raw*(m: Z3Model): RawZ3Model {.inline.} = m.raw
proc ctx*(m: Z3Model): Z3Context {.inline.} = m.ctx
  ## Underlying handle accessors — used by `z3/bitvec` and any external
  ## extension module that needs to construct ASTs against the same
  ## context as the model. Parallel to `Z3Solver`'s accessors.

proc model*(s: Z3Solver): Z3Model =
  ## Retrieve the model from a satisfied solver. Raises `Z3Error` if
  ## the solver's last `check()` was not `zsSat` (Z3 returned a nil
  ## model handle).
  let raw = s.ctx.checkErr Z3_solver_get_model(s.ctx.raw, s.raw)
  wrapModel(s.ctx, raw)

# ============================================================================
# Evaluation
# ============================================================================

proc eval*[T: Z3Term](m: Z3Model, a: T, modelCompletion = true): T =
  ## Evaluate `a` under this model. Returned AST is `a` with the
  ## model's variable assignments substituted in and Z3's simplifier
  ## applied. For a numeral input, you get the numeral back
  ## unchanged; for a variable, you get its assigned value as a
  ## literal.
  ##
  ## With `modelCompletion = true` (the default), variables not
  ## constrained by the assertions get assigned a model-completion
  ## value. With `false`, unconstrained inputs evaluate to themselves.
  ##
  ## v0.3 step 1 collapsed the per-family overloads (Z3Ast[S],
  ## Z3BitVec[W]) into this single generic via the unified `wrap[T]`.
  ## v0.3 step 2 extended it to `Z3Array[K, V]` and
  ## `Z3DatatypeValue[T]` — works for any typed family without
  ## adding a new overload here.
  runnableExamples:
    import z3
    let ctx = newContext()
    let s = newSolver()
    let x = mkIntVar("x")
    let y = mkIntVar("y")
    s.add x + y == mkInt(10)
    s.add x > mkInt(3)
    doAssert s.check() == zsSat
    let m = s.model()
    let xv = m.eval(x).toInt64
    let yv = m.eval(y).toInt64
    doAssert xv + yv == 10 and xv > 3
  var outRaw: RawZ3Ast
  let ok = Z3_model_eval(m.ctx.raw, m.raw, a.raw, modelCompletion, addr outRaw)
  let errCode = Z3_get_error_code(m.ctx.raw)
  if errCode != Z3_OK:
    raiseZ3Error(m.ctx.raw, errCode)
  if not ok:
    var e = newException(Z3InvalidUsageError,
      "Z3_model_eval returned false; the model couldn't evaluate the AST. " &
      "Common causes (in order of frequency): " &
      "(a) the AST was constructed in a different context than the model — " &
      "use `translate(ast, m.ctx)` first; " &
      "(b) `modelCompletion = false` was passed and the AST references an " &
      "unconstrained variable or function the model doesn't pin; " &
      "(c) the AST references a function whose interpretation Z3 didn't " &
      "synthesise (rare).")
    e.code = Z3_INVALID_USAGE
    raise e
  wrap[T](m.ctx, outRaw)

proc `[]`*[T: Z3Term](m: Z3Model, a: T): T =
  ## Sugar for `m.eval(a)`.
  m.eval(a)

# ============================================================================
# Scalar extractors — only valid on numeral / literal ASTs
# ============================================================================
#
# These are typically called on the result of `m.eval(...)` because
# that's where literals come from after solving. Calling on a
# non-literal AST raises Z3Error.

proc toInt64*(a: Z3Int): int64 =
  ## Extract an `int64` value from an integer literal. Raises `Z3Error`
  ## if the AST isn't a literal numeral or its value doesn't fit in
  ## `int64`. For arbitrary-precision integers, use `toBigIntStr`.
  ##
  ## **ADR-N0005 hard break**: renamed from `toInt` in N4.4; no
  ## deprecation alias. Callers should update to `toInt64`.
  var v: int64
  if not Z3_get_numeral_int64(a.ctx.raw, a.raw, addr v):
    var e = newException(Z3InvalidUsageError,
      "Z3Int.toInt64: AST `" & $a & "` is not a literal int (or doesn't " &
      "fit in int64). Use `toBigIntStr` for arbitrary-precision integers.")
    e.code = Z3_INVALID_USAGE
    raise e
  v

proc toIntOpt*(a: Z3Int): Option[int] =
  ## Extract an `int` value from an integer literal as `Option[int]`.
  ## Returns `none` instead of raising when the AST isn't a literal
  ## or doesn't fit in `cint` (32-bit range on most platforms).
  ## For 64-bit range, use `toInt64` directly (which raises) or check
  ## `toBigIntStr` for exact representation.
  var v: cint
  if Z3_get_numeral_int(a.ctx.raw, a.raw, addr v):
    some(int(v))
  else:
    none(int)

proc toBigIntStr*(a: Z3Int): string =
  ## Lossless decimal-string form of an integer literal. Works for
  ## any-precision integers including those that wouldn't fit in
  ## `cint`. Raises `Z3Error` if the AST isn't a numeral.
  let s = Z3_get_numeral_string(a.ctx.raw, a.raw)
  if s.isNil:
    var e = newException(Z3InvalidUsageError,
      "Z3Int.toBigIntStr: AST `" & $a & "` is not a numeral.")
    e.code = Z3_INVALID_USAGE
    raise e
  $s

proc toBigRealStr*(a: Z3Real): string =
  ## Lossless string form of a real literal (`"3/2"`, `"42"`, etc.).
  let s = Z3_get_numeral_string(a.ctx.raw, a.raw)
  if s.isNil:
    var e = newException(Z3InvalidUsageError,
      "Z3Real.toBigRealStr: AST `" & $a & "` is not a numeral.")
    e.code = Z3_INVALID_USAGE
    raise e
  $s

proc toBool*(a: Z3Bool): bool =
  ## Extract the `bool` value from a boolean literal. Raises `Z3Error`
  ## if the AST is `Z3_L_UNDEF` (neither true nor false at the
  ## syntactic level — most commonly because it's an unevaluated
  ## expression).
  let v = Z3_get_bool_value(a.ctx.raw, a.raw)
  case v
  of Z3_L_TRUE: true
  of Z3_L_FALSE: false
  of Z3_L_UNDEF:
    var e = newException(Z3InvalidUsageError,
      "Z3Bool.toBool: AST `" & $a & "` is not a literal true/false. " &
      "Did you forget to evaluate it through `model[ast]` first?")
    e.code = Z3_INVALID_USAGE
    raise e

proc toBoolOpt*(a: Z3Bool): Option[bool] =
  ## `toBool` in `Option[bool]` form.
  case Z3_get_bool_value(a.ctx.raw, a.raw)
  of Z3_L_TRUE: some(true)
  of Z3_L_FALSE: some(false)
  of Z3_L_UNDEF: none(bool)

# ============================================================================
# Composers — eval + extract in one call
# ============================================================================

proc evalInt*(m: Z3Model, a: Z3Int, modelCompletion = true): int64 {.inline.} =
  ## `m.eval(a).toInt64` in one call.
  m.eval(a, modelCompletion).toInt64

proc evalBool*(m: Z3Model, a: Z3Bool, modelCompletion = true): bool {.inline.} =
  ## `m.eval(a).toBool` in one call.
  m.eval(a, modelCompletion).toBool

proc evalBigIntStr*(m: Z3Model, a: Z3Int, modelCompletion = true): string {.inline.} =
  ## `m.eval(a).toBigIntStr` in one call.
  m.eval(a, modelCompletion).toBigIntStr

proc evalBigRealStr*(m: Z3Model, a: Z3Real, modelCompletion = true): string {.inline.} =
  ## `m.eval(a).toBigRealStr` in one call.
  m.eval(a, modelCompletion).toBigRealStr

# ============================================================================
# Real extraction — float64 approximation
# ============================================================================
#
# Z3 stores reals exactly as rationals (`Z3_get_numeral_string` returns
# the exact form, e.g. "1/3" or "3.14"). The float64 approximation is
# lossy by definition; the v0.3 plan §7 Q3 settled the precision
# question as "Z3 picks the closest representable double, no precision
# knob on our side."
#
# Z3's `Z3_get_numeral_double` requires a literal numeral AST. We
# `simplify` the input first — consistent with `toUint` / `toInt64` —
# so concrete expression trees fold to a numeral before extraction.
# Epsilon-bound expressions from optimisation reals (`1/2 + ε`) don't
# fold to a numeral and raise `Z3Error`.

proc toRealApprox*(a: Z3Real): float =
  ## Lossy float64 approximation of a `Z3Real` literal. Internally
  ## `Z3_simplify`s first so concrete expression trees fold before
  ## extraction, mirroring `toUint` / `toInt64` on `Z3BitVec`.
  ##
  ## Raises `Z3Error` if the AST doesn't reduce to a literal numeral
  ## (most commonly: an epsilon-bound expression from optimisation
  ## reals, or a free Real variable).
  let folded = a.ctx.checkErr Z3_simplify(a.ctx.raw, a.raw)
  # No out-param indicator on Z3_get_numeral_double; check the error
  # code instead. A non-numeral AST sets `Z3_INVALID_ARG` (or similar)
  # which `checkErrVoid` would normally raise — we replicate that here.
  let v = Z3_get_numeral_double(a.ctx.raw, folded)
  let errCode = Z3_get_error_code(a.ctx.raw)
  if errCode != Z3_OK:
    raiseZ3Error(a.ctx.raw, errCode)
  float(v)

proc toRealOpt*(a: Z3Real): Option[float] =
  ## `toRealApprox` in `Option[float]` form. Returns `none` instead of
  ## raising when the AST doesn't reduce to a literal numeral (e.g. a
  ## free Real variable or an epsilon-bound expression). Returns
  ## `some(approx)` for any concrete rational literal that Z3 can fold
  ## to a double.
  let folded = a.ctx.checkErr Z3_simplify(a.ctx.raw, a.raw)
  let v = Z3_get_numeral_double(a.ctx.raw, folded)
  let errCode = Z3_get_error_code(a.ctx.raw)
  if errCode != Z3_OK:
    none(float)
  else:
    some(float(v))

proc evalRealApprox*(m: Z3Model, a: Z3Real, modelCompletion = true): float {.inline.} =
  ## `m.eval(a, modelCompletion).toRealApprox` in one call.
  ## **ADR-N0005 hard break**: renamed from `evalReal` in N4.4+; the old name
  ## was misleading because the result is a lossy float64 approximation.
  m.eval(a, modelCompletion).toRealApprox

# ============================================================================
# Pretty-print
# ============================================================================

proc `$`*(m: Z3Model): string =
  ## SMT-LIB rendering of the full model — every assigned variable
  ## and its value.
  $Z3_model_to_string(m.ctx.raw, m.raw)

# ============================================================================
# Model enumeration — N2.1
# ============================================================================

proc numConsts*(m: Z3Model): int =
  ## Number of constant (nullary) function declarations pinned by this model.
  int(Z3_model_get_num_consts(m.ctx.raw, m.raw))

proc constDecl*(m: Z3Model, i: int): Z3FuncDecl[tuple[], Z3AnyAst] =
  ## `i`-th constant declaration (0-based).
  ##
  ## Returns a `Z3FuncDecl[tuple[], Z3AnyAst]` — the widened "I don't
  ## know the sort" form. `ArgsTup = tuple[]` because constants are
  ## nullary; `Ret = Z3AnyAst` because the return sort is only known
  ## at runtime. Use `narrowFuncDecl[ArgsTup, Ret]` (from `z3/funcdecl`)
  ## to recover a typed form with a runtime sort/arity check.
  ##
  ## `wrapFuncDecl` takes ownership (inc_refs). Raises if `i` is out of bounds.
  doAssert i >= 0 and i < m.numConsts,
    "Z3Model.constDecl: index " & $i & " out of bounds [0, " & $m.numConsts & ")"
  let raw = m.ctx.checkErr Z3_model_get_const_decl(m.ctx.raw, m.raw, cuint(i))
  wrapFuncDecl[tuple[], Z3AnyAst](m.ctx, raw)

proc numFuncs*(m: Z3Model): int =
  ## Number of non-nullary function declarations pinned by this model.
  int(Z3_model_get_num_funcs(m.ctx.raw, m.raw))

proc funcDecl*(m: Z3Model, i: int): Z3FuncDecl[tuple[], Z3AnyAst] =
  ## `i`-th function declaration (0-based).
  ##
  ## Returns a `Z3FuncDecl[tuple[], Z3AnyAst]` — the widened "I don't
  ## know the arity or return sort" form. This is the natural type for
  ## dynamically-enumerated declarations. Use `narrowFuncDecl[ArgsTup, Ret]`
  ## (from `z3/funcdecl`) to recover a typed form with a runtime check.
  ##
  ## `wrapFuncDecl` takes ownership (inc_refs). Raises if `i` is out of bounds.
  doAssert i >= 0 and i < m.numFuncs,
    "Z3Model.funcDecl: index " & $i & " out of bounds [0, " & $m.numFuncs & ")"
  let raw = m.ctx.checkErr Z3_model_get_func_decl(m.ctx.raw, m.raw, cuint(i))
  wrapFuncDecl[tuple[], Z3AnyAst](m.ctx, raw)

proc numSorts*(m: Z3Model): int =
  ## Number of uninterpreted sorts whose finite universe the model enumerates.
  int(Z3_model_get_num_sorts(m.ctx.raw, m.raw))

proc sort*(m: Z3Model, i: int): Z3Sort[stUninterpreted] =
  ## `i`-th enumerated uninterpreted sort (0-based).
  ##
  ## Z3's model enumeration only surfaces uninterpreted sorts (declared
  ## via `(declare-sort Foo 0)` or `declareSort`) — built-in sorts
  ## (Int, Bool, BitVec[N], …) are never in this table. The return type
  ## `Z3Sort[stUninterpreted]` reflects that invariant statically.
  ##
  ## Note: `Z3Sort` is a value type; `raw` is accessible on the result.
  ## Raises if `i` is out of bounds.
  doAssert i >= 0 and i < m.numSorts,
    "Z3Model.sort: index " & $i & " out of bounds [0, " & $m.numSorts & ")"
  let raw = m.ctx.checkErr Z3_model_get_sort(m.ctx.raw, m.raw, cuint(i))
  Z3Sort[stUninterpreted](raw: raw, ctx: m.ctx)

proc sortUniverse*(m: Z3Model, s: Z3Sort[stUninterpreted]): Z3AstVector =
  ## Finite set of AST nodes assigned to uninterpreted sort `s` in this model.
  ##
  ## Ownership: despite the Z3 header claiming the caller must release
  ## this vector, `Z3_model_get_sort_universe` returns a vector Z3 keeps
  ## for itself — it registers the vector in the context's managed-object
  ## list and retains an internal alias, then frees it at
  ## `Z3_del_context`. Releasing it ourselves (dec_ref to zero) frees the
  ## block out from under Z3's alias and its `~context()`, a
  ## use-after-free reproduced on both Z3 4.13.4 and 4.15.0. We therefore
  ## return it as a **borrowed** vector: no inc_ref, and a `=destroy` that
  ## skips the dec_ref (Z3 frees it via `Z3_del_context`). See
  ## `wrapAstVectorBorrowed` and ADR-FC-0012 / slice D3.
  let raw = m.ctx.checkErr Z3_model_get_sort_universe(m.ctx.raw, m.raw, s.raw)
  wrapAstVectorBorrowed(m.ctx, raw)

proc hasInterp*[ArgsTup: tuple, Ret](m: Z3Model,
    d: Z3FuncDecl[ArgsTup, Ret]): bool =
  ## `true` if declaration `d` has an interpretation pinned in model `m`.
  Z3_model_has_interp(m.ctx.raw, m.raw, d.raw)

proc translate*(m: Z3Model, target: Z3Context): Z3Model =
  ## Return a copy of `m` with all AST nodes translated into `target`.
  ## Useful for cross-context reasoning (e.g. transfer a satisfying model
  ## to a second solver that works in a sibling context).
  let raw = m.ctx.checkErr Z3_model_translate(m.ctx.raw, m.raw, target.raw)
  wrapModel(target, raw)

# ============================================================================
# Model construction — N2.2
# ============================================================================
#
# These procs construct hand-crafted models — useful for testing formula
# falsity by building a witness, or for synthesis consumers that produce
# models from scratch.
#
# `Z3FuncInterpMut` is a mutable handle to an in-progress function
# interpretation. It holds a context + raw RawZ3FuncInterp pair. The
# interpreter is owned by the parent `Z3Model` (via the model's refcount);
# the `Z3FuncInterpMut` does not hold an extra ref.

type Z3FuncInterpMut* = object
  ## Mutable handle to a function interpretation being constructed.
  ## Obtained from `addFuncInterp`; valid only while the parent
  ## model is alive. Not reference-counted (the model owns the interp).
  ctx*: Z3Context
  raw*: RawZ3FuncInterp

proc newModel*(ctx: Z3Context): Z3Model =
  ## Construct a fresh empty `Z3Model` in context `ctx`.
  ## The model has no constant or function interpretations initially.
  ## Routes through `wrapModel` for consistent nil-guard + inc_ref.
  let raw = ctx.checkErr Z3_mk_model(ctx.raw)
  wrapModel(ctx, raw)

proc addConstInterp*[ArgsTup: tuple, Ret, V: Z3Term](
    m: Z3Model, f: Z3FuncDecl[ArgsTup, Ret], value: V) =
  ## Pin constant declaration `f` to `value` in model `m`.
  ## `f` must be a nullary (0-arity) function declaration. After this
  ## call `m.hasInterp(f)` returns `true` and `m.eval` returns `value`.
  ## `value` accepts any `Z3Term` (typed AST or `Z3AnyAst`).
  m.ctx.checkErrVoid Z3_add_const_interp(m.ctx.raw, m.raw, f.raw, value.raw)

proc addFuncInterp*[ArgsTup: tuple, Ret, D: Z3Term](
    m: Z3Model, f: Z3FuncDecl[ArgsTup, Ret],
    defaultVal: D): Z3FuncInterpMut =
  ## Begin a function interpretation for declaration `f` in model `m`.
  ## `defaultVal` is the else-value (returned for any argument combination
  ## not explicitly covered by `addEntry`). Returns a `Z3FuncInterpMut`
  ## handle for adding entries and updating the else-value.
  ## `defaultVal` accepts any `Z3Term` (typed AST or `Z3AnyAst`).
  let raw = m.ctx.checkErr Z3_add_func_interp(m.ctx.raw, m.raw, f.raw,
                                               defaultVal.raw)
  Z3FuncInterpMut(ctx: m.ctx, raw: raw)

proc setElse*[E: Z3Term](fi: Z3FuncInterpMut, elseVal: E) =
  ## Replace the else-value of function interpretation `fi` with `elseVal`.
  ## Useful to update the default after `addFuncInterp` was called, or to
  ## change the default after adding explicit entries.
  fi.ctx.checkErrVoid Z3_func_interp_set_else(fi.ctx.raw, fi.raw, elseVal.raw)

proc addEntry*[A: Z3Term, V: Z3Term](fi: Z3FuncInterpMut,
                                      args: openArray[A], value: V) =
  ## Add a `(args -> value)` row to function interpretation `fi`.
  ## `args` must have the same length as the declared arity of the
  ## function. After this call `m.eval(f(args))` returns `value`.
  ## All arguments accept any `Z3Term` (typed AST or `Z3AnyAst`).
  ##
  ## Internally this wraps the arg array into a `Z3AstVector` because
  ## `Z3_func_interp_add_entry` takes a `Z3_ast_vector`.
  let v = Z3_mk_ast_vector(fi.ctx.raw)
  Z3_ast_vector_inc_ref(fi.ctx.raw, v)
  for a in args:
    Z3_ast_vector_push(fi.ctx.raw, v, a.raw)
  fi.ctx.checkErrVoid Z3_func_interp_add_entry(fi.ctx.raw, fi.raw, v, value.raw)
  Z3_ast_vector_dec_ref(fi.ctx.raw, v)

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
## 2. **Extract a scalar**: `.toInt`, `.toBool`, `.toBigIntStr`,
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
import ./ffi, ./context, ./sort, ./ast, ./builder, ./solver
export solver

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
    var e = newException(Z3Error,
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

proc eval*[S: static SortTag](m: Z3Model, a: Z3Ast[S],
                              modelCompletion = true): Z3Ast[S] =
  ## Evaluate `a` under this model. The returned AST is `a` with the
  ## model's variable assignments substituted in and Z3's simplifier
  ## applied. For a numeral input, you get the numeral back unchanged;
  ## for a variable, you get its assigned value as a literal.
  ##
  ## With `modelCompletion = true` (the default), variables not
  ## constrained by the assertions get assigned a model-completion
  ## value. With `false`, unconstrained inputs evaluate to themselves
  ## (the same `Z3Ast` you passed in).
  var outRaw: RawZ3Ast
  let ok = Z3_model_eval(m.ctx.raw, m.raw, a.raw, modelCompletion, addr outRaw)
  let errCode = Z3_get_error_code(m.ctx.raw)
  if errCode != Z3_OK:
    raiseZ3Error(m.ctx, errCode)
  if not ok:
    var e = newException(Z3Error,
      "Z3_model_eval returned false; the model couldn't evaluate the AST. " &
      "Most likely cause: the AST references a function the model doesn't " &
      "constrain.")
    e.code = Z3_INVALID_USAGE
    raise e
  wrap[Z3Ast[S]](m.ctx, outRaw)

proc `[]`*[S: static SortTag](m: Z3Model, a: Z3Ast[S]): Z3Ast[S] =
  ## Sugar for `m.eval(a)`.
  m.eval(a)

# ============================================================================
# Scalar extractors — only valid on numeral / literal ASTs
# ============================================================================
#
# These are typically called on the result of `m.eval(...)` because
# that's where literals come from after solving. Calling on a
# non-literal AST raises Z3Error.

proc toInt*(a: Z3Int): int =
  ## Extract an `int` value from an integer literal. Raises `Z3Error`
  ## if the AST isn't a literal numeral or its value doesn't fit in
  ## `cint`. For arbitrary-precision integers, use `toBigIntStr`.
  var v: cint
  if not Z3_get_numeral_int(a.ctx.raw, a.raw, addr v):
    var e = newException(Z3Error,
      "Z3Int.toInt: AST `" & $a & "` is not a literal int (or doesn't " &
      "fit in cint). Use `toBigIntStr` for arbitrary-precision integers.")
    e.code = Z3_INVALID_USAGE
    raise e
  int(v)

proc toIntOpt*(a: Z3Int): Option[int] =
  ## `toInt` in `Option[int]` form. Returns `none` instead of raising
  ## when the AST isn't a literal or doesn't fit in `cint`.
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
    var e = newException(Z3Error,
      "Z3Int.toBigIntStr: AST `" & $a & "` is not a numeral.")
    e.code = Z3_INVALID_USAGE
    raise e
  $s

proc toBigRealStr*(a: Z3Real): string =
  ## Lossless string form of a real literal (`"3/2"`, `"42"`, etc.).
  let s = Z3_get_numeral_string(a.ctx.raw, a.raw)
  if s.isNil:
    var e = newException(Z3Error,
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
    var e = newException(Z3Error,
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

proc evalInt*(m: Z3Model, a: Z3Int, modelCompletion = true): int {.inline.} =
  ## `m.eval(a).toInt` in one call.
  m.eval(a, modelCompletion).toInt

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
# Pretty-print
# ============================================================================

proc `$`*(m: Z3Model): string =
  ## SMT-LIB rendering of the full model — every assigned variable
  ## and its value.
  $Z3_model_to_string(m.ctx.raw, m.raw)

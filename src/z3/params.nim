## `Z3Params` — typed parameter bag.
##
## Z3 uses a single `Z3_params` object to carry configuration for
## tactics, solvers, and the optimiser. Keys are symbol names; values
## are typed (`bool` / `uint` / `double` / symbol). This module wraps
## the lifecycle and the four typed `set` calls.
##
## v0.2 deferral history: step 1 wanted this for `Z3_simplify_ex`,
## step 7 wanted it for box / Pareto multi-objective on `Z3Optimize`,
## step 8 (tactics) needs `using_params`. Landing it here as the
## general primitive every consumer can pick up.

import ./ffi, ./context, ./error, ./lifecycle

type
  Z3ParamsOwn = object
    raw: RawZ3Params
    ctx: Z3Context
  Z3Params* = ref Z3ParamsOwn

emitRefcountLifecycle(Z3ParamsOwn, Z3_params_dec_ref)

proc newParams*(ctx: Z3Context): Z3Params =
  ## Fresh empty parameter bag bound to `ctx`.
  let raw = ctx.checkErr Z3_mk_params(ctx.raw)
  Z3_params_inc_ref(ctx.raw, raw)
  Z3Params(raw: raw, ctx: ctx)

proc newParams*(): Z3Params =
  newParams(requireCurrentContext())

# ============================================================================
# Setters — one per Z3 value type
# ============================================================================
#
# Z3's params API distinguishes bool / uint / double / symbol values
# (no string-as-string; symbol-valued params are how strings appear).
# We expose each with the same `set` name; Nim's overload resolution
# picks the right FFI proc from the value type.

proc symbolFor(ctx: Z3Context, name: string): RawZ3Symbol =
  ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)

proc set*(p: Z3Params, key: string, value: bool) =
  let k = symbolFor(p.ctx, key)
  Z3_params_set_bool(p.ctx.raw, p.raw, k, value)

proc set*(p: Z3Params, key: string, value: uint) =
  let k = symbolFor(p.ctx, key)
  Z3_params_set_uint(p.ctx.raw, p.raw, k, cuint(value))

proc set*(p: Z3Params, key: string, value: int) =
  ## Convenience: take an `int`, cast to `cuint`. Negative values
  ## wrap; pass a `uint` explicitly to avoid surprises.
  let k = symbolFor(p.ctx, key)
  Z3_params_set_uint(p.ctx.raw, p.raw, k, cuint(value))

proc set*(p: Z3Params, key: string, value: float) =
  let k = symbolFor(p.ctx, key)
  Z3_params_set_double(p.ctx.raw, p.raw, k, cdouble(value))

proc set*(p: Z3Params, key: string, value: string) =
  ## String-valued params are encoded as Z3 symbols.
  let k = symbolFor(p.ctx, key)
  let v = symbolFor(p.ctx, value)
  Z3_params_set_symbol(p.ctx.raw, p.raw, k, v)

# ============================================================================
# Raw-handle accessors + pretty
# ============================================================================

proc raw*(p: Z3Params): RawZ3Params {.inline.} = p.raw
proc ctx*(p: Z3Params): Z3Context {.inline.} = p.ctx

proc `$`*(p: Z3Params): string =
  $Z3_params_to_string(p.ctx.raw, p.raw)

# ============================================================================
# Z3ParamDescrs — solver/tactic/simplifier param schema (v0.5 step 6B)
# ============================================================================
#
# A `Z3Params` is the **bag** you set on a solver / tactic. A
# `Z3ParamDescrs` is the **schema** describing what keys that bag
# should conform to: each declared parameter has a name, a kind
# (uint / bool / double / symbol / string / other), and a
# documentation string. Used by tooling that wants to enumerate
# legal params before constructing a `Z3Params` against a specific
# solver / tactic, and to surface better error messages when an
# unknown key is set.
#
# Per-handle constructors (`getParamDescrs(s: Z3Solver)` /
# `getParamDescrs(t: Z3Tactic)`) live in `z3/solver` and `z3/tactic`
# respectively to keep the dependency layering one-directional
# (params is a lower layer than solver / tactic).

type
  Z3ParamDescrsOwn = object
    raw: RawZ3ParamDescrs
    ctx: Z3Context
  Z3ParamDescrs* = ref Z3ParamDescrsOwn
    ## Refcount-managed handle to a Z3 param-descrs schema.

  ParamKind* = enum
    ## Nim-side classification of each parameter's declared type.
    ## Mirrors Z3's `Z3_param_kind`. Used by the indexer
    ## `paramDescrs[name]: ParamKind` to drive value-construction
    ## dispatch at the call site.
    pkUInt    ## `Z3_PK_UINT` — non-negative integer.
    pkBool    ## `Z3_PK_BOOL` — boolean.
    pkDouble  ## `Z3_PK_DOUBLE` — IEEE 754 double.
    pkSymbol  ## `Z3_PK_SYMBOL` — Z3 symbol.
    pkString  ## `Z3_PK_STRING` — string (rarer; some params).
    pkOther   ## `Z3_PK_OTHER` — Z3-internal kinds not exposed in the
              ## public API. Setting these via the public surface is
              ## not supported.
    pkInvalid ## `Z3_PK_INVALID` — sentinel; never returned for a
              ## name that's actually in the schema.

emitRefcountLifecycle(Z3ParamDescrsOwn, Z3_param_descrs_dec_ref)

proc wrapParamDescrs*(ctx: Z3Context,
                      raw: RawZ3ParamDescrs): Z3ParamDescrs =
  ## Adopt a freshly-returned raw param-descrs handle. Public so
  ## sibling modules (`z3/solver` for `getParamDescrs(s)`,
  ## `z3/tactic` for `getParamDescrs(t)`) can build the typed
  ## handle from their own FFI calls.
  if raw.isNil:
    var e = newException(Z3InvalidUsageError,
      "Z3 returned a nil param-descrs handle.")
    e.code = Z3_INVALID_USAGE
    raise e
  Z3_param_descrs_inc_ref(ctx.raw, raw)
  Z3ParamDescrs(raw: raw, ctx: ctx)

proc raw*(pd: Z3ParamDescrs): RawZ3ParamDescrs {.inline.} = pd.raw
proc ctx*(pd: Z3ParamDescrs): Z3Context {.inline.} = pd.ctx

# ----------------------------------------------------------------------------
# ParamKind <-> Z3ParamKindFFI conversion
# ----------------------------------------------------------------------------

proc toParamKind(k: Z3ParamKindFFI): ParamKind {.inline.} =
  case k
  of Z3_PK_UINT:    pkUInt
  of Z3_PK_BOOL:    pkBool
  of Z3_PK_DOUBLE:  pkDouble
  of Z3_PK_SYMBOL:  pkSymbol
  of Z3_PK_STRING:  pkString
  of Z3_PK_OTHER:   pkOther
  of Z3_PK_INVALID: pkInvalid

# ----------------------------------------------------------------------------
# Surface
# ----------------------------------------------------------------------------

proc len*(pd: Z3ParamDescrs): int =
  ## Number of parameters in the schema.
  int(Z3_param_descrs_size(pd.ctx.raw, pd.raw))

proc keys*(pd: Z3ParamDescrs): seq[string] =
  ## All parameter names in the schema, in the order Z3 exposes them.
  ## (Order is not specified by Z3 but is stable across calls on the
  ## same handle.)
  result = newSeq[string](pd.len)
  for i in 0 ..< pd.len:
    let sym = Z3_param_descrs_get_name(pd.ctx.raw, pd.raw, cuint(i))
    let symStr = Z3_get_symbol_string(pd.ctx.raw, sym)
    result[i] = $symStr

proc `[]`*(pd: Z3ParamDescrs, name: string): ParamKind =
  ## Look up the declared kind of parameter `name`. Returns
  ## `pkInvalid` if no such parameter is in the schema (Z3 doesn't
  ## raise for unknown keys here — the `Z3_PK_INVALID` sentinel is
  ## how the lookup signals "no match").
  let sym = symbolFor(pd.ctx, name)
  toParamKind(Z3_param_descrs_get_kind(pd.ctx.raw, pd.raw, sym))

proc getDocumentation*(pd: Z3ParamDescrs, name: string): string =
  ## Human-readable description of parameter `name`. Returns an
  ## empty string if `name` isn't in the schema or Z3 has no
  ## documentation for it.
  let sym = symbolFor(pd.ctx, name)
  let s = Z3_param_descrs_get_documentation(pd.ctx.raw, pd.raw, sym)
  if s.isNil: "" else: $s

proc `$`*(pd: Z3ParamDescrs): string =
  ## SMT-LIB-shaped rendering of the schema — name + kind + doc
  ## for each declared parameter. Useful for `(help-solver)`-style
  ## interactive output.
  $Z3_param_descrs_to_string(pd.ctx.raw, pd.raw)

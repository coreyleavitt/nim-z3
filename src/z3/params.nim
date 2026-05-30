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

import ./ffi, ./context

type
  Z3ParamsOwn = object
    raw: RawZ3Params
    ctx: Z3Context
  Z3Params* = ref Z3ParamsOwn

proc `=destroy`(p: Z3ParamsOwn) {.raises: [].} =
  try:
    if not p.raw.isNil and p.ctx != nil and not p.ctx.raw.isNil:
      Z3_params_dec_ref(p.ctx.raw, p.raw)
  except CatchableError:
    discard

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

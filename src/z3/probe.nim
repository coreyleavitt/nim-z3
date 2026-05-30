## `z3/probe` — goal probes + conditional tactic dispatch.
##
## A **`Z3Probe`** is a function from `Z3Goal` to `float` — the
## numeric measurement Z3 uses to drive conditional tactic dispatch.
## Named probes (`"num-consts"`, `"num-bool-consts"`,
## `"num-arith-consts"`, `"num-bv-consts"`, `"size"`, etc.) inspect
## a goal's structure; numeric / boolean combinators build composite
## predicates; **`condTactic`** dispatches between two tactics based
## on whether a probe's result is non-zero.
##
## ## Operator-overloading note
##
## The comparison operators (`<`, `<=`, `>`, `>=`, `==`) on
## `Z3Probe` return a **new `Z3Probe`** — not `bool`. This is
## intentional: the operator notation reads naturally at the
## call site (`mkProbe("num-consts") < 100.0` builds a probe that
## evaluates to 1.0 when the goal has fewer than 100 constants).
##
## ```nim
## let cheapTactic = mkTactic("simplify")
## let heavyTactic = mkTactic("smt")
## let pipeline = condTactic(
##   mkProbe("num-consts") < 100.0,
##   cheapTactic,
##   heavyTactic)
## ```
##
## ## When you reach for this
##
## Probes + condTactic let you build **adaptive solvers**: dispatch
## a fast tactic for small / well-behaved goals and a heavy one for
## large / hard goals, all decided at solve time by inspecting the
## goal's structure.

import ./ffi, ./context, ./ast, ./lifecycle, ./tactic

# ============================================================================
# Z3Probe — typed ref-handle
# ============================================================================

type
  Z3ProbeOwn = object
    raw: RawZ3Probe
    ctx: Z3Context
  Z3Probe* = ref Z3ProbeOwn

emitRefcountLifecycle(Z3ProbeOwn, Z3_probe_dec_ref)

proc wrapProbe*(ctx: Z3Context, raw: RawZ3Probe): Z3Probe =
  ## Adopt a freshly-returned raw probe handle.
  if raw.isNil:
    var e = newException(Z3Error, "Z3 returned a nil probe handle.")
    e.code = Z3_INVALID_USAGE
    raise e
  Z3_probe_inc_ref(ctx.raw, raw)
  Z3Probe(raw: raw, ctx: ctx)

proc raw*(p: Z3Probe): RawZ3Probe {.inline.} = p.raw
proc ctx*(p: Z3Probe): Z3Context {.inline.} = p.ctx

# ============================================================================
# Construction
# ============================================================================

proc mkProbe*(ctx: Z3Context, name: string): Z3Probe =
  ## Look up a built-in probe by name. Common names: `"num-consts"`,
  ## `"num-bool-consts"`, `"num-arith-consts"`, `"num-bv-consts"`,
  ## `"size"`, `"depth"`, `"num-quantifiers"`. The full list is
  ## printable via Z3's `(get-probes)` SMT command.
  wrapProbe(ctx, ctx.checkErr Z3_mk_probe(ctx.raw, name.cstring))
proc mkProbe*(name: string): Z3Probe =
  mkProbe(requireCurrentContext(), name)

proc mkProbeConst*(ctx: Z3Context, value: float): Z3Probe =
  ## Constant probe — always evaluates to `value`. Used by the
  ## comparison-with-literal overloads below to auto-lift floats.
  wrapProbe(ctx, ctx.checkErr Z3_probe_const(ctx.raw, cdouble(value)))
proc mkProbeConst*(value: float): Z3Probe =
  mkProbeConst(requireCurrentContext(), value)

# ============================================================================
# Evaluation
# ============================================================================

proc apply*(p: Z3Probe, g: Z3Goal): float =
  ## Evaluate the probe on `g`. Boolean probes return 0.0 / 1.0;
  ## numeric probes return the measurement.
  float(Z3_probe_apply(p.ctx.raw, p.raw, g.raw))

# ============================================================================
# Comparison combinators — return new probes (not bool)
# ============================================================================

template emitCmp(opName: untyped, ffi: untyped) =
  proc opName*(p1, p2: Z3Probe): Z3Probe =
    wrapProbe(p1.ctx, p1.ctx.checkErr ffi(p1.ctx.raw, p1.raw, p2.raw))
  proc opName*(p: Z3Probe, v: float): Z3Probe =
    opName(p, mkProbeConst(p.ctx, v))
  proc opName*(v: float, p: Z3Probe): Z3Probe =
    opName(mkProbeConst(p.ctx, v), p)

emitCmp(`<`,  Z3_probe_lt)
emitCmp(`<=`, Z3_probe_le)
emitCmp(`>`,  Z3_probe_gt)
emitCmp(`>=`, Z3_probe_ge)
emitCmp(`==`, Z3_probe_eq)

# ============================================================================
# Boolean combinators
# ============================================================================

proc `and`*(p1, p2: Z3Probe): Z3Probe =
  ## Returns 1.0 iff both `p1` and `p2` evaluate non-zero on the
  ## same goal.
  wrapProbe(p1.ctx, p1.ctx.checkErr Z3_probe_and(p1.ctx.raw, p1.raw, p2.raw))

proc `or`*(p1, p2: Z3Probe): Z3Probe =
  ## Returns 1.0 iff at least one of `p1` / `p2` evaluates non-zero.
  wrapProbe(p1.ctx, p1.ctx.checkErr Z3_probe_or(p1.ctx.raw, p1.raw, p2.raw))

proc `not`*(p: Z3Probe): Z3Probe =
  ## Returns 1.0 iff `p` evaluates to 0.0.
  wrapProbe(p.ctx, p.ctx.checkErr Z3_probe_not(p.ctx.raw, p.raw))

# ============================================================================
# condTactic — the headline combinator
# ============================================================================

proc condTactic*(probe: Z3Probe,
                 ifTactic: Z3Tactic,
                 elseTactic: Z3Tactic): Z3Tactic =
  ## Build a tactic that applies `ifTactic` to a goal when `probe`
  ## evaluates non-zero and `elseTactic` otherwise. The result is a
  ## regular `Z3Tactic` — composes with `andThen` / `orElse` /
  ## `repeat` etc.
  ##
  ## ```nim
  ## let pipeline = condTactic(
  ##   mkProbe("num-consts") < 100.0,
  ##   mkTactic("simplify"),
  ##   mkTactic("smt"))
  ## ```
  let raw = probe.ctx.checkErr Z3_tactic_cond(
    probe.ctx.raw, probe.raw, ifTactic.raw, elseTactic.raw)
  wrapTactic(probe.ctx, raw)

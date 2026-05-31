## `z3/params.Z3ParamDescrs` tests — solver/tactic param schema
## introspection (v0.5 step 6B).
##
## `Z3Params` is the bag you set on a solver / tactic / optimizer.
## `Z3ParamDescrs` is the schema describing what keys the bag should
## conform to, what type each value should be, and what each
## parameter means.

import std/[unittest, strutils]
import z3

suite "Z3ParamDescrs — tracer":
  test "getParamDescrs on a solver returns a non-empty schema":
    let ctx = newContext()
    let s = newSolver()
    let pd = getParamDescrs(s)
    # Z3's solver schema always exposes at least `timeout`,
    # `random_seed`, `model`, `unsat_core`, etc.
    check pd.len > 0

suite "Z3ParamDescrs — solver schema":
  test "solver schema includes the well-known timeout / random_seed keys":
    let ctx = newContext()
    let s = newSolver()
    let pd = getParamDescrs(s)
    let ks = pd.keys
    check "timeout" in ks
    check "random_seed" in ks

  test "timeout is a uint param; random_seed is a uint param":
    let ctx = newContext()
    let s = newSolver()
    let pd = getParamDescrs(s)
    check pd["timeout"] == pkUInt
    check pd["random_seed"] == pkUInt

  test "unknown param name maps to pkInvalid":
    let ctx = newContext()
    let s = newSolver()
    let pd = getParamDescrs(s)
    check pd["definitely_not_a_real_solver_param"] == pkInvalid

  test "getDocumentation returns a non-empty string for known keys":
    let ctx = newContext()
    let s = newSolver()
    let pd = getParamDescrs(s)
    let doc = pd.getDocumentation("timeout")
    check doc.len > 0
    # Z3's actual doc string says "timeout (in milliseconds)" or similar.
    # We don't pin the wording; just verify it isn't empty.

  test "len matches the number of keys":
    let ctx = newContext()
    let s = newSolver()
    let pd = getParamDescrs(s)
    check pd.len == pd.keys.len

  test "dollar renders a non-empty string with the timeout key in it":
    let ctx = newContext()
    let s = newSolver()
    let pd = getParamDescrs(s)
    let rendered = $pd
    check rendered.contains("timeout")

suite "Z3ParamDescrs — tactic schema":
  test "getParamDescrs on a tactic returns a (possibly empty) schema":
    let ctx = newContext()
    let t = mkTactic("simplify")
    let pd = getParamDescrs(t)
    # tactic schemas can legitimately be empty for some tactics, but
    # `simplify` has many knobs; check that we got *a* handle, then
    # for known keys.
    let ks = pd.keys
    check pd.len == ks.len
    # `simplify` tactic exposes at least `elim_and` / `som` / etc.
    # Pin one stable key; Z3 has shipped this since 4.5.
    check "elim_and" in ks

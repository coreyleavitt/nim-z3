## Smoke test for the FFI layer.
##
## Exercises every category of the FFI surface declared in `z3/ffi.nim`
## at least once: configuration, context lifecycle, sort construction,
## numeral/variable construction, boolean ops, arithmetic, solver
## push/pop/check, model evaluation, error code surfacing, pretty-print.
##
## We do raw refcount management here because the idiomatic Nim layer
## (which encapsulates that discipline via `=destroy` / `=copy`) hasn't
## landed yet. These tests duplicate that bookkeeping on purpose so the
## FFI layer is verifiable on its own; once the idiomatic layer lands,
## its tests replace most of this and these become pure FFI smoke.

import std/[unittest, strutils]
import softlink
import z3

# Convenience: wrap each Z3_inc_ref / Z3_dec_ref pair manually.
template inc(ctx: RawZ3Context, a: RawZ3Ast) = Z3_inc_ref(ctx, a)
template dec(ctx: RawZ3Context, a: RawZ3Ast) = Z3_dec_ref(ctx, a)

suite "z3/ffi — softlink loads libz3":
  test "loadZ3 returns lrOk on a system with libz3 installed":
    let r = loadZ3()
    check r.kind == lrOk

  test "z3Loaded reports true after a successful load":
    discard loadZ3()
    check z3Loaded()

suite "z3/ffi — version":
  test "Z3_get_full_version returns 4.x version string":
    discard loadZ3()
    let v = $Z3_get_full_version()
    check v.len > 0
    check v.startsWith("4.")  # CI matrix may swing across 4.10–4.13.x

  test "Z3_get_version components agree with the string form":
    discard loadZ3()
    var major, minor, build, rev: cuint
    Z3_get_version(addr major, addr minor, addr build, addr rev)
    let stringForm = $Z3_get_full_version()
    check stringForm.startsWith($major & "." & $minor & "." & $build)

suite "z3/ffi — configuration + context lifecycle":
  test "Z3_mk_config / Z3_del_config round-trip":
    discard loadZ3()
    let cfg = Z3_mk_config()
    check not cfg.isNil
    Z3_set_param_value(cfg, "model", "true")
    Z3_del_config(cfg)

  test "Z3_mk_context_rc + Z3_del_context round-trip":
    discard loadZ3()
    let cfg = Z3_mk_config()
    let ctx = Z3_mk_context_rc(cfg)
    check not ctx.isNil
    Z3_del_context(ctx)
    Z3_del_config(cfg)

suite "z3/ffi — sorts + pretty-print":
  test "Int / Real / Bool sorts construct and stringify":
    discard loadZ3()
    let cfg = Z3_mk_config(); let ctx = Z3_mk_context_rc(cfg)
    defer:
      Z3_del_context(ctx); Z3_del_config(cfg)
    let intS = Z3_mk_int_sort(ctx)
    let realS = Z3_mk_real_sort(ctx)
    let boolS = Z3_mk_bool_sort(ctx)
    check ($Z3_sort_to_string(ctx, intS)) == "Int"
    check ($Z3_sort_to_string(ctx, realS)) == "Real"
    check ($Z3_sort_to_string(ctx, boolS)) == "Bool"

suite "z3/ffi — numerals + variables":
  test "literals construct (int, real, bool)":
    discard loadZ3()
    let cfg = Z3_mk_config(); let ctx = Z3_mk_context_rc(cfg)
    defer:
      Z3_del_context(ctx); Z3_del_config(cfg)
    let intS = Z3_mk_int_sort(ctx)
    let realS = Z3_mk_real_sort(ctx)

    let i42 = Z3_mk_int(ctx, 42, intS); ctx.inc(i42)
    let r1over2 = Z3_mk_real(ctx, 1, 2); ctx.inc(r1over2)
    let bigNum = Z3_mk_numeral(ctx, "1234567890123456789012345", intS)
    ctx.inc(bigNum)
    let yes = Z3_mk_true(ctx); ctx.inc(yes)
    let no = Z3_mk_false(ctx); ctx.inc(no)

    check ($Z3_ast_to_string(ctx, i42)) == "42"
    check ($Z3_ast_to_string(ctx, r1over2)) == "(/ 1.0 2.0)"
    check ($Z3_ast_to_string(ctx, bigNum)) == "1234567890123456789012345"
    check ($Z3_ast_to_string(ctx, yes)) == "true"
    check ($Z3_ast_to_string(ctx, no)) == "false"

    ctx.dec(no); ctx.dec(yes); ctx.dec(bigNum); ctx.dec(r1over2); ctx.dec(i42)

  test "mk_const constructs a typed variable":
    discard loadZ3()
    let cfg = Z3_mk_config(); let ctx = Z3_mk_context_rc(cfg)
    defer:
      Z3_del_context(ctx); Z3_del_config(cfg)
    let intS = Z3_mk_int_sort(ctx)
    let sym = Z3_mk_string_symbol(ctx, "x")
    let x = Z3_mk_const(ctx, sym, intS); ctx.inc(x)
    check ($Z3_ast_to_string(ctx, x)) == "x"
    ctx.dec(x)

suite "z3/ffi — boolean ops":
  test "and / or / not / implies / iff / ite":
    discard loadZ3()
    let cfg = Z3_mk_config(); let ctx = Z3_mk_context_rc(cfg)
    defer:
      Z3_del_context(ctx); Z3_del_config(cfg)
    let boolS = Z3_mk_bool_sort(ctx)
    let p = Z3_mk_const(ctx, Z3_mk_string_symbol(ctx, "p"), boolS); ctx.inc(p)
    let q = Z3_mk_const(ctx, Z3_mk_string_symbol(ctx, "q"), boolS); ctx.inc(q)

    var pq = [p, q]
    let conj = Z3_mk_and(ctx, 2, cast[ptr UncheckedArray[RawZ3Ast]](addr pq[0]))
    ctx.inc(conj)
    let disj = Z3_mk_or(ctx, 2, cast[ptr UncheckedArray[RawZ3Ast]](addr pq[0]))
    ctx.inc(disj)
    let negation = Z3_mk_not(ctx, p); ctx.inc(negation)
    let imp = Z3_mk_implies(ctx, p, q); ctx.inc(imp)
    let bicond = Z3_mk_iff(ctx, p, q); ctx.inc(bicond)
    let cond = Z3_mk_ite(ctx, p, q, negation); ctx.inc(cond)

    check ($Z3_ast_to_string(ctx, conj)) == "(and p q)"
    check ($Z3_ast_to_string(ctx, disj)) == "(or p q)"
    check ($Z3_ast_to_string(ctx, negation)) == "(not p)"
    check ($Z3_ast_to_string(ctx, imp)) == "(=> p q)"
    check ($Z3_ast_to_string(ctx, bicond)) == "(= p q)"
    check ($Z3_ast_to_string(ctx, cond)) == "(ite p q (not p))"

    for a in [cond, bicond, imp, negation, disj, conj, q, p]: ctx.dec(a)

suite "z3/ffi — arithmetic + comparison":
  test "add / sub / mul / unary_minus / mod":
    discard loadZ3()
    let cfg = Z3_mk_config(); let ctx = Z3_mk_context_rc(cfg)
    defer:
      Z3_del_context(ctx); Z3_del_config(cfg)
    let intS = Z3_mk_int_sort(ctx)
    let x = Z3_mk_const(ctx, Z3_mk_string_symbol(ctx, "x"), intS); ctx.inc(x)
    let y = Z3_mk_const(ctx, Z3_mk_string_symbol(ctx, "y"), intS); ctx.inc(y)

    var xy = [x, y]
    let sum = Z3_mk_add(ctx, 2, cast[ptr UncheckedArray[RawZ3Ast]](addr xy[0]))
    ctx.inc(sum)
    let diff = Z3_mk_sub(ctx, 2, cast[ptr UncheckedArray[RawZ3Ast]](addr xy[0]))
    ctx.inc(diff)
    let prod = Z3_mk_mul(ctx, 2, cast[ptr UncheckedArray[RawZ3Ast]](addr xy[0]))
    ctx.inc(prod)
    let neg = Z3_mk_unary_minus(ctx, x); ctx.inc(neg)
    let modulo = Z3_mk_mod(ctx, x, y); ctx.inc(modulo)

    check ($Z3_ast_to_string(ctx, sum)) == "(+ x y)"
    check ($Z3_ast_to_string(ctx, diff)) == "(- x y)"
    check ($Z3_ast_to_string(ctx, prod)) == "(* x y)"
    check ($Z3_ast_to_string(ctx, neg)) == "(- x)"
    check ($Z3_ast_to_string(ctx, modulo)) == "(mod x y)"

    for a in [modulo, neg, prod, diff, sum, y, x]: ctx.dec(a)

  test "eq / lt / le / gt / ge produce Bool ASTs":
    discard loadZ3()
    let cfg = Z3_mk_config(); let ctx = Z3_mk_context_rc(cfg)
    defer:
      Z3_del_context(ctx); Z3_del_config(cfg)
    let intS = Z3_mk_int_sort(ctx)
    let x = Z3_mk_const(ctx, Z3_mk_string_symbol(ctx, "x"), intS); ctx.inc(x)
    let i5 = Z3_mk_int(ctx, 5, intS); ctx.inc(i5)
    let eq = Z3_mk_eq(ctx, x, i5); ctx.inc(eq)
    let lt = Z3_mk_lt(ctx, x, i5); ctx.inc(lt)
    let le = Z3_mk_le(ctx, x, i5); ctx.inc(le)
    let gt = Z3_mk_gt(ctx, x, i5); ctx.inc(gt)
    let ge = Z3_mk_ge(ctx, x, i5); ctx.inc(ge)

    check ($Z3_ast_to_string(ctx, eq)) == "(= x 5)"
    check ($Z3_ast_to_string(ctx, lt)) == "(< x 5)"
    check ($Z3_ast_to_string(ctx, le)) == "(<= x 5)"
    check ($Z3_ast_to_string(ctx, gt)) == "(> x 5)"
    check ($Z3_ast_to_string(ctx, ge)) == "(>= x 5)"

    for a in [ge, gt, le, lt, eq, i5, x]: ctx.dec(a)

suite "z3/ffi — solver + model end-to-end":
  test "assert (x + y == 10 and x > 3); check sat; extract model":
    discard loadZ3()
    let cfg = Z3_mk_config(); let ctx = Z3_mk_context_rc(cfg)
    defer:
      Z3_del_context(ctx); Z3_del_config(cfg)
    let intS = Z3_mk_int_sort(ctx)
    let x = Z3_mk_const(ctx, Z3_mk_string_symbol(ctx, "x"), intS); ctx.inc(x)
    let y = Z3_mk_const(ctx, Z3_mk_string_symbol(ctx, "y"), intS); ctx.inc(y)
    let i10 = Z3_mk_int(ctx, 10, intS); ctx.inc(i10)
    let i3 = Z3_mk_int(ctx, 3, intS); ctx.inc(i3)

    var xy = [x, y]
    let sum = Z3_mk_add(ctx, 2, cast[ptr UncheckedArray[RawZ3Ast]](addr xy[0]))
    ctx.inc(sum)
    let sumEq = Z3_mk_eq(ctx, sum, i10); ctx.inc(sumEq)
    let xGt3 = Z3_mk_gt(ctx, x, i3); ctx.inc(xGt3)
    var conjArgs = [sumEq, xGt3]
    let constraint = Z3_mk_and(
      ctx, 2, cast[ptr UncheckedArray[RawZ3Ast]](addr conjArgs[0]))
    ctx.inc(constraint)

    let s = Z3_mk_solver(ctx); Z3_solver_inc_ref(ctx, s)
    Z3_solver_assert(ctx, s, constraint)
    let status = Z3_solver_check(ctx, s)
    check status == Z3_L_TRUE   # sat

    let m = Z3_solver_get_model(ctx, s); Z3_model_inc_ref(ctx, m)
    var xVal, yVal: RawZ3Ast
    check Z3_model_eval(ctx, m, x, true, addr xVal)
    Z3_inc_ref(ctx, xVal)
    check Z3_model_eval(ctx, m, y, true, addr yVal)
    Z3_inc_ref(ctx, yVal)
    var xi, yi: cint
    check Z3_get_numeral_int(ctx, xVal, addr xi)
    check Z3_get_numeral_int(ctx, yVal, addr yi)
    check int(xi) + int(yi) == 10
    check int(xi) > 3

    Z3_dec_ref(ctx, yVal); Z3_dec_ref(ctx, xVal)
    Z3_model_dec_ref(ctx, m)
    Z3_solver_dec_ref(ctx, s)
    for a in [constraint, xGt3, sumEq, sum, i3, i10, y, x]: ctx.dec(a)

  test "push/pop scopes constraints; unsat detection works":
    discard loadZ3()
    let cfg = Z3_mk_config(); let ctx = Z3_mk_context_rc(cfg)
    defer:
      Z3_del_context(ctx); Z3_del_config(cfg)
    let intS = Z3_mk_int_sort(ctx)
    let x = Z3_mk_const(ctx, Z3_mk_string_symbol(ctx, "x"), intS); ctx.inc(x)
    let i5 = Z3_mk_int(ctx, 5, intS); ctx.inc(i5)

    let s = Z3_mk_solver(ctx); Z3_solver_inc_ref(ctx, s)
    Z3_solver_push(ctx, s)
    let eq5 = Z3_mk_eq(ctx, x, i5); ctx.inc(eq5)
    Z3_solver_assert(ctx, s, eq5)
    let neq5 = Z3_mk_not(ctx, eq5); ctx.inc(neq5)
    Z3_solver_assert(ctx, s, neq5)
    check Z3_solver_check(ctx, s) == Z3_L_FALSE   # unsat: x == 5 and x != 5
    Z3_solver_pop(ctx, s, 1)
    # After pop, the assertions are gone; the empty context is sat.
    check Z3_solver_check(ctx, s) == Z3_L_TRUE

    for a in [neq5, eq5]: ctx.dec(a)
    Z3_solver_dec_ref(ctx, s)
    for a in [i5, x]: ctx.dec(a)

suite "z3/ffi — error handling API":
  # Note: provoking specific Z3 error codes through the C API is
  # surprisingly delicate — Z3's default error handler longjmps,
  # so when called from Nim without an installed handler, a "real"
  # sort error doesn't necessarily set the context's error code
  # before unwinding. The idiomatic Nim layer will install a
  # capture-only handler at context creation; until then, these
  # tests verify the FFI bindings work, not the semantics of error
  # propagation.

  test "Z3_get_error_code on a fresh context reports Z3_OK":
    discard loadZ3()
    let cfg = Z3_mk_config(); let ctx = Z3_mk_context_rc(cfg)
    defer:
      Z3_del_context(ctx); Z3_del_config(cfg)
    check Z3_get_error_code(ctx) == Z3_OK

  test "Z3_get_error_msg returns a non-empty diagnostic for each code":
    discard loadZ3()
    let cfg = Z3_mk_config(); let ctx = Z3_mk_context_rc(cfg)
    defer:
      Z3_del_context(ctx); Z3_del_config(cfg)
    # Each enumerator has a defined human-readable string.
    for code in Z3ErrorCode:
      let msg = $Z3_get_error_msg(ctx, code)
      check msg.len > 0

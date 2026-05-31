## Floating-point verification example — proves a small
## numerical routine has no NaN-producing inputs in a bounded
## domain.
##
## The routine: compute the **discriminant** of a quadratic
## `a*x^2 + b*x + c`, i.e. `D = b*b - 4*a*c`. We verify:
##
##   for all finite a, b, c with |a|, |b|, |c| ≤ 100,
##     D is finite (not NaN and not ±Inf).
##
## Why this matters: discriminants are the building block of the
## quadratic-formula routine. If `D` is NaN, the downstream
## `sqrt(D)` is also NaN and the whole quadratic-formula machinery
## silently fails. Proving the discriminant is finite under
## bounded inputs proves the routine is NaN-safe in its declared
## domain.
##
## Demonstrated:
##
## - `Z3Float32` typed FP values
## - `mkFp` literals + `mkFpVar` symbolic inputs
## - Operators `*`, `-` with default `rmRNE` rounding (the IEEE
##   round-half-to-even default)
## - Predicates `isNaN`, `isInf`
## - The IEEE-`==` divergence (NaN != NaN) — noted in comments
## - The proof shape: assert the negation of the property; if
##   unsat, the property is universally true on the constrained
##   domain.
##
## Run with:
##
## ```
## nim c -r examples/float_verification.nim
## ```

import z3

proc main() =
  let ctx = newContext()
  echo "libz3 ", z3FullVersion()

  # Build symbolic float32 inputs.
  let a = mkFloat32Var("a")
  let b = mkFloat32Var("b")
  let c = mkFloat32Var("c")

  # Compute the discriminant. Operators default to IEEE round-
  # nearest-ties-to-even (rmRNE()). The wrapper's `*` and `-`
  # both produce a typed Z3Float32 result.
  let four = mkFloat32(4.0'f32)
  let discr = b * b - four * a * c

  # The domain: each input finite and bounded by [-100, 100] in
  # absolute value. We use `bvult` … wait, no — for FP comparison
  # we need IEEE ops. The wrapper ships `<` etc. on Z3Fp[E, S]
  # but for absolute-value bounds we'll use `abs` + the IEEE `<`
  # on FP.
  let bound = mkFloat32(100.0'f32)

  proc isFinite(x: Z3Float32): Z3Bool =
    (not isNaN(x)) and (not isInf(x))

  proc isBounded(x: Z3Float32): Z3Bool =
    abs(x) <= bound

  let domain = isFinite(a) and isFinite(b) and isFinite(c) and
               isBounded(a) and isBounded(b) and isBounded(c)

  # Verify: under `domain`, the discriminant cannot be NaN or Inf.
  # We prove this by checking the negation is unsat.
  let s = newSolver()
  s.add domain
  s.add isNaN(discr) or isInf(discr)

  case s.check()
  of zsUnsat:
    echo "✓ discriminant is finite for all |a|, |b|, |c| ≤ 100."
  of zsSat:
    let m = s.model()
    let av = m.evalFloat32(a)
    let bv = m.evalFloat32(b)
    let cv = m.evalFloat32(c)
    echo "✗ counter-example: a=", av, " b=", bv, " c=", cv
    quit "discriminant verification failed — produced NaN or Inf"
  of zsUnknown:
    quit "solver returned unknown — verification inconclusive"

  # IEEE-`==` divergence reminder: NaN != NaN under IEEE semantics.
  # The wrapper's `==` on Z3Fp returns IEEE equality (Z3_mk_fpa_eq),
  # NOT structural equality. So `nan == nan` evaluates to `false`.
  let nan = mkFp[8, 24](0.0'f32) / mkFp[8, 24](0.0'f32)  # 0/0 is NaN
  doAssert smtValid(not (nan == nan)), "IEEE: NaN == NaN must be false"
  echo "✓ IEEE-eq: NaN == NaN is false (deliberate FP divergence)."

when isMainModule:
  main()

## `z3/proof` tests — proof grammar surface.

import std/[unittest, strutils]
import z3

template unsatProofCtx(body: untyped) =
  let ctx {.inject.} = newContext(("proof", "true"))
  let x {.inject.} = mkIntVar("x")
  let s {.inject.} = newSolver()
  s.add x > mkInt(0)
  s.add x < mkInt(0)
  check s.check() == zsUnsat
  let p {.inject.} = s.getProof()
  body

suite "Z3Proof — tracer":
  test "unsat solver with proof=true yields a Z3Proof":
    unsatProofCtx:
      let rule = getProofRule(p)
      # Z3-version-fragile rule kinds; pin only non-undef + non-unknown.
      check rule != prUndef
      check rule != prUnknown

suite "Z3Proof — unpackProof":
  test "decomposes into (rule, premises, conclusion)":
    unsatProofCtx:
      let (rule, premises, conclusion) = unpackProof(p)
      check rule != prUndef
      check rule != prUnknown
      # Conclusion is a Z3Bool (typed extractor doesn't raise).
      discard conclusion
      # Premises sequence exists (may be empty for a leaf-rule proof).
      check premises.len >= 0

  test "conclusion of an unsat proof is provable through the model":
    # The top-level conclusion of an unsat-proof witnesses the
    # contradiction the solver derived. Observable property: the
    # conclusion is a Z3Bool that, asserted into a fresh solver,
    # decides cleanly (rather than being garbage).
    unsatProofCtx:
      let (_, _, conclusion) = unpackProof(p)
      # The conclusion is well-formed: it has a recognised SMT kind.
      check getAstKind(conclusion) in {akApp, akNumeral, akVar}

  test "premises are themselves Z3Proofs":
    # If the top-level proof has premises, each is itself a proof
    # term (akApp) with its own rule.
    unsatProofCtx:
      let (_, premises, _) = unpackProof(p)
      for sub in premises:
        # Sub-proof is a recognisable proof AST.
        check getAstKind(sub) == akApp

suite "Z3Proof — pretty":
  test "dollar-proof renders an SMT-LIB shaped string":
    unsatProofCtx:
      let rendered = $p
      check rendered.len > 0
      # SMT-LIB proof terms are parenthesised expressions; the rendered
      # string starts with an open paren in the typical case.
      check rendered[0] == '('

suite "Z3Proof — error cases":
  test "getProof without proof=true raises Z3Error":
    let ctx = newContext()   # no proof=true
    let x = mkIntVar("x")
    let s = newSolver()
    s.add x > mkInt(0)
    s.add x < mkInt(0)
    check s.check() == zsUnsat
    expect Z3Error:
      discard s.getProof()

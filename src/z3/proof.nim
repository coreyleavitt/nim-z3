## `z3/proof` — proof grammar surface.
##
## When `proof=true` is set on a `Z3Context`, an unsat `check()` result
## carries a proof witness that can be extracted via
## `Z3Solver.getProof` (also wrapped here for discoverability — the
## proc itself lives in `z3/solver` since it's a solver operation).
##
## ## The proof family
##
## A `Z3Proof` is a typed handle for a Z3 proof term. Z3 represents
## proofs as application ASTs whose head function-decl encodes the
## proof rule (per the `Z3_OP_PR_*` discipline) and whose arguments are
## sub-proofs followed by a final conclusion (a `Z3Bool`):
##
## ```
##   proof = (rule_decl premise_1 premise_2 ... premise_n conclusion)
## ```
##
## `unpackProof` decomposes this structure into `(rule: ProofRule,
## premises: seq[Z3Proof], conclusion: Z3Bool)`.
##
## ## The ProofRule enum
##
## 42 entries covering every `Z3_OP_PR_*` value in Z3 4.13.x's
## `Z3_decl_kind`, plus `prUnknown` as the catch-all for proof terms
## whose head decl isn't a recognised proof rule (rare; happens when
## the solver dispatched through a non-proof-producing tactic).
##
## ## Test discipline
##
## Z3's proof generation chooses among many derivation strategies; the
## same unsat formula can produce different concrete proof trees
## across Z3 versions. Tests should pin **structural** properties (a
## proof exists; its rule is not `prUndef` / `prUnknown`; unpacking
## yields a conclusion that's a `Z3Bool`) rather than **specific**
## proof-tree shapes.

import ./ffi, ./context, ./error, ./ast, ./introspect, ./solver

# ============================================================================
# Z3Proof — typed AST family
# ============================================================================

type
  Z3Proof* = object
    ## A Z3 proof term. Satisfies the `Z3Term` concept; participates
    ## in every generic over `Z3Term` (structural introspection,
    ## refcount lifecycle, …). Built only via `Z3Solver.getProof` (or
    ## by sub-proof extraction through `unpackProof`); there is no
    ## public constructor that builds a proof literal.
    raw*: RawZ3Ast
    ctx*: Z3Context

emitTermLifecycle(Z3Proof, Z3_dec_ref, Z3_inc_ref)

# ============================================================================
# ProofRule — the typed enum mirroring Z3's Z3_OP_PR_* discipline
# ============================================================================

type
  ProofRule* = enum
    ## **Source**: `Z3_decl_kind` PR_* entries in `z3_api.h` (Z3 4.13).
    ## Docstrings paraphrase Z3's header documentation; the
    ## `See: z3_api.h Z3_OP_PR_*` cite anchors each entry to the
    ## upstream source for users who need the formal semantics.
    prUndef             ## Undef / null proof object. See: z3_api.h Z3_OP_PR_UNDEF.
    prTrue              ## Proof for the expression `true`. See: z3_api.h Z3_OP_PR_TRUE.
    prAsserted          ## Proof for a fact asserted by the user. See: z3_api.h Z3_OP_PR_ASSERTED.
    prGoal              ## Proof for a fact tagged as a goal. See: z3_api.h Z3_OP_PR_GOAL.
    prModusPonens       ## Given `p` and `(implies p q)`, produces `q`. See: z3_api.h Z3_OP_PR_MODUS_PONENS.
    prReflexivity       ## Proof of `(R t t)` for a reflexive `R`. See: z3_api.h Z3_OP_PR_REFLEXIVITY.
    prSymmetry          ## Symmetric closure of a relation proof. See: z3_api.h Z3_OP_PR_SYMMETRY.
    prTransitivity      ## Transitive closure step. See: z3_api.h Z3_OP_PR_TRANSITIVITY.
    prTransitivityStar  ## Condensed transitivity. See: z3_api.h Z3_OP_PR_TRANSITIVITY_STAR.
    prMonotonicity      ## Monotonicity over compatible relations. See: z3_api.h Z3_OP_PR_MONOTONICITY.
    prQuantIntro        ## Quantifier introduction. See: z3_api.h Z3_OP_PR_QUANT_INTRO.
    prBind              ## Lambda binding. See: z3_api.h Z3_OP_PR_BIND.
    prDistributivity    ## Distributivity over conjunction / disjunction. See: z3_api.h Z3_OP_PR_DISTRIBUTIVITY.
    prAndElim           ## Conjunction elimination. See: z3_api.h Z3_OP_PR_AND_ELIM.
    prNotOrElim         ## Disjunction-negation elimination. See: z3_api.h Z3_OP_PR_NOT_OR_ELIM.
    prRewrite           ## A local rewriting step. See: z3_api.h Z3_OP_PR_REWRITE.
    prRewriteStar       ## Full rewrite proof. See: z3_api.h Z3_OP_PR_REWRITE_STAR.
    prPullQuant         ## Pull-out quantifier. See: z3_api.h Z3_OP_PR_PULL_QUANT.
    prPushQuant         ## Push-in quantifier. See: z3_api.h Z3_OP_PR_PUSH_QUANT.
    prElimUnusedVars    ## Elimination of unused bound variables. See: z3_api.h Z3_OP_PR_ELIM_UNUSED_VARS.
    prDer               ## Destructive equality resolution. See: z3_api.h Z3_OP_PR_DER.
    prQuantInst         ## Quantifier instantiation. See: z3_api.h Z3_OP_PR_QUANT_INST.
    prHypothesis        ## Natural-deduction hypothesis introduction. See: z3_api.h Z3_OP_PR_HYPOTHESIS.
    prLemma             ## Lemma derivation. See: z3_api.h Z3_OP_PR_LEMMA.
    prUnitResolution    ## Unit-clause resolution. See: z3_api.h Z3_OP_PR_UNIT_RESOLUTION.
    prIffTrue           ## `(iff p true)` introduction. See: z3_api.h Z3_OP_PR_IFF_TRUE.
    prIffFalse          ## `(iff p false)` introduction. See: z3_api.h Z3_OP_PR_IFF_FALSE.
    prCommutativity     ## Commutativity rewrite. See: z3_api.h Z3_OP_PR_COMMUTATIVITY.
    prDefAxiom          ## Tseitin-style definitional axiom. See: z3_api.h Z3_OP_PR_DEF_AXIOM.
    prAssumptionAdd     ## SAT-solver assumption addition. See: z3_api.h Z3_OP_PR_ASSUMPTION_ADD.
    prLemmaAdd          ## SAT-solver lemma addition. See: z3_api.h Z3_OP_PR_LEMMA_ADD.
    prRedundantDel      ## SAT-solver redundant-clause deletion. See: z3_api.h Z3_OP_PR_REDUNDANT_DEL.
    prClauseTrail       ## Clause-trail proof. See: z3_api.h Z3_OP_PR_CLAUSE_TRAIL.
    prDefIntro          ## Definitional name introduction. See: z3_api.h Z3_OP_PR_DEF_INTRO.
    prApplyDef          ## Apply a definitional rewrite. See: z3_api.h Z3_OP_PR_APPLY_DEF.
    prIffOeq            ## `(iff p q)` ↔ `(oeq p q)`. See: z3_api.h Z3_OP_PR_IFF_OEQ.
    prNnfPos            ## Positive NNF step. See: z3_api.h Z3_OP_PR_NNF_POS.
    prNnfNeg            ## Negative NNF step. See: z3_api.h Z3_OP_PR_NNF_NEG.
    prSkolemize         ## Skolemization. See: z3_api.h Z3_OP_PR_SKOLEMIZE.
    prModusPonensOeq    ## Modus-ponens for equi-satisfiability. See: z3_api.h Z3_OP_PR_MODUS_PONENS_OEQ.
    prTheoryLemma       ## Generic theory-lemma proof. See: z3_api.h Z3_OP_PR_TH_LEMMA.
    prHyperResolve      ## Hyper-resolution rule. See: z3_api.h Z3_OP_PR_HYPER_RESOLVE.
    prUnknown           ## Proof term whose head decl isn't a recognised proof rule
                        ## (rare — happens when proof generation dispatched
                        ## through a non-proof-producing tactic).

proc toProofRule(k: Z3DeclKindFFI): ProofRule =
  case k
  of Z3_OP_PR_UNDEF_E:            prUndef
  of Z3_OP_PR_TRUE_E:             prTrue
  of Z3_OP_PR_ASSERTED_E:         prAsserted
  of Z3_OP_PR_GOAL_E:             prGoal
  of Z3_OP_PR_MODUS_PONENS_E:     prModusPonens
  of Z3_OP_PR_REFLEXIVITY_E:      prReflexivity
  of Z3_OP_PR_SYMMETRY_E:         prSymmetry
  of Z3_OP_PR_TRANSITIVITY_E:     prTransitivity
  of Z3_OP_PR_TRANSITIVITY_STAR_E: prTransitivityStar
  of Z3_OP_PR_MONOTONICITY_E:     prMonotonicity
  of Z3_OP_PR_QUANT_INTRO_E:      prQuantIntro
  of Z3_OP_PR_BIND_E:             prBind
  of Z3_OP_PR_DISTRIBUTIVITY_E:   prDistributivity
  of Z3_OP_PR_AND_ELIM_E:         prAndElim
  of Z3_OP_PR_NOT_OR_ELIM_E:      prNotOrElim
  of Z3_OP_PR_REWRITE_E:          prRewrite
  of Z3_OP_PR_REWRITE_STAR_E:     prRewriteStar
  of Z3_OP_PR_PULL_QUANT_E:       prPullQuant
  of Z3_OP_PR_PUSH_QUANT_E:       prPushQuant
  of Z3_OP_PR_ELIM_UNUSED_VARS_E: prElimUnusedVars
  of Z3_OP_PR_DER_E:              prDer
  of Z3_OP_PR_QUANT_INST_E:       prQuantInst
  of Z3_OP_PR_HYPOTHESIS_E:       prHypothesis
  of Z3_OP_PR_LEMMA_E:            prLemma
  of Z3_OP_PR_UNIT_RESOLUTION_E:  prUnitResolution
  of Z3_OP_PR_IFF_TRUE_E:         prIffTrue
  of Z3_OP_PR_IFF_FALSE_E:        prIffFalse
  of Z3_OP_PR_COMMUTATIVITY_E:    prCommutativity
  of Z3_OP_PR_DEF_AXIOM_E:        prDefAxiom
  of Z3_OP_PR_ASSUMPTION_ADD_E:   prAssumptionAdd
  of Z3_OP_PR_LEMMA_ADD_E:        prLemmaAdd
  of Z3_OP_PR_REDUNDANT_DEL_E:    prRedundantDel
  of Z3_OP_PR_CLAUSE_TRAIL_E:     prClauseTrail
  of Z3_OP_PR_DEF_INTRO_E:        prDefIntro
  of Z3_OP_PR_APPLY_DEF_E:        prApplyDef
  of Z3_OP_PR_IFF_OEQ_E:          prIffOeq
  of Z3_OP_PR_NNF_POS_E:          prNnfPos
  of Z3_OP_PR_NNF_NEG_E:          prNnfNeg
  of Z3_OP_PR_SKOLEMIZE_E:        prSkolemize
  of Z3_OP_PR_MODUS_PONENS_OEQ_E: prModusPonensOeq
  of Z3_OP_PR_TH_LEMMA_E:         prTheoryLemma
  of Z3_OP_PR_HYPER_RESOLVE_E:    prHyperResolve
  else:                           prUnknown

# ============================================================================
# Introspection
# ============================================================================

proc getProofRule*(p: Z3Proof): ProofRule =
  ## Head proof rule. Z3 represents the rule as the function-decl at
  ## the head of the proof's application AST.
  if getAstKind(p) != akApp:
    return prUnknown
  let decl = getAppDecl(p)
  toProofRule(Z3_get_decl_kind(p.ctx.raw, decl))

proc unpackProof*(p: Z3Proof): tuple[rule: ProofRule,
                                     premises: seq[Z3Proof],
                                     conclusion: Z3Bool] =
  ## Full structural decomposition. The last argument of a proof
  ## application is its conclusion (a `Z3Bool`); all preceding args
  ## are sub-proofs. Raises `Z3Error` if `p` isn't an application AST.
  if getAstKind(p) != akApp:
    var e = newException(Z3InvalidUsageError,
      "unpackProof: AST is not a proof application (kind = " &
      $getAstKind(p) & ")")
    e.code = Z3_INVALID_USAGE
    raise e
  result.rule = getProofRule(p)
  let n = getAppNumArgs(p)
  result.premises = newSeq[Z3Proof](max(n - 1, 0))
  for i in 0 ..< (n - 1):
    let arg = getAppArg(p, i)
    result.premises[i] = wrap[Z3Proof](p.ctx, arg.raw)
  let conclArg = getAppArg(p, n - 1)
  result.conclusion = wrap[Z3Bool](p.ctx, conclArg.raw)

# ============================================================================
# Pretty
# ============================================================================

proc `$`*(p: Z3Proof): string = termToSmt2(p)
  ## SMT-LIB rendering of the proof term.

# ============================================================================
# Z3Solver.getProof — extraction (originally planned as v0.4 step 7; shipped
# here because step 4's proof family is undefined without a way to extract
# one to introspect — the two are tightly coupled and ship as one merged step)
# ============================================================================

proc getProof*(s: Z3Solver): Z3Proof =
  ## Extract the proof witness from a solver that has just returned
  ## `zsUnsat` with `proof=true` enabled on the context (typically via
  ## `newContext(("proof", "true"))`). Raises `Z3Error` if proof
  ## generation wasn't enabled, the last `check()` didn't return
  ## unsat, or Z3 otherwise returned nil.
  ##
  ## ```nim
  ## let ctx = newContext(("proof", "true"))
  ## let s = newSolver()
  ## s.add x > mkInt(0)
  ## s.add x < mkInt(0)
  ## doAssert s.check() == zsUnsat
  ## let p = s.getProof()
  ## let (rule, premises, conclusion) = unpackProof(p)
  ## ```
  let raw = s.ctx.checkErr Z3_solver_get_proof(s.ctx.raw, s.raw)
  if raw.isNil:
    var e = newException(Z3InvalidUsageError,
      "Z3Solver.getProof: nil proof returned. Most likely cause: " &
      "proof generation wasn't enabled on the context, or the last " &
      "check() did not return zsUnsat.")
    e.code = Z3_INVALID_USAGE
    raise e
  wrap[Z3Proof](s.ctx, raw)

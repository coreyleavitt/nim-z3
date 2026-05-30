# nim-z3 v0.4 plan (live)

> **Status: live, written 2026-05-30** during the v1.0-readiness review at the end of v0.3. Pairs with the forward-draft `docs/V0.5_PLAN.md` (the 1.0-readiness polish release). When v0.4 ships, this file is archived to `docs/V0.4_PLAN.md` and `V0.5_PLAN.md` is promoted into the live slot.

A type-safe, memory-safe, idiomatic Nim wrapper for the Z3 SMT solver.

**Status (at plan-promotion time)**: v0.3 shipped 2026-05-30 with 890 OKs across both backends, zero failures, zero warnings. The post-v0.3 architectural review surfaced 8 candidates for v1.0-readiness work. **v0.4 owns candidate 1** — the contract-completion release. **v0.5 owns candidates 2–8** — the 1.0-readiness polish.

**Audience**: future-me, future contributors, anyone reading this after v0.4 ships and wondering "why is the wrapper this big — what's the 1.0 scope?"

## What changes between v0.3 and v0.4

v0.3 was the architectural-unification + theory-completion release. It landed the `Z3Term` concept + unified lifecycle + `z3/sortdispatch`, every SMT-LIB theory family (Char / String / Sequences / Regex / FP / FuncDecl), the solver-tactic bridges, and the `z3/semantics` relocation. The cumulative effect: **every SMT-LIB *theory* Z3 exposes is reachable through the wrapper**.

v0.4 is the **contract-completion release**. v0.3 closed the theory side; v0.4 closes everything else Z3's C API ships. Specifically:

- **Fixedpoint engine** — Horn-clause / CHC verification (`Z3Fixedpoint`)
- **Proof grammar** — typed `Z3Proof` family + `ProofRule` enum + introspection
- **Solver extensions** — unsat-core, proof, statistics, consequences, `assert_and_track`
- **Structural introspection** — `Z3AstKind` for AST node taxonomy + `Z3SortKind` for sort taxonomy + the full programmatic-walk surface (`getAppDecl`, `getAppArg`, `unpackApp`, `bitVecWidth`, `arrayKey`, …)
- **Term rewriting** — `Z3_substitute` (by-term) + `Z3_substitute_vars` (de-Bruijn-indexed)
- **Cross-context AST transfer** — `Z3_translate` + `compatibleWith` introspection
- **Quantifier introspection** — `Z3_get_quantifier_*` family
- **Z3DatatypeValue as a sortOf element type** — closes the v0.3 §8 carryover (runtime decl-table lookup)
- **Probes + conditional tactics** — `Z3Probe` family + `condTactic(probe, ifT, elseT)` combinator
- **Global params** — `Z3_set_param_value` / `Z3_global_param_*` library-level tuning
- **Full I/O surface** — `z3/io` module relocating + extending the parse/render surface (`parseSmt2File`, streaming `Z3ParserContext`, etc.)

The scope statement after v0.4 is **literally true**: every capability the Z3 C API exposes is reachable through the wrapper, with type-safety and memory-safety invariants preserved. v0.5 polishes; v0.6 commits to 1.0.

## 1. Goals and non-goals

### Goals

1. **`Z3Fixedpoint`** — wrap Z3's Horn-clause solver as a typed family / ref-handle module comparable in size to `z3/optimize`. Surface includes:
   - `newFixedpoint(ctx)` constructor + `Z3_fixedpoint_inc_ref` / `_dec_ref` lifecycle via `emitRefcountLifecycle`
   - `addRule(fp, rule: Z3Bool, name: Z3Symbol)` for Horn-clause assertion
   - `addFact(fp, ...)` for ground facts
   - `query(fp, query: Z3Bool): Z3Status` — the CHC decision procedure
   - `query(fp, relation: Z3FuncDecl[...]): Z3Status` — relational query form
   - `getAnswer(fp): Z3Bool` — the witness formula after a sat query
   - `setParams(fp, p: Z3Params)` — symmetric with `setParams(s: Z3Solver, p)` from v0.3 step 8
   - `addCover` / `getReachableExpressions` / `addVariable` — the auxiliary surface
   - `$fp` / `pretty(fp)` parity with other ref-typed families

   Lives in new module `z3/fixedpoint`.

2. **`Z3Proof` family + `ProofRule` enum + introspection.** Z3's proof terms are typed ASTs with their own kind discipline (~30 proof rules). Best-in-class wrapper exposes the full enum + a generic `unpackProof` that lets users walk proof trees programmatically.

   - `type Z3Proof = object` — phantom-typed (no generic param; proofs aren't sort-parameterised) family slotting into `Z3Term`
   - `type ProofRule = enum prRefl, prModusPonens, prResolve, prHypothesis, prAxiom, prSymm, prTrans, prMonotonicity, prQuantInst, prDistributivity, prAndElim, prNotOrElim, prRewrite, prRewriteStar, prPullQuant, prPushQuant, prElimUnusedVars, prDer, prQuantIntro, prBindProof, prUnitResolution, prIffTrue, prIffFalse, prCommutativity, prDefAxiom, prApplyDef, prIffOEq, prNnfPos, prNnfNeg, prSkolemize, prModusPonensOEq, prTheoryLemma, prHyperResolve, prUnknown` — one entry per `Z3_OP_PR_*` value, with paraphrased docstrings sourced from Z3's documentation (per the resolved design decision from §7)
   - `getProofRule(p: Z3Proof): ProofRule` — extracts the kind
   - `unpackProof(p: Z3Proof): tuple[rule: ProofRule, premises: seq[Z3Proof], conclusion: Z3Bool]` — full structural unpack
   - `$p` renders as SMT-LIB proof syntax

   Lives in new module `z3/proof`. Foundational for goal 4 (`Z3Solver.getProof`).

3. **Structural introspection — AST + sort.** The duality between AST-node kinds and sort kinds is fundamental; best-in-class ships both as a unified capability rather than asymmetrically. Lives in `z3/introspect`.

   **AST introspection** (`Z3_ast_kind`, `Z3_get_app_*`):
   - `type Z3AstKind = enum akNumeral, akApp, akVar, akQuantifier, akSort, akFuncDecl, akUnknown` — wraps `Z3_ast_kind`
   - `getAstKind*[T: Z3Term](a: T): Z3AstKind` — generic over every typed family
   - `getAppDecl*[T: Z3Term](a: T): RawZ3FuncDecl` — for `akApp` ASTs (typed `Z3FuncDecl[...]` lift available where arity matches a registered signature; raw fallback otherwise)
   - `getAppNumArgs*[T: Z3Term](a: T): int`
   - `getAppArg*[T: Z3Term](a: T, i: int): Z3AnyAst` — returns runtime-erased AST (i-th arg's sort isn't compile-time known)
   - `unpackApp*(a: Z3AnyAst): tuple[decl: RawZ3FuncDecl, args: seq[Z3AnyAst]]` — full decomposition
   - `getNumeralString*[T: Z3Term](a: T): string` — generalises `toBigIntStr` / `toBigRealStr`

   **Sort introspection** (`Z3_get_sort_kind`, `Z3_get_bv_sort_size`, etc.):
   - `type Z3SortKind = enum skInt, skReal, skBool, skBitVec, skChar, skArray, skSeq, skRegex, skFp, skRoundingMode, skDatatype, skFuncDecl, skUninterpreted, skUnknown` — wraps `Z3_sort_kind`
   - `getSortKind*(s: RawZ3Sort): Z3SortKind`
   - `bitVecWidth*(s: RawZ3Sort): int` — for `skBitVec`
   - `arrayKey*(s: RawZ3Sort): RawZ3Sort` / `arrayRange(s)` — for `skArray`
   - `seqElement*(s: RawZ3Sort): RawZ3Sort` — for `skSeq`
   - `fpEbits*(s: RawZ3Sort): int` / `fpSbits(s)` — for `skFp`
   - `regexBasis*(s: RawZ3Sort): RawZ3Sort` — for `skRegex`
   - `datatypeName*(s: RawZ3Sort): string` — for `skDatatype`

   **`Z3AnyAst`** — runtime-erased `Z3Term`. Value-typed wrapper carrying `raw` + `ctx`, full lifecycle via `emitTermLifecycle`. Acts as the return type of `getAppArg` and the parameter type of `unpackApp`. Typed lifters ship for every family — `asZ3Int(a: Z3AnyAst): Z3Int`, `asZ3Bool`, `asZ3BitVec[W]`, `asZ3Fp[E, S]`, etc. — each runtime-checks the sort kind before returning the typed handle and raises `Z3SortError` on mismatch.

4. **Solver extensions** (`z3/solver` additions). Closes the v0.3 step-8 half-implementation (could set `unsat_core=true` but couldn't extract).

   - `assertConstraintAndTrack(s, c: Z3Bool, tracker: Z3Bool): Z3Bool` — tag an assertion with a tracker proposition for unsat-core extraction. Returns the tracker for fluent use.
   - `getUnsatCore(s): seq[Z3Bool]` — extract the minimal unsatisfiable subset of tagged assertions (uses the v0.4 `Z3AstVector` typed handle from step 1).
   - `getProof(s): Z3Proof` — extract the proof witness after an unsat `check()` with `proof=true`. Returns the typed `Z3Proof` from goal 2.
   - `getStatistics(s): Z3Stats` — extract solver runtime statistics. New typed ref-handle `Z3Stats` with `len(stats): int`, `[](stats, key: string): float`, `keys(stats): seq[string]`, iteration support.
   - `getConsequences(s, assumptions: seq[Z3Bool], variables: seq[Z3Term]): tuple[status: Z3Status, consequences: seq[Z3Bool]]` — implied-literals enumeration.

5. **Term rewriting** — `Z3_substitute` and `Z3_substitute_vars`. Both surfaces ship at PhD-tier.

   - `substitute*[T: Z3Term](a: T, replacements: openArray[(Z3AnyAst, Z3AnyAst)]): T` — by-term substitution. Replaces matching subterms; returns same-type result.
   - `substituteVars*[T: Z3Term](a: T, replacements: openArray[Z3AnyAst]): T` — de-Bruijn-indexed substitution into a quantifier body. The `replacements` array is indexed by bound-variable position. Loud docstring on the de-Bruijn discipline ("the array's i-th entry replaces the i-th bound variable counted from innermost — the same convention Z3 uses").

   Lives in new module `z3/rewrite`.

6. **Cross-context AST transfer** — `Z3_translate` + compatibility introspection.

   - `translate*[T: Z3Term](t: T, targetCtx: Z3Context): T` — generic over every typed family. Type system reflects that sort is preserved; Z3 itself validates target-context acceptance at runtime.
   - `compatibleWith*(ctxA, ctxB: Z3Context): bool` — predicate for whether `translate` from A to B will succeed. Smoke-tests the documented compatibility rules; runs a no-op translation under exception capture if Z3 doesn't expose a direct predicate. Best-in-class wrappers don't make users discover compatibility via "try and catch the error."

   Lives in new module `z3/translate` — tiny, but its own seam because cross-context concerns are conceptually distinct.

7. **Quantifier introspection** — the `Z3_get_quantifier_*` family.

   - `getQuantifierNumBoundVars(q: Z3Bool): int`
   - `getQuantifierBoundVarName(q: Z3Bool, i: int): string`
   - `getQuantifierBoundVarSort(q: Z3Bool, i: int): RawZ3Sort` — users dispatch via `getSortKind(...)` from goal 3
   - `getQuantifierBody(q: Z3Bool): Z3Bool`
   - `getQuantifierNumPatterns(q: Z3Bool): int`
   - `getQuantifierPatternAst(q: Z3Bool, i: int): Z3Pattern`
   - `isForall(q: Z3Bool): bool`, `isExists(q: Z3Bool): bool`, `isLambda(q: Z3Bool): bool`
   - `getQuantifierWeight(q: Z3Bool): int`

   Adds to `z3/quantifier`.

8. **`Z3DatatypeValue` as a `sortOf` element type.** Closes the v0.3 §8 carryover. Datatype sorts are made at runtime by `declareDatatype` and held on the decl — `sortOf(_: typedesc[Z3DatatypeValue[T]], ctx)` needs a runtime decl-table lookup keyed by `T`'s marker type.

   Mechanism: `z3/context` carries a `datatypeRegistry: Table[string, RawZ3Sort]` per-context. `declareDatatype[T]` registers the resulting sort under `$T`. `sortOf(_: typedesc[Z3DatatypeValue[T]], ctx)` looks it up; raises `Z3UsageError` with a helpful message if not yet registered. Unlocks `Z3Array[Z3Int, Z3DatatypeValue[Foo]]`, `Z3Seq[Z3DatatypeValue[Foo]]`, `Z3FuncDecl[(Z3DatatypeValue[Foo],), Z3Bool]`, etc.

9. **Probes + conditional tactics.** New module `z3/probe`.

   - `type Z3Probe = ref Z3ProbeOwn` — typed ref-handle for Z3 probes
   - Built-in probes: `mkProbe("name")` (e.g. `"num-consts"`, `"num-bool-consts"`, `"num-arith-consts"`)
   - Numeric combinators: `<`, `<=`, `>`, `>=`, `==` on `(Z3Probe, float)` returning `Z3Probe`
   - Boolean combinators: `and`, `or`, `not` on `Z3Probe`
   - Tactic combinator: `condTactic(probe: Z3Probe, ifT: Z3Tactic, elseT: Z3Tactic): Z3Tactic` (`Z3_tactic_cond`)
   - `applyProbe(p: Z3Probe, g: Z3Goal): float` for direct evaluation

10. **Global parameters** — new module `z3/globalparams`.

    - `setGlobalParam(name: string, value: string)` — wraps `Z3_global_param_set`
    - `getGlobalParam(name: string): Option[string]` — wraps `Z3_global_param_get`
    - `resetAllGlobalParams()` — wraps `Z3_global_param_reset_all`

11. **Full I/O surface** — new module `z3/io`. Relocates `parseSmt2` / `smt2Script` / `writeSmt2` from `z3/pretty` (where they currently sit because there was no better home) into a dedicated I/O module. Adds:

    - `parseSmt2File(path: string): seq[Z3Bool]` — file-based parse
    - `parseSmt2String(s: string): seq[Z3Bool]` — relocated
    - `smt2Script(...): string` — relocated, the round-trip renderer
    - `writeSmt2(path: string, ...)` — relocated file emitter
    - `type Z3ParserContext = ref Z3ParserContextOwn` — typed ref-handle for incremental parsing. **Step-style API** (per the resolved design decision from §7): construct, mutate via methods, terminal-call.
    - `newParserContext(ctx)` + `inc_ref` / `dec_ref` via `emitRefcountLifecycle`
    - `addSort(pc, name, sort)` — pre-register a sort the input expects
    - `addDecl(pc, name, decl)` — pre-register a function decl
    - `parseFromString(pc, s: string): seq[Z3Bool]` — incremental parse against the registered context

    After this relocation, `z3/pretty` is purely for visual pretty-printing. Cleaner module boundary.

### Non-goals (re-asserted from earlier plans)

- **Custom theories via user propagators** (`Z3_solver_propagate_*`) — still v1.x+ research-grade. The user-propagator surface requires callback registration with thread-state discipline; out of v0.4 scope.
- **High-level macro DSL** (`solve: forall x in Int, x + 1 > x`) — still non-goal; the wrapper IS the API.
- **Differential testing against Python z3** — still rolled forward.
- **Visualization / DOT export / interactive REPL / SMT-COMP driver** — sibling packages per v0.3 §8 scope discipline.

### What this release is NOT

- **Not a polish release.** That's v0.5.
- **Not the v1.0 tag.** That's v0.6 (or v1.0.0 — same content as v0.5 with version delta).
- **Not the moment we add a Nim-shaped DSL on top.** The wrapper at every version is "raw Z3 surface with Nim's type system encoding sort identity." Higher-level DSLs (if any) live in sibling packages.

---

## 2. The shape of the v0.4 expansion

v0.4 grows in three dimensions:

**New ref-typed handles** — `Z3Fixedpoint`, `Z3Stats`, `Z3Probe`, `Z3ParserContext`, `Z3AstVector`. Each is a typed ref over a `Z3_*_inc_ref` / `_dec_ref` pair, generated via the existing `emitRefcountLifecycle` template. The v0.3 step 1 unification *exists for this*: each new handle is one line.

**New typed value family** — `Z3Proof`. Slots into `Z3Term`, gets `wrap[Z3Proof]` / `eval[Z3Proof]` / etc. for free via the v0.3 step 1 generators. Its uniqueness is the `ProofRule` enum + `unpackProof` introspection — a surface that has no analogue in v0.3's families.

**Cross-cutting structural capabilities** — AST + sort introspection (the duality from goal 3), substitution, translation + compatibility predicate, quantifier-intro. These attach to the existing `Z3Term` concept without needing new families. `getAstKind` + `getAppDecl` + `getAppArg` + `getSortKind` + the sort-parameter extractors are the most user-visible — they let users walk arbitrary terms AND inspect arbitrary sorts, which is *table stakes* for any production-grade SMT wrapper (Python z3, JavaSMT, smt-z3-rs all ship this).

The single piece of v0.3 architectural debt this release closes is **`Z3DatatypeValue` as `sortOf` element type** — runtime decl-table indexed by marker-type name. Once that lands, every typed family is reachable from every other typed family via `sortdispatch`: `Z3Array[Z3DatatypeValue[Foo], Z3Seq[Z3Fp[8, 24]]]` and friends.

---

## 3. Module structure

Net additions (nine new modules):

- **`z3/astvector`** — `Z3AstVector` typed ref-handle with typed iteration / conversion. Foundational; used by goals 4 (unsat-core, consequences), 7 (quantifier patterns), 11 (parser-context output).
- **`z3/fixedpoint`** — Horn-clause solving (goal 1)
- **`z3/proof`** — `Z3Proof` family + `ProofRule` enum + `unpackProof` (goal 2)
- **`z3/introspect`** — `Z3AstKind` + `Z3SortKind` + the full programmatic-walk surface + `Z3AnyAst` + typed lifters (goal 3)
- **`z3/rewrite`** — `substitute` + `substituteVars` (goal 5)
- **`z3/translate`** — `translate[T: Z3Term]` + `compatibleWith` (goal 6)
- **`z3/probe`** — `Z3Probe` + numeric/boolean combinators + `condTactic` (goal 9)
- **`z3/globalparams`** — `setGlobalParam` / `getGlobalParam` / `resetAllGlobalParams` (goal 10)
- **`z3/io`** — parser context + `parseSmt2*` (relocated from `pretty`) + file I/O (goal 11)

Modifications:

- **`z3/solver`** — adds `getUnsatCore`, `getProof`, `getStatistics`, `getConsequences`, `assertConstraintAndTrack`. Imports `z3/proof` and `z3/astvector`.
- **`z3/quantifier`** — adds the `getQuantifier*` introspection family.
- **`z3/context`** — adds `datatypeRegistry: Table[string, RawZ3Sort]`.
- **`z3/datatypes`** — `declareDatatype` registers into the new context table.
- **`z3/sortdispatch`** — adds the `sortOf(_: typedesc[Z3DatatypeValue[T]], ctx)` overload doing the runtime lookup.
- **`z3/pretty`** — loses `parseSmt2`/`smt2Script`/`writeSmt2` (moved to `z3/io`); narrows scope to pure pretty-printing.

New supporting types (not their own modules, declared in the modules above):

- **`Z3Stats`** — typed ref-handle for solver statistics. Declared in `z3/solver` alongside `getStatistics`.
- **`Z3AnyAst`** — runtime-erased `Z3Term`. Declared in `z3/introspect`.

---

## 4. Phasing — what ships when

Architectural foundations first, then visible-payoff items, then cross-cutting, then small surface.

1. **`Z3AstVector` typed handle** (`z3/astvector`). ✅ shipped. Needed by goals 4 (unsat-core, consequences), 7 (quantifier patterns), 11 (parser-context output). Also landed the `Z3Term` concept properly in `z3/lifecycle` — see §8 spec correction.

2. **Structural introspection** (`z3/introspect`). ✅ shipped. Both AST-side (`Z3AstKind`, `getAppDecl`, `getAppArg`, `unpackApp`) and sort-side (`Z3SortKind`, `bitVecWidth`, `arrayKey`, `fpEbits`, …) capabilities, with the `Z3AnyAst` erased type and the per-family typed lifters.

3. **`Z3DatatypeValue` as `sortOf` element type.** ✅ shipped. Closes the v0.3 §8 carryover. Added the per-context `datatypeRegistry`, updated all `declareDatatype` / `declareDatatypes` variants to register, added the `sortOf` overload that does runtime lookup with helpful error on miss.

4. **`Z3Proof` family + `ProofRule` enum + `unpackProof` + `Z3Solver.getProof`.** ✅ shipped (with step 7 merged in — see §8). Lives in `z3/proof`.

5. **`Z3Fixedpoint`** (`z3/fixedpoint`). ✅ shipped. Largest single module added in v0.4 — comparable to `z3/optimize`. Spec corrections logged in §8 (push/pop, get_ground_sat_answer don't exist).

6. **Solver extensions — `assertConstraintAndTrack` + `getUnsatCore`.** ✅ shipped. First half of goal 4. Uses `Z3AstVector` from step 1.

7. **Solver extensions — `getProof`.** ✅ shipped together with step 4 (merged — see §8). Returns the `Z3Proof` from step 4.

8. **Solver extensions — `getStatistics` + `getConsequences`.** ✅ shipped. Adds `Z3Stats` typed handle (own module `z3/stats`). Closes goal 4 and the step-5 §8 fixedpoint-stats deferral.

9. **Term rewriting** (`z3/rewrite`). ✅ shipped. `substitute` + `substituteVars` generic over `Z3Term`. Also added `mkBound` for manual de-Bruijn bound-var construction.

10. **Cross-context transfer + compatibility** (`z3/translate`). ✅ shipped. `translate[T: Z3Term]` + `compatibleWith(ctxA, ctxB): bool`.

11. **Quantifier introspection.** Extends `z3/quantifier`. Mechanical wrapping of `Z3_get_quantifier_*`. Bound-var sort dispatch uses `getSortKind` from step 2.

12. **Probes + condTactic** (`z3/probe`).

13. **Global parameters** (`z3/globalparams`).

14. **I/O surface refactor** (`z3/io`). Step-style `Z3ParserContext` API per the resolved design decision.

15. **Pre-tag audit + §8b block** per the v0.3 precedent.

16. **v0.4 tag.**

---

## 5. Implementation sequence

Each step closes with a §8 deferral entry if anything surfaced mid-cycle (same discipline as v0.1 / v0.2 / v0.3).

1. **`Z3AstVector` foundation** (`z3/astvector`). New typed ref-handle. `emitRefcountLifecycle(Z3AstVectorOwn, Z3_ast_vector_dec_ref)`. Wrap `Z3_ast_vector_size` / `_get` / `_set` / `_resize` / `_push` / `_to_string`. Iteration: `iterator items(v: Z3AstVector): RawZ3Ast`. Conversion: `proc toSeq[T: Z3Term](v: Z3AstVector): seq[T]` — typed-family-resolving, mixin-dispatched. Single-cycle step. TDD tracer: build a vector, push two ASTs, check `len == 2` and `toSeq[Z3Bool]` returns them.

2. **Structural introspection** (`z3/introspect`). Two halves shipped together as one step because they're the duality of the same capability:

   - **AST side**: `Z3AstKind` enum mirroring `Z3_ast_kind`. `Z3AnyAst` — value-typed wrapper carrying the raw + ctx, lifecycle via `emitTermLifecycle`, slots into `Z3Term`. `getAstKind*(a: Z3AnyAst): Z3AstKind` + `getAstKind*[T: Z3Term](a: T): Z3AstKind` (lifts). `getAppNumArgs` / `getAppArg` / `getAppDecl` / `unpackApp(a): tuple[decl: RawZ3FuncDecl, args: seq[Z3AnyAst]]`. `getNumeralString[T](a)`.
   - **Sort side**: `Z3SortKind` enum mirroring `Z3_sort_kind`. `getSortKind(s: RawZ3Sort): Z3SortKind`. Per-family parameter extractors: `bitVecWidth`, `arrayKey` / `arrayRange`, `seqElement`, `fpEbits` / `fpSbits`, `regexBasis`, `datatypeName`.
   - **Typed lifters from `Z3AnyAst`**: `asZ3Int(a: Z3AnyAst): Z3Int`, `asZ3Bool`, `asZ3Real`, `asZ3BitVec[W]`, `asZ3Char`, `asZ3Fp[E, S]`, `asZ3Seq[E]`, `asZ3Regex[Basis]`, `asZ3FuncDecl[Args, Ret]`, `asZ3DatatypeValue[T]`. Each runtime-checks via `getSortKind` and raises `Z3SortError` on mismatch.

   TDD: build `mkInt(2) + mkInt(3)`, `unpackApp` returns the `+` decl + two-arg seq, recursive `unpackApp` on a child returns a numeral; assert `getSortKind(s) == skBitVec` + `bitVecWidth(s) == 32` for a `mkBitVecSort(32)`; lift `Z3AnyAst` carrying an Int back to `Z3Int` via `asZ3Int`.

3. **`Z3DatatypeValue` `sortOf` element type.** Add `datatypeRegistry: Table[string, RawZ3Sort]` to `Z3ContextOwn`. `declareDatatype[T]` registers the resulting `RawZ3Sort` under `$T`. `sortOf(_: typedesc[Z3DatatypeValue[T]], ctx)` looks up `$T`; raises `Z3UsageError` ("`Z3DatatypeValue[Foo]` is not registered — call `declareDatatype[Foo]()` first") if missing. TDD: `declareDatatype[Color]`; build `Z3Array[Z3Int, Z3DatatypeValue[Color]]`; round-trip a model.

4. **`Z3Proof` family + `ProofRule` enum + `unpackProof`.** New module `z3/proof`. `type Z3Proof = object` with `raw: RawZ3Ast` / `ctx: Z3Context`; `emitTermLifecycle(Z3Proof, ...)`. `sortOf*(_: typedesc[Z3Proof], ctx)` for sortdispatch parity. `ProofRule` enum with ~30 entries + paraphrased Z3-doc-sourced docstrings + `## See: z3_api.h Z3_OP_PR_*` source cites. `getProofRule(p)` extracts via `Z3_get_decl_kind` on the app's decl. `unpackProof(p): tuple[rule: ProofRule, premises: seq[Z3Proof], conclusion: Z3Bool]` via the introspection from step 2.

   **Test note**: proof introspection is hard to TDD against literal proofs (Z3 doesn't expose a "make a proof literal" entry point). Tests must drive Z3 to produce a proof via `set_param("proof", true)` on a solver, assert an unsat formula, extract via `getProof`, then unpack. The headline test: assert `(x > 0) and (x < 0)` over a `Z3Int x`, check unsat, extract proof, walk top-level rule, assert it's one of the unsat-derivation rules (typically `prTheoryLemma` or `prResolve`).

5. **`Z3Fixedpoint`** (`z3/fixedpoint`). Largest single step in v0.4. Comparable to v0.2's optimize work. Full surface per goal 1. Tests: classic CHC reachability example (e.g. graph reachability — `path(x, y)` Horn-clause family, query whether two nodes connect).

6. **Solver `assertConstraintAndTrack` + `getUnsatCore`.** `assertConstraintAndTrack(s, c, tracker)`: wraps `Z3_solver_assert_and_track`. `getUnsatCore(s): seq[Z3Bool]`: wraps `Z3_solver_get_unsat_core` (returns `Z3_ast_vector` — convert via step 1's `toSeq`). TDD: assert `x > 5` tracked as `t1`, `x < 3` tracked as `t2`, check unsat, `getUnsatCore` returns `[t1, t2]`.

7. **Solver `getProof`.** ✅ shipped together with step 4 (commit `ae9b105`). Closed in step 4 because the `Z3Proof` family is untestable without a way to extract one — Z3 has no public proof-literal constructor. No work happens at "step 7" in the sequence; the numbered slot is preserved for historical traceability against the original plan ordering. See §8 "From step 4 (Z3Proof family + getProof — steps 4 and 7 merged)".

8. **Solver `getStatistics` + `getConsequences`.** `Z3Stats` typed handle with `len` / `[]` / `keys` / iteration. `getStatistics(s): Z3Stats`. `getConsequences(s, assumptions, variables): tuple[status: Z3Status, consequences: seq[Z3Bool]]`. TDD: solve trivial problem, `getStatistics` returns non-zero `len`, lookup a known key.

9. **Term rewriting** (`z3/rewrite`). `substitute*[T: Z3Term](a: T, replacements: openArray[(Z3AnyAst, Z3AnyAst)]): T`. `substituteVars*[T: Z3Term](a: T, replacements: openArray[Z3AnyAst]): T`. TDD: `substitute(x + y, [(x, mkInt(3))])` equals `3 + y`; `substituteVars` on a forall body replaces the bound var.

10. **Cross-context transfer + compatibility** (`z3/translate`). `translate*[T: Z3Term](t: T, targetCtx: Z3Context): T`. `compatibleWith(ctxA, ctxB: Z3Context): bool` — uses a no-op translation under exception capture if Z3 doesn't expose a direct predicate. TDD: build `x: Z3Int` in ctx A, `compatibleWith(A, B)` returns true, translate to ctx B, evaluate to same SMT-LIB string.

11. **Quantifier introspection** (extends `z3/quantifier`). ✅ shipped. Wraps `Z3_get_quantifier_*` family. Bound-var sort dispatch uses step 2's `getSortKind`.

12. **Probes + condTactic** (`z3/probe`). ✅ shipped. `Z3Probe` ref-handle with `emitRefcountLifecycle`. `mkProbe(name)` / `mkProbeConst(value)` for construction; `apply(p, g): float` for evaluation. Comparison operators (`<`, `<=`, `>`, `>=`, `==`) return **new probes** (not `bool`) so call-site notation reads naturally — auto-lifts `float` literals on both sides. Boolean combinators `and` / `or` / `not`. `condTactic(probe, ifT, elseT)` dispatches between tactics by the probe's truthiness. Required public `raw`/`ctx` accessors on `Z3Tactic`/`Z3Goal` and exported `wrapTactic`. 7 behaviors × 2 backends GREEN; total suite 1090 OKs.

13. **Global parameters** (`z3/globalparams`). ✅ shipped. Three procs: `setGlobalParam(name, value)`, `getGlobalParam(name): Option[string]`, `resetGlobalParams()`. Auto-loads `libz3` via newly-exported `context.ensureLoaded` so calls work before any `Z3Context` is allocated (the common case for `"verbose"` / `"memory_max_size"`). `Option` semantics match Z3's `_get` return — `none` for unknown names, `some(v)` for known names where `v` is the effective value (override or default); Z3 does not distinguish "user-set" from "at default". `Z3_string_ptr` (`const char **`) maps via `pointer` + cast to satisfy strict cpp typechecking. 5 behaviors × 2 backends GREEN; total suite 1100 OKs.

14. **I/O surface refactor** (`z3/io`). ✅ shipped. Relocated `smt2Script` / `writeSmt2` / `parseSmt2` (renamed `parseSmt2String`) out of `z3/pretty` into a dedicated `z3/io` module. Added `parseSmt2File`, `loadSmt2String` / `loadSmt2File` (direct-to-solver via `Z3_solver_from_string` / `_from_file`), `evalSmt2` (`Z3_eval_smtlib2_string`), `toSmt2Benchmark` (`Z3_benchmark_to_smtlib_string`), and `Z3ParserContext` refcount-managed handle with `addSort[S]` / `addDecl[A, R]` / `parseFromString` for streaming parse with persisted declarations. **Scope-creep addition:** `mkUninterpretedSort(name)` / `declareSort(name)` in `z3/sort` with new `stUninterpreted` `SortTag` — uninterpreted sorts are first-class SMT-LIB and were a real gap surfaced by the parser-context tests. 15 behaviors × 2 backends GREEN; total suite 1114 OKs. tpretty.nim's smt2 suites removed (covered exhaustively in tio.nim); examples updated.

15. **Pre-tag audit + §8b block.** Walk every §1 goal + every §4 step, classify each as landed / rolled-to-v0.5 / dropped, log spec corrections, write the cross-reference. Same format as V0.3 §8b.

16. **v0.4 tag.** Annotated tag, CHANGELOG entry, archive promotion (this file → `docs/V0.4_PLAN.md`; `docs/V0.5_PLAN.md` → `docs/IMPLEMENTATION_PLAN.md`).

---

## 6. Risks specific to v0.4

### `Z3AnyAst` becomes a path-of-least-resistance escape hatch

Goal 3's introspection introduces `Z3AnyAst` as a runtime-erased AST handle. **The risk is that users build with typed families, drop to `Z3AnyAst` for introspection, never lift back.** The wrapper should document the lift path (pattern-match on `getAstKind` + `getSortKind`, then `asZ3Int` etc.) and the typed lifters ship as part of step 2 so the round-trip is one call. Mitigation: lifters land alongside `Z3AnyAst` in the same step; docstrings emphasise the lift discipline.

### Proof grammar is large and Z3-version-coupled

Goal 2's `ProofRule` enum has ~30 entries today. Z3 4.14 / 5.x might add proof rules; our enum has to gain entries (semver minor bumps can add enum values cleanly). The bigger risk is **proof-rule semantics drift** — Z3 may change what a given rule's premises/conclusion shape looks like, breaking `unpackProof` callers. Mitigation: pin Z3's tested version explicitly in the README; surface as a v1.x compatibility concern post-1.0.

### `compatibleWith` semantics fragility

Goal 6's `compatibleWith` predicate has no direct Z3 entry point. Implementation strategy: attempt a no-op `Z3_translate` under exception capture and return `false` if it raises, `true` otherwise. **The risk is that side-effects of the attempted translation leak state** (Z3 may allocate intermediate ASTs that we don't get to clean up cleanly). Mitigation: investigate during step 10; if leakage is real, document the predicate as "may allocate up to one transient AST per call" and add a usage caveat.

### Fixedpoint surface depth

Goal 1's `Z3Fixedpoint` has ~25 distinct C entry points. Best-in-class wraps all of them. **The risk is scope creep mid-step** — once we start adding `addRecursiveFunction` / `addCover` / `getRulesAlongTrace` etc., the step expands. Mitigation: target the full surface from the start, treat as the single largest v0.4 step (1.5–2× a typical step's size).

### Cross-cutting test infrastructure for proof extraction

Steps 4 (proof extraction) and 7 (solver getProof) need careful test discipline because Z3's proof generation is sensitive to which solver tactics fire, which can vary by Z3 version. **Tests should assert the proof's top-level rule kind, not specific intermediate steps.** Mitigation: test policy doc inline in the test file at step 4.

### `Z3DatatypeValue` sortOf raises rather than compile-errors

Goal 8's `sortOf(_: typedesc[Z3DatatypeValue[T]], ctx)` does a runtime lookup. If `Z3Array[Z3Int, Z3DatatypeValue[UnregisteredFoo]]` is constructed before `declareDatatype[UnregisteredFoo]` runs, the construction raises at runtime — different discipline from every other `sortOf` overload (which `{.error.}`s at compile time). **The risk is users hit this at runtime in test code where compile-time errors would be more obvious.** Mitigation: clear error message naming the missing marker type + the fix.

---

## 7. Open questions (genuinely open — answer during implementation)

1. **Global params interaction with thread-locals.** Goal 10's `setGlobalParam` mutates Z3's library-wide state. The wrapper's `currentContext` is a `threadvar`. How do `setGlobalParam` calls from multiple threads interact? Z3 documents this poorly. Resolution requires reading Z3 source + writing a smoke test under concurrent load. Decide during step 13.

*(All other planning-time decisions resolved before promotion to live plan: `Z3AnyAst` as the erased-type name, step-style `Z3ParserContext` API, full `Z3SortKind` surface shipped, full `compatibleWith` predicate shipped, paraphrased proof-rule docstrings with Z3-source cites. These were genuine decisions; their resolutions are encoded in §1 goals 3 / 6 / 11 above.)*

---

## 8. Deferred from v0.4 (running list, populated as work happens)

Same append-only format as v0.1 §18, v0.2 §8, v0.3 §8. Format: **what / why / where it goes** (v0.5 / dropped / sibling-package).

### From step 14 (I/O surface refactor)

- **`toSmt2Benchmark` `status=""` produces malformed SMT2.** `Z3_benchmark_to_smtlib_string` unconditionally emits `(set-info :status <s>)` even when the status argument is empty, yielding the syntactically-invalid `(set-info :status )`. **Fix:** changed the wrapper's `status` default from `""` to `"unknown"` — a valid SMT-LIB status value that round-trips through `parseSmt2String`. The other three metadata fields (`name`, `logic`, `attributes`) are properly omitted by Z3 when empty.
- **Uninterpreted sorts added as scope creep but a real gap.** `Z3ParserContext.addSort` is meaningful only when there's a sort that isn't already known to Z3 by name (built-ins like `Int` are accessible without registration). The wrapper had no surface for `Z3_mk_uninterpreted_sort`, so step 14's testing surfaced this. Added a new `stUninterpreted` `SortTag` plus `mkUninterpretedSort(name)` / `declareSort(name)` (SMT-LIB-styled alias). Two uninterpreted sorts with the same name in the same context are the same sort, matching Z3 semantics.
- **`parseSmt2` renamed to `parseSmt2String`.** Symmetric with `parseSmt2File`; matches Z3's own `Z3_parse_smtlib2_string` / `_file` naming. Pre-v1, no compat. Updated `tests/tproperty.nim` and `examples/pretty_and_smt2.nim`; deleted `tests/tpretty.nim`'s SMT2 suites (the new `tests/tio.nim` covers them exhaustively).
- **Module ownership: `z3/pretty` for human-facing format, `z3/io` for SMT2 wire format.** They had been muddled into one file because both rendered solver state to text; the *purpose* differs (debugging vs. interchange), and so do the call sites. Result: `z3/pretty` is now four pretty-printers (`pretty(ast | sort | solver | model)`) and nothing else; `z3/io` owns the SMT-LIB2 surface end-to-end.
- **`Z3_string_ptr` not needed here.** Unlike step 13's `Z3_global_param_get`, all `z3/io` C calls take or return `Z3_string` (`const char *`) directly; no `const char **` mapping pain.
- **`Z3_benchmark_to_smtlib_string` buffer ownership.** Z3's docstring warns the returned string is overwritten on the next call to the same function. The wrapper copies into a Nim `string` immediately (`$ s`), so this is safe in single-threaded use; multi-threaded callers would need their own coordination, but that's already the standing thread-safety contract.
- **No parametric stateless overloads** (`parseSmt2String(ctx, src; sorts, decls)`). Considered and rejected — would require `Z3AnySort` / `Z3AnyFuncDecl` heterogeneous-array machinery that doesn't exist, and `Z3ParserContext` strictly subsumes the use case with cleaner ergonomics.
- **Nothing deferred to v0.5.** The SMT-LIB I/O surface is complete for v0.4's contract claim: emission (script + benchmark), one-shot parse (string + file), direct-to-solver feeds (string + file), eval, and streaming parse with pre-registered sorts / decls.

### From step 13 (Global parameters)

- **`Z3_global_param_get` returns effective value, not user-set value.** The C API's `bool` return is `true` for any parameter Z3 knows about (yielding the override or built-in default), and `false` only for unrecognised names. The initial spec note hinted `none` would mean "at default"; that's not what Z3 offers. Wrapper now documents this faithfully: `none` ⇔ unknown name; `some(v)` ⇔ effective value as a string. To track "did *we* override this?", callers must keep a shadow record — Z3 surfaces no signal.
- **Numeric/typed params parse on set, normalise on bad input.** Z3 parses each parameter into its declared C type (`unsigned int`, `bool`, `string`) inside `Z3_global_param_set`; a malformed numeric value (e.g. `"  42  "` with leading whitespace) is rejected and the parameter falls back to its built-in default with a `WARNING:` line on Z3's stderr. The wrapper does no pre-validation — surfacing Z3's actual diagnostic is more honest than reimplementing the parse.
- **`Z3_string_ptr` is `const char **`; Nim's `ptr cstring` decays to `char **`.** Strict `nim cpp` rejects the mismatch. Mapped the `param_value` parameter as opaque `pointer` in the FFI block and cast at the call site — semantics identical (Z3 only writes through it), and the cpp backend compiles.
- **`ensureLoaded` promoted to public.** Global-param calls reach a libz3 symbol with no `Z3Context` allocated, so callers may invoke them before any `newContext`. Rather than duplicate the softlink load logic, exported the existing idempotent hook from `z3/context`. Useful precedent for any future symbol that's reachable pre-context.
- **No `withGlobalParam` RAII helper.** Considered and rejected: Z3 offers no per-key unset (only `reset_all`), so a faithful "restore previous value" is unrepresentable when the previous state was `none`. The three-proc surface is exactly what Z3 supports.

### From step 12 (Probes + condTactic)

- **Operator return type — design decision.** Comparison operators on `Z3Probe` (`<`, `<=`, `>`, `>=`, `==`) return **`Z3Probe`**, not `bool`. This matches Z3's underlying API (`Z3_probe_lt` produces a probe) and lets the call site read naturally — `mkProbe("num-consts") < 100.0` builds a predicate probe instead of fighting the eye. Documented loudly in the module header.
- **Float-literal auto-lift.** Each comparator has three overloads — `(probe, probe)`, `(probe, float)`, `(float, probe)` — emitted by a single `emitCmp` template. `mkProbeConst` is the lifting bridge. No spec correction; this is purely ergonomic.
- **`Z3Tactic` / `Z3Goal` accessor lift.** `wrapTactic`, `Z3Tactic.raw`, `Z3Tactic.ctx`, `Z3Goal.raw`, `Z3Goal.ctx` were promoted from private to public in `z3/tactic` so `z3/probe` can build a `Z3Tactic` from `Z3_tactic_cond` and evaluate probes against `Z3Goal`s without a cyclic dep. Mirrors the precedent set for `Z3FuncDecl` in step 5.
- **Test technique — observable dispatch.** `condTactic`'s dispatch is verified by giving one branch `mkTactic("smt")` (decision procedure → `zsSat`) and the other `mkTactic("fail")` (always-fail). The probe value then determines whether `check()` returns `zsSat`, making dispatch directly observable in the test without any side-channel. Worth recording for future tactic-combinator tests.
- **Nothing deferred to v0.5.** The Z3 probe surface is fully covered: `Z3_mk_probe`, `Z3_probe_const`, `Z3_probe_apply`, all six comparators (`lt`/`le`/`gt`/`ge`/`eq`), all three booleans (`and`/`or`/`not`), and `Z3_tactic_cond`.

### From step 11 (quantifier introspection)

- **Clean landing.** Extended `z3/quantifier` with the full `Z3_get_quantifier_*` surface: bound vars (count / name / sort), body, kind discriminators (`isForall` / `isExists` / `isLambda`), weight, patterns + no-patterns. No spec corrections.
- **Bound-var sort returns `RawZ3Sort`** per plan; users dispatch via step 2's `getSortKind` (`skInt`, `skBool`, …). The plan's §7 open question (Q2: "do we ship a runtime sort→typedesc dispatcher?") is resolved as planned: no, document the comparison pattern. The `getSortKind` route is sufficient for every introspection use case shipped so far.
- **`assertIsQuantifier` template** added as a private precondition guard. Every getter calls it first to surface a clear "AST is not a quantifier" error rather than Z3's opaque `Z3_INVALID_USAGE`.

### From step 10 (cross-context transfer + compatibility)

- **Clean landing.** Smallest module in v0.4; one FFI proc + the smoke-test predicate. No spec corrections.
- **`compatibleWith` implementation strategy worked.** No direct Z3 predicate exists; the wrapper uses a `Z3_mk_true → Z3_translate` round-trip under exception capture, returning `false` on any failure. Documented as "conservative" and noting the per-call transient-AST allocation.
- **Typed family preservation verified across Z3Int / Z3Bool / Z3BitVec[W] / Z3Real.** The `Z3Term` constraint + `wrap[T](targetCtx, raw)` round-trips the typed family cleanly; sort identity preserved at the SMT-LIB string level (Z3 emits the same syntactic form regardless of which context owns the AST).
- **End-to-end solver round-trip works**: build constraint in ctx A, translate to ctx B, B's solver decides identically. This is the canonical multi-threading / multi-solver use case the capability exists for.

### From step 9 (term rewriting)

- **Clean landing.** No spec corrections this step. The two `Z3_substitute*` C functions wrap cleanly via the `Z3Term` constraint with `Z3AnyAst`-typed replacements.
- **Two surfaces ship side-by-side**: the general `substitute(a, openArray[(Z3AnyAst, Z3AnyAst)])` form and a single-pair convenience `substitute(a, fromTerm, toTerm)` that auto-lifts typed values to `Z3AnyAst`. PhD ergonomic balance: typed callers write `substitute(x + y, x, mkInt(3))`; multi-sort callers write `substitute(a, [(toAnyAst(x), toAnyAst(mkInt(3))), (toAnyAst(p), toAnyAst(mkBool(true)))])`.
- **`mkBound` added for de-Bruijn bound-var construction.** Z3 represents quantifier bodies internally with bound vars at de-Bruijn indices; `mkBound(ctx, index, sort): Z3AnyAst` lets users manually construct these for `substituteVars` instantiation (or for any user doing low-level quantifier-body programming). Required to TDD `substituteVars` without depending on step 11's quantifier introspection.
- **Typed return preservation works through the `Z3Term` concept**. `substitute(b: Z3Bool, ...): Z3Bool` round-trips the type — proven via the "substitute on a Z3Bool returns Z3Bool" test using the explicit return-type annotation.

### From step 8 (getStatistics + getConsequences)

- **Clean landing.** Two solver extensions + a new typed family (`Z3Stats` in own module `z3/stats`) + parity addition to `Z3Fixedpoint`. No spec corrections.
- **`Z3Stats` deep-module placement.** New module `z3/stats` (parallel to `z3/astvector` from step 1) — own conceptually-coherent surface used by both `Z3Solver.getStatistics` and `Z3Fixedpoint.getStatistics`. Lifecycle via `emitRefcountLifecycle`; surface includes `len`, `keys()`, `[key]` uniform-float view, `contains`, `isInt` discriminator, `getInt` (lossless for huge uints), `getFloat`, `pairs` iterator matching Nim's `Table` convention, `$` SMT-LIB rendering.
- **`getConsequences` reuses step-1's `Z3AstVector` for input + output**. Implementation builds three vectors (assumptions, variables, output), calls `Z3_solver_get_consequences`, converts the result through `Z3AstVector.toSeq(Z3Bool)` to expose typed implication ASTs.
- **Fixedpoint statistics closes the step-5 §8 deferral.** `Z3_fixedpoint_get_statistics` returns the same `Z3_stats` handle type as solvers; one-line addition to `z3/fixedpoint`.

### From step 7 (Solver.getProof) — explicit close-out

- **No work done in step 7's slot.** All of step 7's planned scope (`getProof` extraction) shipped in step 4 (commit `ae9b105`) per the merge rationale logged in this §8 above. Step 7 is closed without code as a docs-only marker, preserving the numbered slot for historical alignment with the original plan and the V0.4_PLAN.md archive. Step 8 (`getStatistics` + `getConsequences`) is the next active step.

### From step 6 (assertConstraintAndTrack + getUnsatCore)

- **Clean landing.** Closes the v0.3 step-8 half-implementation (could set `unsat_core=true` but couldn't extract). `Z3AstVector.toSeq(Z3Bool)` from v0.4 step 1 carries the typed extraction. No spec corrections.
- **Two user-facing surfaces ship side-by-side**: `assertConstraintAndTrack(s, c, tracker: Z3Bool)` (explicit-tracker form matching the C API) and `track(s, c, name: string)` (convenience that auto-creates `mkBoolVar(name)` and returns it). Both return the tracker; both are `{.discardable.}` so users can ignore the return when they captured the tracker via the input or via a named helper.
- **Optional `unsat_core=true` param turned out not to be required.** Z3 enables unsat-core extraction implicitly whenever any `assert_and_track` is used. The v0.3 step-8 `setParams("unsat_core", true)` path still works but is redundant; tests don't set it. **No work deferred.**

### From step 5 (Z3Fixedpoint)

- **Spec correction: `Z3_fixedpoint_push` and `Z3_fixedpoint_pop` don't exist.** The plan's initial design ported `Z3Solver`'s `push` / `pop` / `withFrame` scoping pattern by analogy. Z3's actual Fixedpoint API has no user-controlled scope management — rules + facts accumulate for the handle's lifetime. Users who want fresh state allocate a new `Z3Fixedpoint`. Wrapper documents this in source comments where `push`/`pop` would have lived.
- **Spec correction: `Z3_fixedpoint_get_ground_sat_answer` doesn't exist.** The plan listed `getGroundSatAnswer` as a sat-witness extractor distinct from `getAnswer`. Z3 only ships `Z3_fixedpoint_get_answer`; the wrapper uses that as the canonical witness extractor.
- **Spec correction: `datalog` engine requires finite-domain sorts.** The plan's draft test set `engine=datalog` on a graph-reachability test that used unbounded `Z3Int`s — datalog returned `zsUnknown` because the predicates aren't finite-domain. Resolution: tests use Z3's default engine, which picks an appropriate strategy for the problem shape. `engine=datalog` is real but requires the user to use `Z3_mk_finite_domain_sort` or BVs — a niche path not exercised by step 5's tests.
- **Z3Stats / fixedpoint statistics deferred to step 8.** `Z3_fixedpoint_get_statistics` returns `Z3_stats`; the typed `Z3Stats` handle lands in step 8 (`Z3Solver.getStatistics` parallel). Step 5's surface excludes statistics; will be added retroactively to fixedpoint when step 8 lands.
- **SMT-LIB I/O for fixedpoint deferred to step 14.** `Z3_fixedpoint_from_string` / `_from_file` are real entry points; they land alongside the rest of the I/O surface in step 14's `z3/io` module rewrite.
- **Callback registration (`Z3_fixedpoint_init`, `_set_predicate_representation`, `_set_reduce_*_callback`) deferred indefinitely.** Same category as user propagators — callback-based extension to Z3's solver; substantial scope; no real user demand. Logged for v1.x+ research-grade follow-up.
- **`raw` / `ctx` accessors added to `Z3FuncDecl`.** The funcdecl module had `Z3FuncDeclOwn`'s `raw` and `ctx` fields private. Sibling modules (`z3/fixedpoint` needs the raw decl handle for `registerRelation` / cover ops) couldn't reach in. Added `raw*` / `ctx*` accessor procs in `z3/funcdecl` parallel to the `Z3Solver` / `Z3Model` precedent. **No work deferred** — minor pre-1.0 cleanup that v0.4 step 5 surfaced.

### From step 4 (Z3Proof family + getProof — steps 4 and 7 merged)

- **Plan restructure: steps 4 and 7 ship together as one merged step.** The original plan put `getProof` in step 7 and the `Z3Proof` family + `ProofRule` enum + `unpackProof` in step 4, with the rationale that the family should land before its only consumer. In practice the family is **untestable** without a way to extract a proof from a solver — Z3 has no public "make a proof literal" entry point. Steps 4 and 7 are therefore tightly coupled in the test discipline. Merged into one step labelled "step 4 (with step 7)"; subsequent step numbers don't shift (step 5 = Fixedpoint stays at 5; step 6 = unsat-core / assert_and_track stays at 6; **what was step 7 is now empty in the sequence**).
- **Spec correction: Nim FFI under the C++ backend.** The plan's initial draft declared `Z3_get_decl_kind` as returning `cuint`. softlink's `_Static_assert` under `nim cpp` checks the Nim-declared return type against the actual C signature with strict type equality — Z3's `Z3_get_decl_kind` returns the `Z3_decl_kind` enum, NOT `unsigned int`. The C backend accepts the implicit enum→int conversion; C++ rejects it. Resolution: declared `Z3DeclKindFFI` as a typed Nim enum with `{.importc: "Z3_decl_kind", header: "z3.h", size: sizeof(cint).}` carrying just the proof-rule subset (42 entries from 0x500). The Nim type emits as `Z3_decl_kind`; softlink's static_assert sees `is_same<Z3_decl_kind, Z3_decl_kind>` which is true; C++ build passes. Imported enums tolerate out-of-range runtime values (non-proof decl kinds Z3 may return); `toProofRule`'s `else` branch maps them to `prUnknown`. **No work deferred** — the fix is the right shape.
- **`sortOf[Z3Proof]` overload not shipped.** Z3 doesn't expose a public way to construct a "proof sort" handle, and users won't realistically want `Z3Seq[Z3Proof]` / `Z3Array[K, Z3Proof]` at the modeling level. The plan's "sortOf for sortdispatch parity" item is deferred indefinitely — if a real user needs Z3Proof as a sortdispatch element, we figure out Z3's internal proof-sort representation then. Logged here so future-me doesn't try to ship it speculatively.
- **Test discipline confirmed**: proofs assert *structural* properties (a proof exists; rule is recognised; unpack yields a Z3Bool conclusion; sub-proofs are themselves akApp ASTs) rather than specific proof-tree shapes — Z3-version-fragile per §6 risks.

### From step 3 (Z3DatatypeValue as sortOf element type)

- **Clean landing.** The runtime decl-table mechanism worked exactly as planned: `Z3ContextOwn` gained a `datatypeRegistry: Table[string, RawZ3Sort]` keyed by marker-type name (`$T`); all four `declareDatatype` / `declareDatatypes` variants register the produced sort(s) at finalisation; the `sortOf*[T](_: typedesc[Z3DatatypeValue[T]], ctx)` overload looks up `$T` and raises `Z3Error` with a precise registration-required message on miss. No spec corrections surfaced.
- **Idempotency policy: overwrite.** Re-registering the same `T` overwrites the previous sort handle. Z3 itself would build a fresh sort on duplicate `declareDatatype` calls anyway, so the registry tracks only the most recent. Documented in the `sortOf` docstring; no user-facing error on duplicate registration.
- **One departure from compile-time sortdispatch.** This is the only `sortOf` overload in the wrapper that does runtime table lookup — every other typed family's sort is determined entirely at compile time. The departure is justified because Z3 datatype sort identity literally cannot be encoded compile-time (the underlying sort handle is dynamic). Comment in `z3/datatypes.nim` calls this out as the one principled exception to the sortdispatch discipline.
- **Headline capability unlocked**: `Z3Array[Z3Int, Z3DatatypeValue[Color]]`, `Z3Seq[Z3DatatypeValue[Color]]`, `Z3FuncDecl[(Z3DatatypeValue[Color],), Z3Bool]` all construct + round-trip through models. Mutually-recursive datatypes (`declareDatatypes(forDatatype[Tree], forDatatype[Forest])`) register both sides in one batch.

### From step 2 (structural introspection)

- **Spec correction**: Z3's FP sort-parameter extractors are `Z3_fpa_get_ebits` / `Z3_fpa_get_sbits`, NOT `Z3_get_fpa_sort_ebits` / `_sbits` as the plan's draft spec assumed. The naming convention isn't perfectly consistent across Z3's sort-introspection family (`Z3_get_bv_sort_size`, `Z3_get_array_sort_domain`, `Z3_get_seq_sort_basis` follow `Z3_get_*_sort_*`, but FP and Char use `Z3_fpa_*` / `Z3_*_char_sort` variants). Resolution: name FFI bindings after the actual C symbols; the Nim wrapper presents a clean unified surface (`fpEbits` / `fpSbits` / `bitVecWidth` / `arrayKey` / `seqElement`). **No work deferred.**
- **Z3 represents `Bool` literals as 0-arity applications.** `mkBool(true)` has `getAstKind == akApp`, not `akNumeral` — Z3 treats `true` / `false` as nullary applications of the boolean-constant function decl. Same for free constants (`mkIntVar("x")` is also `akApp`). The wrapper documents this in the `getAstKind` docstring on `akApp`. Test pins the observable behaviour. **No work deferred.**
- **`Z3SortError` typed exception subclass not used yet.** Sort-mismatch errors raised by `asZ3X` lifters use the flat `Z3Error` with `Z3_INVALID_USAGE` code. The plan's V0.5_PLAN.md goal 3 (error type hierarchy) will introduce `Z3SortError` as a subclass; v0.4 step 2 uses the flat form because the hierarchy doesn't exist yet. Naming the eventual subclass and ensuring all sort-mismatch raise sites flow through one helper (`raiseSortMismatch` template) makes the v0.5 step-3 refactor mechanical. **No work deferred** — v0.5 step 3 handles the hierarchy.

### From step 1 (Z3AstVector foundation)

- **Spec correction landed: the `Z3Term` concept was never an actual Nim concept until now.** v0.3 step 1's plan documented landing it; the unification *machinery* (`wrap[T]`, `emitTermLifecycle`, `emitRefcountLifecycle`) shipped but `Z3Term` as a constraint was left implicit — `wrap*[T]` was unconstrained. Every docstring referencing "the `Z3Term` concept" was aspirational rather than factual. v0.4 step 1 lands the real concept in `z3/lifecycle`:
  ```nim
  type Z3Term* = concept x
    x.raw is RawZ3Ast
    x.ctx is Z3Context
  ```
  Backward-compatible: every typed family already has the field shape, so no family migration needed. v0.4 step 1's `Z3AstVector.add[T: Z3Term]` and `toSeq[T: Z3Term]` are the first users. **v0.5 step 2's "make Z3Term load-bearing" work then retroactively constrains v0.3's unconstrained generics.**
- **`Nim 2 system.==` ambiguity with FFI typed-`==`.** Tests trying to compare raw AST handles directly with `==` hit a Nim-2-vs-FFI ambiguity (system's auto-derived object `==` competes with ffi.nim's explicit raw-pointer `==`). Resolution: test through *typed observable behavior* (`smtValid(extracted == original)`) rather than raw-pointer identity. PhD-defensible: the user-facing surface IS the typed family; testing through it is the right discipline. **No work deferred** — this is a test-policy choice, not a wrapper bug.



---

## 9. Closing note

After v0.4 ships, the wrapper's scope statement is **literally true**: every capability the Z3 C API exposes is reachable through nim-z3, with type-safety and memory-safety invariants preserved. That's the contract 1.0 commits to. v0.5 then polishes the surface (load-bearing `Z3Term` concept, naming hygiene, error type hierarchy, examples, docs, feature flags) so the 1.0 commitment is on a stable foundation.

The chronology: v0.4 (capability completion) → v0.5 (polish) → v0.6 = v1.0 (version-only tag).

If reading this, future-me, after v0.4 has shipped: archive this file to `docs/V0.4_PLAN.md`, promote `docs/V0.5_PLAN.md` to `docs/IMPLEMENTATION_PLAN.md` as the live plan, update the README's "Design" section to point at all four archives (V0.1, V0.2, V0.3, V0.4). Same rotation pattern as v0.1 → v0.2 → v0.3.

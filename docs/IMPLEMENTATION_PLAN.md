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

5. **`Z3Fixedpoint`** (`z3/fixedpoint`). Independent of other goals. Largest single module added in v0.4 — comparable to `z3/optimize`.

6. **Solver extensions — `assertConstraintAndTrack` + `getUnsatCore`.** First half of goal 4. Uses `Z3AstVector` from step 1.

7. **Solver extensions — `getProof`.** ✅ shipped together with step 4 (merged — see §8). Returns the `Z3Proof` from step 4.

8. **Solver extensions — `getStatistics` + `getConsequences`.** Adds `Z3Stats` typed handle. Closes goal 4.

9. **Term rewriting** (`z3/rewrite`). `substitute` + `substituteVars`. Generic over `Z3Term`.

10. **Cross-context transfer + compatibility** (`z3/translate`). `translate[T: Z3Term]` + `compatibleWith(ctxA, ctxB): bool`.

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

7. **Solver `getProof`.** `proc getProof(s: Z3Solver): Z3Proof`. Requires `setParams(p with proof=true)` before assertion. TDD: same shape as step 4's note — assert unsat formula, extract proof, walk root rule.

8. **Solver `getStatistics` + `getConsequences`.** `Z3Stats` typed handle with `len` / `[]` / `keys` / iteration. `getStatistics(s): Z3Stats`. `getConsequences(s, assumptions, variables): tuple[status: Z3Status, consequences: seq[Z3Bool]]`. TDD: solve trivial problem, `getStatistics` returns non-zero `len`, lookup a known key.

9. **Term rewriting** (`z3/rewrite`). `substitute*[T: Z3Term](a: T, replacements: openArray[(Z3AnyAst, Z3AnyAst)]): T`. `substituteVars*[T: Z3Term](a: T, replacements: openArray[Z3AnyAst]): T`. TDD: `substitute(x + y, [(x, mkInt(3))])` equals `3 + y`; `substituteVars` on a forall body replaces the bound var.

10. **Cross-context transfer + compatibility** (`z3/translate`). `translate*[T: Z3Term](t: T, targetCtx: Z3Context): T`. `compatibleWith(ctxA, ctxB: Z3Context): bool` — uses a no-op translation under exception capture if Z3 doesn't expose a direct predicate. TDD: build `x: Z3Int` in ctx A, `compatibleWith(A, B)` returns true, translate to ctx B, evaluate to same SMT-LIB string.

11. **Quantifier introspection** (extends `z3/quantifier`). Wraps `Z3_get_quantifier_*` family. Bound-var sort dispatch uses step 2's `getSortKind`. TDD: build `forall x: Z3Int. p(x)`, introspect bound-var count = 1, name = `"x"`, sort kind = `skInt`, body is `p(x)`.

12. **Probes + condTactic** (`z3/probe`). `Z3Probe` ref-handle. `mkProbe("name")`. Numeric/boolean combinators. `condTactic(p, t1, t2)`. TDD: `mkProbe("num-consts") < 100.0` returns a probe; `condTactic(thatProbe, mkTactic("smt"), mkTactic("simplify"))` constructs a tactic.

13. **Global parameters** (`z3/globalparams`). Three procs. TDD: `setGlobalParam("verbose", "5")` then `getGlobalParam("verbose")` returns `some("5")`.

14. **I/O surface refactor** (`z3/io`). Relocate `parseSmt2`/`smt2Script`/`writeSmt2` from `z3/pretty`. Add `parseSmt2File`, `Z3ParserContext` typed handle with step-style API (`newParserContext(ctx); pc.addSort(...); pc.addDecl(...); pc.parseFromString(text)`), streaming parse. TDD: round-trip a complex formula via `smt2Script` → `parseSmt2String`; parse from file; build a parser context with a pre-registered sort and parse against it.

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

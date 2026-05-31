# Changelog

All notable changes to nim-z3. Format loosely follows [Keep a
Changelog](https://keepachangelog.com/en/1.1.0/); semver applies once
1.0 ships.

## [Unreleased]

— Work toward v0.5 (1.0-readiness polish); see
`docs/IMPLEMENTATION_PLAN.md`.

## [0.4.0] — 2026-05-30

The **contract-completion** release. v0.3 unified the typed-family
architecture and added the remaining theory families (FP, Char,
String, Sequences, Regex, uninterpreted functions). v0.4 closes the
gap between the wrapper's "every Z3 C-API capability" scope claim
and reality: nine new modules (`z3/astvector`, `z3/introspect`,
`z3/proof`, `z3/fixedpoint`, `z3/rewrite`, `z3/translate`, `z3/probe`,
`z3/globalparams`, `z3/io`), five new solver extensions
(`assertConstraintAndTrack` / `getUnsatCore` / `getStatistics` /
`getConsequences` / `getProof`), the runtime-erased `Z3AnyAst`
family, the per-context `datatypeRegistry` that lets
`Z3DatatypeValue[T]` participate in `sortdispatch`, quantifier
introspection, and the `mkUninterpretedSort` / `declareSort` surface
surfaced as a real gap by step 14. Every §1 goal of the v0.4 plan
landed. Tests: **1114 OKs** across `nim c` + `nim cpp` (up from
v0.3's 890).

Full per-step plan + audit: archived in
[`docs/V0.4_PLAN.md`](docs/V0.4_PLAN.md) (§8b "Pre-tag audit" block).

### Added

- **`Z3AstVector` foundation + `Z3Term` concept** (`d472bef`) — typed
  refcount-managed handle wrapping `Z3_ast_vector_*`. `newAstVector`,
  `len`, `[i]`, `[]=` / `add[T: Z3Term]` / `resize`, `items` / `pairs`
  iterators, `toSeq[T]` typed conversion, `$` SMT-LIB rendering. The
  same step lands the `Z3Term` structural concept — anything with
  `x.raw is RawZ3Ast; x.ctx is Z3Context` — making the wrapper's
  cross-cutting surfaces (lifecycle hooks, `wrap[T]`, `eval[T]`,
  `smtEquiv[T]`) generic over every typed family.
- **Structural introspection** (`6acb50b`) — `z3/introspect`.
  `Z3AstKind` enum mirroring `Z3_ast_kind`; `getAstKind[T: Z3Term]` /
  `getSort` / `getAppNumArgs` / `getAppArg` / `getAppDecl` /
  `unpackApp` / `getNumeralString`. `Z3SortKind` + `getSortKind` +
  per-family parameter extractors (`bitVecWidth`, `arrayKey` /
  `arrayRange`, `seqElement`, `regexBasis`, `fpEbits` / `fpSbits`,
  `datatypeName`). The runtime-erased **`Z3AnyAst`** family with
  `toAnyAst` up-cast + typed lifters (`asZ3Int`, `asZ3Real`,
  `asZ3Bool`, `asZ3Char`, `asZ3BitVec[W]`, `asZ3Fp[E, S]`,
  `asZ3Seq[E]`, `asZ3Regex[B]`) that runtime-verify sort + parameters.
- **`Z3DatatypeValue` as a `sortdispatch` element** (`35ad348`) —
  closes the v0.3 §8 carryover. Per-context `datatypeRegistry: Table[
  string, RawZ3Sort]`; `declareDatatype[T]` registers under `$T`;
  `sortOf(_: typedesc[Z3DatatypeValue[T]], ctx)` looks it up and
  raises `Z3UsageError` with a "call `declareDatatype[T]()` first"
  hint if missing. Unlocks `Z3Array[Z3Int, Z3DatatypeValue[Foo]]`,
  `Z3Seq[Z3DatatypeValue[Foo]]`,
  `Z3FuncDecl[(Z3DatatypeValue[Foo],), Z3Bool]`, etc.
- **`Z3Proof` family + `getProof`** (`ae9b105`) — new module
  `z3/proof`. `Z3Proof` value family slotted into `Z3Term`. The
  `ProofRule` enum mirrors every Z3 proof rule (`prRefl`,
  `prModusPonens`, `prResolve`, `prHypothesis`, `prAxiom`, …,
  `prTheoryLemma`, `prHyperResolve`, `prUnknown`) with paraphrased
  Z3-doc-sourced docstrings. `getProofRule(p)` / `unpackProof(p) →
  (rule, premises, conclusion)`. `Z3Solver.getProof` extracts the
  proof witness after an unsat `check()` with `proof=true`. Plan
  steps 4 and 7 merged because `Z3Proof` is untestable without
  `getProof` (Z3 has no public proof-literal constructor).
- **`Z3Fixedpoint`** (`2c29768`) — new module `z3/fixedpoint`,
  Horn-clause / CHC solver. Refcounted handle; `newFixedpoint`,
  `addRule(fp, rule, name)`, `addFact(fp, decl, args)`,
  `query(fp, q): Z3Status` (formula and relation-decl forms),
  `getAnswer(fp): Z3Bool`, `setParams(fp, p)`, `addCover` /
  `getReachableExpressions` / `addVariable`, `$fp` SMT-LIB rendering.
- **Solver `assertConstraintAndTrack` + `getUnsatCore`** (`9fb1c96`) —
  closes the v0.3 step-8 half-implementation. Tag assertions with a
  tracker proposition; extract the minimal unsatisfiable subset of
  tagged assertions via the step-1 `Z3AstVector` plumbing.
- **`Z3Stats` + `getStatistics` + `getConsequences`** (`4e24e99`) —
  typed refcount-managed handle for solver runtime statistics.
  `len`, `[key]`, `keys`, iteration. `getStatistics(s): Z3Stats`.
  `getConsequences(s, assumptions, variables) → (status, consequences)`
  for implied-literal enumeration.
- **Term rewriting (`z3/rewrite`)** (`64df21b`) — `substitute[T:
  Z3Term](a, replacements: openArray[(Z3AnyAst, Z3AnyAst)]): T` for
  by-term substitution, `substituteVars[T: Z3Term](a, replacements:
  openArray[Z3AnyAst]): T` for de-Bruijn-indexed substitution into
  quantifier bodies. `mkBound(index, sort): Z3AnyAst` companion for
  building bound-variable references.
- **Cross-context transfer (`z3/translate`)** (`99894b5`) —
  `translate[T: Z3Term](t, targetCtx): T` preserves the typed-family
  phantom across contexts. `compatibleWith(a, b)` predicate uses a
  no-op translation under exception capture.
- **Quantifier introspection** (`f47fa36`) — extends `z3/quantifier`.
  `getQuantifierNumBoundVars`, `getQuantifierBoundVarName` /
  `getQuantifierBoundVarSort`, `getQuantifierBody`, `isForall` /
  `isExists` / `isLambda`, `getQuantifierWeight`,
  `getQuantifierNumPatterns` / `getQuantifierPatternAst`.
  `assertIsQuantifier` template surfaces a clear precondition error
  rather than Z3's opaque `Z3_INVALID_USAGE`. Bound-var sort returns
  `RawZ3Sort`; users dispatch via step 2's `getSortKind`.
- **Probes + condTactic (`z3/probe`)** (`fb09556`) — `Z3Probe`
  ref-handle. `mkProbe(name)` / `mkProbeConst(value)`,
  `apply(p, g): float`. Comparison operators (`<`, `<=`, `>`, `>=`,
  `==`) return **`Z3Probe`** (not `bool`) — matches Z3's underlying
  API and reads naturally at call sites; auto-lifts `float` literals
  on both sides. Boolean `and` / `or` / `not`. `condTactic(probe,
  ifT, elseT)` for adaptive tactic dispatch.
- **Global parameters (`z3/globalparams`)** (`c8a31c2`) —
  `setGlobalParam(name, value)`, `getGlobalParam(name): Option[
  string]`, `resetGlobalParams()`. Auto-loads `libz3` via the newly-
  exported `context.ensureLoaded` so calls work before any
  `Z3Context` exists. `Option` semantics: `none` ⇔ Z3 doesn't
  recognise the name; `some(v)` ⇔ effective value (override or
  built-in default).
- **SMT-LIB2 I/O surface refactor (`z3/io`)** (`1bfe4ff`) — relocates
  `smt2Script` / `writeSmt2` / `parseSmt2` (renamed `parseSmt2String`)
  out of `z3/pretty` into a dedicated module. Adds `parseSmt2File`,
  `loadSmt2String` / `loadSmt2File` (direct-to-solver feed via
  `Z3_solver_from_string` / `_from_file`), `evalSmt2`
  (`Z3_eval_smtlib2_string` — runs `(check-sat)` etc. and returns
  Z3's text response), `toSmt2Benchmark` for single-formula
  serialisation, and `Z3ParserContext` refcount-managed streaming
  parser with `addSort[S]` / `addDecl[A, R]` / `parseFromString`.
- **Uninterpreted sorts** (`1bfe4ff`, surfaced during step 14) —
  new `stUninterpreted` `SortTag` + `mkUninterpretedSort(name)` /
  `declareSort(name)` in `z3/sort`. SMT-LIB-styled alias matches the
  `(declare-sort Color)` reading site. Two sorts with the same name
  in the same context are the same sort.

### Changed

- **`parseSmt2` → `parseSmt2String`**. Renamed for symmetry with
  `parseSmt2File`. Pre-v1, no compat. Migrated
  `tests/tproperty.nim` and `examples/pretty_and_smt2.nim`;
  `tests/tpretty.nim`'s smt2 suites removed (covered exhaustively
  by the new `tests/tio.nim`).
- **`z3/pretty` slimmed to human-facing formatting only.** SMT-LIB2
  emission and parsing moved to `z3/io`. `z3/pretty` now hosts only
  the four `pretty(...)` overloads (ASTs, sorts, solvers, models).
- **`context.ensureLoaded`** promoted from private to public —
  documented entry point for any future symbol reachable before a
  `Z3Context` exists (step 13 needed it for global-param calls).
- **`wrapTactic` + `Z3Tactic.raw` / `.ctx` + `Z3Goal.raw` / `.ctx`**
  promoted from private to public in `z3/tactic` — so `z3/probe`
  can build a `Z3Tactic` from `Z3_tactic_cond` and evaluate probes
  against `Z3Goal`s without a cyclic dep. Mirrors the step-5
  `Z3FuncDecl` precedent.

### Spec corrections logged mid-cycle (per §8b cross-reference)

Every step that hit a Z3-spec assumption needing change surfaced it
back to the user before continuing; the corrections live in their
per-step §8 entries in [`docs/V0.4_PLAN.md`](docs/V0.4_PLAN.md).
Headline corrections:

- **Step 5**: `Z3_fixedpoint_get_ground_sat_answer` doesn't exist
  as advertised in older docs — use `Z3_fixedpoint_get_answer`.
  Three more Fixedpoint corrections (push/pop semantics differ;
  datalog needs finite-domain sorts) all caught pre-ship.
- **Steps 4 + 7 merged**: `Z3Proof` is untestable without
  `Solver.getProof`; Z3 has no public proof-literal constructor.
  Plan steps 4 and 7 merged into a single commit; slot 7 retained
  for plan-traceability with a docs-only marker (`fb36a59`).
- **Step 12**: probe operators return `Z3Probe`, not `bool` —
  matches Z3 and reads naturally as a predicate constructor.
- **Step 13**: `Z3_global_param_get` returns the **effective** value
  (override or default), `false` only for unknown names — wrapper
  documents `Option` semantics accordingly. `Z3_string_ptr` maps via
  `pointer` + cast (strict cpp rejects `ptr cstring → char **`).
- **Step 14**: `toSmt2Benchmark` `status=""` produces malformed SMT2
  because Z3 unconditionally emits `(set-info :status <s>)` —
  default changed to `"unknown"` (a valid SMT-LIB status). Surfaced
  the uninterpreted-sort gap (no `Z3_mk_uninterpreted_sort` in the
  wrapper) — closed by adding the surface in the same commit.

### Scope-pruned / deferred to v0.5

Documented in [`docs/V0.4_PLAN.md` §8b](docs/V0.4_PLAN.md). Summary:
advanced Fixedpoint surface (assertion-set introspection;
`from_string` / `from_file` for CHC ingestion now that `z3/io`
exists); `Z3AstMap` typed handle; `Z3FuncInterp` tabular extraction
(carried from v0.3); `Z3Char` BV interop (carried); `Z3Float16` /
`Z3Float128` structured extraction (carried); param-descrs schema
introspection (carried); CI items (carry-forward of v0.2 #1);
`{.optional.}` softlink (no v0.4 step triggered a 4.13+-only
symbol).

### Dropped

None this release. Every §1 goal of the v0.4 plan landed.

## [0.3.0] — 2026-05-30

The **architectural-unification + theory-completion** release. v0.2
covered the theories that turn SMT into a software-verification engine
(arrays, datatypes, quantifiers, optimisation, tactics). v0.3 unifies
the typed-family contract, closes the v0.2 audit's user-visible gaps,
and adds the remaining SMT-LIB theory families (FloatingPoint,
Strings + Char + Regex, Sequences) plus uninterpreted functions and
solver-tactic bridges. Tests: **890 OKs** across `nim c` + `nim cpp`
(up from v0.2's 652).

Full per-step plan + audit: archived in
[`docs/V0.3_PLAN.md`](docs/V0.3_PLAN.md) (§8b "Pre-tag audit" block).

### Added

- **Architectural unification** (`ea46a86`) — `Z3Term` concept binding
  the five typed value families (`Z3Ast[S]`, `Z3BitVec[W]`,
  `Z3Array[K, V]`, `Z3DatatypeValue[T]`, `Z3Pattern`) by their shared
  shape; unified `wrap[T: Z3Term](ctx, raw): T` template replacing five
  family-specific `wrap*` helpers; lifecycle-hook generator
  (`emitTermLifecycle` / `emitRefcountLifecycle`) collapsing 22
  verbatim `=destroy` / `=copy` / `=dup` copies. Behaviour-preserving;
  external API unchanged.
- **`z3/semantics` module** (`78852f4`) — `smtValid` relocated from
  `z3/solver`, `smtEquiv` collapsed to a generic `smtEquiv[T]` working
  for every typed family with `==`. Single discovery point. Also lands
  `Z3Model.eval` / `[]` as a generic for any `T`, the
  tactic-pipeline model-conversion bridge `convertModel(applyResult,
  idx, subModel)`, and `evalReal` / `toRealApprox` for `Z3Real` model
  values. Closes v0.2 §8 carryover items.
- **Small cleanups** (`7b2d59f`) — retired dead `stArray` /
  `stDatatype` from `SortTag` (zero referents); normalised `mkBitVec`
  to bracket-W form (`mkBitVec[8](5'u32)` matching the rest of the BV
  surface).
- **`z3/char` + `z3/string` + `z3/regex`** (`f5c7e91`) — SMT-LIB
  string theory. `Z3Char` Unicode-codepoint family with codepoint
  ordering / `isDigit` / `toInt`. `Z3String` family with `mkString` /
  `mkStringVar`, `len`, varargs `concat` + `&`, `contains`, `substr`,
  `at`, `startsWith` / `endsWith`, `indexOf`, `replace`, `strToInt` /
  `intToStr`, Nim-`string`-literal lifts. `Z3Regex[Basis]` regex
  family with `mkRegex` / `mkRegexEmpty` / `mkRegexFull` / `mkRegexAll`
  / `matches` / `star` / `plus` / `option` / `complement` / varargs
  `concat` / `union` / `intersect` / `range` / `loop` / `power`.
- **`z3/seq` + `Z3String` alias refactor** (`f0965ce`) — `Z3Seq[E]`
  phantom-typed over element type. Step 5 collapses `Z3String` to
  `Z3Seq[Z3Char]` (Z3's own definition), so every generic sequence op
  (`len`, `concat`, `nth`, `at`, `substr`, `contains`, `startsWith` /
  `endsWith`, `indexOf`, `replace`) applies to strings automatically.
  Regex basis-sort dispatch widened from `Z3String` to any `Z3Seq[E]`.
- **`z3/fp`** (`438594d`) — IEEE 754 / SMT-LIB FloatingPoint theory.
  `Z3Fp[Ebits, Sbits]` family with `Z3Float16` / `Z3Float32` /
  `Z3Float64` / `Z3Float128` aliases. Rounding-mode in two shapes —
  `RoundingMode` Nim enum (`rmRNE` / `rmRNA` / `rmRTP` / `rmRTN` /
  `rmRTZ`) and `Z3RoundingMode` AST family for quantification.
  Operators `+` `-` `*` `/` default to `rmRNE`; explicit forms
  `fpAdd` / `fpSub` / `fpMul` / `fpDiv` / `sqrt` / `fma` /
  `roundToIntegral`. **`==` / `!=` use IEEE equality** (NaN ≠ NaN,
  +0 = -0) — deliberate divergence from every other typed family.
  Predicates `isNaN` / `isInf` / `isZero` / `isNormal` / `isSubnormal`
  / `isPositive` / `isNegative`. No-rounding ops `abs` / unary `-` /
  `rem` / `min` / `max`. Conversions `toIeeeBv` / `toFp` (from BV /
  FP / Real) / `toFpFromSigned` / `toFpFromUnsigned` / `toReal` /
  `toSbv` / `toUbv`. Model extraction `toFloat32` / `toFloat64` /
  `evalFloat32` / `evalFloat64`.
- **`z3/funcdecl`** (`78ff9dc`) — uninterpreted function declarations.
  `Z3FuncDecl[ArgsTup: tuple, Ret]` phantom-typed over a tuple of
  argument types. Per-arity `apply` overloads + `()` callable hooks
  for 0..6 args (macro-generated) so `f(x, y)` works naturally.
  `evalAt(m, f, args)` composer for "value of f at this point under
  the model."
- **Solver-tactic bridges** (`8be9bee`) — `newSolverFromTactic(t)` /
  `t.toSolver()` wrap a tactic pipeline as a `Z3Solver` with the
  familiar add / check / model surface. `setParams(s, p)` symmetric
  with `setParams(o: Z3Optimize, p)`.
- **`z3/sortdispatch` consolidation** (`0250381`, v0.3 step 9) — the
  three `sortOfType` / `sortOfTypeSeq` / `sortOfTypeFD` cascades from
  steps 1..7 collapsed to a single `mixin sortOf` dispatch. Each
  typed family owns its own `sortOf` overload at the declaration
  site. Closes the v0.2 §8 "nested arrays deferred — typedesc-
  reflection limit" as a side effect: `Z3Array[Z3Int, Z3Array[Z3Int,
  Z3Int]]` round-trips, and `Z3FuncDecl[(Z3Array[Z3Int, Z3Int],),
  Z3Bool]` etc. compile.

### Changed

- **`mkBitVec` signature** is now `mkBitVec[W: static int](v:
  SomeInteger): Z3BitVec[W]`. Previous positional form
  `mkBitVec(v, 8)` is gone (pre-1.0 breaking change; no consumers).
- **`Z3String`** is a type alias for `Z3Seq[Z3Char]` rather than its
  own family. All generic sequence ops apply to strings automatically;
  the string-specific surface in `z3/string` shrank to `mkString` /
  `mkStringVar` / `toStr` / `evalStr` / `strToInt` / `intToStr` plus
  the Nim-`string`-literal lifts.
- **`Z3Fp[E, S]` `==` / `!=`** use IEEE semantics (`Z3_mk_fpa_eq`),
  not structural equality. Deliberate divergence from every other
  typed family because NaN ≠ NaN is what FP users expect.
- **`SortTag` enum** dropped `stArray` and `stDatatype` (zero
  referents in v0.2 + v0.3).

### Spec corrections logged during v0.3

Each step that hit a "specification assumption needed changing"
moment surfaced it back before continuing; full list in
`docs/V0.3_PLAN.md` §8b "Spec corrections during v0.3" cross-
reference. Summary:

- `Z3_apply_result_convert_model` retired in Z3 4.8.0; using
  `Z3_goal_convert_model` (same capability, per-subgoal) — step 2.
- `toRealApprox` precision-knob lean was a misread — `Z3_get_numeral
  _double` has no precision arg — step 2.
- `mkBitVec[W, T]` two-generic shape didn't compile under Nim's
  inference; collapsed to `mkBitVec[W: static int](v: SomeInteger)` —
  step 3.
- `Z3_mk_re_range` operands are `Z3String`, **not** `Z3Char` — step 4.
- `Z3_fpa_get_numeral_double` does not exist; FP model extraction
  routes through `Z3_mk_fpa_to_ieee_bv` + `simplify` + bit-cast —
  step 6.
- `forall x. f(g(x)) == x` headline test for funcdecls hung Z3
  (quantifier-without-trigger); replaced with concrete-witness
  composition — step 7.
- Z3 4.13.3 does not honour `model=false` on a solver; observable-
  effect test replaced with typed-params-breadth check — step 8.

### Deferred to v0.4

See `docs/V0.3_PLAN.md` §8b "Items rolled forward to v0.4" and
`docs/IMPLEMENTATION_PLAN.md` "Rolled forward from v0.3" — short
list: `Z3Fixedpoint`, `Z3_solver_get_unsat_core` /
`Z3_solver_get_proof` / `Z3_solver_get_param_descrs`,
`Z3_func_interp` tabular extraction, `Z3Char` BV interop,
`Z3DatatypeValue` as a `sortdispatch` element type, `Z3Float128` /
`Z3Float16` structured extraction, epsilon-bound `Z3Real` extraction,
`replace-all` on `Z3String`, CI work blocked on the same upstream as
v0.2 issue #1.

### Scope-pruned

- **DOT / GraphViz AST export** — out of wrapper scope; redirected
  to a future `nim-z3-tools` sibling per V0.3_PLAN §8 "Scope
  discipline."
- **Wider-width BV recipes as a numbered step** — demoted to
  continuous practice in `tests/recipes.nim`.

## [0.2.0] — 2026-05-29

The theory-expansion release. v0.1 covered the core SMT primitives;
v0.2 covers the theories that turn SMT from "arithmetic checker"
into "general decision procedure for software verification."

### Added

- **`Z3_simplify` + `z3/simplify`** — phantom-type-preserving simplifier
  overloads for `Z3Ast[S]` and `Z3BitVec[W]`. Default-params and
  customised (`simplify(a, p: Z3Params)`) forms.
- **Big-width `Z3BitVec[W]`** — `mkBigBitVec[W](numeral: string)`
  for arbitrary-precision construction; `toBigUintStr` / `toBigIntStr`
  for arbitrary-width extraction (signed via `Z3_mk_bv2int` round-trip).
  `mkBitVec(v, W)` now works for any `W` (v0.1 capped it at `W ≤ 64`
  defensively; the cap was wrong — `Z3_mk_unsigned_int64` accepts any
  width). `toUint`/`toInt` simplify-then-extract, so concrete
  expression trees (`mkBitVec(0xFF, 8) + mkBitVec(1, 8)`) extract
  directly without manual `simplify`.
- **`z3/array`** — `Z3Array[Key, Val]` phantom-typed over typedescs of
  AST families. Surface: `mkConstArray`, `mkArrayVar`, `store`,
  `select` / `[]`, `==`, `!=`. Supports the canonical memory model
  (`Array[BV[32], BV[8]]`); nested arrays deferred to v0.3.
- **`z3/datatypes`** — inductive sums via marker-type phantoms.
  `declareDatatype[T]` for single datatypes, `declareDatatypes(fd1,
  fd2, …)` for mutually recursive families (arity 2 and 3). Surface:
  `field` / `selfField` / `crossField`, `constructor`, `.con` /
  `.recognizer` / `.accessor`, `.apply` (arity 0–5) / `.test` /
  `.read`, `mkDatatypeVar`.
- **`z3/quantifier`** — `forall` / `exists` with per-arity templates
  (1–5 bound vars). Bound vars can be any typed AST family. `Z3Pattern`
  refcount-managed trigger; `mkPattern(t1, …)` for multi-trigger
  conjunction, multiple patterns in `forall(…, patterns=[p1, p2])` for
  alternative-trigger disjunction.
- **`z3/optimize`** — `Z3Optimize` with hard / soft constraints,
  `maximize` / `minimize`, phantom-typed `Z3OptHandle[T]` for
  `upper` / `lower`, `push` / `pop`, `setParams(o, p)` exposing
  `priority="lex"` (default) / `"box"` / `"pareto"` multi-objective
  modes. BV-objective bounds re-typed through `Z3_mk_int2bv` so the
  typed return promise holds.
- **`z3/params`** — `Z3Params` typed parameter bag for tactics,
  solvers, optimisers. `newParams` + overloaded `set(key, value)`
  for `bool` / `uint` / `int` / `float` / `string`.
- **`z3/tactic`** — `Z3Goal`, `Z3Tactic`, `Z3ApplyResult` with
  combinators: `mkTactic`, `tacticSkip` / `tacticFail`, `andThen` /
  `orElse` / `repeat` / `tryFor` / `withParams`, `apply` (with and
  without params), `numSubgoals` / `subgoal(i)`.

### Other changes

- `z3/model`'s `wrapModel(ctx, raw)` is now public so sibling
  modules (`z3/optimize`, future tactics, …) can wrap models they
  obtain from their own FFI paths.
- Test infrastructure refactor: `IntRecipe` / `BoolRecipe` /
  `BvRecipe` ADTs + strategies + interpreters extracted from
  `tests/tproperty.nim` into shared `tests/recipes.nim`. Now used by
  `tproperty.nim`, `tsimplify.nim`, and `tarray.nim`.

### Deferred to v0.3 (per `docs/V0.2_PLAN.md` + the live `docs/IMPLEMENTATION_PLAN.md`)

Promised-v0.2 items that didn't land before the tag — all rolled
forward to v0.3 (a v0.2.1 point release was considered and rejected;
no consumers, no point in a separate vehicle):

- `Z3Model.eval`/`[]` overloads for `Z3DatatypeValue[T]` and
  `Z3Array[K, V]`; `smtEquiv` overloads for those types;
  `Z3_apply_result_convert_model` for tactic-pipeline witnesses.
  (v0.3 plan §5 step 2.)
- `evalReal` / `toRealApprox`, DOT / GraphViz AST export, wider-width
  BV recipes, differential testing against `z3` CLI, valgrind job,
  `.optional` softlink declarations. (v0.3 plan §5 steps 2, 4, 5.)
- Dropped: colourised pretty output, public `z3/strategies` module
  (proptest will depend on nim-z3, not the other way round).
- macOS / aarch64 CI rows + `nim doc --project` Pages publishing —
  filed as [#1](https://github.com/coreyleavitt/nim-z3/issues/1),
  blocked on the same private-dep upstream that's keeping v0.1's CI
  red. Rolls back into scope when `coreyleavitt/milpa` and
  `coreyleavitt/proptest` go public (or a deploy key is wired).

Plus a post-v0.2 architectural audit surfaced unification opportunities
(refcount lifecycle boilerplate × 22 instances, fragmented `wrap*`
helpers × 5, per-arity templates × 24) that fold into v0.3 plan §1
goal 1 as the step-1 work.

652 tests pass on both Nim backends (c + cpp); zero failures.

## [0.1.0] — 2026-05-29

## [0.1.0] — 2026-05-29

The initial release. A user can write the headline `x + y == 10 ∧ x > 3`
example in their first 5 minutes (per the §11 deliverable target in
`docs/IMPLEMENTATION_PLAN.md`).

### Added

- **`Z3Context` lifecycle** with `=destroy` discipline, current-context
  threadvar, `withContext(ctx): body` scoping template, auto-load of
  libz3 on first `newContext()`, typed `Z3Error` carrying a
  `Z3ErrorCode` enum, `checkErr` template wrapping every FFI call.
- **Phantom-typed sorts and ASTs**. `SortTag` enum (`stInt`, `stReal`,
  `stBool`, `stBitVec`); `Z3Sort[S]` and `Z3Ast[S]` value types with
  refcount-discipline lifecycle hooks (`=destroy` / `=copy` / `=dup`);
  type aliases `Z3Int`, `Z3Real`, `Z3Bool`.
- **Builders for literals + variables**: `mkInt` / `mkBigInt`,
  `mkReal` / `mkBigReal`, `mkBool` / `mkTrue` / `mkFalse`, and the
  `*Var` family — every builder in both implicit (current-context) and
  explicit (`ctx.mkIntVar(…)`) forms.
- **Boolean operators**: `and`, `or`, `not`, `xor`, `implies`, `iff`,
  `ite[S]`, varargs `mkAnd` / `mkOr`, `mkDistinct[S]`, with Nim-bool
  literal lifts.
- **Arithmetic operators on Int and Real**: `+`, `-`, `*`, `div`, `/`,
  `mod`, `rem`, `<`, `<=`, `>`, `>=`, `==`, `!=` — all with int-literal
  lifts on both sides.
- **Width-tracked bit-vectors** via a separate `Z3BitVec[W: static int]`
  type. Modular arithmetic operators (`+`, `-` binary + unary, `*`,
  `and`, `or`, `xor`, `not`, `shl`) overload normally; sign-dependent
  ops require explicit `bvudiv` / `bvsdiv`, `bvurem` / `bvsrem` /
  `bvsmod`, `bvult` / `bvule` / `bvugt` / `bvuge`, `bvslt` / `bvsle` /
  `bvsgt` / `bvsge`, `lshr` / `ashr`. Width manipulation —
  `extract(hi, lo)`, `concat`, `zeroExtend(N)`, `signExtend(N)`,
  `repeat(N)` — computes the result width at the type level.
  Polymorphic `ite` and `mkDistinct` overloads for BV. Model extraction
  via `toUint` (unsigned) and `toInt` (signed 2's-complement) plus
  `eval` / `[]` indexing.
- **Solver + model**: `Z3Solver` with `add`, `assertConstraint`,
  `check`, `push`, `pop`, `reset`, `withFrame: body` template,
  `Z3Status` enum (`zsSat`, `zsUnsat`, `zsUnknown`), `reasonUnknown`.
  `Z3Model` with `eval` / `[]`, scalar extractors (`toInt`, `toBool`,
  `toBigIntStr`, `toBigRealStr`), and composers (`evalInt`, `evalBool`,
  `evalBigIntStr`, `evalBigRealStr`).
- **Validity oracles** in `z3/solver`: `smtValid(p: Z3Bool)` and
  `smtEquiv[S](a, b: Z3Ast[S])` (plus a `Z3BitVec[W]` overload).
  Both use a throwaway solver per call so the caller's primary state
  stays untouched.
- **Indented pretty-printing** via a Wadler-style "fit or stack"
  reformatter in `z3/pretty`. Typed `pretty(node, indent, width)`
  overloads for AST / BV / sort / solver / model.
- **SMT2 script emission and parsing**: `smt2Script(s)` writes a
  self-contained runnable script; `writeSmt2(s, path)` is the
  to-disk variant; `parseSmt2(ctx, source)` returns a `seq[Z3Bool]`
  of parsed assertions. Round-trip preserves sat / unsat / model.
- **Version probes**: `z3Version(): (major, minor, build, revision)`,
  `z3FullVersion(): string`, `finalizeZ3Memory()`.
- **Property-based test suite** dogfooding [proptest](https://github.com/coreyleavitt/proptest)
  with random integer / boolean / BV expression trees (depth 2-3)
  asserting algebraic laws (commutativity, associativity, identity,
  de Morgan, idempotence, absorption, involutions, extract/concat
  round-trips) at the SMT level.
- **CI**: multi-version Z3 matrix (4.10.2 / 4.11.2 / 4.12.6 / 4.13.4)
  pulled from microsoft/z3 release tarballs, dual-backend (`nim c` +
  `nim cpp`) every row. Separate AddressSanitizer job on the
  lifecycle-critical test suites.
- **Examples**: `basic_solve`, `nqueens`, `bitvec_solve`,
  `pretty_and_smt2`, `properties`.

### Deferred to v0.2 (per `docs/IMPLEMENTATION_PLAN.md` §18)

- Array theory, quantifiers, optimization, custom datatypes, tactics
  (§11 v0.2 wave).
- Wide BitVec literal construction + extraction (`mkBigBitVec`,
  `toBigUintStr` for W > 64).
- `Z3_simplify` FFI + wrapper.
- DOT / GraphViz AST export, colourised pretty output, multi-byte
  UTF-8 atom tokenising.
- Public `z3/strategies` module exposing the recipe ADTs from the test
  suite.
- macOS / aarch64 CI runners, valgrind job, differential testing
  against the `z3` CLI and Python `z3-solver`.

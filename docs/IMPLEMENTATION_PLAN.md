# nim-z3 v0.5 plan (live)

> **Status: live, promoted 2026-05-30** from its v0.3-era draft after the v0.4.0 tag shipped. The previous live plan (v0.4 — the contract-completion release) is archived at [docs/V0.4_PLAN.md](V0.4_PLAN.md). When v0.5 ships, this file is archived to `docs/V0.5_PLAN.md` and a v0.6 plan (the v1.0 tag itself) is promoted into the live slot.

A type-safe, memory-safe, idiomatic Nim wrapper for the Z3 SMT solver.

**Status (at plan-promotion time)**: v0.4 shipped 2026-05-30 with **1114 OKs** across both backends, zero failures. Every §1 goal of the v0.4 contract-completion release landed (see [V0.4_PLAN.md §8b](V0.4_PLAN.md)). v0.5 owns the cross-cutting 1.0-readiness polish — originally scoped as candidates 2–8 from the post-v0.3 review (cross-family parity, naming + cohesion hygiene, examples, docs + GOTCHAS, error type hierarchy, property-test extension, feature flags); a post-v0.4 architectural review on **2026-05-30** surfaced four additional 1.0-readiness items folded in below (goals 9–12): the `z3/context` dual-responsibility split, Z3 C-API micro-gap closure to make the v0.4 contract-completion claim *literally* true, `add` vs `assertConstraint` canonical-name resolution, and a contributor-facing "internal API" doc seam.

**Audience**: future-me, future contributors, anyone wondering why v0.5 reads like a polish release rather than a feature release.

## What changes between v0.4 and v0.5

- v0.4 makes the **scope commitment** (and either lands the capabilities or narrows the statement) that v1.0 is going to inherit.
- v0.5 is **the 1.0-readiness release**. The work is cross-cutting polish: makes the `Z3Term` architectural concept load-bearing, fixes pre-1.0 naming/cohesion debt, refactors the error-handling story for typed catching, audits memory + thread safety under the unified lifecycle, extends property tests to the v0.3 theory families, adds worked examples, refreshes docs, ships a minimal-build story.
- After v0.5 ships, **v0.6 is the v1.0 tag itself** — a release whose only deliverable is the version bump, the changelog entry, the readme stability commitment, and the deferral of anything not in the v1.0 scope to a v1.x or v2.x track. No new code in v0.6.

The framing: v0.4 = "what 1.0 is"; v0.5 = "the polish that makes 1.0 stable"; v0.6 = "the commitment."

## 1. Goals and non-goals

### Goals

1. **Cross-family parity for the `Z3Term`-concept surface** (was candidate 2). The architectural unification in v0.3 step 1 made `wrap[T: Z3Term]`, `eval[T]`, `smtEquiv[T]` generic — but several pre-step-1 cross-family surfaces (`pretty`, `astEqual`, the `toXxx` / `evalXxx` scalar shorthand convention) weren't migrated. v0.5 finishes the migration so the concept is genuinely load-bearing:

   - **Generic `pretty[T: Z3Term](v: T): string`** — currently 5 overloads (`Z3Ast[S]`, `Z3BitVec[W]`, `Z3Sort[S]`, `Z3Solver`, `Z3Model`). Need overloads for every v0.3 typed family — `Z3Char`, `Z3Seq[E]`, `Z3Regex[Basis]`, `Z3Fp[E, S]`, `Z3FuncDecl[ArgsTup, Ret]`, `Z3RoundingMode` (or its v0.5 successor — see goal 2 below). Best PhD shape: a single `pretty[T: Z3Term]` body using `mixin` to defer to family-specific format helpers where pretty differs from `$`.
   - **Generic `astEqual[T: Z3Term]`** — currently `astEqual[S: static SortTag](a, b: Z3Ast[S]): bool` only. Same shape as `==` got in step 1; mechanical.
   - **`Z3Model` scalar-shorthand audit** — `evalInt` / `evalBool` / `evalFloat32` / `evalFloat64` / `evalStr` / `evalBigIntStr` / `evalBigRealStr` exist; the convention is "if there's a `toXxx` extractor, there should be an `evalXxx` composer." Audit for: missing `evalChar(m, c): int` (codepoint), missing `evalBitVec`-as-uint64 shorthand, missing `evalSeqLen` (a frequent SMT use case). Add the missing ones; document the convention explicitly so contributors adding a new family know what to wire.
   - **`$` operator parity** — every typed family should have `$` defined (delegating to `Z3_ast_to_string` for now); audit and add anywhere missing.

2. **Naming + cohesion hygiene** (was candidate 3, re-scoped after pushback-2 directive). Three real items, all breaking (no consumers — fine):

   - **Rename `z3/seq` → `z3/sequence`** to stop shadowing Nim's `seq[T]`. The `Z3Seq[E]` type name stays; only the module path changes. Every internal `import ./seq` becomes `import ./sequence`, the `import z3/seq` users would write becomes `import z3/sequence`, and the `system.seq[T]`-vs-our-module collision I had to work around in v0.3 step 7 (`newSeq[X]` instead of `seq[X]`) disappears.
   - **Consolidate `RoundingMode` enum + `Z3RoundingMode` AST into a single typed family.** Today there's a dual representation: the Nim enum for ergonomics, the AST family for quantification. Every other typed family (`Z3Char`, `Z3BitVec`, `Z3Fp`, `Z3Seq`, …) carries the AST family AND uses pattern (typically `mkX(literal)` and `mkXVar(name)`) — and exactly one of them has a parallel enum. The v0.3 §7 Q2 lean was "ship both because both are real" — that was true, but the right consolidation is to make `Z3RoundingMode` a first-class typed family with its own `sortOf` overload (it already half-exists at v0.3) and **delete the `RoundingMode` Nim enum**. Replace it with `Z3RoundingMode` literal helpers: `rmRNE()` returns a `Z3RoundingMode` literal, etc. The "quantification over rounding modes" case stays (it's the same family); the ergonomic case loses one keystroke ( `rmRNE` → `rmRNE()`) and one indirection layer (no more `mkRoundingMode(rmRNE)`). One pattern across the wrapper. Breaking.
   - **Internal `naryOp` macro for varargs duplication.** `mkAnd` / `mkOr` / `mkDistinct` / `concat` (3 modules: bitvec, sequence, string-via-alias) / `union` / `intersect` / regex `concat` / `fma` (almost) all share the same 5-line body shape. A macro `naryOp(name, ffi, returnType)` emits the wrapper from (Nim name, Z3 FFI symbol, return type). User-facing names stay (they're semantically distinct operations). Internal bodies become one line. Same idiom as v0.3 step 1's `emitTermLifecycle` for lifecycle hooks.

3. **Error type hierarchy** (was candidate 6 part A). Pre-1.0 decision made: **typed exception hierarchy**. v0.1 chose `Z3Error` with `code: Z3ErrorCode` for pragmatic flat catching; at 1.0 that locks in. The refactor:

   ```nim
   type
     Z3Error*           = object of CatchableError  ## abstract base
     Z3InvalidUsageError* = object of Z3Error       ## misuse — wrong sort, etc.
     Z3InvalidArgError*   = object of Z3Error       ## a specific arg failed validation
     Z3SortError*         = object of Z3Error       ## sort mismatch
     Z3MemOutOfMemoryError* = object of Z3Error     ## allocation failed
     Z3FileError*           = object of Z3Error     ## parser / file I/O
     Z3ParserError*         = object of Z3Error     ## SMT-LIB parse error
     Z3UnreachableError*    = object of Z3Error     ## Z3 internal "unreachable"
     Z3UnknownError*        = object of Z3Error     ## anything else
   ```

   The `raiseZ3Error(ctx, code)` helper in `z3/context` dispatches on `code` to the right subclass. Existing `except Z3Error as e` catches still work (subclass-of). New code can `except Z3SortError except Z3InvalidUsageError`. The `code` field stays on `Z3Error` for users who want the raw enum. Test impact: every `expect Z3Error: ...` block continues to pass (subclass catches base); tests that genuinely want to assert a specific kind tighten to `expect Z3SortError`. Breaking only for callers that did exhaustive matching on `code` outside an `except` block — none of those exist in the test suite.

4. **Memory + thread safety audit** (was candidate 6 part B). Three pieces:

   - **Valgrind clean run.** Step 1 of v0.3 unified lifecycle across every typed family; the test suite catches functional regressions but `=destroy` / `=copy` / `=dup` bugs at the refcount layer can pass functional tests and still leak. Add a `make valgrind` target (or `nimble valgrind` task) that runs the suite under valgrind and asserts zero leaks. CI integration follows whatever the v0.2 issue #1 blocker resolution looks like — for now, local-machine sufficiency.
   - **Threading safety document + smoke tests.** The current-context threadvar pattern is documented in `z3/context` but never under concurrent load. Write `tests/tconcurrency.nim` exercising: per-thread `withContext` correctness; per-thread solver isolation; non-shared model handles across threads (which would be UB); the documented limitation surfacing as `Z3InvalidUsageError` rather than UB.
   - **`docs/THREADING.md`** — short canonical doc. "What's safe: per-thread contexts. What's not: sharing model handles across threads." Three paragraphs.

5. **Property tests for v0.3 families** (was candidate 7). `tests/recipes.nim` currently models v0.1/v0.2 AST recipes for proptest-driven invariant verification. Extend:

   - **String recipes** — concat / substr / contains / replace identity properties (e.g. `replace(s, x, x) == s`).
   - **Sequence recipes** — `len(concat(a, b)) == len(a) + len(b)`, `nth(unit(x), 0) == x`, etc.
   - **FP recipes** — `abs(abs(x)) == abs(x)`, `0.0 + x == x` *under normal values* (exclude NaN/Inf via `isFinite` filter).
   - **Regex recipes** — `matches(s, mkRegex(s))` is always true.
   - **FuncDecl recipes** — `f(args) == f(args)` (structural identity).
   - **Z3Term-generic recipes** — `smtEquiv(a, a)` for any term.

   The proptest-driven test count delta should land in the same neighbourhood as v0.3's added 200+ tests — probably 50–80 generative tests across the new families.

6. **Examples for v0.3 families** (was candidate 4). The `examples/` directory has 5 worked examples, all v0.1/v0.2 surface. Add (one per major family is overkill — bundle related ones):

   - **`examples/string_constraints.nim`** — solve "find a 5-char string where chars are letters and contains a digit." Exercises `Z3String` + `Z3Regex` together.
   - **`examples/float_verification.nim`** — verify a floating-point routine doesn't produce NaN under bounded inputs. Exercises `Z3Fp` + predicates + the IEEE-`==` divergence.
   - **`examples/uninterpreted_axioms.nim`** — declare an uninterpreted commutative function and verify the solver finds inconsistencies with hand-written non-commutative assertions. Exercises `Z3FuncDecl` + `forall`.
   - **`examples/tactic_pipeline.nim`** — `simplify.andThen(smt).toSolver()`, applied to a real benchmark (e.g. n-queens). Exercises step-8's solver-tactic bridge.

   Each should be ≤ 80 lines, follow the existing example style, runnable via `nimble examples` task.

7. **GOTCHAS doc + README freshness** (was candidate 5).

   - **`docs/GOTCHAS.md`** — promote the 7 v0.3 spec corrections from archived `V0.3_PLAN.md §8` into a discoverable user-facing doc. Format: per-gotcha, **symptom** / **root cause** / **what the wrapper does** / **what you should do**. Cross-link from the README and from the relevant module docstrings.
   - **README "Design" section rewrite** — the current table lists 5 modules; actual is 27. Replace with a tiered hierarchy (Core / Scalars / Collections / Constraints / Modular / Theory Families) or replace with a direct link to `src/z3.nim`'s module-level docstring (which is current and comprehensive) and add per-tier prose. Also update the headline example, the use-cases list, and any v0.2-anchored prose.

8. **Feature flags / minimal-build story** (was candidate 8). Two parts:

   - **Per-theory `when defined(z3Without*)` compile-time guards** — `z3WithoutFP`, `z3WithoutStrings`, `z3WithoutRegex`, `z3WithoutSeq`, `z3WithoutFuncDecl`, `z3WithoutDatatypes`, `z3WithoutOptimize`, `z3WithoutTactics`. Each gates the corresponding module's inclusion via `src/z3.nim`'s import block + the FFI block's relevant symbols.
   - **`config.nims` template + docs** — show users how to build a minimal binary (solver + Int/Bool + BV only). Verify CI builds at least one minimal-flag combination so the guards don't bit-rot.

   *Open question for §7:* are theory-pair dependencies (`Z3Regex` needs `Z3Seq`, `Z3String` IS `Z3Seq[Z3Char]`) cleanly expressible with these flags, or do we need a `requires`-style dependency declaration? Decide during implementation.

9. **`z3/context` dual-responsibility split — extract `z3/error`** (added post-v0.4 review). `z3/context` (326 LOC, 15 public items) currently conflates four concerns: (a) `Z3Context` lifecycle, (b) error type + `checkErr` template + `raiseZ3Error` dispatch, (c) current-context threadvar (`currentContext` / `setCurrentContext` / `withContext`), (d) library bootstrap (`ensureLoaded` + `LibZ3UnavailableError`). Every typed-family module imports the whole thing just to reach `checkErr`. Concerns (c) and (d) are legitimately tied to the context — the threadvar IS the context's per-thread anchor; the bootstrap IS the context's "create the first one" hook. **Only (b) wants out.**

   The extraction: pull `Z3Error` + the v0.5 goal-3 subclass tree + `checkErr` / `checkErrVoid` templates + `raiseZ3Error` proc into a new **`z3/error`** module. `z3/context` keeps the handle lifecycle, threadvar, and bootstrap. Every cross-cutting module that needs `checkErr` imports `z3/error` instead of (or in addition to) `z3/context` — making the dependency intent legible at the import line. Mechanical refactor; tests pass unchanged; one PR pairs naturally with goal 3 because goal 3 *populates* the new module with the typed-subclass tree.

10. **Z3 C-API micro-gap closure** (added post-v0.4 review). The v0.4 §8b "Pre-tag audit" concluded "every Z3 C-API capability is reachable" with three asterisks, deferred to v0.5 with stated rationale per item. The point of v0.5's polish round is to **make that claim literal** before 1.0 — otherwise the v1.0 changelog inherits the asterisks. Three sub-items:

    - **`Z3FuncInterp` tabular extraction** — the structured representation of an uninterpreted function's model interpretation: a sequence of (`args`, `value`) **entries** plus an **else-value** that applies to all other arg tuples. v0.3 step 7 shipped `evalAt(m, f, args)` for point queries against `Z3FuncDecl`; the full tabular view is its complement and the canonical surface for "show me what value `f` takes everywhere the solver pinned it." Wraps `Z3_model_get_func_interp`, `Z3_func_interp_inc_ref` / `_dec_ref`, `Z3_func_interp_get_num_entries`, `Z3_func_interp_get_entry`, `Z3_func_entry_get_value`, `Z3_func_entry_get_num_args`, `Z3_func_entry_get_arg`, `Z3_func_interp_get_else`, `Z3_func_interp_get_arity`. Lives as **`Z3FuncInterp[Args, Ret]`** ref-handle in `z3/funcdecl` (or its own `z3/funcinterp` if it grows; decide during impl). Entry tuples deserialise via the existing `Z3AnyAst` → typed-lifter path from v0.4 step 2.
    - **Param-descrs schema introspection** — `Z3_solver_get_param_descrs` and `Z3_tactic_get_param_descrs` return a refcounted `Z3_param_descrs` describing the parameter schema (names, types, defaults, help text) for a given solver / tactic. The wrapper currently has `Z3Params` (the bag you set) but not the introspection (the schema the bag must conform to). Wrap as **`Z3ParamDescrs`** ref-handle in `z3/params`. Surface: `len`, `keys`, `[name]: ParamKind` (Bool / UInt / Double / Symbol / String), `getDocumentation(name)`, `$` SMT-LIB rendering. Use case: tooling that enumerates legal params for a solver before constructing a `Z3Params` against it; better error messages when an unknown key is set.
    - **`Z3Char` BV interop** — `Z3_mk_char_to_bv(c)` returns a bit-vector of width `:unicode-char-width` (typically 18 bits for Unicode-21 but Z3 makes it configurable); `Z3_mk_bv_to_char(bv)` is the inverse. The carry-forward blocker from v0.3 was "needs runtime `:char-width` thread + cross-module visibility." v0.4 didn't surface a reason to land it; v0.5 closes it. The width thread reads via `Z3_global_param_get("unicode-char-width")` (or its solver-param equivalent), parses to `int`, returns a `Z3BitVec[width]` typed at call time. *Open question:* does the cross-context width-tracking discipline need a per-context cache, or is the global-param read fast enough to do per-call? Decide during impl.

    Each of these is small (≤ 100 LOC + ~10 tests each); together they remove the v0.4 §8b asterisks. After v0.5, the audit's "every Z3 C-API capability is reachable" statement is unconditional.

11. **`add` vs `assertConstraint` canonical-name resolution** (added post-v0.4 review). `z3/solver` ships both `add(s, c: Z3Bool)` (primary, established v0.1) and `assertConstraint(s, c: Z3Bool)` (an `{.inline.}` alias added later for SMT-LIB-styled reading). Violates the "one canonical name per operation" principle. Pre-v1 with no consumers — delete the alias, settle on `add`, audit `tests/` and `examples/` for any remaining `assertConstraint` callers and migrate them. The same audit covers `Z3Goal.add` (already canonical), `Z3Optimize.add` / `assertConstraint` (check), `Z3Fixedpoint.addRule` / `addFact` (distinct semantics — keep). Mechanical; one commit.

12. **Internal API documentation seam** (added post-v0.4 review). Mid-v0.4 implementation, five items were promoted private→public to unblock cross-module coordination: `context.ensureLoaded` (needed by `z3/globalparams` for pre-context calls); `Z3Tactic.raw` / `Z3Tactic.ctx` + `wrapTactic` (needed by `z3/probe` for `condTactic`); `Z3Goal.raw` / `Z3Goal.ctx` (needed by `z3/probe` for `apply`); `Z3FuncDecl.raw` / `Z3FuncDecl.ctx` (needed by `z3/fixedpoint` step 5). Nim's visibility model is binary (`*` or not); there's no `internal` middle ground, so the promotions look identical to user-facing surface. **Without a documented contract, future contributors don't know whether to promote a new helper or refactor to avoid the need.**

    The seam: a new **`docs/INTERNAL_API.md`** listing every "technically public but only meant for sibling-module use" symbol, with the consumer module named, the reason the seam exists, and an invariant ("user code SHOULD NOT call this; if you find yourself needing to, file an issue — the wrapper probably wants a real user-facing surface instead"). Cross-link from each promoted symbol's docstring. This is contributor-facing, not user-facing — it lives alongside `docs/GOTCHAS.md` (user-facing) from goal 7. Both ship in the docs step. ~50 lines of doc; no code change required.

### Non-goals (re-asserted from earlier plans + new for v0.5)

- **`Z3Fixedpoint`** — owned by v0.4 (candidate 1 — either landed or explicitly narrowed-out at v0.4 tag time).
- **Unsat-core / proof / AST-introspection / substitute / translate** — same, owned by v0.4.
- **Custom theories via user propagators** (`Z3_solver_propagate_*`) — still v1.x+ research-grade.
- **High-level macro DSL** (`solve: forall x in Int, x + 1 > x`) — still non-goal; the wrapper IS the API.
- **Differential testing against Python z3** — still rolled forward.

---

## 2. The shape of the v0.5 expansion

v0.5 is **the polish release**. Reading the §1 goals out loud: "make Z3Term load-bearing, fix naming debt, refactor error types, audit safety, extract `z3/error`, write examples, refresh docs, ship a minimal build, close three C-API micro-gaps, settle one canonical name, document the internal API seam." None of those are new theories. Several are net-negative LOC (the unification work pulls duplicated bodies into generators; the canonical-name resolution deletes the `assertConstraint` alias).

Concretely: the wrapper's typed-family count grows by **one ref-handle** in v0.5 — `Z3FuncInterp[Args, Ret]` from goal 10's C-API micro-gap closure (tabular UF-model extraction). The wrapped Z3 surface grows by exactly the three v0.4 §8b asterisks (FuncInterp + ParamDescrs + Char↔BV); after v0.5 the "every Z3 C-API capability is reachable" statement is unconditional. The user-visible surface area shrinks (the `RoundingMode` enum is replaced by `Z3RoundingMode` literal helpers; the `naryOp` macro means contributors don't write per-family varargs anymore; the `assertConstraint` alias deletes; feature flags mean some users will compile *less* of the wrapper).

This is the release whose architectural payoff is **"every concept is load-bearing, every name is principled, every error is typed."** Pre-1.0 hygiene done deliberately.

---

## 3. Module structure

Net additions: still few — most v0.5 work is rewriting existing modules.

- **`z3/error`** — new module extracted from `z3/context` (goal 9). Hosts the `Z3Error` subclass tree (goal 3) + `checkErr` / `checkErrVoid` templates + `raiseZ3Error` dispatch.
- **`z3/sequence`** — renamed from `z3/seq` (goal 2).
- **`Z3FuncInterp[Args, Ret]`** ref-handle — new typed family in `z3/funcdecl` (goal 10).
- **`Z3ParamDescrs`** ref-handle — new typed family in `z3/params` (goal 10).
- **`docs/GOTCHAS.md`** — new doc (goal 7).
- **`docs/THREADING.md`** — new doc (goal 4).
- **`docs/INTERNAL_API.md`** — new doc, contributor-facing (goal 12).
- **`tests/tconcurrency.nim`** — new test file (goal 4).
- **`tests/tfuncinterp.nim`** — new test file (goal 10).
- **`tests/tparamdescrs.nim`** — new test file (goal 10).
- **`tests/tcharbv.nim`** — new test file (goal 10) covering `Z3Char` ↔ `Z3BitVec[width]`.
- **`tests/recipes.nim`** — extended (goal 5).
- **4 new example files** (goal 6).
- **`config.nims`** at repo root — template for minimal builds (goal 8).

Net removals:

- **`RoundingMode` Nim enum + `mkRoundingMode(rm: RoundingMode)`** — superseded by `Z3RoundingMode` literal helpers (goal 2).
- **`Z3Solver.assertConstraint` `{.inline.}` alias** — superseded by canonical `add` (goal 11).
- **5 per-family `pretty` overloads** — superseded by generic `pretty[T: Z3Term]` (goal 1).
- **6+ per-family varargs bodies** — superseded by `naryOp` macro instantiations (goal 2).
- **`Z3Error` + `checkErr` from `z3/context`** — moved to `z3/error` (goal 9; no surface change for callers, only an import line).

---

## 4. Phasing — what ships when

### v0.5.0 — the 1.0-readiness polish release

1. **`z3/context` split — extract `z3/error`** (goal 9). Pure file move + import line updates; no surface change. Lands first because it creates the home goal 3 will populate with the subclass tree.
2. **Naming + cohesion hygiene** (goal 2) **+ `add`/`assertConstraint` resolution** (goal 11). `z3/seq` → `z3/sequence` rename. `Z3RoundingMode` consolidation (delete `RoundingMode` enum, expose AST-family literal helpers). Delete the `assertConstraint` alias; migrate callers to `add`. Internal `naryOp` macro for varargs body unification. All breaking; one pre-1.0-clean commit per sub-item, suite green between each.
3. **Cross-family parity** (`Z3Term` concept becomes load-bearing) (goal 1). Generic `pretty[T: Z3Term]`, generic `astEqual[T: Z3Term]`, scalar-shorthand audit, `$` parity.
4. **Typed error hierarchy** (goal 3). Populate `z3/error` (created in step 1) with the subclass tree (`Z3InvalidUsageError`, `Z3SortError`, …); update `raiseZ3Error` dispatch on `code`. Tests using `expect Z3Error` continue to pass via subclass-of.
5. **Memory + thread safety audit** (goal 4). Valgrind clean run; `tests/tconcurrency.nim`; `docs/THREADING.md`.
6. **Z3 C-API micro-gap closure** (goal 10). `Z3FuncInterp[Args, Ret]` ref-handle + tabular extraction; `Z3ParamDescrs` ref-handle + schema introspection; `Z3Char` ↔ `Z3BitVec[width]` conversion threading the runtime `:unicode-char-width` param. Each sub-item is its own commit + test file (`tfuncinterp.nim`, `tparamdescrs.nim`, `tcharbv.nim`).
7. **Property tests for v0.3 families** (goal 5). Extend `recipes.nim`; add proptest properties for String / Sequence / FP / Regex / FuncDecl invariants.
8. **Examples for v0.3 families** (goal 6). Four new example files (string constraints, FP verification, uninterpreted axioms, tactic pipeline).
9. **GOTCHAS + INTERNAL_API + README freshness** (goals 7 + 12). Promote v0.4 §8 spec corrections to `docs/GOTCHAS.md`; write `docs/INTERNAL_API.md` enumerating the cross-module-internal seam (the symbols promoted private→public in v0.4); rewrite README "Design" section.
10. **Feature flags + minimal-build story** (goal 8). Per-theory compile-time guards; `config.nims` template; CI smoke for at least one minimal combination.
11. **Pre-tag audit.** Same discipline as v0.3 step 9.
12. **v0.5 tag.**

### v0.6 — the v1.0 tag

Whatever shipped at v0.5.0 IS v1.0 modulo the version bump + changelog + README stability statement. v0.6 doesn't add functionality. (If v0.5 surfaces something that should be in 1.0 but isn't, that becomes v0.6 work — but the *intent* is v0.5.0 → v1.0.0 with a version-only delta.)

---

## 5. Implementation sequence

Architecture-affecting items first (so subsequent steps inherit the cleaned state); hygiene + docs late (so they reflect the final API).

1. **`z3/context` split — extract `z3/error`** (goal 9). Pure file move: pull `Z3Error` + `Z3ErrorCode` re-export + `checkErr` / `checkErrVoid` templates + `raiseZ3Error` proc into a new `z3/error.nim`. Update every typed-family module's import (currently `import ./context` mostly for `checkErr`) to `import ./error` where that's the only need. `z3/context` stays as the handle-lifecycle + threadvar + bootstrap module. No surface change for callers; mechanical refactor. Lands first because step 4 populates `z3/error` with the subclass tree and depends on the module existing.

2. **Naming + cohesion hygiene** (goal 2) **+ `add`/`assertConstraint` canonical-name resolution** (goal 11). `seq → sequence` rename; `RoundingMode` consolidation; `naryOp` macro; delete the `Z3Solver.assertConstraint` alias and migrate any callers to `add`. The rename is purely mechanical; the `RoundingMode` consolidation breaks every test calling `mkRoundingMode(rmRNE)` — update to `rmRNE()`. The `naryOp` macro doesn't change call sites; internal refactor only. The `assertConstraint` deletion may touch a handful of test sites — `grep -rn 'assertConstraint' tests/ examples/` and migrate. All sub-items pre-v1-clean breakage.

3. **Cross-family parity** (goal 1). Generic `pretty[T: Z3Term]` with `mixin` for family-specific format helpers; generic `astEqual[T: Z3Term]`; audit + add the missing `evalXxx` shortcuts on `Z3Model`; add `$` parity where missing. Document the "for every new family, here's what you implement" contract in a comment at the top of `z3/lifecycle` or a new `z3/parity.nim`.

4. **Typed error hierarchy** (goal 3). Add subclass types to `z3/error` (created in step 1); update `raiseZ3Error` to dispatch on `code` to the right subclass; ensure every internal `raise` site goes through `raiseZ3Error` rather than constructing `Z3Error` directly (audit — the three hand-set `Z3_INVALID_USAGE` raise sites in `context.nim` / `model.nim` / `solver.nim` are the seeds). Tests pass unchanged via subclass-of; tighten a few `expect Z3Error` to `expect Z3SortError` etc. where the intent is clear.

5. **Memory + thread safety audit** (goal 4). `nimble valgrind` task running the suite + reporting `definitely lost: 0 bytes`; `tests/tconcurrency.nim` exercising per-thread context isolation + the documented cross-thread limitation surfacing properly; `docs/THREADING.md` 3-paragraph canonical doc.

6. **Z3 C-API micro-gap closure** (goal 10). Three sub-items, each its own commit + test file:

   - **`Z3FuncInterp[Args, Ret]`** ref-handle in `z3/funcdecl` (or `z3/funcinterp` if it grows). Wrap `Z3_model_get_func_interp` + the `Z3_func_interp_*` / `Z3_func_entry_*` family. Surface: `getFuncInterp(m, f): Z3FuncInterp[A, R]`, `len(fi)`, `[i]: (args: tuple, value: R)`, `elseValue(fi): R`, `arity(fi)`. Entries deserialise via existing `Z3AnyAst` lifters. Test: declare uninterpreted `f: (Int) → Int`, assert `f(0) == 7 and f(1) == 11`, extract `Z3FuncInterp`, assert two entries plus an else.
   - **`Z3ParamDescrs`** ref-handle in `z3/params`. Wrap `Z3_solver_get_param_descrs` + `Z3_tactic_get_param_descrs` + the `Z3_param_descrs_*` family. Surface: `getParamDescrs(s: Z3Solver): Z3ParamDescrs`, `getParamDescrs(t: Z3Tactic): Z3ParamDescrs`, `len`, `keys`, `[name]: ParamKind` (enum: pkBool / pkUInt / pkDouble / pkSymbol / pkString), `getDocumentation(name)`, `$` SMT-LIB rendering. Test: solver schema includes known keys (`timeout`, `random_seed`); per-key kind matches expectation; `getDocumentation` returns a non-empty string.
   - **`Z3Char` ↔ `Z3BitVec[width]`** in `z3/char`. `toBitVec(c: Z3Char): Z3BitVec[width]` and `mkChar(bv: Z3BitVec[width]): Z3Char` where `width = unicodeCharWidth(ctx)`. Width thread reads via `Z3_global_param_get("unicode-char-width")` once per context (or per-call if the cost is negligible — measure during impl). Test: round-trip `mkChar('a')` → BV → back == original; `mkChar('a').toBitVec.toUint == ord('a')`.

7. **Property tests for v0.3 families** (goal 5). Extend the `recipes.nim` ADT to cover String / Sequence / FP / Regex / FuncDecl. Add proptest properties for each (round-trip identity, structural-equivalence, theory-specific invariants). Expected delta: 50–80 generative tests.

8. **Examples** (goal 6). Write the four example files. Each runs to a model that demonstrates the headline use case for its theory. Add to `nimble examples` task.

9. **GOTCHAS + INTERNAL_API + README freshness** (goals 7 + 12). Promote V0.3_PLAN §8 *and* V0.4_PLAN §8 spec corrections to `docs/GOTCHAS.md` with the **symptom / cause / wrapper behavior / what you should do** template. Write `docs/INTERNAL_API.md` enumerating the cross-module-internal symbols (`ensureLoaded`, `wrapTactic`, `Z3Tactic.raw`/`.ctx`, `Z3Goal.raw`/`.ctx`, `Z3FuncDecl.raw`/`.ctx`, any added during v0.5) with consumer-module attribution and the "user code SHOULD NOT call this" invariant. Cross-link from each symbol's docstring. Rewrite README "Design" section + headline example + version-anchored prose.

10. **Feature flags + minimal-build story** (goal 8). Add `when defined(z3Without*)` guards around theory imports + FFI blocks. Write `config.nims` template at repo root. Add a CI matrix entry (or a local `nimble test-minimal` task pending CI unblock) that builds with `-d:z3WithoutFP -d:z3WithoutStrings`. *Decide during impl* whether feature flags need a `requires`-style dependency declaration (since `Z3Regex` depends on `Z3Seq`, etc.).

11. **Pre-tag audit + rollforward annotations** per the v0.3 / v0.4 precedent. The §8b "Pre-tag audit" block this round catalogues every §1 goal (1–12) as landed / rolled to v0.6 / dropped; the running §8 deferral ledger catches anything that surfaced mid-implementation.

12. **v0.5 tag.** Then v0.6 = v1.0 tag with a version-only delta.

---

## 6. Risks specific to v0.5

### Naming changes break test files; risk of churn

The `RoundingMode` → `Z3RoundingMode` literal helpers consolidation touches `tests/tfp.nim` (31 tests). Mostly mechanical (`rmRNE` → `rmRNE()`) but if the literal-helper function names *also* change shape (e.g. `mkRme()` for "make rounding mode equal-nearest-even"), the churn could be worse. Mitigation: keep the user-facing name `rmRNE` (now a proc instead of an enum value) so the source delta is `rmRNE` → `rmRNE()`.

### Typed error hierarchy might surface untested raise sites

Step 3 will audit every `raise` site to ensure dispatch goes through `raiseZ3Error`. We may find sites that construct `Z3Error` directly with a hand-set `code` — those become typed subclasses. The test suite catches behavior; the typed dispatch is invisible to tests that just `expect Z3Error`. Risk is low but real: an untested raise site might dispatch to `Z3UnknownError` when it should be `Z3SortError`. Mitigation: code review + a new "subclass type matches code" test for each subclass.

### Valgrind step might surface a real leak

The v0.3 step-1 lifecycle unification was behaviour-preserving by design. The tests catch functional regressions. Refcounting bugs in `=destroy` / `=copy` / `=dup` can pass functional tests and still leak. If valgrind surfaces a leak, the work is "find it, write a test, fix it" — that's a normal cycle but it might be the longest step. Mitigation: schedule step 4 with slack; honest reporting if the audit surfaces real work.

### Feature flags introduce conditional compilation paths the tests don't sweep

Per-theory `when defined(z3Without*)` guards add a combinatoric explosion of build configurations. Sweeping all of them in CI is overkill; one minimal-flag combination + the maximal (default) configuration cover 80% of real risk. The rest is on contributors to remember "if you touch theory X, build with `-d:z3WithoutX` locally." Mitigation: document the convention; bit-rot risk is acknowledged.

### v0.4's scope decision might invalidate parts of v0.5

If v0.4 lands fixedpoint / unsat-core / etc., v0.5 has to extend cross-family parity / `pretty` / `naryOp` / etc. to cover those new families. The work is mechanical (same idiom). Mitigation: write the v0.5 plan now (this doc), revisit after v0.4 ships, append "and don't forget to extend to the v0.4 additions" to each goal where it applies. **Done at promotion time** — v0.4 shipped every §1 goal; the post-v0.4 review folded the additional findings in as goals 9–12 (this preamble note + the headline of §0).

### `z3/error` extraction reshuffles every typed-family import (goal 9)

Step 1 moves `checkErr` / `raiseZ3Error` from `z3/context` to `z3/error`. Every typed-family module currently does `import ./context` partly for the handle type, partly for `checkErr`. Post-split, modules that need *only* `checkErr` should swap to `import ./error`; modules that touch handles keep both. Risk: import-line churn surfaces unused-import warnings at strict compile time. Mitigation: do the import audit as part of step 1; run `nim c --hints:on tests/...` after the split to catch every `UnusedImport` and tighten.

### C-API micro-gap closure may surface Z3-version-coupled symbols (goal 10)

`Z3_param_descrs_*` is stable since Z3 4.0; safe. `Z3_func_interp_*` is stable since 4.4; safe (our 4.10 baseline covers it). `Z3_mk_char_to_bv` / `_from_bv` are newer — these landed in Z3 4.8.x range; if either is missing in the 4.10 baseline, the wrapper either bumps the floor (probably fine — Z3 4.10 is from 2022) or surfaces them via `{.optional.}` softlink. **This is the first plausible trigger for the v0.3 §8 deferred `{.optional.}` softlink story.** Mitigation: probe Z3 4.10 headers during step 6 sub-item C; if symbols missing, decide softlink-optional vs floor-bump (lean: floor-bump given v0.5 is pre-v1 polish).

### `Z3FuncInterp[Args, Ret]` discovery: where does it live?

Sub-item A of step 6 adds a new typed family. It logically belongs alongside `Z3FuncDecl` (which produced it). Open question (§7): does it live IN `z3/funcdecl` (one module, two adjacent ref-handles) or in its own `z3/funcinterp.nim` (one capability per module)? Lean: in `z3/funcdecl` initially; promote out if it grows past ~100 LOC. Mitigation: decide during impl; document the choice in the §8 ledger.

### Canonical-name resolution (goal 11) may surface a counter-example

If `assertConstraint` reads more clearly than `add` in a specific user-facing example or doc, the resolution might want the *opposite* direction (delete `add`, keep `assertConstraint`). Lean: `add` wins — established v0.1, matches collection-type ergonomics, parallels `Z3Goal.add` and `Z3Optimize.add` (both canonical with no alias). Mitigation: audit the existing examples + docs during impl; if `assertConstraint` reads better in a high-traffic doc, revisit the call.

---

## 7. Open questions (genuinely open — answer during implementation)

1. **Feature-flag dependency declarations.** Goal 8 raises the question of whether `Z3Regex needs Z3Seq` etc. should be expressed as a static `requires` table or just left as "if you disable a theory, also disable its dependents and we'll error at compile if you forget." Lean: latter; compile-time error is fine since the dependency chain is shallow. Decide during step 8.

2. **`pretty` for `Z3FuncDecl`** — how do we render a function declaration without applying it? Z3's `$Z3_ast_to_string(func_decl_to_ast(fd))` is the FFI path; the format is SMT-LIB syntax `(declare-fun f (Int Int) Bool)`. That's fine. Decide during step 2 whether we surface anything richer (a Nim-shaped `proc-signature-like` rendering) — lean no, SMT-LIB form is canonical.

3. **`evalXxx` shorthand cap.** Audit might surface "every typed family wants its own `evalXxx`" — that's 7+ new shortcuts for v0.3 families alone. Cap by: shortcut exists only if it differs from the generic `m.eval(x)` pattern by more than the extractor name. Decide during step 2.

4. **`Z3Error` hierarchy specifics.** The exact subclass list in §1 goal 3 is my draft; the right list is whatever set covers every Z3 error code with a meaningful semantic distinction. Audit `Z3ErrorCode` during step 3 and refine.

5. **README "Design" section format.** Tiered hierarchy table vs prose vs link-to-`src/z3.nim`-docstring. Decide during step 9 with the working draft in hand.

6. **`Z3FuncInterp` module placement** (goal 10 sub-item A). Lives in `z3/funcdecl` (one module, adjacent capabilities) or `z3/funcinterp` (one capability per module)? Lean: in `z3/funcdecl` initially; promote out if it grows past ~100 LOC. Decide during step 6.

7. **`unicode-char-width` thread caching** (goal 10 sub-item C). Read the global param per `toBitVec` / `mkChar(bv)` call, or cache once per `Z3Context`? Lean: cache per context (FFI roundtrip + cstring parse adds up under loops). Decide during step 6 with a microbenchmark.

8. **`{.optional.}` softlink decision** (goal 10 sub-item C if `Z3_mk_char_to_bv` is post-4.10). Bump the floor (probably fine) or surface via softlink-optional? Lean: floor-bump given v0.5 is pre-v1 polish and Z3 4.10 is from 2022. Decide during step 6.

9. **Canonical-name direction** (goal 11). Default lean is `add` wins, `assertConstraint` deletes. Revisit if the audit surfaces a high-traffic doc where `assertConstraint` reads better. Decide during step 2.

10. **`docs/INTERNAL_API.md` shape** (goal 12). Per-symbol table vs prose? Lean: table (symbol / consumer module / reason / invariant). Decide during step 9.

---

## 8. Deferred from v0.5 (running list, populated as work happens)

Same append-only format as v0.1 §18, v0.2 §8, v0.3 §8. Format: **what / why / where it goes** (v0.6 / dropped / sibling-package).

### From step 6 (Z3 C-API micro-gap closure)

- **Z3FuncInterp entry-vs-else representation is solver-dependent.** Z3 can store a `(args, value)` constraint as an explicit entry OR fold it into the else-value — the choice is solver-internal and not part of any wire contract. Original test design pinned `fi.len == 2` for two assertions; that failed because Z3 chose to fold. Resolution: tests pin **semantic round-trip** (every entry's value matches `evalAt` at the same args, AND `evalAt` at each asserted point returns the asserted value) rather than table shape. Documented in tests/tfuncinterp.nim suite comments.
- **`emitRefcountLifecycle` doesn't unify across two phantom params.** `Z3FuncInterp[ArgsTup, Ret]` has two static-typed phantoms; the existing lifecycle template generator doesn't generate matched-arity hooks for two-parameter generic types. Resolution: per-instantiation `=destroy` hook spelled out inline (8 lines). Logged as a v0.6 polish candidate — the lifecycle template family could grow a two-phantom variant if more new families share this shape.
- **`encoding` global param, not `unicode-char-width`.** The plan's "open question" about caching `unicode-char-width` collapses: Z3 doesn't expose a `unicode-char-width` param; the BV width is determined by `encoding` (default `unicode` = 18 bits, alternates `bmp` = 16, `ascii` = 8). The wrapper commits to `Z3BitVec[18]` (the default) and documents the user-changes-encoding escape hatch. No per-context caching needed; the width is compile-time on the wrapper's surface.
- **`(char.to_bv (_ Char N))` doesn't fold to a BV numeral.** Z3's evaluator doesn't have a rewrite rule that simplifies `char.to_bv` applied to a literal Char to a literal BV numeral. So `evalUint(m, c.toBitVec)` fails with "AST does not reduce to a literal BV numeral." Resolution: tests use `smtValid(c.toBitVec == mkBitVec[18](codepoint))` which uses a fresh solver to prove the semantic equivalence — works regardless of Z3's rewrite-rule coverage.
- **`ParamKind` enum names use lowercase prefix.** `pkUInt` / `pkBool` / `pkDouble` / `pkSymbol` / `pkString` / `pkOther` / `pkInvalid` — matches `Z3_PK_*` enough to read at the call site but doesn't collide via Nim's style-insensitive identifier rules (the FFI enum is `Z3_PK_UINT` etc.; `pkUInt` normalises to `pkuint`, no collision with `z3pkuint` either).
- **`ParamDescrs.\[name\]` returns `pkInvalid` for unknown keys.** Z3's API uses `Z3_PK_INVALID` as the sentinel rather than raising; wrapper mirrors this. Documented; the alternative (`Option[ParamKind]`) would be Nim-idiomatic but loses the direct mapping from the FFI semantics.

### From step 5 (memory + thread safety audit)

- **`newContext()` auto-sets `currentZ3Ctx`** as a side effect — surfaced during the `withContext`-per-thread test (#3). Creating a second context clobbers the threadvar before the test enters its `withContext` block, so the post-`withContext` check fails because the "original" was already overwritten. Resolution: documented the auto-set behaviour explicitly in [docs/THREADING.md](docs/THREADING.md) "Pattern: parallel solving" section, with the canonical `setCurrentContext(primary)` restore pattern. Test #3 uses the restore pattern, exercising the workaround in code that other readers will study.
- **`--threads:on` enforces GC-safety on thread procs.** Z3's `Z3_set_error_handler` call inside `newContext` is `{.cdecl.}` and doesn't touch Nim's heap (it's just an FFI call), but the softlink layer's function-pointer indirection breaks Nim's safety analysis. Test bodies wrap the FFI sites in `{.cast(gcsafe).}:` blocks. Documented in `tests/tconcurrency.nim`'s body docstrings.
- **Valgrind audit: gate on `definitely lost: 0 bytes`, not exit code.** Initial task used `--error-exitcode=1` which fired on ANY valgrind error — but libz3 triggers ~3000 "Invalid read of size 1" warnings inside its own hash-cons tables. None are wrapper bugs. Resolution: run with `--error-exitcode=0` and grep the log for the plan's stated gate (`definitely lost: 0 bytes`). The leak summary is what's actionable; non-leak errors inside libz3 are Z3's concern.
- **No suppression file needed.** Z3's allocations show as "still reachable" (program-lifetime singletons) — that category is excluded from `definitely lost` by valgrind's classifier. Nim's GC arena shows as "possibly lost" — also excluded. The wrapper's path-of-control is what definite leaks would point at, and there are zero of them on the v0.5 step 5 commit.
- **`docs/THREADING.md` framing:** 5 sections instead of the plan's "3 paragraphs". Three sections wasn't enough to also cover the `newContext` auto-set discovery (it deserves its own example) and the cross-link to `z3/translate` for the cross-context route. The doc is still <200 lines so this isn't scope creep — it's the right shape for a contract that has nuance.

### From step 4 (typed error hierarchy)

- **Nim's style-insensitive identifier rules cause naming collisions with FFI enum values.** `Z3SortError` (the planned subclass name) and `Z3_SORT_ERROR` (the FFI `Z3ErrorCode` value) collapse to the same identifier under Nim's normalisation (`z3sorterror`). Same for `Z3ParserError` ↔ `Z3_PARSER_ERROR`. **Resolution:** rename the colliding subclasses to `Z3SortMismatchError` and `Z3ParseError`. The remaining 10 subclasses don't collide and keep their planned names (`Z3InvalidUsageError`, `Z3InvalidArgError`, `Z3MemoryError`, `Z3FileError`, etc.). Documented in each renamed subclass's docstring so the next time someone reads "why isn't this `Z3SortError`?" the answer is in the type itself.
- **13 subclasses, not the plan's 8.** Audit of `Z3ErrorCode`'s 12 non-OK values plus a forward-compat fallback for unrecognised codes (`Z3UnknownError`) yields 13 subclasses. Plan-list additions: `Z3IndexOutOfBoundsError` (`Z3_IOB`, distinct from generic `InvalidArg` because index errors are common enough to deserve their own catcher); `Z3InvalidPatternError` (`Z3_INVALID_PATTERN`); `Z3RefcountError` (`Z3_DEC_REF_ERROR` — diagnostic for wrapper bugs); `Z3OperationError` (`Z3_EXCEPTION` — generic Z3 exception). Plan renames: `Z3MemOutOfMemoryError` → `Z3MemoryError` (cleaner); `Z3UnreachableError` → `Z3InternalError` (more accurate — Z3 internal corruption, not "unreachable code").
- **`Z3_PARSER_ERROR` and `Z3_NO_PARSER` bundled** under the same subclass (`Z3ParseError`). Both are SMT-LIB-input-shaped failures with the same recovery pattern; callers handling one almost always want to handle the other identically.
- **`case` over `Z3ErrorCode` works** despite the identifier collisions, because case-arms are looked up by enum-value identity and Nim's enum-value resolution is stricter than the open-overload context that broke `code == Z3SortError`. The dispatch code uses `case code of Z3_SORT_ERROR: raiseSubclass(Z3SortMismatchError, ...)` cleanly.
- **`raiseSubclass` template takes `SubT: untyped`** rather than `typedesc`. The `typedesc` form ran into the same identifier-collision parsing as the `==` form; `untyped` defers resolution to expansion site where context disambiguates.
- **Direct-raise migration (~33 sites).** Sweep of `newException(Z3Error, ...)` across `src/z3/`: introspect.nim's 4 sort-mismatch raises → `Z3SortMismatchError` (semantically correct — they're erased-AST sort-check failures); the other ~29 raises (datatypes validation, "AST not a literal numeral", "nil handle", "no current context", etc.) → `Z3InvalidUsageError` (canonical "user did something the API doesn't support"). The `e.code = Z3_INVALID_USAGE` lines stay where they existed; subclasses carry it implicitly but the field stays addressable for case-dispatch in handlers.
- **All existing `except Z3Error` catches continue to work** via subclass-of inheritance. Test suite picked up 0 backward-compat breakages from the migration.

### From step 3 (cross-family parity)

- **`$[T: Z3Term]` generic doesn't beat `system.$` in Nim 2.** Initial implementation replaced 5 per-family `$` overloads with one `$[T: Z3Term]`. At runtime every `$mkInt(42)` produced `(raw: (), ctx: ...)` — the auto-derived tuple-style `$` from `system` won the overload resolution. Concept-constrained generics are *less* specific than `system`'s typed-object overloads in Nim 2.6. Resolution: keep per-family `$` overloads, factor the body into a shared `termToSmt2*[T: Z3Term]` template in `z3/ast`; each per-family `$` becomes a one-liner `= termToSmt2(v)`. Unification at the *body* level rather than the *signature* level. `astEqual[T: Z3Term]` and `pretty[T: Z3Renderable]` don't have this problem because there's no `system.astEqual` / `system.pretty` to lose to.
- **`Z3Renderable` concept is wider than `Z3Term`.** Pretty-print covers sorts (`Z3Sort[S]` has `RawZ3Sort`, not `RawZ3Ast`) and ref handles (`Z3Solver` etc.). The shared invariant is `($x) is string; x.ctx is Z3Context` — captured cleanly by a new concept. Documented in [docs/PARITY.md](docs/PARITY.md).
- **`mkCharVar` parity gap fixed.** Every other family had `mkXVar`; `Z3Char` was missing one. Required for the `evalChar` test (constructs an unknown the solver pins). Added alongside the eval shortcut audit.
- **`evalChar` needs a simplify pass.** `m.eval(a.toInt)` returns `(char.to_int (_ Char N))` — Z3's evaluator doesn't auto-fold the `char.to_int` wrapper to the literal `N`. Resolution: `simplify(m.eval(a, ...).toInt).toInt`. Documented in the proc's docstring.
- **`mkRegex` takes a `Z3Seq[E]`, not a string.** Initial test used `mkRegex("abc")` — wrong shape. Use `mkRegex(mkString("abc"))`. Noted because the v0.5 plan's goal-1 examples might bake this mistake in.
- **`docs/PARITY.md`** lives alongside the planned (goal 7) `GOTCHAS.md` (user-facing) and (goal 12) `INTERNAL_API.md` (cross-module-internal seam). Contributor-facing checklist: when adding a new `Z3Foo` family, here are the items every existing family ships and why. The "for every new family, here's what you implement" rule from the plan now has a concrete home.

### From step 2 (naming + cohesion hygiene)

- **`Z3Fixedpoint.assertConstraint` kept** (not deleted alongside the solver alias). Distinct semantics: Horn-clause domain has rules / facts / background axioms as three distinct ops; calling all three `add` would be ambiguous. Documented as the canonical axiom-assertion method.
- **`bitvec.mkDistinct` empty-input bug fixed incidentally.** The pre-v0.5 hand-written body indexed `xs[0].ctx` on empty input — would crash at runtime. The unified `emitVarargsDistinctW` helper handles the empty case via `requireCurrentContext()`. Bug → fix → no test added (empty `mkDistinct[W]()` was unreachable in the test suite); flagged here for the audit.
- **`emitVarargsRequired1` couldn't take generics as a single `untyped` parameter.** Nim parses `proc name*generic(...)` as a binary expression at line start (`*` operator binds with whitespace), not as a proc-with-template-substituted-generics. Tried `proc \`name\`generic(...)` and macro routes; settled on per-shape templates — `emitVarargsRequired1Basis` (regex), `emitVarargsRequired1E` (sequence), `emitVarargsDistinctS` (boolean `Z3Ast[S]`), `emitVarargsDistinctW` (bitvec `Z3BitVec[W]`), `emitVarargsMonoid` (boolean `Z3Bool`, no generic). Five small templates rather than one giant macro; each instantiation is one line. The plan said "a macro `naryOp`" — this is the per-shape-template variant of that idea. The shared FFI-call core lives in `naryFFICall`.
- **Docstring placement** matters under macro/template calls. `emitVarargsMonoid(mkAnd, ...)` followed by indented `## doc lines` parses the doc as the template-call body and breaks. Resolution: convert per-call docstrings to leading `#` comments above the macro call. Less ergonomic than `proc`-attached docs (no `nim doc` integration for those entries) — a real polish loss. Will revisit if `nim doc` generation becomes a v0.6 goal.

### From step 1 (z3/context split — extract z3/error)

- **Layering inversion.** The original plan said "z3/error imports z3/context for the `Z3Context` type used in proc/template signatures." That creates a cycle: `z3/context.requireCurrentContext` raises `Z3Error`, so `z3/context` needs `z3/error` too. **Correction:** `z3/error` depends only on `z3/ffi`. `raiseZ3Error` takes `rawCtx: RawZ3Context` (not `Z3Context`); `checkErr` / `checkErrVoid` accept `ctx: untyped` and dot-access `ctx.raw` at template expansion. This makes `z3/error` a *lower* layer than `z3/context` — siblings importing both get a clean one-directional dependency graph.
- **`raiseZ3Error` signature change.** Five sibling call sites (`io.nim`, `model.nim` ×2, `solver.nim`, `introspect.nim`, `string.nim`) plus `tests/tcontext.nim` migrated from `raiseZ3Error(ctx, code)` → `raiseZ3Error(ctx.raw, code)`. Mechanical; one-line per site.
- **`checkErr` template `ctx` parameter is now `untyped`.** Loses static type-checking on the first argument (a non-`Z3Context` value would fail at "undeclared field: raw" inside the template body rather than at the call site). Acceptable cost: every call site already passes a `Z3Context`-shaped value, and the failure mode is still clear. PhD-tier benefit: `z3/error` doesn't need `Z3Context` visible at definition time, enabling the layering inversion above.
- **No re-export from `z3/context`.** Initially added `export error` from context for transitional convenience, then removed it: the plan's intent is that the seam is load-bearing. Every sibling module that uses the error discipline `import ./error` explicitly. `import z3` users still see `Z3Error` via `src/z3.nim`'s direct import of both modules.
- **`Z3ErrorCode` enum re-exported as a type only.** Tried `export Z3_OK, Z3_INVALID_ARG, …` explicitly and hit `Error: cannot export: Z3_OK; enum field cannot be exported individually`. Resolution: `export Z3ErrorCode` re-exports the enum type *and its values* transitively per Nim 2 semantics. Less verbose, same result.

---

## 8b. Pre-tag audit — v0.5

Structured walk before tagging, mirroring the v0.2 / v0.3 / v0.4 precedent. Each §1 goal + §5 step is classified **landed / rolled to v0.6 / dropped / sibling-package**, with the commit hash for landed items.

### §1 Goals

| # | Goal | Status | Commit / Notes |
|---|---|---|---|
| 1 | Cross-family parity for the `Z3Term` concept surface | ✅ landed | `4b3b956` (3B astEqual), `ad25d3f` (3C evalXxx + mkCharVar + docs/PARITY.md), `eb9789b` (3A pretty), `fe5f07d` (3D `$`) |
| 2 | Naming + cohesion hygiene | ✅ landed | `2de0447` (2A seq→sequence), `8a537a5` (2C RoundingMode consolidation), `463e6c2` (2D naryOp macro family) |
| 3 | Error type hierarchy | ✅ landed | `db01dcc` — v0.5 step 4. 13 typed subclasses (more than plan's draft 8 — see §8 step 4) |
| 4 | Memory + thread safety audit | ✅ landed | `9b3a067` (5A tconcurrency), `4f33a09` (5B nimble valgrind), `6b38b24` (5C THREADING.md) |
| 5 | Property tests for v0.3 families | ✅ landed | `8a66190` (FuncDecl), `be546cf` (String), `34b0f5d` (Sequence), `4f8761f` (Regex), `13abd17` (FP) — 21 new shape-properties × 25 iterations = 525 generative invocations per backend |
| 6 | Examples for v0.3 families | ✅ landed | `daddc4b` (tactic_pipeline), `49e75af` (uninterpreted_axioms), `b227adc` (float_verification), `9696697` (string_constraints) |
| 7 | GOTCHAS doc + README freshness | ✅ landed | `ad908b4` (9A GOTCHAS.md), `3ea70aa` (9C README rewrite + cross-links) |
| 8 | Feature flags + minimal-build story | ✅ landed | `aee9694` (10A cascading flags), `a39d01a` (10B config.nims.example), `8323095` (10C MINIMAL_BUILD.md), `61586bb` (10D testMinimal task) |
| 9 | `z3/context` dual-responsibility split — extract `z3/error` | ✅ landed | `fc5d072` — v0.5 step 1 |
| 10 | Z3 C-API micro-gap closure | ✅ landed | `004e8d2` (6A Z3FuncInterp), `3cc0f0a` (6B Z3ParamDescrs), `65b86a2` (6C Z3Char↔Z3BitVec) — closes the three v0.4 §8b asterisks; "every Z3 C-API capability is reachable" is now literally true |
| 11 | `add` vs `assertConstraint` canonical-name resolution | ✅ landed | `3bc3f41` — v0.5 step 2B. `Z3Solver.assertConstraint` deleted; `Z3Fixedpoint.assertConstraint` kept (distinct semantics) |
| 12 | Internal API documentation seam | ✅ landed | `5466c48` — v0.5 step 9B (`docs/INTERNAL_API.md`) |

**Every §1 goal landed.** v0.5 is the polish release the plan promised; nothing rolled to v0.6.

### §5 Steps

| Step | Deliverable | Status | Commits |
|---|---|---|---|
| 1 | `z3/context` split — extract `z3/error` | ✅ landed | `fc5d072` |
| 2 | Naming + cohesion hygiene + `add`/`assertConstraint` | ✅ landed | `2de0447` (A), `3bc3f41` (B), `8a537a5` (C), `463e6c2` (D) |
| 3 | Cross-family parity | ✅ landed | `4b3b956` (B), `ad25d3f` (C), `eb9789b` (A), `fe5f07d` (D) |
| 4 | Typed error hierarchy | ✅ landed | `db01dcc` |
| 5 | Memory + thread safety audit | ✅ landed | `9b3a067` (A), `4f33a09` (B), `6b38b24` (C) |
| 6 | Z3 C-API micro-gap closure | ✅ landed | `004e8d2` (A), `3cc0f0a` (B), `65b86a2` (C) |
| 7 | Property tests for v0.3 families | ✅ landed | `8a66190` (A), `be546cf` (B), `34b0f5d` (C), `4f8761f` (D), `13abd17` (E) |
| 8 | Examples for v0.3 families | ✅ landed | `daddc4b` (A), `49e75af` (B), `b227adc` (C), `9696697` (D) |
| 9 | GOTCHAS + INTERNAL_API + README freshness | ✅ landed | `ad908b4` (A), `5466c48` (B), `3ea70aa` (C) |
| 10 | Feature flags + minimal-build story | ✅ landed | `aee9694` (A), `a39d01a` (B), `8323095` (C), `61586bb` (D) |
| 11 | Pre-tag audit + §8b block | ✅ this commit | The audit you are reading. |
| 12 | v0.5 tag | next commit | The actual `v0.5.0` git tag, CHANGELOG entry, archive promotion. |

### Spec corrections logged during v0.5 (cross-reference)

Every step that hit a spec or Nim-language assumption needing change surfaced it back to the user before continuing; the corrections live in their per-step §8 entries above. Summary for the audit:

- **Step 1** (extract `z3/error`): **layering inversion.** Original plan had `z3/error` importing `z3/context` for `Z3Context` type; that creates a cycle because `z3/context.requireCurrentContext` raises `Z3Error`. Resolution: `z3/error` depends only on `z3/ffi`; `raiseZ3Error` takes `RawZ3Context` (not `Z3Context`); `checkErr` accepts `ctx: untyped` and dot-accesses `ctx.raw` at template expansion. Five sibling raise sites + 1 test migrated from `raiseZ3Error(ctx, code)` → `raiseZ3Error(ctx.raw, code)`.
- **Step 2** (naming hygiene): **`Z3Fixedpoint.assertConstraint` kept** (canonical axiom-assertion method; rules / facts / background axioms are three distinct ops). **`bitvec.mkDistinct` empty-input bug** fixed incidentally by the unified `emitVarargsDistinctW` helper. **`emitVarargsRequired1` can't take generics as a single `untyped` parameter** (Nim parses `proc name*generic(...)` as a binary expression); resolved with per-shape templates (`emitVarargsRequired1Basis`, `…E`, `emitVarargsDistinctS`, `…W`, `emitVarargsMonoid`). **`mkRoundingMode` collapsed to `rmRNE()` literal procs** — every other typed family is one family with literal-helper constructors; rounding mode was the lone holdout.
- **Step 3** (parity): **`$[T: Z3Term]` doesn't beat `system.$` in Nim 2.6.** Concept-constrained generics lose to `system`'s typed-object overloads; the unified `$` produced `(raw: (), ctx: ...)` instead of SMT-LIB. Resolution: keep per-family `$` overloads, factor body into `termToSmt2*[T: Z3Term]` template. **`Z3Renderable` concept wider than `Z3Term`** for `pretty`. **`evalChar` needs a `simplify` pass** — Z3 doesn't auto-fold `(char.to_int (_ Char N))`. **`mkCharVar` parity gap fixed** (every other family had one).
- **Step 4** (error hierarchy): **Nim's style-insensitive identifier rules cause naming collisions with FFI enum values.** `Z3SortError` ≡ `Z3_SORT_ERROR` and `Z3ParserError` ≡ `Z3_PARSER_ERROR` collapse to the same identifier. Resolution: rename to `Z3SortMismatchError` and `Z3ParseError`. **13 subclasses, not the plan's 8.** Audit of `Z3ErrorCode` added `Z3IndexOutOfBoundsError`, `Z3InvalidPatternError`, `Z3RefcountError`, `Z3OperationError`; renamed `Z3MemOutOfMemoryError` → `Z3MemoryError` and `Z3UnreachableError` → `Z3InternalError`. **`raiseSubclass` template needs `SubT: untyped`** (not `typedesc`) — `typedesc` form hit the same identifier-collision parsing.
- **Step 5** (memory + thread safety): **`newContext()` auto-sets `currentZ3Ctx`** as a side effect — surfaced during the `withContext`-per-thread test; documented in [docs/THREADING.md](docs/THREADING.md). **`--threads:on` enforces gcsafe on thread procs** — FFI is gcsafe but softlink's function-pointer indirection breaks Nim's analysis; tests wrap FFI sites in `{.cast(gcsafe).}:` blocks. **Valgrind audit gates on `definitely lost: 0 bytes`**, not exit code — libz3 triggers ~3000 non-leak "Invalid read" warnings inside its hash-cons internals; only the leak summary is actionable.
- **Step 6** (C-API micro-gaps): **`Z3FuncInterp` entry-vs-else representation is solver-dependent** — Z3 can fold a constraint into the else-value rather than emitting an entry. Tests pin semantic round-trip (not table shape). **Plan's `unicode-char-width` doesn't exist** — Z3 uses `encoding` global param (default Unicode = 18 bits). Wrapper commits to `Z3BitVec[18]`. **`(char.to_bv (_ Char N))` doesn't fold to a BV numeral** in Z3's evaluator. Tests use `smtValid` against explicit BV literal. **`emitRefcountLifecycle` doesn't unify across two phantom params** (`Z3FuncInterp[ArgsTup, Ret]`) — per-instantiation `=destroy` spelled inline.
- **Step 7** (property tests): **`tuples3` doesn't exist in proptest** — used nested `tuples2(a, tuples2(b, c))` for 3-arg properties. **FP properties conditioned on `isFinite`** — naïve `x + 0 ≡ x` is false on NaN.
- **Step 8** (examples): clean landing. All four examples landed first-try after one `import sequtils` for `anyIt`.
- **Step 9** (docs): clean landing. Curated 14 user-facing GOTCHAS entries from the §8 ledgers; 4 INTERNAL_API.md categories driven by `grep`-audited symbol lists.
- **Step 10** (feature flags): **`config.nims` template placed at `docs/config.nims.example`**, not at repo root — Nim auto-discovers `config.nims` at the project root; the template would break our own tests. **§7 open question 4 resolved** in favour of automatic-cascade design (vs. compile-time-error-if-deps-not-passed). **Honesty disclaimer in MINIMAL_BUILD.md**: flags hide the umbrella re-export but don't necessarily reduce wrapper compile time because `z3/introspect`, `z3/io`, etc. hard-import transitive theory modules.

### Items rolled forward to v0.6

These are logged per-step in §8 above. Consolidated here for the rollforward:

- **Nothing.** v0.5 is the 1.0-readiness polish; v0.6 is the v1.0 tag with version-only delta. The plan's framing is "v0.5.0 → v1.0.0 with no new functionality between them." Anything not in v0.5 that's also not a real-user blocker rolls to a post-1.0 v1.x track.

### Scope-pruned items (redirected to sibling packages or post-1.0 v1.x)

Same as v0.4:

- **DOT / GraphViz AST export** — sibling package (`nim-z3-tools` / `-viz`); not a wrapper concern.
- **Visualisation / interactive REPL / SMT-COMP driver** — sibling packages.
- **High-level macro DSL** — non-goal; the wrapper IS the API.
- **Carry-forward CI items (#1)** — same private-dep blocker as v0.2 / v0.3 / v0.4.

### Dropped (won't ship)

(None this release.)

### Cumulative test count

v0.4 closed at **1114 OKs** across `nim c` + `nim cpp`. v0.5 closes at **1262 OKs** under the default config plus **18 OKs** for the minimal-build verification (`nimble testMinimal`). Step-by-step delta:

| After step | Total | Delta | New tests (× 2 backends) |
|---|---|---|---|
| 1 (`z3/error` extracted)            | 1118 | +4   | 2 × 2  (tracer + behaviour) |
| 2 (naming hygiene)                  | 1116 | −2   | −1 test (`assertConstraint` alias deleted) × 2 |
| 3 (cross-family parity)             | 1148 | +32  | 16 × 2 (parity surfaces × 5 sub-items) |
| 4 (typed error hierarchy)           | 1176 | +28  | 14 × 2 (subclass tree + dispatch) |
| 5 (memory + thread safety)          | 1184 | +8   | 4 × 2 (concurrency); valgrind task adds no `[OK]`s |
| 6 (C-API micro-gap closure)         | 1220 | +36  | 18 × 2 (FuncInterp + ParamDescrs + Char↔BV) |
| 7 (property tests for v0.3)         | 1262 | +42  | 21 × 2 (5 sub-items: FuncDecl + String + Seq + Regex + FP) |
| 8 (examples)                        | 1262 | 0    | 4 new example files; no `[OK]`s (examples assert via `doAssert`) |
| 9 (docs)                            | 1262 | 0    | docs-only |
| 10 (feature flags)                  | 1262 | 0    | default config unchanged; +18 OKs via `nimble testMinimal` (9 tests × 2 backends, separate task) |

**Cumulative breakdown** (v0.4 → v0.5):
- Tests: 1114 → 1262 OKs default (+148) + 18 minimal-config (`testMinimal` task)
- New typed families: +2 (`Z3FuncInterp[Args, Ret]`, `Z3ParamDescrs`)
- New modules: +1 (`z3/error`, extracted from `z3/context`)
- Renamed module: `z3/seq` → `z3/sequence`
- New typed sort: none (uninterpreted shipped in v0.4)
- New polish docs: `GOTCHAS.md`, `INTERNAL_API.md`, `PARITY.md`, `THREADING.md`, `MINIMAL_BUILD.md`, `config.nims.example`
- New nimble tasks: `valgrind`, `testMinimal`
- Architecture: typed error hierarchy (13 subclasses); generic `pretty[T]`, `astEqual[T]`, `$` via `termToSmt2`; cascading feature flags

---

## 9. Closing note

v0.5 is the boring release. Nothing flashy lands; the wrapper just *settles*. After it ships, the work in v0.4 (which landed every contract-completion §1 goal) plus the load-bearing concepts + extracted error module + closed C-API micro-gaps + canonical names + documented internal seam in v0.5 IS what 1.0 looks like. The four goals added post-v0.4 (9 = `z3/error` split, 10 = C-API micro-gaps, 11 = `add`/`assertConstraint` canonical-name resolution, 12 = `INTERNAL_API.md`) make the v1.0 "every Z3 capability reachable" claim *literal* and the contributor-onboarding story explicit.

When v0.5 ships: archive this file to `docs/V0.5_PLAN.md` (it's there already in draft), promote whatever `docs/V0.4_PLAN.md` ended up being to its own archived form, write a minimal `docs/IMPLEMENTATION_PLAN.md` for v0.6 (which is just "tag v1.0; here's the checklist"), and update the README's "Design" section to point at all four archives — V0.1, V0.2, V0.3, V0.4, V0.5 — the historical record of how the wrapper got to 1.0.

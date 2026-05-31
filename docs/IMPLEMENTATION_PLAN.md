# nim-z3 v0.5 plan (live)

> **Status: live, promoted 2026-05-30** from its v0.3-era draft after the v0.4.0 tag shipped. The previous live plan (v0.4 — the contract-completion release) is archived at [docs/V0.4_PLAN.md](V0.4_PLAN.md). When v0.5 ships, this file is archived to `docs/V0.5_PLAN.md` and a v0.6 plan (the v1.0 tag itself) is promoted into the live slot.

A type-safe, memory-safe, idiomatic Nim wrapper for the Z3 SMT solver.

**Status (at plan-promotion time)**: v0.4 shipped 2026-05-30 with **1114 OKs** across both backends, zero failures. Every §1 goal of the v0.4 contract-completion release landed (see [V0.4_PLAN.md §8b](V0.4_PLAN.md)). v0.5 owns the cross-cutting 1.0-readiness polish (candidates 2–8 from the post-v0.3 review): cross-family parity, naming + cohesion hygiene, examples, docs + GOTCHAS, error type hierarchy, property-test extension, feature flags.

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

### Non-goals (re-asserted from earlier plans + new for v0.5)

- **`Z3Fixedpoint`** — owned by v0.4 (candidate 1 — either landed or explicitly narrowed-out at v0.4 tag time).
- **Unsat-core / proof / AST-introspection / substitute / translate** — same, owned by v0.4.
- **Custom theories via user propagators** (`Z3_solver_propagate_*`) — still v1.x+ research-grade.
- **High-level macro DSL** (`solve: forall x in Int, x + 1 > x`) — still non-goal; the wrapper IS the API.
- **Differential testing against Python z3** — still rolled forward.

---

## 2. The shape of the v0.5 expansion

v0.5 is **the polish release**. Reading the §1 goals out loud: "make Z3Term load-bearing, fix naming debt, refactor error types, audit safety, write examples, refresh docs, ship a minimal build." None of those are new theories. Several are net-negative LOC (the unification work pulls duplicated bodies into generators).

Concretely: the wrapper's typed-family count doesn't grow in v0.5. The wrapped Z3 surface doesn't grow (that's v0.4). The user-visible surface area shrinks (the `RoundingMode` enum is replaced by `Z3RoundingMode` literal helpers; the `naryOp` macro means contributors don't write per-family varargs anymore; feature flags mean some users will compile *less* of the wrapper).

This is the release whose architectural payoff is **"every concept is load-bearing, every name is principled, every error is typed."** Pre-1.0 hygiene done deliberately.

---

## 3. Module structure

Net additions: very few — most v0.5 work is rewriting existing modules.

- **`z3/sequence`** — renamed from `z3/seq` (goal 2).
- **`docs/GOTCHAS.md`** — new doc (goal 7).
- **`docs/THREADING.md`** — new doc (goal 4).
- **`tests/tconcurrency.nim`** — new test file (goal 4).
- **`tests/recipes.nim`** — extended (goal 5).
- **4 new example files** (goal 6).
- **`config.nims`** at repo root — template for minimal builds (goal 8).

Net removals:

- **`RoundingMode` Nim enum + `mkRoundingMode(rm: RoundingMode)`** — superseded by `Z3RoundingMode` literal helpers (goal 2).
- **5 per-family `pretty` overloads** — superseded by generic `pretty[T: Z3Term]` (goal 1).
- **6+ per-family varargs bodies** — superseded by `naryOp` macro instantiations (goal 2).

---

## 4. Phasing — what ships when

### v0.5.0 — the 1.0-readiness polish release

1. **Naming + cohesion hygiene.** `z3/seq` → `z3/sequence` rename. `Z3RoundingMode` consolidation (delete `RoundingMode` enum, expose AST-family literal helpers). Internal `naryOp` macro for varargs body unification. All breaking; one pre-1.0-clean commit per sub-item, suite green between each.
2. **Cross-family parity** (`Z3Term` concept becomes load-bearing). Generic `pretty[T: Z3Term]`, generic `astEqual[T: Z3Term]`, scalar-shorthand audit, `$` parity.
3. **Typed error hierarchy.** Refactor `Z3Error` into a tree (`Z3InvalidUsageError`, `Z3SortError`, …); update `raiseZ3Error` dispatch on `code`. Tests using `expect Z3Error` continue to pass via subclass-of.
4. **Memory + thread safety audit.** Valgrind clean run; `tests/tconcurrency.nim`; `docs/THREADING.md`.
5. **Property tests for v0.3 families.** Extend `recipes.nim`; add proptest properties for String / Sequence / FP / Regex / FuncDecl invariants.
6. **Examples for v0.3 families.** Four new example files (string constraints, FP verification, uninterpreted axioms, tactic pipeline).
7. **GOTCHAS.md + README freshness.** Promote v0.3 spec corrections; rewrite README "Design" section.
8. **Feature flags + minimal-build story.** Per-theory compile-time guards; `config.nims` template; CI smoke for at least one minimal combination.
9. **Pre-tag audit.** Same discipline as v0.3 step 9.
10. **v0.5 tag.**

### v0.6 — the v1.0 tag

Whatever shipped at v0.5.0 IS v1.0 modulo the version bump + changelog + README stability statement. v0.6 doesn't add functionality. (If v0.5 surfaces something that should be in 1.0 but isn't, that becomes v0.6 work — but the *intent* is v0.5.0 → v1.0.0 with a version-only delta.)

---

## 5. Implementation sequence

Architecture-affecting items first (so subsequent steps inherit the cleaned state); hygiene + docs late (so they reflect the final API).

1. **Naming + cohesion hygiene** — `seq → sequence`, `RoundingMode` consolidation, `naryOp` macro. The rename is purely mechanical; the `RoundingMode` consolidation breaks every test calling `mkRoundingMode(rmRNE)` — update them to `rmRNE()`. The `naryOp` macro doesn't change call sites; internal refactor only.

2. **Cross-family parity.** Generic `pretty[T: Z3Term]` with `mixin` for family-specific format helpers; generic `astEqual[T: Z3Term]`; audit + add the missing `evalXxx` shortcuts on `Z3Model`; add `$` parity where missing. Document the "for every new family, here's what you implement" contract in a comment at the top of `z3/lifecycle` or a new `z3/parity.nim`.

3. **Typed error hierarchy.** Add subclass types to `z3/context`; update `raiseZ3Error` to dispatch on `code` to the right subclass; ensure every internal `raise` site goes through `raiseZ3Error` rather than constructing `Z3Error` directly (audit). Tests pass unchanged via subclass-of; tighten a few `expect Z3Error` to `expect Z3SortError` etc. where the intent is clear.

4. **Memory + thread safety audit.** `nimble valgrind` task running the suite + reporting `definitely lost: 0 bytes`; `tests/tconcurrency.nim` exercising per-thread context isolation + the documented cross-thread limitation surfacing properly; `docs/THREADING.md` 3-paragraph canonical doc.

5. **Property tests for v0.3 families.** Extend the `recipes.nim` ADT to cover String / Sequence / FP / Regex / FuncDecl. Add proptest properties for each (round-trip identity, structural-equivalence, theory-specific invariants). Expected delta: 50–80 generative tests.

6. **Examples.** Write the four example files. Each runs to a model that demonstrates the headline use case for its theory. Add to `nimble examples` task.

7. **GOTCHAS.md + README rewrite.** Promote V0.3_PLAN §8 spec corrections to GOTCHAS.md with the **symptom / cause / wrapper behavior / what you should do** template. Rewrite README "Design" section + headline example + version-anchored prose.

8. **Feature flags + minimal-build story.** Add `when defined(z3Without*)` guards around theory imports + FFI blocks. Write `config.nims` template at repo root. Add a CI matrix entry (or a local `nimble test-minimal` task pending CI unblock) that builds with `-d:z3WithoutFP -d:z3WithoutStrings`. *Decide during impl* whether feature flags need a `requires`-style dependency declaration (since `Z3Regex` depends on `Z3Seq`, etc.).

9. **Pre-tag audit + rollforward annotations** per the v0.3 precedent. The §8b "Pre-tag audit" block this round will be small (no scope surprises since v0.4 already locked the scope) and the running §8 deferral ledger will catch anything that surfaced mid-implementation.

10. **v0.5 tag.** Then v0.6 = v1.0 tag with a version-only delta.

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

If v0.4 lands fixedpoint / unsat-core / etc., v0.5 has to extend cross-family parity / `pretty` / `naryOp` / etc. to cover those new families. The work is mechanical (same idiom). Mitigation: write the v0.5 plan now (this doc), revisit after v0.4 ships, append "and don't forget to extend to the v0.4 additions" to each goal where it applies.

---

## 7. Open questions (genuinely open — answer during implementation)

1. **Feature-flag dependency declarations.** Goal 8 raises the question of whether `Z3Regex needs Z3Seq` etc. should be expressed as a static `requires` table or just left as "if you disable a theory, also disable its dependents and we'll error at compile if you forget." Lean: latter; compile-time error is fine since the dependency chain is shallow. Decide during step 8.

2. **`pretty` for `Z3FuncDecl`** — how do we render a function declaration without applying it? Z3's `$Z3_ast_to_string(func_decl_to_ast(fd))` is the FFI path; the format is SMT-LIB syntax `(declare-fun f (Int Int) Bool)`. That's fine. Decide during step 2 whether we surface anything richer (a Nim-shaped `proc-signature-like` rendering) — lean no, SMT-LIB form is canonical.

3. **`evalXxx` shorthand cap.** Audit might surface "every typed family wants its own `evalXxx`" — that's 7+ new shortcuts for v0.3 families alone. Cap by: shortcut exists only if it differs from the generic `m.eval(x)` pattern by more than the extractor name. Decide during step 2.

4. **`Z3Error` hierarchy specifics.** The exact subclass list in §1 goal 3 is my draft; the right list is whatever set covers every Z3 error code with a meaningful semantic distinction. Audit `Z3ErrorCode` during step 3 and refine.

5. **README "Design" section format.** Tiered hierarchy table vs prose vs link-to-`src/z3.nim`-docstring. Decide during step 7 with the working draft in hand.

---

## 8. Deferred from v0.5 (running list, populated as work happens)

Same append-only format as v0.1 §18, v0.2 §8, v0.3 §8. Format: **what / why / where it goes** (v0.6 / dropped / sibling-package).

*(empty until the first deferral surfaces.)*

---

## 9. Closing note

v0.5 is the boring release. Nothing flashy lands; the wrapper just *settles*. After it ships, the work in v0.4 (whatever scope choice that release made) plus the load-bearing concepts in v0.5 IS what 1.0 looks like.

When v0.5 ships: archive this file to `docs/V0.5_PLAN.md` (it's there already in draft), promote whatever `docs/V0.4_PLAN.md` ended up being to its own archived form, write a minimal `docs/IMPLEMENTATION_PLAN.md` for v0.6 (which is just "tag v1.0; here's the checklist"), and update the README's "Design" section to point at all four archives — V0.1, V0.2, V0.3, V0.4, V0.5 — the historical record of how the wrapper got to 1.0.

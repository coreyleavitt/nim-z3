# nim-z3 RFC — completeness pass (v5 — round-4 architect review applied; ready for `/loop`)

**Status:** Stage 1 v5 — **READY FOR `/loop`**. Four architect rounds complete; convergence achieved (R1=75 findings → R2=42 → R3=64 → R4=43; final CRIT count = 1, resolved in v5 with bvToInt rationale note). All round-4 clear-best fixes applied; residual MEDIUM/LOW items annotated inline at their cycle sites for `/tdd` cycle-time resolution.
**Input:** `docs/AUDIT-completeness.md` (~80 findings) + round-1 architect review (75 findings) + round-2 architect review (42 findings, 44% lighter than round 1) + round-3 (64) + round-4 (43).
**Owner:** complete-library scope per `complete-lib-not-consumer`. Breaking changes are in scope per `nim-z3-proptest-only-consumer`.
**Version target:** `2.0.0` (multiple breaking renames + new theory modules; **single break, no deprecation window**).

**Revision history:**
- v1 (initial draft): 11 clusters, 73 cycles, 5 ADRs.
- v2 (round-1): ADR-N0002 reversed (marker-phantom `Z3UninterpretedVal[T]`); ADR-N0004 rewritten; ADR-N0006/N0007 added; deprecation window dropped; ~15 cycle splits + 8 new cycles; ~30 factual corrections; N10.6 deleted.
- v5 (round-4): Applied round-4 clear-best fixes — ADR-N0004 push/pop "shim strips ctx" doc + diseq separate-registration clarification + `clearSubBoxes` public API; N1.6 `Z3AstVector` workaround correction + N0.1 dep note + ADR table type-name fix; deleted N6.8/N6.9/N9.6 reserved-cycle stubs; N6.1 removed from slice plan; N6 inventory recounted (7); N3.3 `bvToInt` naming rationale; N6.5a IEEE-vs-structural `==` decision; N5.5 foldli arg-order citation; N7.4 cite of existing `Z3AccessorDecl`; N8.1 `Z3_solver_get_levels` Nim wrapper spec; N8.7 explicit `Z3SimplifierOwn` + `Z3Simplifier` type decls; N10.4 rounding-mode SMT-LIB long-name doc fold; N10.5 dropped `toReal` alias (collides with `fp.nim:431`); N11.4 split into `tpropagator.nim` (a) + `tonclause.nim` (b); N11.7 adds `docs/THREADING.md`; cycle-count reconciliation (75 cycles + 7 ADRs = 82 work units).
- v4 (round-3 atomic rewrite): backlog absorbed into canonical sections; ADR/cycle/inventory/slice-plan/compat-table synced; ADR-N0004 corrected push/pop fields + final_eh multi-fire + gcsafe stance.
- v3 (round-2): **Round-2 review found 7 inspect-before-pessimizing failures in v2** — fast editing under round-1 finding pressure introduced precise-looking text not verified against actual code/headers. v3 corrects: lifecycle pattern across all new types (CRITICAL — `ref object` + `emitTermLifecycle` was mutually exclusive); `mkBitVecFromBools` dropped (FFI mismatch); `getNumeralSignificandUint64` corrected to `Option[uint64]`; `experimental: templateDefining` pragma dropped (doesn't exist); N7.8 fixedpoint callback FFI rescoped (one function, not seven); ADR-N0003 switched to macro (round 2 challenged round 1's hand-write verdict; the existing `apply` template ladder is the structural precedent); ADR-N0007 gate naming aligned with `z3Without*` convention; `Z3_fresh_eh` sub-solver registration table added (closes GC leak); N6.1 deleted (3-lens consensus); reserved cycle slots removed; cycle count reconciled.

---

## Why now

Audit confirms nim-z3 v1.0 is structurally complete but has a bounded completeness tail (7 CRITICAL whole-theory gaps + ~30 HIGH + ~30 MEDIUM + ~15 LOW). Round-1 review surfaced ~25 distinct corrections (after dedupe across lenses), including reversals of two ADRs. v2 absorbs all of them.

Proptest's planned Phase 15+ language-fragment expansion blocks on at least the CRITICAL + most HIGH gaps closing. This RFC closes the full audit in 12 clusters (one new cluster N0 added for `ffi.nim` refactor prerequisites).

---

## Pre-cycle ADRs

Seven settle-it-now design calls (v1 had 5; v2 adds ADR-N0006 + ADR-N0007).

### ADR-N0001: `Z3Set[E]` representation

Semantically Z3's `array(E → Bool)`. Three options:

- **(a)** Plain alias of `Z3Array[E, Z3Bool]`.
- **(b)** `distinct Z3Array[E, Z3Bool]` with explicit converters.
- **(c)** Standalone type.

**Decision: (b) — `distinct Z3Array[E, Z3Bool]`.** Set semantics ≠ array semantics. Distinct enforces the boundary. Explicit `toArray` / `toSet` converters provided. **Round-1 addition:** `==` must explicitly delegate via `toArray` (don't reimplement `Z3_mk_eq` redundantly); `!=` is mandatory and must be in the API surface; both proc bodies are specified in N1.1.

### ADR-N0002: `Z3UninterpretedVal` shape (REVISED in v2)

**Decision: marker-type phantom `Z3UninterpretedVal[T]`, identical to `Z3DatatypeValue[T]`'s pattern.** v1's "dynamic sort handle" decision was wrong:

1. v1's RED test claimed "two on different sorts are statically incompatible (compile-error contract)" — that contract is **unachievable** without phantom typing. With v1's design, cross-sort `==` would compile and fail at runtime via `Z3SortMismatchError`.
2. `sortdispatch.nim`'s `sortOfType[T](ctx)` is a *typedesc-level* dispatch. A type with a *value-level* sort cannot serve as the array-key generic parameter. `Z3Array[Z3UninterpretedVal_v1, V]` is unconstructible via the generic path.
3. v1 argued phantom typing was "invasive for proptest's N-distinct-Loc-types case." This conflates "N user-defined Z3 sorts" with "N hand-declared Nim marker types." Nim `type` declarations are cheap; `Z3DatatypeValue[T]` already proves the pattern is ergonomic at scale.
4. The dynamic-sort runtime equality check (proposed in v1 H8) would silently miscompare two values whose carried sorts happened to share a name but had distinct sort handles.

The marker-phantom shape:
```nim
type Z3UninterpretedVal*[T] = object
  raw*: RawZ3Ast
  ctx*: Z3Context
```

The sort is recovered via `sortOf[T](ctx)` reading from `ctx.uninterpretedRegistry[$T]`, mirroring `datatypes.nim:214-233`. Construction goes through `declareUninterpretedSort[T](ctx, name)` which registers the sort handle keyed on `$T` (parallel to `declareDatatype[T]`). For proptest's dynamic-sorts use case (sorts arise from N distinct Nim ref types), proptest can declare one marker type per ref type at parse time — same cost as proptest already pays for datatype-backed variants today.

### ADR-N0003: `declareDatatypes` N-ary surface (REVISED in v3 — switched to macro)

**Decision (v3): macro `declareDatatypesGen(N: static int)` generates the arity-N overload at compile time; expose `declareDatatypesN(specs: openArray[...])` as escape hatch for N > 8.**

v2 said "hand-write arity 4–8" with the argument "engineering cost exceeds the ~350-line hand-copy." Round 2 Lens 3 H2 challenged this and was correct:

- The codebase already contains a structural precedent: `datatypes.nim:589-606` ships `apply` templates for arities 0–5 over a shared `applyImpl` core — exact same per-arity generation pattern. `quantifier.nim`'s arity ladder is another. The "we can't do macros here" claim was unfounded.
- 5 hand-written copies = 5× maintenance surface. Any future Z3-side primitive change (e.g., `Z3_del_constructor_list` ordering relative to `queryConstructorsInto`) requires editing 5 procs.
- Generating an N-tuple return type from a `static int N` is straightforward via `nnkTupleConstr.newTree` with N entries built in a compile-time loop. v2 incorrectly handwaved this as impossible.
- Macro complexity bounded: ~50-80 lines. Hand-copy: ~350 lines. Net savings ~270 lines + 5× maintenance reduction.

The macro reads `N: static int`, emits N typeparams `T1..TN`, emits the proc body with N repetitions of the four pattern groups (registry insert, `buildRawConstructors` call, `doAssert`, `queryConstructorsInto`/`del_constructor_list`), and emits the N-tuple return type. The arity-2/3 hand-written overloads stay as canonical reference forms (delete them only if the macro produces structurally identical output, verified by a code-equivalence test).

### ADR-N0004: User-propagator plugin architecture (REWRITTEN in v2)

v1's "the marshalling layer is the same pattern used for context-error callbacks" is **wrong**. The error-handler pattern (`error.nim`, `context.nim:203`) registers a single bare `proc` (not a closure) and uses the context handle itself as the data binding. Propagators have:

1. **9 distinct C callback function types** (verified at `z3_api.h:1435-1443`): `push_eh`, `pop_eh`, `fresh_eh`, `fixed_eh`, `eq_eh` (also used for diseq), `final_eh`, `created_eh`, `decide_eh`, `on_clause_eh`. (v4 round-3 Lens 1 LOW-1: `consequence_eh`, `next_split_eh`, `declare_eh`, `register_eh` are NOT callback types — they are outbound API functions the user calls inside callbacks. v1+v2+v3 listed them as callback types, which was wrong.)
2. **Nim closures are 2-word fat pointers** (proc address + env pointer). Z3's `user_data` slot is one `void*`. A closure cannot be stored directly.
3. **`Z3_fresh_eh`** spawns sub-solvers with new contexts; Z3 calls callbacks with the new context handle. The user-data slot for the sub-solver is set by `fresh_eh`'s return value — a separate Nim object that the GC must trace.
4. **The `Z3_solver_callback`** opaque handle passed to `consequence`/`next_split` is only valid *inside* an active callback invocation; it cannot be cached on the `Z3Propagator` object.

**Decision: heap-allocated `ref PropagatorCtxBox` registered with Z3; typed closure API as primary surface; explicit thread-safety contract.**

```nim
type
  Z3PropagatorHandlers* = object   # value type, all fields public
    # Required by Z3_solver_propagate_init (v4 round-3 Lens 1 CRIT-2 correction):
    push*:        proc(cb: Z3SolverCallback) {.closure.}
      ## Fires when the solver pushes a CDCL decision scope. Required by Z3
      ## (pure-virtual in z3++.h). If nil, newPropagator supplies a no-op.
    pop*:         proc(cb: Z3SolverCallback, numScopes: uint) {.closure.}
      ## Fires when the solver pops `numScopes` decision scopes. Required by
      ## Z3 (pure-virtual). If nil, newPropagator supplies a no-op.
    fresh*:       proc(newCtx: Z3Context): Z3PropagatorHandlers {.closure.}
      ## Called when Z3 spawns a sub-solver with a new context. Must return
      ## a fresh handler set bound to `newCtx`. The returned object is heap-
      ## allocated by newPropagator's internal shim and kept GC-reachable via
      ## the parent's subBoxes registry.

    # Optional theory-extension callbacks:
    fixed*:       proc(cb: Z3SolverCallback, e, val: Z3AnyAst) {.closure.}
    final*:       proc(cb: Z3SolverCallback) {.closure.}
    eq*:          proc(cb: Z3SolverCallback, a, b: Z3AnyAst) {.closure.}
    diseq*:       proc(cb: Z3SolverCallback, a, b: Z3AnyAst) {.closure.}
    created*:     proc(cb: Z3SolverCallback, e: Z3AnyAst) {.closure.}
    decide*:      proc(cb: Z3SolverCallback, t: var Z3AnyAst, idx: var uint, phase: var int) {.closure.}
    # NOTE: `{.gcsafe.}` is intentionally OMITTED (v4 round-3 Lens 3 M2).
    # Z3 fires callbacks on the thread that called check(); they don't
    # execute concurrently. Users who need to capture Nim ref-types can
    # wrap captures in `{.cast(gcsafe).}: ... ` blocks. Documenting this
    # in docs/THREADING.md is part of N11.7's scope.

  PropagatorCtxBox = ref object   # heap-allocated, GC-rooted, internal
    handlers: Z3PropagatorHandlers
    ctx: Z3Context
    solver: Z3Solver

  Z3Propagator* = ref object   # public; reference semantics
    box: PropagatorCtxBox      # strong ref keeps the box alive
    solver*: Z3Solver
    ctx*: Z3Context

proc newPropagator*(s: Z3Solver, handlers: Z3PropagatorHandlers): Z3Propagator
  ## Allocates a PropagatorCtxBox on the heap, casts its address to void*,
  ## registers it via Z3_solver_propagate_init with C-side shim functions
  ## that cast user_data back to ptr PropagatorCtxBox and dispatch to the
  ## stored Nim closure. The returned Z3Propagator holds a strong ref so
  ## the box outlives the solver's check() invocation.

proc consequence*(cb: Z3SolverCallback, lits, eqs: seq[Z3AnyAst], conseq: Z3AnyAst)
proc nextSplit*(cb: Z3SolverCallback, t: Z3AnyAst, idx: uint, phase: int)
  ## These take Z3SolverCallback as their first arg — it's only valid
  ## inside a callback invocation; cannot be cached on the propagator.
```

**Thread-safety contract:** Propagator callbacks fire on whatever thread invoked `s.check()`. All closures must be `{.gcsafe.}`. The `Z3Propagator` must outlive every `check()` call that uses it. v2 forbids storing a `Z3Propagator` as a value type because moves invalidate the pointer Z3 holds in `user_data`. Documented in N8.4's type declaration.

**`Z3_fresh_eh` (REVISED in v3 per round-2 Lens 1 H3):** Z3 has no sub-solver-destruction notification — `GC_ref`-without-`GC_unref` would leak permanently. v3 uses a **registration table** on the parent `PropagatorCtxBox`:

```nim
type PropagatorCtxBox = ref object
  handlers: Z3PropagatorHandlers
  ctx: Z3Context
  solver: Z3Solver
  subBoxes: seq[PropagatorCtxBox]   # NEW in v3 — sub-solver registration
```

When Z3 calls `fresh_eh(ctx, new_context)`:
1. The Nim closure receives `new_context` and returns a fresh `Z3PropagatorHandlers` bound to it.
2. The C-side shim heap-allocates a new `PropagatorCtxBox` for the returned handlers.
3. The shim **appends the new box to the parent's `subBoxes` seq** (keeps it GC-reachable).
4. The shim returns the new box's address as the sub-solver's `user_data`.

**No `GC_ref` / `GC_unref` calls** — the registration table is the only GC-reachability mechanism. v2's prior `GC_ref` design is dropped (would have leaked permanently per round-2 Lens 1 H3).

**Sub-box lifetime (v4 round-3 Lens 1 HIGH-3 correction):** `final_eh` fires whenever CDCL reaches a complete assignment (`z3_api.h:7134`) — NOT once at `check()` return. Z3 can backtrack and re-fire `final_eh` multiple times per single `check()`. v3's plan to clear `subBoxes` in the `final_eh` shim was therefore unsound (would release sub-solver boxes mid-check while sub-solvers still hold pointers).

v4 strategy: sub-boxes are released **at `Z3Propagator` collection**, not at any callback. Since `Z3Propagator` must outlive every `check()` invocation (documented lifecycle contract), sub-boxes are GC-reachable via the parent's `subBoxes` seq for the entire duration of every `check()`. Across multiple `check()` calls on the same propagator, `subBoxes` accumulates — boxes are lightweight (closure storage + ctx + solver refs), and the user can manually clear after `check()` if desired.

The `final_eh` shim only dispatches to the user's `handlers.final` closure (if provided). It does NOT touch `subBoxes`.

**`clearSubBoxes` user API (v5):** to support the "release accumulated sub-boxes after `check()` returns" pattern explicitly:

```nim
proc clearSubBoxes*(p: Z3Propagator)
  ## Releases all sub-solver PropagatorCtxBox entries accumulated by Z3's
  ## fresh_eh during prior check() invocations. Safe to call only OUTSIDE
  ## of an active check() — calling during a callback would invalidate
  ## pointers Z3 still holds. The Z3Propagator itself remains valid.
```

**`eq_eh` vs `diseq_eh` registration (v5 clarification):** Z3's C API uses the **same callback function type** (`Z3_eq_eh`) for both equality and disequality notifications, but they are registered through **two distinct C entry points**: `Z3_solver_propagate_eq` and `Z3_solver_propagate_diseq`. Implementation must call both — the `handlers.eq` field is wired through the first, `handlers.diseq` through the second. They share the shim dispatch shape (`(cb, a, b) → user closure`) but live in independent C-side slots.

**`push_eh` / `pop_eh` shim signature (v5):** Z3's C signatures pass `user_data: voidp` as the first argument (recovered to `ptr PropagatorCtxBox`), then the callback-specific args. The Nim-visible closures in `Z3PropagatorHandlers` deliberately **omit `user_data`** — the shim recovers the box from `user_data`, dispatches `box.handlers.push(cb)` / `box.handlers.pop(cb, numScopes)`, so the user closure never sees the marshalling pointer. Same convention as `fixed_eh`/`final_eh`/`eq_eh`/`created_eh`/`decide_eh`. Documenting this here avoids future implementer confusion about why the public signatures look "shorter" than the FFI types.

### ADR-N0005: Version bump policy (REVISED in v2)

**Decision: `2.0.0` with no deprecation window.** v1 said "deprecated alias kept one release." Round-1 review (Lens 1 M7 + Lens 3 L3 + Lens 4 LOW-3 — three-lens consensus) flagged that this contradicts the "single rotation event" framing in this same ADR. Per `nim-z3-proptest-only-consumer.md`, proptest is the only consumer and ships in lockstep. There is no 2.1.0 in the roadmap, so deprecated aliases would persist indefinitely as dead code. v2 drops the deprecation window entirely: renames are hard breaks in 2.0.0, documented in `MIGRATION-1.x-to-2.0.md`.

**Round-1 confirmation:** Lens 4 grep of proptest's full source tree found NONE of the renamed symbols (`mkNaN`, `mkInf`, `mkZero`, `strToInt`, `intToStr`, `toFp(bv, _: typedesc)`, `mkRegexAll`) in proptest. The proptest migration delta for these renames is **empty** — only the `.nimble` version pin needs updating.

### ADR-N0006: Per-new-type lifecycle table (REWRITTEN in v3)

Round-2 Lens 1 C1 + Lens 4 CRIT-2 surfaced that v2's table mixed two incompatible lifecycle mechanisms. v3 enforces the **single established pattern** used everywhere in the codebase: plain `object` for the owned type (e.g., `Z3SolverOwn`) + `ref` alias for the public type (e.g., `Z3Solver* = ref Z3SolverOwn`) + `emitRefcountLifecycle(Z3SolverOwn, Z3_solver_dec_ref)`. This is the only pattern that interacts correctly with Nim 2.x's `=destroy(v: T)` (non-`var`) hook signature.

| New type | Header | inc_ref proc | dec_ref proc | Lifecycle mechanism | Notes |
|---|---|---|---|---|---|
| `Z3Set[E]` (N1.1) | `z3.h` (Z3_ast) | `Z3_inc_ref` | `Z3_dec_ref` | **Explicit `=destroy`/`=copy`/`=dup` delegation procs** (Nim `distinct` does NOT propagate hooks) | Defined in N1.1. **v5.1 correction (N1.1 implementer):** delegate to `termDestroy`/`termCopy`/`termDup` from `lifecycle.nim` (which read `.raw`/`.ctx` directly), NOT to `=destroy(Z3Array[E, Z3Bool](s))` — the cast produces an rvalue and Nim ARC `=destroy` requires `var`. Same pattern applies to every future `distinct`-over-term-type. |
| `Z3AstMap` (N1.2) | `z3_ast_containers.h` | `Z3_ast_map_inc_ref` | `Z3_ast_map_dec_ref` | `emitRefcountLifecycle(Z3AstMapOwn, Z3_ast_map_dec_ref)` | Plain `object` + `ref` alias pattern (NOT `emitTermLifecycle`). |
| `Z3UninterpretedVal[T]` (N1.3) | `z3.h` (Z3_ast) | `Z3_inc_ref` | `Z3_dec_ref` | `wrap[T]` | Phantom over `Z3_ast`; standard term lifecycle (term, not ref). |
| `Z3RcfNum` (N1.6) | `z3_rcf.h` | **(none — no inc_ref)** | `Z3_rcf_del` | **Plain `object` with `=copy` `{.error.}` + custom `=destroy(a: Z3RcfNum)` calling `Z3_rcf_del`** | NOT a `ref` type — `=copy {.error.}` doesn't fire on ref aliases because ref-copy is pointer-copy not value-copy. Move-only contract requires plain `object`. Type name is `Z3RcfNum` (no `Own` suffix — the plain-object IS the public type since no ref alias exists). |
| Algebraic (N1.7a) | `z3_algebraic.h` | `Z3_inc_ref` | `Z3_dec_ref` | `wrap[T]` | Operates on `Z3_ast` for algebraic numbers. |
| Spacer (N1.7b) | `z3_spacer.h` | (uses Fixedpoint lifecycle) | (uses Fixedpoint lifecycle) | extends `Z3Fixedpoint` | No new opaque types. |
| `Z3Simplifier` (N8.7) | `z3.h` (Z3 ≥ 4.12) | `Z3_simplifier_inc_ref` | `Z3_simplifier_dec_ref` | `emitRefcountLifecycle(Z3SimplifierOwn, Z3_simplifier_dec_ref)` | Plain `object` + `ref` alias pattern. |
| `Z3Propagator` (N8.4) | `z3.h` | (none — user-managed) | (none — solver-scoped) | Custom: `Z3Propagator = ref Z3PropagatorOwn` holding strong refs to `PropagatorCtxBox` + sub-solver `seq[PropagatorCtxBox]` registry | See ADR-N0004 (revised in v3 for sub-solver registration table). |

**Critical clarifications (v3):**

1. **`Z3RcfNum` cannot be a `ref` type** — ref-copy in Nim is pointer-copy, which `=copy {.error.}` does not intercept. The move-only contract requires plain `object`. Common pattern documentation must accompany this (see N1.6 v3).

2. **`Z3Set[E] = distinct Z3Array[E, Z3Bool]` does NOT inherit lifecycle hooks** — Nim `distinct` requires explicit re-declaration of `=destroy`/`=copy`/`=dup`. Without them, double-free is silent. N1.1 v3 ships the explicit delegation procs.

3. **`emitTermLifecycle` is for plain `object` value types** (e.g., `Z3Char`, `Z3RoundingMode`). Every existing ref-counted handle (`Z3SolverOwn`, `Z3ModelOwn`, `Z3OptimizeOwn`) uses `emitRefcountLifecycle`. v2's `Z3AstMapOwn = ref object` + `emitTermLifecycle` was incoherent — corrected in v3.

4. **Nim 2.x `=destroy` signature is non-`var`:** `proc =destroy(v: T) {.raises: [].}` — NOT `proc =destroy(v: var T)` (Nim 1.x form). v3 corrects all custom destructor signatures.

### ADR-N0007: Z3 version policy + build gates (NEW in v2)

Round-1 Lens 2 M-B5 + M-B7 raised the minimum-Z3-version and build-gate questions.

**Minimum Z3 version:** **4.10.x** (matches existing CI floor). APIs added in later Z3 versions are gated at compile-time using the established `z3Without*` opt-out convention (v3 fix per round-2 Lens 2 H2):

| API | Min Z3 version | Gate define | Cycles affected |
|---|---|---|---|
| `Z3Simplifier` object | 4.12 | **`-d:z3WithoutSimplifierObject`** (opt-out; default OFF = available on 4.12+; set ON for 4.10/4.11 builds) | N8.7 |
| `Z3_mk_seq_replace_re` | 4.14+ (verified absent in 4.13.3.0) | `-d:z3WithSeqReplaceRe` (forward-compat opt-IN; default OFF) | N5.4 |
| `Z3_mk_seq_replace_all` | 4.14+ (verified absent in 4.13.3.0) | `-d:z3WithSeqReplaceAll` (forward-compat opt-IN; default OFF) | N5.4 |
| `Z3_mk_seq_last_index` | present in 4.13.3.0 | (no gate) | N5.4 |
| `Z3_solver_register_on_clause` | 4.12 | **`-d:z3WithoutOnClause`** (opt-out; default OFF = available on 4.12+) | N8.4 |
| `Z3_solver_propagate_*` | 4.10 | (no gate; available since min version) | N8.4 |
| Polynomial/RCF/Spacer/Algebraic | 4.10 | `-d:z3WithoutNonlinear` opt-out (default OFF; setting ON excludes all four modules) | N1.5/N1.6/N1.7 |

**Gate naming convention (v3 codified):**
- **`z3Without<X>`** = opt-OUT for features present in minimum supported Z3 version (default OFF means feature is available).
- **`z3With<X>`** = opt-IN for forward-compat features absent from minimum version (default OFF means feature is unavailable until user explicitly opts in for newer bundled Z3).

The `z3With*` form is reserved exclusively for features Z3 hasn't shipped yet at the minimum version; all other gates use `z3Without*` per the existing `src/z3.nim:254-266` convention.

**Coupling constraint (v3):** `-d:z3WithoutOnClause` and `-d:z3WithoutPropagator` are independent gates BUT the on_clause shim uses `PropagatorCtxBox`-style marshalling (separate `OnClauseBox` type — see N8.4d). If `-d:z3WithoutPropagator` is set AND `-d:z3WithoutOnClause` is unset, `propagator.nim` is excluded but `on_clause` still compiles (its `OnClauseBox` is defined in a separate module). No incoherent gate combination.

**Build flag map** (extends existing `z3WithoutX` family):
- `-d:z3WithoutSpacer` — excludes `spacer.nim` (Spacer engine may be stripped from some Z3 distributions).
- `-d:z3WithoutPolynomial` — excludes `polynomial.nim` (niche).
- `-d:z3WithoutRcf` — excludes `rcf.nim`.
- `-d:z3WithoutAlgebraic` — excludes `algebraic.nim`.
- `-d:z3WithoutPropagator` — excludes `propagator.nim` (callback machinery is intricate; some users won't want it).
- `-d:z3WithoutSets` / `WithoutAstMap` / `WithoutOrder` / `WithoutSimplifier` — granular controls.

`testMinimal` in `z3.nimble:125` updated in N11.7 to verify the no-new-modules build still compiles.

---

## Inventory — what's in scope

12 clusters (v1 had 11; v2 adds **N0** for ffi.nim preparatory refactor). **76 cycles + 7 ADRs = 83 work units** (v1 had 73+5=78; v2 adds 3 cycles net after consolidations: cycle splits +8, new audit-miss cycles +6, deletions −1, merges −2).

| Cluster | Theme | Cycles | Severity mix |
|---|---|---|---|
| **N0** | `ffi.nim` opaque-type refactor (NEW) | 1 | 1 MEDIUM (prerequisite) |
| N1 | Missing whole theories | 8 cycles (v1: 7; N1.7 split) | 7 CRITICAL |
| N2 | Model + introspection | 7 cycles (v1: 5; N2.4 split into a/b/c + new N2.6) | 1 HIGH, 6 MEDIUM |
| N3 | BV completeness | 4 cycles (v1: 4; N3.3+N3.4 merged, N3.2 reshaped) | 3 HIGH, 1 LOW |
| N4 | Arith completeness | 4 cycles | 3 HIGH, 1 MEDIUM |
| N5 | Strings + Seq | 7 cycles | 4 HIGH, 3 MEDIUM |
| N6 | FPA completeness | 9 cycles (v1: 7; N6.4 + N6.5 each split) | 5 HIGH, 4 LOW |
| N7 | Datatypes + Optimize + Fixedpoint | 9 cycles (v1: 8; N7.6 split a/b) | 4 HIGH, 5 MEDIUM |
| N8 | Solver + Tactic + Simplifier | 13 cycles (v1: 9; N8.4 split a/b/c; +1 each for on_clause, interrupt, print_mode, ast_vector_translate) | 3 HIGH, 10 MEDIUM |
| N9 | Pseudo-boolean + Order + Misc | 6 cycles (v1: 5; +1 for logging API) | 1 HIGH, 5 MEDIUM |
| N10 | Consistency + ergonomics pass | 11 cycles (v1: 12; N10.6 deleted) | 8 HIGH, 3 MEDIUM |
| N11 | Test hygiene + docs | 8 cycles (v1: 7; +1 for round-trip integration tests) | 8 LOW |

**Inter-cluster ordering (v2 tightened):**
- **N0 → all others** (ffi.nim opaque-type refactor blocks any new opaque handle types).
- N1 → all others.
- **N6 strictly before N10.2 + N10.5** (renames touch fp.nim identifiers; cannot be paired or reversed).
- **N7 strictly before N8** (datatype N-ary blocks proptest's exception-hierarchy work and is independent prerequisite for the typed simplifier surface).
- **Within N1: N1.7a (algebraic.nim) and N1.7b (spacer.nim) can land in parallel** (round-3 correction). Round-2 verification against `_audit_headers/z3_spacer.h` confirmed the 7 spacer entry points reference no algebraic types — the dependency is Z3-internal only, not in the C surface. v1+v2's claim of "Spacer consumes algebraic at the surface" was unfounded.
- **N8.4a (FFI) → N8.4b (types/registration) → N8.4c (consequence/nextSplit) → N8.4d (on_clause registration).**
- N11 lands last (its `runnableExamples` adoption can interleave).

---

## Cluster N0 — `ffi.nim` opaque-type refactor (NEW in v2)

### N0.1 — Consolidate opaque-type `isNil`/`==`/`!=` unions into a macro (CORRECTED in v3)

Round-1 Lens 4 MED-2 flagged the per-new-type registration tax (3 union expressions × 9 new types = 27 manual `ffi.nim` edits). v2 specified a non-existent `{.experimental: "templateDefining".}` pragma and the wrong macro signature; round-2 Lens 1 M1 + Lens 4 H3 caught the inspect-failure.

v3 specification:
- `import std/macros` added to `ffi.nim`.
- Standard Nim macro: `macro emitOpaqueOps(types: varargs[typed]): untyped` — NO experimental pragma required.
- Generates `isNil`/`==`/`!=` overloads for each type in the input list.
- Output lives OUTSIDE the `dynlib` block (the existing `isNil`/`==`/`!=` procs in `ffi.nim:112-152` are outside; the macro placement matches).
- Add `RawZ3AstMap`, `RawZ3RcfNum`, `RawZ3Simplifier`, `RawZ3PropagatorCtxBox` to the input list now so registrations are batched. **v5 → v5.1 correction (N0.1 implementer escalation):** the RFC originally listed `RawZ3OnClauseBox` as a 5th opaque handle. Verified against `z3_api.h`: `Z3_on_clause_eh` is declared via `Z3_DECLARE_CLOSURE` — a **function-pointer typedef**, NOT a `DEFINE_TYPE` opaque struct. Wrapping it as an opaque handle fails at C compile time (struct union over a function pointer is illegal C). The on-clause callback belongs in **N8.4d** as a proc-type alias (`type Z3OnClauseEh = proc(ctx: pointer, …)` `{.cdecl.}`), NOT in N0.1's opaque-handle batch. N0.1 ships 4 opaque handles; N8.4d adds the function-pointer alias.

RED tests: existing `ffi.nim`-touching tests stay green; new test exercises `isNil`/`==`/`!=` on each newly-registered raw handle type.

**~1.5h effort. Blocks N1.2, N1.6, N8.4, N8.7. Cluster N0 stays as separate cluster** (round-2 Lens 3 L1 suggested folding into N1.1; v3 keeps N0 because batching all 5 new raw handle types in one cycle is cleaner than threading the macro extension through 5 separate cycles).

---

## Cluster N1 — Missing whole theories

### N1.1 — `src/z3/sets.nim` (Z3Set[E])

Per ADR-N0001 (revised). FFI additions (note `Z3_mk_` prefix throughout — v1 dropped it in citation):

```
Z3_mk_set_sort, Z3_mk_empty_set, Z3_mk_full_set, Z3_mk_set_add, Z3_mk_set_del,
Z3_mk_set_union, Z3_mk_set_intersect, Z3_mk_set_difference, Z3_mk_set_complement,
Z3_mk_set_member, Z3_mk_set_subset, Z3_mk_set_has_size
```

`Z3_mk_set_union` and `Z3_mk_set_intersect` are **n-ary** (`(c, num_args, args[])`); FFI binding uses the `naryFFICall` pattern (same as `Z3Bool.mkAnd`/`mkOr`).

```nim
type Z3Set*[E] = distinct Z3Array[E, Z3Bool]

# Constructors
proc mkEmptySet*[E](ctx: Z3Context): Z3Set[E]
proc mkEmptySet*[E](_: typedesc[E]): Z3Set[E]
proc mkFullSet*[E](ctx: Z3Context): Z3Set[E]
proc mkFullSet*[E](_: typedesc[E]): Z3Set[E]

# Element ops (binary form)
proc add*[E](s: Z3Set[E], e: E): Z3Set[E]
proc del*[E](s: Z3Set[E], e: E): Z3Set[E]
proc member*[E](e: E, s: Z3Set[E]): Z3Bool

# Set ops (n-ary; varargs)
proc union*[E](a, b: Z3Set[E]): Z3Set[E]
proc union*[E](xs: varargs[Z3Set[E]]): Z3Set[E]
proc intersect*[E](a, b: Z3Set[E]): Z3Set[E]
proc intersect*[E](xs: varargs[Z3Set[E]]): Z3Set[E]
proc difference*[E](a, b: Z3Set[E]): Z3Set[E]
proc complement*[E](a: Z3Set[E]): Z3Set[E]
proc subset*[E](a, b: Z3Set[E]): Z3Bool
proc hasSize*[E](s: Z3Set[E], k: Z3Int): Z3Bool

# Conversions
proc toArray*[E](s: Z3Set[E]): Z3Array[E, Z3Bool] = Z3Array[E, Z3Bool](s)
proc toSet*[E](a: Z3Array[E, Z3Bool]): Z3Set[E] = Z3Set[E](a)

# Equality — must explicitly delegate via toArray (distinct loses ==)
proc `==`*[E](a, b: Z3Set[E]): Z3Bool = toArray(a) == toArray(b)
proc `!=`*[E](a, b: Z3Set[E]): Z3Bool = not (a == b)
proc `$`*[E](s: Z3Set[E]): string

# Lifecycle hooks — REQUIRED (v3 round-3 correction). Nim `distinct` does
# NOT propagate =destroy / =copy / =dup from the underlying type. Without
# explicit delegation procs, every copy of a Z3Set[E] would silently
# double-dec_ref both the original and copy on destruction.
proc `=destroy`[E](s: Z3Set[E]) {.raises: [].} =
  termDestroy(s)   # reads s.raw / s.ctx directly; works because distinct
                   # types share field layout with their base
proc `=copy`[E](dst: var Z3Set[E], src: Z3Set[E]) {.raises: [].} =
  termCopy(dst, src)
proc `=dup`[E](src: Z3Set[E]): Z3Set[E] {.raises: [].} =
  termDup(src)
```

RED test (v3 round-3 addition per Lens 3 finding 7): create a `Z3Set[int]`, copy it via `let b = a` (triggers `=copy`), drop the original `a`, verify `b` is still valid (no double-free).

RED tests: empty/full constructors; `add(empty, x).member(x)` valid; `subset(empty, any)` valid; `hasSize(union(empty, singleton(x)), 1)` valid; `==`/`!=` work; `toArray`/`toSet` round-trip preserves identity.

### N1.2 — `src/z3/astmap.nim` (Z3AstMap)

FFI additions: `Z3_mk_ast_map`, `Z3_ast_map_inc_ref`, `Z3_ast_map_dec_ref`, `Z3_ast_map_insert`, `Z3_ast_map_find`, `Z3_ast_map_contains`, `Z3_ast_map_erase`, `Z3_ast_map_reset`, `Z3_ast_map_size`, `Z3_ast_map_keys`, `Z3_ast_map_to_string`.

Lifecycle (v4 round-3 correction per ADR-N0006): `emitRefcountLifecycle(Z3AstMapOwn, Z3_ast_map_dec_ref)` — **plain `object`** + **`ref` alias** pattern (matches every other ref-counted handle in the codebase: `Z3SolverOwn`/`Z3Solver*`, `Z3ModelOwn`/`Z3Model*`, etc.). v2/v3 said `emitTermLifecycle` + `ref object` — that combination is incoherent (`emitTermLifecycle` is for plain value types only). v4 fixes both the macro name and the type kind.

```nim
type
  Z3AstMapOwn = object   # plain object (v4 correction; NOT ref object)
    raw: RawZ3AstMap
    ctx: Z3Context
  Z3AstMap* = ref Z3AstMapOwn   # ref alias (v4 correction)

proc newAstMap*(ctx: Z3Context): Z3AstMap
proc insert*[K, V: Z3Term](m: Z3AstMap, k: K, v: V)
proc find*[V: Z3Term](m: Z3AstMap, k: Z3AnyAst, _: typedesc[V]): Option[V] =
  ## Calls contains-then-find; returns none() when absent.
  if not m.contains(k): return none(V)
  some(V(raw: Z3_ast_map_find(...), ctx: m.ctx))
proc contains*(m: Z3AstMap, k: Z3AnyAst): bool
proc erase*(m: Z3AstMap, k: Z3AnyAst)
proc reset*(m: Z3AstMap)
proc len*(m: Z3AstMap): int
proc keys*(m: Z3AstMap): Z3AstVector
proc `$`*(m: Z3AstMap): string
```

RED tests: round-trip insert→find; contains-then-erase; len after insert-same-key multiple times.

### N1.3 — `src/z3/uninterpretedval.nim` (Z3UninterpretedVal[T])

Per ADR-N0002 (REVISED). Marker-phantom shape:

```nim
type Z3UninterpretedVal*[T] = object
  raw*: RawZ3Ast
  ctx*: Z3Context

# Registry plumbing (mirrors datatypes.nim's pattern)
proc declareUninterpretedSort*[T](ctx: Z3Context, name: string): Z3Sort[stUninterpreted]
  ## Creates a Z3_uninterpreted_sort with name, stores it in
  ## ctx.uninterpretedRegistry[$T] keyed on the marker type T.
proc sortOf*[T](_: typedesc[Z3UninterpretedVal[T]], ctx: Z3Context): RawZ3Sort =
  ## Looks up the registered sort for marker type T. Raises if not declared.
  ctx.uninterpretedRegistry[$T]

# Construction
proc mkUninterpretedVar*[T](name: string, ctx: Z3Context): Z3UninterpretedVal[T]
proc mkUninterpretedVar*[T](name: string): Z3UninterpretedVal[T]   # current-ctx

# Equality (statically constrained to same T)
proc `==`*[T](a, b: Z3UninterpretedVal[T]): Z3Bool
proc `!=`*[T](a, b: Z3UninterpretedVal[T]): Z3Bool
proc `$`*[T](v: Z3UninterpretedVal[T]): string

# Z3Array[Z3UninterpretedVal[T], V] instantiates via the standard sortOfType
# path because Z3UninterpretedVal[T].sortOf is now typedesc-level.
```

`context.nim` adds `uninterpretedRegistry*: Table[string, RawZ3Sort]` field on `Z3ContextOwn`, parallel to the existing `datatypeRegistry` field.

RED tests:
1. `declareUninterpretedSort[ColorSort](ctx, "Color")` returns a sort; `sortOf(Z3UninterpretedVal[ColorSort], ctx)` returns same handle.
2. Two `Z3UninterpretedVal[ColorSort]` values can be `==`'d producing a `Z3Bool`.
3. **`Z3UninterpretedVal[ColorSort]` and `Z3UninterpretedVal[LocSort]` are statically incompatible** — `not compiles(eq(colorVal, locVal))` (this is the compile-error contract v1 advertised but couldn't deliver).
4. `Z3Array[Z3UninterpretedVal[ColorSort], Z3Int]` instantiates via `sortOfType` without manual sort threading. **v5.1 implementer note (N1.3, Z3 4.15.0):** `Z3_mk_const_array` rejects an uninterpreted sort as its domain parameter (`invalid array sort definition, parameter is not a sort`). The "no manual sort wiring" property is exercised through `mkArrayVar[Key, Value]` instead, which also flows through `sortOf[K,V]` → `sortOfType[Key]`. Z3 quirk, not a wrapper bug.

### N1.4 — `datatypes.nim` N-ary `declareDatatypes` (REVISED in v3 per ADR-N0003 macro decision)

Per ADR-N0003 (v3): use `macro declareDatatypesGen(N: static int)` to generate the arity-N overload at compile time. Call sites:

```nim
# In datatypes.nim, after the existing arity-2/3 hand-written procs:
declareDatatypesGen(4)
declareDatatypesGen(5)
declareDatatypesGen(6)
declareDatatypesGen(7)
declareDatatypesGen(8)

# Each call expands to a proc declareDatatypes*[T1, ..., TN](
#   ctx: Z3Context, d1: DatatypeSpec[T1], ..., dN: DatatypeSpec[TN]
# ): (Z3DatatypeDecl[T1], ..., Z3DatatypeDecl[TN])
# overloaded on arity via type-parameter count.

# Plus the seq-form escape hatch (hand-written, not macro):
proc declareDatatypesN*(ctx: Z3Context,
    specs: openArray[(string, seq[ConstructorSpec])]):
    seq[Z3DatatypeDecl[void]]
```

Macro body sketch (~50-80 lines):
```nim
macro declareDatatypesGen(N: static int): untyped =
  # 1. Build N typedesc params [T1, T2, ..., TN]
  # 2. Build proc signature: declareDatatypes*[T1..TN](ctx, d1: DatatypeSpec[T1], ..., dN: DatatypeSpec[TN])
  # 3. Build return type: nnkTupleConstr.newTree(N entries of Z3DatatypeDecl[Ti])
  # 4. Build body with N repetitions of each pattern group:
  #    - nameToIdx[$Ti] = i-1
  #    - buildRawConstructors call into work[i-1]
  #    - doAssert constructor.len > 0
  #    - registry.add($Ti, declAt(i-1))
  # 5. Build Z3_mk_datatypes call with N-element arrays seqs
  # 6. Build N queryConstructorsInto + N Z3_del_constructor_list cleanup
  # 7. Build N-tuple return expression
  result = newTree(nnkProcDef, ...)
```

The arity-2 (`datatypes.nim:379`) and arity-3 (`datatypes.nim:457`) hand-written overloads remain as canonical reference forms — the macro must produce structurally equivalent output, verifiable via code-emission diffing.

RED tests: 4-way mutually-recursive `(Stmt, Expr, Type, Kind)`; 8-way arity stress (using simple variant types); seq-form returns correct count; macro-generated arity-4 produces same Z3-side result as hand-written arity-4 (sanity).

### N1.5 — `polynomial.nim` (MERGED into `algebraic.nim` per Lens 3 M5)

v1 had `polynomial.nim` as a one-proc module wrapping `Z3_polynomial_subresultants`. v2 merges this single proc into `algebraic.nim` to avoid a one-proc module. Cluster count for N1 stays the same because N1.7 splits.

The `subresultants` proc lands in N1.7a:

```nim
proc subresultants*(p, q, x: Z3AnyAst): Z3AstVector
  ## Returns the subresultant chain of polynomials p and q in variable x.
```

RED test (formerly N1.5): `subresultants(x², x+1, x)` returns a `Z3AstVector` of length 3; the first element evaluates to a nonzero constant (the resultant); the chain is non-empty. (v1's RED test was unspecified beyond "expected subresultant chain" — v2 names the exact assertion.)

### N1.6 — `src/z3/rcf.nim` (Real Closed Field) — REWRITTEN AGAIN in v3 per round-2 Lens 1 H1 + Lens 4 H4

Per ADR-N0006 (v3): `Z3RcfNum` is **plain `object`** (NOT `ref object`) with single `Z3_rcf_del` destructor and `=copy` `{.error.}`. The `ref object` form in v2 was wrong because Nim's ref-copy is pointer-copy and `=copy {.error.}` only intercepts value-copies. Move-only semantics require plain `object`.

**Depends on N0.1** — `RawZ3RcfNum` must be added to the `isNil`-supporting opaque-type tagged union in `ffi.nim` so `a.raw.isNil` works in `=destroy`. The Z3_rcf_num handle is an opaque C pointer; without N0.1's plumbing the destructor cannot guard against destroying a moved-from value.

Nim 2.x `=destroy` signature is `proc =destroy(a: T)` (no `var`; T is the owned plain-object type).

FFI additions: `Z3_rcf_del`, `Z3_rcf_mk_rational`, `Z3_rcf_mk_small_int`, `Z3_rcf_mk_pi`, `Z3_rcf_mk_e`, `Z3_rcf_mk_infinitesimal`, `Z3_rcf_add`, `Z3_rcf_sub`, `Z3_rcf_mul`, `Z3_rcf_div`, `Z3_rcf_neg`, `Z3_rcf_inv`, `Z3_rcf_power`, `Z3_rcf_lt`, `Z3_rcf_le`, `Z3_rcf_gt`, `Z3_rcf_ge`, `Z3_rcf_eq`, `Z3_rcf_neq`, `Z3_rcf_num_to_string`, `Z3_rcf_num_to_decimal_string`.

```nim
type
  Z3RcfNum* = object   # plain object, move-only (NOT a ref type per v3 correction)
    raw*: RawZ3RcfNum
    ctx*: Z3Context

# Constants — RFC v1's mkRational signature was wrong (took int64); fixed:
proc mkRational*(ctx: Z3Context, numerator, denominator: int): Z3RcfNum
  ## Wraps Z3_rcf_mk_rational which takes a decimal string;
  ## implementation formats "$numerator/$denominator" internally.
proc mkSmallInt*(ctx: Z3Context, n: int): Z3RcfNum   # Z3_rcf_mk_small_int
proc mkPi*(ctx: Z3Context): Z3RcfNum
proc mkE*(ctx: Z3Context): Z3RcfNum
proc mkInfinitesimal*(ctx: Z3Context): Z3RcfNum

# Arithmetic
proc `+`*(a, b: Z3RcfNum): Z3RcfNum
proc `-`*(a, b: Z3RcfNum): Z3RcfNum
proc `*`*(a, b: Z3RcfNum): Z3RcfNum
proc `/`*(a, b: Z3RcfNum): Z3RcfNum
proc `-`*(a: Z3RcfNum): Z3RcfNum
proc inv*(a: Z3RcfNum): Z3RcfNum
proc `^`*(a: Z3RcfNum, k: int): Z3RcfNum

# Ordering
proc `<`*(a, b: Z3RcfNum): bool
proc `<=`*(a, b: Z3RcfNum): bool
proc `>`*(a, b: Z3RcfNum): bool
proc `>=`*(a, b: Z3RcfNum): bool
proc `==`*(a, b: Z3RcfNum): bool
proc `!=`*(a, b: Z3RcfNum): bool

# Conversion — RFC v1's $ signature dropped html; fixed:
proc `$`*(a: Z3RcfNum, compact = false, html = false): string
proc toDecimalString*(a: Z3RcfNum, precision: int): string

# Lifecycle hooks (v3 — Nim 2.x signatures; plain object)
proc `=destroy`(a: Z3RcfNum) {.raises: [].} =
  if not a.raw.isNil and a.ctx != nil and not a.ctx.raw.isNil:
    Z3_rcf_del(a.ctx.raw, a.raw)
proc `=copy`(dst: var Z3RcfNum, src: Z3RcfNum) {.error: "Z3RcfNum is move-only; produce a new value via re-derivation (e.g., `a + mkSmallInt(ctx, 0)`)".}
proc `=dup`(src: Z3RcfNum): Z3RcfNum {.error: "Z3RcfNum is move-only; produce a new value via re-derivation".}
```

**Move-only common-pattern documentation (v3 per round-2 Lens 3 M1):**

```nim
# WORKS: arithmetic produces a fresh value (move semantics through expressions)
let result = mkPi(ctx) + mkE(ctx)

# WORKS: returning from a proc (move into the result slot)
proc compute(ctx: Z3Context): Z3RcfNum =
  result = mkPi(ctx) * mkSmallInt(ctx, 2)

# FAILS to compile (=copy error): rebinding shares no semantics
# let x = result; let y = result   # second binding triggers =copy

# WORKS: introduce a fresh derived value
let x = result
let y = result + mkSmallInt(ctx, 0)   # re-derive — `+` produces a new node

# FAILS: seq[Z3RcfNum].add requires =copy
# var xs: seq[Z3RcfNum]; xs.add(mkPi(ctx))   # =copy fires

# Workaround for collections: Z3RcfNum is NOT a Z3 AST (it's a separate
# Z3_rcf_num handle, lifecycle managed via Z3_rcf_del), so Z3AstVector
# does NOT apply. Options:
#   (a) store the underlying RawZ3RcfNum pointers in a `seq[RawZ3RcfNum]`
#       and re-wrap on demand (caller responsible for not double-freeing);
#   (b) store the symbolic recipe (e.g., a tuple of operations) and
#       re-derive the Z3RcfNum on demand;
#   (c) wrap each in a `ref Z3RcfNum` indirection at the call site (the
#       move-only contract applies to the value type, not heap-allocated
#       references to it — but you lose the ergonomics of `=destroy`).
```

RED tests:
1. `2 + π > 5` is true (relational, no algebraic dep — Lens 4 MED-1 note: don't use algebraic.nim from N1.6 tests).
2. `mkE() * mkE() ^ 0 == mkE()` is true.
3. `mkRational(1, 2) + mkRational(1, 2) == mkSmallInt(1)` is true.
4. `=copy` fails to compile. **v5.1 implementer correction (N1.6):** Nim's `compiles()` does NOT check pragma enforcement — it returns `true` even when `=copy` is `{.error.}`. The test must instead be a `when false:` documentation block showing the snippet that fails, with reliance on direct `nim c` to enforce. The enforcement is verified by build-time compilation, not by runtime `compiles()`.

### N1.7a — `algebraic.nim` (split from v1's N1.7)

FFI additions: `Z3_algebraic_is_value`, `Z3_algebraic_is_pos`, `Z3_algebraic_is_neg`, `Z3_algebraic_is_zero`, `Z3_algebraic_sign`, `Z3_algebraic_add`, `Z3_algebraic_sub`, `Z3_algebraic_mul`, `Z3_algebraic_div`, `Z3_algebraic_neg`, `Z3_algebraic_root`, `Z3_algebraic_power`, `Z3_algebraic_lt`, `Z3_algebraic_le`, `Z3_algebraic_gt`, `Z3_algebraic_ge`, `Z3_algebraic_eq`, `Z3_algebraic_neq`, `Z3_algebraic_roots`, `Z3_algebraic_eval`, plus `Z3_polynomial_subresultants` (merged from former N1.5).

Lifecycle: standard `wrap[T]` via Z3_ast inc/dec_ref.

RED tests: sqrt(2) (via `algebraic_root(mkRcf(2), 2)`) squares to 2; algebraic comparison; `roots(x²−2)` returns 2 ASTs; `subresultants(x², x+1, x)` non-empty.

### N1.7b — `spacer.nim` (split from v1's N1.7)

Depends on N1.7a. FFI additions: `Z3_fixedpoint_query_from_lvl`, `Z3_fixedpoint_add_invariant`, `Z3_fixedpoint_get_ground_sat_answer`, `Z3_fixedpoint_get_rules_along_trace`, `Z3_model_extrapolate`, `Z3_qe_lite`, `Z3_qe_model_project`.

Build gate: `-d:z3WithoutSpacer` excludes the module (Spacer may be stripped from some Z3 distros).

---

## Cluster N2 — Model + introspection

### N2.1 — Model enumeration API

Same as v1: `Z3_model_get_num_consts/_const_decl/_num_funcs/_func_decl/_num_sorts/_sort/_sort_universe/_has_interp/_translate`.

**v5.1 Z3 4.15.0 quirk (implementer note):** `Z3_mk_context_rc` (which `newContext` uses for refcount-managed lifecycle) interacts badly with uninterpreted sort constants in Z3 4.15: passing them to `Z3_mk_distinct`/`Z3_mk_eq`/`Z3_mk_app` SIGSEGVs. Affects `Z3_mk_const` AND `Z3_mk_fresh_const`. Reproduces in pure C. **Workaround:** use `Z3_parse_smtlib2_string` / `loadSmt2String` to construct uninterpreted-sort terms — that path is unaffected. Used in N2.1's `sortUniverse` test (see `tests/tmodel_enum.nim`).

### N2.2 — Model construction API

Same as v1: `Z3_mk_model/_add_const_interp/_add_func_interp/_func_interp_set_else/_func_interp_add_entry`.

### N2.3 — Datatype sort introspection

Same as v1: `Z3_get_datatype_sort_num_constructors/_constructor/_recognizer/_constructor_accessor`.

### N2.4a — Decl name/arity/domain/range introspection (split per Lens 4 MED-6)

`Z3_get_decl_name`, `Z3_get_domain_size` (NOT `Z3_get_decl_arity` — that name doesn't exist in the C API), `Z3_get_domain`, `Z3_get_range`, `Z3_get_func_decl_id`. ~5 procs, returns typed values.

### N2.4b — Decl parameter introspection (split per Lens 4 MED-6)

`Z3_get_decl_num_parameters/_parameter_kind/_int/_double/_symbol/_sort/_ast/_func_decl/_rational_parameter`. ~9 procs. Returns `Z3_parameter_kind`-tagged sum-type — design the Nim sum type in the cycle.

### N2.4c — AST-level introspection (split per Lens 4 MED-6)

`Z3_is_well_sorted/_is_app/_is_numeral_ast/_get_ast_id/_get_sort_id/_get_index_value`. ~6 procs. Plus `Z3_get_global_param_descrs` (Lens 2 M-B2) and `Z3_mk_type_variable` (Lens 2 M-B4).

### N2.5 — Quantifier ID + skolem ID + substituteVars

Same as v1.

**v5.1 implementer correction (N2.5):** `Z3_get_quantifier_id` and `Z3_get_quantifier_skolem_id` return `Z3_symbol` (NOT `int`). Nim surface uses `string` via `Z3_get_symbol_string`, which uniformly handles both int-kind and string-kind symbols. Unnamed quantifiers built via `mk_forall_const` produce int-symbol `"0"`. `substituteVars` already exists generically in `rewrite.nim` as `substituteVars[T: Z3Term](a, replacements)` — no duplication needed.

### N2.6 — N-ary quantifier escape hatch (NEW per Lens 2 C-B1)

```nim
proc forallN*(bound: openArray[Z3AnyAst], body: Z3Bool,
              patterns: openArray[Z3Pattern] = []): Z3Bool
proc existsN*(bound: openArray[Z3AnyAst], body: Z3Bool,
              patterns: openArray[Z3Pattern] = []): Z3Bool
```

Wraps the existing `quantifierImpl(ctx, isForall, bound, body, patterns)` (currently private). Public escape hatch for arity > 5 (the per-arity templates 1–5 stay as the ergonomic surface).

---

## Cluster N3 — BV completeness

### N3.1 — Overflow / underflow predicates

Same as v1. All 8 predicates.

### N3.2 — Reduction + extended rotation (REVISED in v3 per round-2 Lens 1 C2)

v1 + v2 tried two forms of per-bit BV assembly; both wrong. v1's `array[W, bool]` is unusable for large W. v2's `array[W, Z3Bool]` claimed to wrap `Z3_mk_bv_numeral` — that C function takes `bool const*` (concrete C booleans), NOT `Z3_ast*`. The symbolic-per-bit assembly has **no Z3 primitive**.

v3 drops the proc entirely. Users do explicit `concat`-chain over `Z3BitVec[1]` values, which is exactly the Z3-encoded form Z3's internal AST would produce anyway:

```nim
proc redAnd*[W: static int](a: Z3BitVec[W]): Z3BitVec[1]
proc redOr*[W: static int](a: Z3BitVec[W]): Z3BitVec[1]
proc extRotateLeft*[W: static int](a, b: Z3BitVec[W]): Z3BitVec[W]
proc extRotateRight*[W: static int](a, b: Z3BitVec[W]): Z3BitVec[W]

# REMOVED in v3: mkBitVecFromBools (no Z3 primitive exists).
# Symbolic per-bit assembly: concat(b[W-1], concat(b[W-2], ..., concat(b[1], b[0])))
# where each b[i]: Z3BitVec[1] is produced from a Z3Bool via toBitVec (N3.3).
# Nim-side compile-time constants: mkBigBitVec[W]("0b101010...").
```

### N3.3 — Public theory conversions (merged with v1's N3.4 per Lens 3 M2 + Lens 4 LOW-2)

Both BV↔Int theory conversions + Bool→BV[1] derived form land in one cycle.

```nim
# Theory-level conversions (NOT named `toInt` to avoid collision with the
# existing Z3BitVec[W].toInt model-extractor):
proc bvToInt*[W: static int](a: Z3BitVec[W], signed: bool = false): Z3Int  # Z3_mk_bv2int
proc intToBv*[W: static int](a: Z3Int, _: typedesc[Z3BitVec[W]]): Z3BitVec[W]  # Z3_mk_int2bv

# Bool → BV[1] — derived via ite (no Z3 primitive exists; v1 incorrectly
# implied a direct FFI binding):
proc toBitVec*(b: Z3Bool): Z3BitVec[1] =
  ite(b, mkBitVec[1](1), mkBitVec[1](0))
```

RED tests: `bvToInt(mkBitVec[8](42), signed=false)` equals `mkInt(42)`; `toBitVec(mkTrue()).toUint == 1`; `toBitVec(mkFalse()).toUint == 0`.

**`bvToInt` naming rationale (v5 per round-4 Lens 4 CRIT-1):** the `bvToInt` / `intToBv` pair deliberately follows the established `<src>To<dst>` shape used by `bvToFpBits` (N6.7) and the existing `Z3BitVec[W].toInt` / `Z3BitVec[W].toUint` model extractors. The theory-level conversion is a *constraint* over symbolic AST (returns a `Z3Int` expression node), while `Z3BitVec[W].toInt` is a *model extractor* (returns a Nim `int64` from a concrete model). Using `bvToInt` for the theory form and `Z3BitVec[W].toInt` for the model form keeps both inside the same naming family without collision — Nim's overload resolution distinguishes them by return type and arg pattern. An earlier proposal to call this `mkBv2Int` was rejected because it leaks Z3's C-side `Z3_mk_bv2int` shape into the Nim surface.

### N3.4 — (was the standalone `toBitVec(Z3Bool)` — merged into N3.3)

REMOVED. v1's N3.4 is now part of N3.3.

---

## Cluster N4 — Arith completeness

### N4.1 — abs/power/divides/isInt/mkRealInt64

Same as v1.

### N4.2 — int2real / real2int / is_int

Same as v1 (FFI additions: `Z3_mk_int2real`, `Z3_mk_real2int`, `Z3_mk_is_int`).

### N4.3 — Algebraic number polynomial + index introspection (REVISED v5.1 per implementer escalation)

**v1's spec was wrong.** `Z3_algebraic_get_lower(a, precision)` and `Z3_algebraic_get_upper(a, precision)` do **NOT exist** in the Z3 C API (verified against `_audit_headers/z3_algebraic.h` — 18 functions total, no precision-parameterized bound extraction). v5.1 reframes the slice as exposing the two existing FFI entries `Z3_algebraic_get_poly` and `Z3_algebraic_get_i`:

```nim
proc algebraicGetPoly*(a: Z3Real): Z3AstVector
  ## Returns the defining polynomial of an algebraic number as a vector of
  ## coefficient ASTs (constants in the polynomial sort, from low-degree to
  ## high-degree). Wraps Z3_algebraic_get_poly.
proc algebraicGetI*(a: Z3Real): int
  ## Returns the index of this algebraic number among the roots of its
  ## defining polynomial (1-based, ordered by value). Wraps Z3_algebraic_get_i.
```

These are the actual building blocks; users who need rational isolation bounds can compute them via Cauchy's bound on the returned polynomial coefficients. Implementing those bounds in nim-z3 is out of scope for v1.0 (no Z3 API support; would require ~100 lines of pure-Nim rational arithmetic + Newton refinement).

### N4.4 — Option extractors + int64 consistency (CLARIFIED per Lens 3 M4 + Lens 4 MED-3)

**Scope clarification:** N4.4 covers **arith-side** extractors only:
- Add `Z3Int.toIntOpt` returning `Option[int]`.
- Add `Z3Real.toRealOpt` returning `Option[float]`.
- **Rename `Z3Int.toInt` → `Z3Int.toInt64`** for consistency with `Z3BitVec[W].toInt` which already returns `int64`. Hard rename, no deprecation alias (per ADR-N0005).

**N4.4 does NOT cover `Z3BitVec[W].toUintOpt`/`toIntOpt`** — those land in N10.7 (BV consistency pass) to avoid dual-cycle coverage. Cross-reference noted.

---

## Cluster N5 — Strings + Seq completeness

### N5.1 — String ordering

Same as v1.

### N5.2 — Codepoint conversion + BV-to-string

Same as v1.

### N5.3 — `Z3_get_string_contents` + `Z3_get_string_length`

Same as v1.

### N5.4 — Sequence ops with Z3 version gates (REVISED per Lens 1 H7 + Lens 4 MED-4)

**Hard-fact verified against bundled Z3 4.13.3.0 headers (`_audit_headers/z3_api.h`):**

| Proc | Status in 4.13.3.0 | Gate |
|---|---|---|
| `Z3_mk_seq_last_index` | **present** (line 3806) | (no gate — always available) |
| `Z3_mk_seq_replace_all` | **absent** | `-d:z3WithSeqReplaceAll` (default OFF; future Z3 ≥ 4.14) |
| `Z3_mk_seq_replace_re` | **absent** | `-d:z3WithSeqReplaceRe` (default OFF; future Z3 ≥ 4.14) |

Implementation: ship `last_index` unconditionally; the two `replace_*` procs land in `sequence.nim` under `when defined(z3WithSeqReplaceAll)` and `when defined(z3WithSeqReplaceRe)` gates. Per ADR-N0007.

```nim
proc lastIndexOf*[E](a, sub: Z3Seq[E]): Z3Int
when defined(z3WithSeqReplaceAll):
  proc replaceAll*[E](a, old, new: Z3Seq[E]): Z3Seq[E]
when defined(z3WithSeqReplaceRe):
  proc replaceRe*[E](a: Z3Seq[E], pattern: Z3Regex[Z3Seq[E]],
                     replacement: Z3Seq[E]): Z3Seq[E]
```

### N5.5 — Seq HOF (REVISED per Lens 1 M6)

`mapi` / `foldli` take a starting-index `i: Z3Int` parameter (per `Z3_mk_seq_mapi(c, f, i, s)`). v1 omitted this — silent FFI mismatch.

**Arg-order verification (v5):** confirmed against `_audit_headers/z3_api.h` — `Z3_mk_seq_foldli(c, f, i, a, s)` orders arguments as `(context, func, starting-index, accumulator, sequence)`. The Nim wrapper below matches this order verbatim (`startIdx`, `init`, `s`). Implementers MUST cite the header line in the cycle commit message when landing this — past audits caught silent FFI arg-order mismatches in similar HOF wrappings.

```nim
proc seqMap*[E, F](f: Z3FuncDecl[tuple[a: E], F],
                   s: Z3Seq[E]): Z3Seq[F]   # Z3_mk_seq_map
proc seqMapi*[E, F](f: Z3FuncDecl[tuple[i: Z3Int, a: E], F],
                    startIdx: Z3Int, s: Z3Seq[E]): Z3Seq[F]   # Z3_mk_seq_mapi
proc seqFoldl*[E, A](f: Z3FuncDecl[tuple[a: A, e: E], A],
                     init: A, s: Z3Seq[E]): A   # Z3_mk_seq_foldl
proc seqFoldli*[E, A](f: Z3FuncDecl[tuple[i: Z3Int, a: A, e: E], A],
                      startIdx: Z3Int, init: A, s: Z3Seq[E]): A   # Z3_mk_seq_foldli
```

### N5.6 — Seq index `int`-literal lifts

Same as v1.

### N5.7 — Eval shortcuts + naming sweep

Same as v1.

---

## Cluster N6 — FPA completeness

### N6.1 — DELETED in v3 (3-lens consensus: round-1 Lens 1 + round-2 Lens 3 + round-2 Lens 4)

v1+v2's N6.1 was a docs-only cycle (update `fp.nim` doc comments to reference SMT-LIB long rounding-mode names). Round-2 review found this had no RED test, no implementation, no GREEN phase — same orphan-cycle pattern that got N10.6 deleted earlier. The doc-comment update folds into **N10.4** (module doc-header sweep). N10.4's scope is extended in v3 to include the rounding-mode SMT-LIB long-name doc additions.

### N6.2 — Sort aliases (CORRECTED per Lens 1 H5)

`Z3Float16 = Z3Fp[5, 11]` and `Z3Float128 = Z3Fp[15, 113]` **already exist** in `fp.nim:70, 73`. v1 sloppily proposed to "Add" them — that's the [[inspect-before-pessimizing]] failure mode again. v2 ships only the missing sort-handle constructors:

```nim
# All return typed Z3Sort[stFp], not RawZ3Sort (per Lens 1 L2):
proc mkFpSortHalf*(ctx: Z3Context): Z3Sort[stFp]       # Z3_mk_fpa_sort_half
proc mkFpSortSingle*(ctx: Z3Context): Z3Sort[stFp]     # Z3_mk_fpa_sort_single
proc mkFpSortDouble*(ctx: Z3Context): Z3Sort[stFp]     # Z3_mk_fpa_sort_double
proc mkFpSortQuadruple*(ctx: Z3Context): Z3Sort[stFp]  # Z3_mk_fpa_sort_quadruple
```

Existing `mkFpVar[Z3Float16](name)` / `mkFpVar[Z3Float128](name)` patterns continue to work via the existing typed-family dispatch.

### N6.3 — `mkFpFromParts` (CORRECTED per Lens 1 H4)

`Z3_mk_fpa_fp(c, sgn, exp, sig)` takes **no rounding mode** — it's an exact bit-pattern assembly. v1's signature wrongly included `rm: Z3RoundingMode`. Corrected:

```nim
proc mkFpFromParts*[E, S: static int](sgn: Z3BitVec[1], exp: Z3BitVec[E],
                                       sig: Z3BitVec[S]): Z3Fp[E, S]
  ## Assembles an FP value from sign/exponent/significand bit vectors.
  ## No rounding — this is bit-exact assembly. For lossy float-to-FP,
  ## use toFp(rm, fp, _: typedesc[Z3Fp[E,S]]).
```

### N6.4a — FPA numeral predicates (split from v1's N6.4 per Lens 4 HIGH-3)

7 predicates returning `bool`:

```nim
proc isNumeralNaN*(a: Z3Fp): bool        # Z3_fpa_is_numeral_nan
proc isNumeralInf*(a: Z3Fp): bool        # Z3_fpa_is_numeral_inf
proc isNumeralZero*(a: Z3Fp): bool       # Z3_fpa_is_numeral_zero
proc isNumeralNormal*(a: Z3Fp): bool     # Z3_fpa_is_numeral_normal
proc isNumeralSubnormal*(a: Z3Fp): bool  # Z3_fpa_is_numeral_subnormal
proc isNumeralPositive*(a: Z3Fp): bool   # Z3_fpa_is_numeral_positive
proc isNumeralNegative*(a: Z3Fp): bool   # Z3_fpa_is_numeral_negative
```

**v5.1 implementer caveat (N6.4a):** `Z3_fpa_is_numeral_*` predicates only fire on **true numeral AST nodes**. `mkFpFromParts` (N6.3) produces an `fpa.fp(...)` application node — even with concrete BV inputs — and silently returns `false` for every predicate. Use `mkFloat32`/`mkFloat64`/`mkFpFromFloat` (constants built via `Z3_mk_fpa_numeral_*`) when you need the numeral predicates to apply.

### N6.4b — FPA numeral decomposition (CORRECTED in v3 per round-2 Lens 1 H2)

v2 invented an `isNormalised: bool` field on `getNumeralSignificandUint64`'s tuple return. The C signature (`z3_fpa.h:1257`) is `bool Z3_API Z3_fpa_get_numeral_significand_uint64(Z3_context c, Z3_ast t, uint64_t * n)` — the `bool` return is a success/fail flag, and `n` is the output. There is NO `isNormalised` output. v3 corrects to `Option[uint64]`:

```nim
proc getNumeralSign*(a: Z3Fp): Option[bool]
  ## None when a is not a numeral; Some(sign) otherwise (true = negative).
proc getNumeralSignificandString*(a: Z3Fp): string
proc getNumeralSignificandBv*[E, S: static int](a: Z3Fp[E, S]): Z3BitVec[S]
proc getNumeralSignificandUint64*(a: Z3Fp): Option[uint64]
  ## None when not a numeral or significand doesn't fit uint64; Some(value) otherwise.
proc getNumeralExponentString*(a: Z3Fp, biased: bool = false): string
proc getNumeralExponentInt64*(a: Z3Fp, biased: bool = false): Option[int64]
  ## None when not a numeral or exponent doesn't fit int64; Some(value) otherwise.
proc getNumeralExponentBv*[E, S: static int](a: Z3Fp[E, S], biased: bool = false): Z3BitVec[E]
```

### N6.5a — FPA comparison literal lifts (split from v1's N6.5 per Lens 3 H4)

**Semantics decision (v5 per round-4 Lens 3 H1):** the `==` overload uses **`Z3_mk_fpa_eq` (IEEE 754 equality)**, NOT `Z3_mk_eq` (structural AST equality). IEEE equality means `NaN == NaN` is false and `+0.0 == -0.0` is true — matching float comparison semantics in Nim, C, and SMT-LIB FP theory. Structural FP equality (`+0 ≠ −0`, `NaN = NaN`) is omitted from the `==` overload because it would silently misbehave for users writing `r == 0.0`. Users who need structural equality can call `Z3_mk_eq` directly via the FFI surface; this is rare and intentionally awkward.

6 comparison overloads for `float64` (and `float32` for `Z3Float32`):

```nim
proc `==`*[E, S: static int](a: Z3Fp[E, S], b: float64): Z3Bool
proc `==`*[E, S: static int](a: float64, b: Z3Fp[E, S]): Z3Bool
proc `!=`*[E, S: static int](a: Z3Fp[E, S], b: float64): Z3Bool
proc `!=`*[E, S: static int](a: float64, b: Z3Fp[E, S]): Z3Bool
proc `<`*[E, S: static int](a: Z3Fp[E, S], b: float64): Z3Bool
proc `<`*[E, S: static int](a: float64, b: Z3Fp[E, S]): Z3Bool
# ... + <=, >, >=, all symmetric pairs
```

Plus parallel `float32` overloads for `Z3Float32`.

### N6.5b — FPA arithmetic literal lifts (split from v1's N6.5)

4 arithmetic overloads:

```nim
proc `+`*[E, S: static int](a: Z3Fp[E, S], b: float64): Z3Fp[E, S]
proc `+`*[E, S: static int](a: float64, b: Z3Fp[E, S]): Z3Fp[E, S]
# ... + -, *, /, all symmetric pairs; rounding via implicit rmRNE (default)
```

The `liftBin`/`liftCmp` templates in `bitvec.nim:342-370` are extended to `Z3Fp[E, S]` — but the lift constructor is `mkFp[E, S](v: float64)`, not `mkBitVec[W](v)`. New templates `liftFpBin` / `liftFpCmp` in `fp.nim`.

### N6.6 — Option extractors + generic evalFp (CLARIFIED)

```nim
proc toFloat64Opt*(a: Z3Float64): Option[float]
proc toFloat32Opt*(a: Z3Float32): Option[float32]
proc evalFp*[E, S: static int](m: Z3Model, a: Z3Fp[E, S]): Z3Fp[E, S]
  ## Generic over arbitrary [E, S]; replaces the width-pinned
  ## evalFloat32/evalFloat64 with a parametric form.
```

### N6.7 — Renames (REVISED per ADR-N0005)

- `mkNaN` → `mkFpNaN`, `mkInf` → `mkFpInf`, `mkZero` → `mkFpZero` — hard breaks in 2.0.0. No deprecated aliases.
- `toFp(bv, _: typedesc[Z3Fp[E,S]])` → `bvToFpBits` — hard break.
- Extends `optimize.maximize`/`minimize` constraint set to allow `Z3Fp` objectives.

**v5.1 implementer caveat (N6.7):** Z3 `Z3_optimize_maximize`/`minimize` accept any AST in C signature but **categorically reject FP objectives at runtime** (`Z3_EXCEPTION: Objective must be bit-vector, integer or real`). Nim overloads compile and dispatch; users get `Z3OperationError` at solve time. Wrapper is correct — Z3 itself does not support FP optimization at v4.15. Tests document this via try/catch.

---

## Cluster N7 — Datatypes + Optimize + Fixedpoint

### N7.1 — Datatypes: enumeration sort

Same as v1.

### N7.2 — Datatypes: tuple sort

Same as v1.

### N7.3 — Datatypes: recursive function definitions

Same as v1.

### N7.4 — Datatypes: `update_field` (CLARIFIED per Lens 1 L4)

```nim
proc updateField*[T, Ret](a: Z3AccessorDecl[T, Ret],
                          record: Z3DatatypeValue[T],
                          newVal: Ret): Z3DatatypeValue[T]
  ## Functional record update: `{record with a = newVal}`.
  ## Wraps Z3_datatype_update_field; takes the accessor decl
  ## (not a string name), the record, and the new value.
```

**Type prerequisite (v5):** `Z3AccessorDecl[T, Ret]` **already exists** at `src/z3/datatypes.nim:149` — it is the typed wrapper Nim emits from `declareDatatypes` for each accessor in a datatype constructor. N7.4 introduces no new type; the cycle only adds the `updateField` proc that consumes the existing decl. Implementers should not redeclare this type.

### N7.5 — Datatypes: `mkDatatypeVar` parallel overload + readRaw

```nim
proc mkDatatypeVar*(dt: Z3DatatypeDecl[T], name: string): Z3DatatypeValue[T]  # existing
proc mkDatatypeVar*[T](name: string): Z3DatatypeValue[T]                       # NEW; uses ctx.datatypeRegistry[$T]
proc readRaw*(dt: Z3DatatypeDecl[T], cname, fname: string,
              v: Z3DatatypeValue[T]): RawZ3Ast
```

### N7.6a — Optimize: non-FP-dependent extensions (split per Lens 4 HIGH-2)

`Z3_optimize_assert_and_track`, `Z3_optimize_get_unsat_core`, `Z3_optimize_from_string`, `Z3_optimize_from_file`, `Z3_optimize_get_help`. 5 procs. No FP dependency. Lands **before N6**.

### N7.6b — Optimize: FP-dependent extensions (split per Lens 4 HIGH-2)

`Z3_optimize_get_statistics`, `Z3_optimize_get_assertions`, `Z3_optimize_get_objectives`, `Z3_optimize_set_initial_value`, `Z3_optimize_get_lower_as_vector`, `Z3_optimize_get_upper_as_vector`, **plus** `Z3_optimize_register_model_eh` (Lens 2 M-B3 — typed-closure form per ADR-N0004's pattern, or FFI-stub-only if the marshalling is intrusive; cycle decides). 6–7 procs.

### N7.7 — Fixedpoint: I/O + descrs + addFact

Same as v1.

### N7.8 — Fixedpoint callback FFI stubs (CORRECTED in v3 per round-2 Lens 2 H1)

v2 claimed "7 `Z3_fixedpoint_register_*` FFI entries." Verified against `_audit_headers/z3_fixedpoint.h`: only **one** `Z3_fixedpoint_register_*` function exists (`Z3_fixedpoint_register_relation`) and it's **already wrapped** at `fixedpoint.nim:95`. The actual unwrapped fixedpoint callback API is 4 functions with different prefixes:

- `Z3_fixedpoint_init(c, fp, state)` — initializes callback state.
- `Z3_fixedpoint_set_reduce_assign_callback(c, fp, cb)` — user-defined reduction for assignments.
- `Z3_fixedpoint_set_reduce_app_callback(c, fp, cb)` — user-defined reduction for applications.
- `Z3_fixedpoint_add_callback(c, fp, state, newLemmaEh, predecessorEh, unfoldEh)` — adds three lemma/predecessor/unfold callback hooks.

Plus 3 associated `{.cdecl.}` callback function pointer typedefs (`Z3_fixedpoint_new_lemma_eh`, `Z3_fixedpoint_predecessor_eh`, `Z3_fixedpoint_unfold_eh`) and 2 reduction callback typedefs (`Z3_fixedpoint_reduce_assign_callback_fptr`, `Z3_fixedpoint_reduce_app_callback_fptr`).

v3 scope:
- Ship the 4 unwrapped FFI entries + 5 callback typedefs in `ffi.nim`.
- Expose raw-typed wrappers in `fixedpoint.nim` taking `state: pointer` + the C function pointers directly:

```nim
proc setReduceAssignCallback*(fp: Z3Fixedpoint, state: pointer,
  cb: Z3FixedpointReduceAssignCallbackFptr)
proc setReduceAppCallback*(fp: Z3Fixedpoint, state: pointer,
  cb: Z3FixedpointReduceAppCallbackFptr)
proc addCallback*(fp: Z3Fixedpoint, state: pointer,
  newLemmaEh: Z3FixedpointNewLemmaEh,
  predecessorEh: Z3FixedpointPredecessorEh,
  unfoldEh: Z3FixedpointUnfoldEh)
proc init*(fp: Z3Fixedpoint, state: pointer)
```

Each proc's doc comment explains the state-pointer pattern: "`state` is a `void*` passed back through every callback invocation; the caller owns the pointed-to object's lifetime." The typed-closure wrapper (closure-based marshalling parallel to ADR-N0004's propagator pattern) is **deferred to a follow-on RFC: "nim-z3 fixedpoint typed callback API."**

The follow-on RFC is the **only escalation** per `complete-lib-not-consumer.md` in this RFC. Rationale: fixedpoint callbacks fire in Datalog-engine-internal contexts where the closure state-capture story differs from propagator (multi-callback batching via `addCallback`'s 3-argument shape; per-callback ownership semantics). The marshalling design merits its own discussion.

---

## Cluster N8 — Solver + Tactic + Simplifier

### N8.1 — Solver: trail/units/non_units/levels/set_initial_value

FFI additions (Lens 4 HIGH-6 — all currently absent):
- `Z3_solver_get_trail`, `Z3_solver_get_units`, `Z3_solver_get_non_units`, `Z3_solver_get_levels`, `Z3_solver_set_initial_value`.

Typed surface:

```nim
proc trail*(s: Z3Solver): Z3AstVector
proc units*(s: Z3Solver): Z3AstVector
proc nonUnits*(s: Z3Solver): Z3AstVector
proc levels*(s: Z3Solver, lits: Z3AstVector): seq[uint]
  ## Wraps Z3_solver_get_levels(c, s, literals, sz, levels) — the C signature
  ## requires the caller to allocate a `unsigned* levels` buffer of size
  ## `lits.len`. Nim wrapper allocates a `seq[uint]`, passes its data pointer,
  ## and returns the filled seq. Length is locked to `lits.len`; one-to-one
  ## with the input literal vector.
proc setInitialValue*(s: Z3Solver, v, value: Z3AnyAst)
  ## Suggests a starting assignment for variable `v` to the solver's
  ## decision heuristic. No guarantee the solver respects it.
```

### N8.2 — Solver: cube + congruence

FFI additions: `Z3_solver_cube`, `Z3_solver_congruence_root`, `Z3_solver_congruence_next`.

### N8.3 — Solver: misc constructors + introspection (EXPANDED per Lens 2 H-B2)

FFI additions: `Z3_mk_simple_solver`, `Z3_mk_solver_for_logic`, `Z3_solver_get_num_scopes`, `Z3_solver_to_dimacs_string`, `Z3_solver_import_model_converter`, **`Z3_solver_interrupt`** (Lens 2 H-B2 — per-solver interrupt).

### N8.4a — Propagator FFI surface (split per Lens 4 CRIT-1)

FFI additions: all 15 `Z3_solver_propagate_*` entries (per ADR-N0004 callback set), `Z3_propagator_get_context`, `Z3_solver_callback` opaque-type definition + `{.cdecl.}` callback function type declarations for each `*_eh` shape.

### N8.4b — `propagator.nim` types + registration (split per Lens 4 CRIT-1)

Per ADR-N0004 (rewritten):
- `Z3PropagatorHandlers` value type with all callback closure fields.
- `PropagatorCtxBox` internal ref object (heap allocation root).
- `Z3Propagator` public ref type holding strong ref to the box.
- `newPropagator` allocates the box via `new`, casts to `void*`, registers via `Z3_solver_propagate_init`.
- C-side shim functions for each callback type cast `user_data` back to `ptr PropagatorCtxBox` and dispatch to the stored Nim closure.
- `Z3_fresh_eh` shim heap-allocates a new `PropagatorCtxBox` for the sub-solver, appends it to the parent's `subBoxes: seq[PropagatorCtxBox]` registry (keeps it GC-reachable via the parent), returns the new box's address as the sub-solver's `user_data`. **No `GC_ref`/`GC_unref` calls** — per ADR-N0004 v3.

Lifecycle contract: documented on the `Z3Propagator` type — must outlive solver's `check()` invocation. Thread safety: closures must be `{.gcsafe.}`.

RED tests: register a propagator with a `fixed` callback that counts invocations during a SAT `check()`; verify count > 0.

### N8.4c — Propagator advanced callbacks (split per Lens 4 CRIT-1)

`consequence`, `nextSplit`, `decide` callbacks. `Z3_solver_callback cb` threaded explicitly:

```nim
proc consequence*(cb: Z3SolverCallback, lits, eqs: seq[Z3AnyAst], conseq: Z3AnyAst)
proc nextSplit*(cb: Z3SolverCallback, t: Z3AnyAst, idx: uint, phase: int)
```

These take the callback handle as their first arg (only valid inside a callback invocation — cannot be cached).

RED tests: a propagator with `fixed(cb, p, val)` that calls `consequence([p], [], q)` where `q` is a Z3Bool; verify the produced model has `q == true`.

### N8.4d — `Z3_solver_register_on_clause` (NEW per Lens 2 H-B1)

Separate from propagator. Gated `-d:z3WithoutOnClause` (opt-out per ADR-N0007's `z3Without*` convention; default OFF means feature available on Z3 ≥ 4.12).

```nim
proc registerOnClause*(s: Z3Solver,
                       cb: proc(proofHint: Z3AnyAst, deps: seq[uint],
                                lits: Z3AstVector) {.closure, gcsafe.})
```

Uses the same `PropagatorCtxBox`-style marshalling shim.

**FFI prelude (v5.1 from N0.1 implementer escalation):** `Z3_on_clause_eh` is a function-pointer typedef in `z3_api.h`, not an opaque handle. The Nim FFI alias goes here, not in N0.1:

```nim
type
  Z3OnClauseEh* = proc(ctx: pointer, proof_hint: RawZ3Ast,
                       deps: ptr UncheckedArray[cuint],
                       num_deps: cuint, lits: RawZ3AstVector) {.cdecl.}
  RawZ3OnClauseBox = ref object   # Nim-side closure storage, NOT a Z3 opaque
    cb: proc(proofHint: Z3AnyAst, deps: seq[uint],
             lits: Z3AstVector) {.closure.}
    ctx: Z3Context
    solver: Z3Solver
```

`registerOnClause` heap-allocates a `RawZ3OnClauseBox`, registers it with Z3 via the C-side shim, and keeps a strong ref on the `Z3Solver` so the box outlives the solver's check() calls. No `RawZ3*` opaque-handle declaration is involved.

### N8.5 — Tactic / probe / simplifier enumeration

Same as v1.

### N8.6 — Tactic parallel + conditional combinators

Same as v1.

### N8.7 — `src/z3/simplifier.nim` (Z3 ≥ 4.12)

Same as v1 surface. Lifecycle (corrected in v3): `emitRefcountLifecycle(Z3SimplifierOwn, Z3_simplifier_dec_ref)` per ADR-N0006. Gated `-d:z3WithoutSimplifierObject` per ADR-N0007 (opt-out; default OFF means available on Z3 ≥ 4.12).

**Type declaration (v5 explicit):**

```nim
when not defined(z3WithoutSimplifierObject):
  type
    Z3SimplifierOwn* {.pure, inheritable.} = object
      raw*: RawZ3Simplifier
      ctx*: Z3Context
    Z3Simplifier* = ref Z3SimplifierOwn

  emitRefcountLifecycle(Z3SimplifierOwn, Z3_simplifier_dec_ref)
```

Matches the `Z3SolverOwn` / `Z3Solver` pattern at `src/z3/solver.nim`; no novel mechanism.

### N8.8 — Goal introspection

Same as v1.

### N8.9 — AstVector + Goal translate parity

Same as v1.

### N8.10 — `Z3_set_ast_print_mode` (NEW per Lens 2 H-B3)

```nim
type AstPrintMode* = enum
  apSmtLib2Full, apLowLevel, apSmtLibCompliant

proc setAstPrintMode*(ctx: Z3Context, mode: AstPrintMode)
```

Update `pretty.nim` doc comment to reference this.

---

## Cluster N9 — Pseudo-boolean + Order + Misc

### N9.1 — Pseudo-boolean (CORRECTED per Lens 1 M2)

```nim
# atMost/atLeast take unsigned k (Z3 C API uses `unsigned k`):
proc atMost*(lits: openArray[Z3Bool], k: uint): Z3Bool
proc atLeast*(lits: openArray[Z3Bool], k: uint): Z3Bool

# pble/pbge/pbeq take signed k (Z3 C API uses `int k` for these):
proc pbLe*(lits: openArray[Z3Bool], weights: openArray[int], k: int): Z3Bool
proc pbGe*(lits: openArray[Z3Bool], weights: openArray[int], k: int): Z3Bool
proc pbEq*(lits: openArray[Z3Bool], weights: openArray[int], k: int): Z3Bool
```

### N9.2 — Order theory (CLARIFIED per Lens 4 MED-7)

```nim
# Use the standard sortOfType[E] pattern (parallel to arrays.nim):
proc mkLinearOrder*[E](ctx: Z3Context, id: int): Z3FuncDecl[tuple[a, b: E], Z3Bool]
proc mkPartialOrder*[E](ctx: Z3Context, id: int): Z3FuncDecl[tuple[a, b: E], Z3Bool]
proc mkPiecewiseLinearOrder*[E](ctx: Z3Context, id: int): Z3FuncDecl[tuple[a, b: E], Z3Bool]
proc mkTreeOrder*[E](ctx: Z3Context, id: int): Z3FuncDecl[tuple[a, b: E], Z3Bool]
proc mkTransitiveClosure*[ArgsTup, Ret](f: Z3FuncDecl[ArgsTup, Ret]): Z3FuncDecl[ArgsTup, Ret]
```

### N9.3 — N-ary arrays + array_map + array_ext + as_array

Same as v1.

### N9.4 — substituteFuns + fresh names

Same as v1.

### N9.5 — Concurrency + relation introspection + logging (EXPANDED per Lens 2 L-B5)

- `Z3_enable_concurrent_dec_ref` (existing in v1).
- `Z3_get_relation_arity`/`_column` (existing in v1).
- **Logging API:** `Z3_open_log`, `Z3_close_log`, `Z3_append_log`, `Z3_toggle_warning_messages` (Lens 2 L-B5; per `complete-lib-not-consumer`).

---

## Cluster N10 — Consistency + ergonomics pass

### N10.1 — `Z3Char` `>` / `>=`

Same as v1.

### N10.2 — Cross-theory conversion naming pass (CLARIFIED)

Rename `strToInt`/`intToStr` → `Z3String.toInt`/`Z3Int.toStr`. Also `bvToFpBits` rename per N6.7.

**Strict ordering: N6.7 MUST complete before N10.2 starts.** Both touch `fp.nim` identifiers.

### N10.3 — `translate` generic over `Z3FuncDecl` / `Z3Sort` / `Z3Model` + bounded-set documentation (per Lens 2 H-B4)

```nim
proc translate*[ArgsTup, Ret](f: Z3FuncDecl[ArgsTup, Ret], target: Z3Context): Z3FuncDecl[ArgsTup, Ret]
proc translate*[S](s: Z3Sort[S], target: Z3Context): Z3Sort[S]
proc translate*(m: Z3Model, target: Z3Context): Z3Model
```

**Doc note added in this cycle:** Z3 does not expose `optimize_translate`, `tactic_translate`, or `fixedpoint_translate` — the `translate` family covers `Z3_ast`, `Z3_model`, `Z3_sort` (via the existing sortdispatch), `Z3_func_decl`, `Z3_goal`, `Z3_ast_vector`, `Z3_solver`. Cross-context Optimize/Tactic/Fixedpoint requires re-construction in the target context.

### N10.4 — Module doc-header `z3/` prefix sweep + rounding-mode SMT-LIB long-name doc

Two folded scopes:

1. **Module headers:** Every `src/z3/*.nim` module's `##` header gains a `z3/` prefix on internal references (e.g., `## See z3/fp.nim` instead of `## See fp.nim`) so external doc consumers can grep cleanly.

2. **Rounding-mode SMT-LIB long names (folded from deleted N6.1):** `fp.nim`'s rounding-mode constructor doc comments (`mkRoundNearestTiesToEven`, `mkRoundNearestTiesToAway`, `mkRoundTowardPositive`, `mkRoundTowardNegative`, `mkRoundTowardZero`) gain references to their SMT-LIB long names (`RNE`, `RNA`, `RTP`, `RTN`, `RTZ`) so users searching SMT-LIB literature find the bindings. Example doc form:

   ```nim
   proc mkRoundNearestTiesToEven*(ctx: Z3Context): Z3RoundingMode
     ## Z3_mk_fpa_round_nearest_ties_to_even. SMT-LIB long name: `RNE`
     ## (round nearest, ties to even). Default rounding mode for IEEE 754.
   ```

No new procs. GREEN signal: `nim doc src/z3.nim` output mentions `RNE`/`RNA`/`RTP`/`RTN`/`RTZ` next to their Nim constructors; CI grep test confirms.

### N10.5 — `Z3Real` float lift + `toRealOpt` (REVISED v5)

Scope:
- `mkReal(ctx, v: float64)` constructor via decimal-string formatting (`$v` round-trips through Z3's decimal parser).
- `r + 0.5`-style arithmetic literal lifts (binary operators accepting `float` on either side, lifting to `mkReal` internally).
- `Z3Real.toRealOpt: Option[float]` — model extractor returning `none` when the model assigns the real to a non-finite or unbounded value; parallel to `Z3Int.toIntOpt` from N4.4.

**v5 correction (round-4 Lens 2):** the `toReal` alias proposed in earlier revisions is **dropped**. `fp.nim:431` already defines `toReal` as a Z3FP→Z3Real cast (`Z3_mk_fpa_to_real`); reusing that identifier for the arith-side model extractor would collide. `toRealApprox` and `toRealOpt` are the two arith-side names; no alias.

Strict ordering after N6 (touches `arith.nim` which interacts with FP lifts).

### N10.6 — DELETED (was "subsumed by N6.5")

Per three-lens consensus (Lens 1 L3, Lens 3 L3, Lens 4 LOW-1).

### N10.7 — `Z3BitVec` Option extractors (BV-side; scope confirmed per Lens 4 MED-3)

`Z3BitVec[W].toUintOpt`, `Z3BitVec[W].toIntOpt`, `Z3BitVec[W].toInt64Opt`.

(N4.4 covers arith side; N10.7 covers BV side. No overlap.)

### N10.8 — `evalFp[E,S]` generic — folded into N6.6

REMOVED as separate cycle. (Already covered by N6.6 in v2's revised N6 layout.)

### N10.9 — Inline-pragma discipline pass

Same as v1.

### N10.10 — `runnableExamples` adoption

Same as v1.

### N10.11 — `mkRegexAll` → `mkRegexAllChar`

Same as v1.

### N10.12 — `newScratchContext` + `enable_concurrent_dec_ref`

Same as v1.

---

## Cluster N11 — Test hygiene + docs

### N11.1 — Orphan test binary cleanup

Same as v1.

### N11.2 — `tchar.nim` expansion

Same as v1.

### N11.3 — Per-new-module test files (`tsets.nim`, `tastmap.nim`, `tuninterpretedval.nim`, `trcf.nim`, `tspacer.nim`, `talgebraic.nim`)

Same as v1 (polynomial folded into algebraic, so 6 new test files not 7).

### N11.4 — `tpropagator.nim` (full coverage including `tonclause.nim` for N8.4d)

Same as v1.

### N11.5 — `tsimplifier.nim`

Same as v1.

### N11.6 — Migration guide (`docs/MIGRATION-1.x-to-2.0.md`) + proptest sync (EXPANDED per Lens 2 H-B5)

Renames table, removed-deprecated table, new-module index, recommended migration sequence, **plus**:

**Proptest sync delta:** Lens 4 grep of `/home/corey/projects/nimlibs/proptest/src/` confirms proptest currently uses NONE of the breaking-renamed symbols. The migration delta is:

```bash
# In proptest's milpa.kdl / .nimble:
- nim-z3 = "1.0.0"
+ nim-z3 = "2.0.0"
```

That's it. No source changes required for the rename set. Coordination: proptest's Phase 15+ branch lands the version pin bump before the nim-z3 2.0.0 tag is pushed; re-verify the grep at tag time in case proptest's interim work introduces FP usage.

### N11.7 — README + CHANGELOG + IMPLEMENTATION_PLAN.md + MINIMAL_BUILD.md + CI matrix sweep (EXPANDED per Lens 2 L-B3 + L-B4)

CHANGELOG `[2.0.0]` entry summarizing all clusters; README "What's wrapped" table refreshed; `docs/IMPLEMENTATION_PLAN.md` archived with completion mark; **`docs/MINIMAL_BUILD.md`** updated to reflect the new gate set (per ADR-N0007); **CI matrix** reviewed — if Z3 4.14 is available at tag time, add a row.

### N11.8 — Parse-modify-serialize round-trip integration test (NEW per Lens 2 M-B8)

New test `tio_roundtrip.nim`:
1. Parse SMT-LIB source with named declarations.
2. Extract decl handle via the new N2.4 introspection procs.
3. Build a new formula using the extracted decl.
4. Serialize back to SMT-LIB.
5. Verify round-trip preserves semantics.

This is the integration test that validates the composition of N2.4 (decl introspection) + existing parse/write surface.

---

## Slice plan — 76 cycles + 7 ADRs

(Numbered linearly through the slice plan; cycle IDs preserved from the cluster definitions above.)

### Pre-cycle ADRs (7)

ADR-N0001 through ADR-N0007. ~1h each, no code.

### Cluster N0 (1 cycle)

1. **N0.1** — `ffi.nim` opaque-type refactor

### Cluster N1 — Missing whole theories (8 cycles)

2. **N1.1** — `sets.nim`
3. **N1.2** — `astmap.nim`
4. **N1.3** — `uninterpretedval.nim` (marker-phantom shape)
5. **N1.4** — `declareDatatypes` arity 4–8 + seq-form
6. **N1.5** — (merged into N1.7a — polynomial.nim subresultants)
7. **N1.6** — `rcf.nim` (plain object move-only, single `Z3_rcf_del`)
8. **N1.7a** — `algebraic.nim` (+ subresultants from former N1.5)
9. **N1.7b** — `spacer.nim` (depends on N1.7a)

### Cluster N2 — Model + introspection (7 cycles)

10. **N2.1** — Model enumeration API
11. **N2.2** — Model construction API
12. **N2.3** — Datatype sort introspection
13. **N2.4a** — Decl name/arity/domain/range
14. **N2.4b** — Decl parameter introspection
15. **N2.4c** — AST-level introspection + global param descrs + type variables
16. **N2.5** — Quantifier ID + substituteVars
17. **N2.6** — N-ary forall/exists escape hatch

### Cluster N3 — BV (3 cycles, was 4 — merged N3.3+N3.4)

18. **N3.1** — Overflow/underflow predicates
19. **N3.2** — Reduction ops (`redAnd`/`redOr`) + extended rotations (`extRotateLeft`/`extRotateRight`)
20. **N3.3** — Theory conversions (`bvToInt`/`intToBv`) + Bool→BV[1] derived

### Cluster N4 — Arith (4 cycles)

21. **N4.1** — abs/power/divides/isInt/mkRealInt64
22. **N4.2** — int2real/real2int/is_int
23. **N4.3** — Algebraic number bounds
24. **N4.4** — Arith Option extractors + `toInt64` rename

### Cluster N5 — Strings + Seq (7 cycles)

25. **N5.1** — String ordering
26. **N5.2** — Codepoint conversion + BV-to-string
27. **N5.3** — `get_string_contents` + `get_string_length`
28. **N5.4** — `last_index` (gated for `replace_all` / `replace_re`)
29. **N5.5** — Seq HOF (with corrected index parameters)
30. **N5.6** — Seq `int`-literal lifts
31. **N5.7** — Eval shortcuts + naming sweep

### Cluster N6 — FPA (7 cycles; reduced from 9 after consolidations and N6.1 deletion)

32. **N6.2** — Sort constructors (typed `Z3Sort[stFp]` returns)
33. **N6.3** — `mkFpFromParts` (no rounding-mode param)
34. **N6.4a** — Numeral predicates (7)
35. **N6.4b** — Numeral decomposition (6 with Option/tuple)
36. **N6.5a** — FP comparison literal lifts (6) — uses `Z3_mk_fpa_eq` for IEEE semantics (NaN ≠ NaN, +0 == −0); structural equality via `==` deliberately omitted (folded into N10.4 doc sweep)
37. **N6.5b** — FP arithmetic literal lifts (4)
38. **N6.6** — Option extractors + generic `evalFp[E,S]`
39. **N6.7** — Renames (`mkFp*` + `bvToFpBits`) + optimize constraint extension

### Cluster N7 — Datatypes + Optimize + Fixedpoint (9 cycles)

41. **N7.1** — Enumeration sort
42. **N7.2** — Tuple sort
43. **N7.3** — Recursive function defs
44. **N7.4** — `update_field` (`Z3AccessorDecl[T, Ret]` signature)
45. **N7.5** — `mkDatatypeVar` parallel overload + `readRaw`
46. **N7.6a** — Optimize non-FP-dep (5 procs)
47. **N7.6b** — Optimize FP-dep + model_eh (7 procs)
48. **N7.7** — Fixedpoint I/O + descrs + addFact
49. **N7.8** — Fixedpoint callback FFI stubs (typed wrapper = separate RFC)

### Cluster N8 — Solver + Tactic + Simplifier (13 cycles)

50. **N8.1** — Solver trail/units/non_units/levels/set_initial_value
51. **N8.2** — Solver cube + congruence
52. **N8.3** — `mkSimpleSolver`/`mkSolverForLogic`/`numScopes`/`toDimacs`/`importModelConverter`/`solver_interrupt`
53. **N8.4a** — Propagator FFI surface
54. **N8.4b** — Propagator types + registration (heap-allocated ref pattern)
55. **N8.4c** — Propagator consequence/nextSplit/decide (with cb threading)
56. **N8.4d** — `Z3_solver_register_on_clause` (gated)
57. **N8.5** — Tactic / probe / simplifier enumeration
58. **N8.6** — Tactic par + conditional combinators
59. **N8.7** — `simplifier.nim` (gated for Z3 ≥ 4.12)
60. **N8.8** — Goal introspection
61. **N8.9** — AstVector + Goal translate parity
62. **N8.10** — `Z3_set_ast_print_mode`

### Cluster N9 — PB + Order + Misc (5 cycles)

63. **N9.1** — Pseudo-boolean cardinality (`unsigned k` correction)
64. **N9.2** — Order theory + transitive closure
65. **N9.3** — N-ary arrays + map + ext + as_array
66. **N9.4** — `substituteFuns` + fresh names
67. **N9.5** — Concurrency + relation introspection + logging API

### Cluster N10 — Consistency + ergonomics (10 cycles; was 12)

68. **N10.1** — `Z3Char` `>` / `>=`
69. **N10.2** — Cross-theory conversion naming pass (strict order after N6.7)
70. **N10.3** — `translate` generic extensions + bounded-set doc
71. **N10.4** — Module doc-header prefix sweep
72. **N10.5** — `Z3Real` float lift + `toReal` rename
73. **N10.7** — `Z3BitVec` Option extractors (BV-side)
74. **N10.9** — Inline-pragma discipline pass
75. **N10.10** — `runnableExamples` adoption
76. **N10.11** — `mkRegexAllChar` rename
77. **N10.12** — `newScratchContext` + `enable_concurrent_dec_ref`

### Cluster N11 — Test hygiene + docs (8 cycles)

78. **N11.1** — Orphan binary cleanup
79. **N11.2** — `tchar.nim` expansion
80. **N11.3** — Per-new-module test files (6 files)
81a. **N11.4a** — `tpropagator.nim` (push/pop/fresh + fixed/eq/diseq theory callbacks)
81b. **N11.4b** — `tonclause.nim` (gated under `z3WithoutOnClause` not set)
82. **N11.5** — `tsimplifier.nim`
83. **N11.6** — `MIGRATION-1.x-to-2.0.md` + proptest sync delta
84. **N11.7** — README/CHANGELOG/MINIMAL_BUILD/IMPLEMENTATION_PLAN/CI sweep + new `docs/THREADING.md` (consolidates `newScratchContext`/`enable_concurrent_dec_ref`/`translate`/`global_param_*` thread-safety story) + `2.0.0` tag
85. **N11.8** — Round-trip integration test (`tio_roundtrip.nim`)

**Total: 75 cycles (after v5: −2 reserved deletions N6.8/N6.9/N9.6, +1 N11.4 a/b split, −1 N6.1 deleted, already removed in inventory) + 7 ADRs = 82 work units.** Cluster counts authoritative: N1=8, N2=7, N3=3, N4=4, N5=7, N6=7, N7=9, N8=13, N9=5, N10=10, N11=9 (after N11.4 split). Reconciliation note: counts above the cluster headers reflect post-v5 reality; pre-v5 round-4 reports cited 76 cycles because the deleted reserved slots were still listed.

---

## Compatibility on upgrade (1.x → 2.0)

| Change | Impact |
|---|---|
| `mkNaN`/`mkInf`/`mkZero` → `mkFp{NaN,Inf,Zero}` | **Hard break**, no deprecation alias. |
| `strToInt`/`intToStr` → `Z3String.toInt`/`Z3Int.toStr` | **Hard break**. |
| `toFp(bv, _: typedesc)` → `bvToFpBits` | **Hard break**; existing lossy `toFp(rm, fp, _)` keeps the name. |
| `mkRegexAll` → `mkRegexAllChar` | **Hard break**. |
| `Z3Int.toInt` → `Z3Int.toInt64` | **Hard break**; consistency with `Z3BitVec[W].toInt`. |
| `mkDatatypeVar` gains `(name)` form | Pure addition. |
| `declareDatatypes` gains arity 4–8 | Pure addition. |
| New theory modules (sets, astmap, uninterpreted, rcf, spacer, algebraic, simplifier, propagator, order) | Additive imports; some gated. |
| `Z3Fp` literal lifts (6 cmp + 4 arith) | Additive overloads. |
| `Z3Char` `>` / `>=` | Additive overloads. |
| `translate` overloads for FuncDecl/Sort/Model | Additive. |
| `Z3BitVec.toUintOpt`/`toIntOpt`/`toInt64Opt` | Additive overloads. |
| `Z3RcfNum` `=copy` `{.error.}` | Move-only type; users must clone via re-derivation. |
| Minimum Z3 version | 4.10.x (unchanged from v1.0). |
| New gate defines (v3 corrected) | **Opt-out** (default OFF, feature available): `z3WithoutSpacer`, `z3WithoutPolynomial`, `z3WithoutRcf`, `z3WithoutAlgebraic`, `z3WithoutPropagator`, `z3WithoutSets`, `z3WithoutAstMap`, `z3WithoutOrder`, `z3WithoutSimplifierObject`, `z3WithoutOnClause`. **Forward-compat opt-in** (default OFF, feature unavailable; opt-in when bundling Z3 4.14+): `z3WithSeqReplaceAll`, `z3WithSeqReplaceRe`. |

**Proptest migration:** version pin bump only. No source changes (Lens 4 grep verified).

---

## Open questions

**Zero genuine forks** at the standing-directive bar after all four architect rounds. The remaining MEDIUM/LOW micro-items from round-4 (cleaner doc phrasings, additional examples, minor cross-references) are annotated inline at their respective cycle sites and resolvable during `/tdd` cycle-time without spec-level architectural input. Implementers should apply the bar (PhD-CS, no consumers, escalate wrong-spec) per `/tdd` standing rules.

---

## v4 absorption note — backlog deleted

v3 carried a "round-2 backlog" section listing ~30 unapplied findings. Round 3 consolidation surfaced that this section created a split-spec hazard: implementers reading a cycle body could miss mandatory correctness constraints that lived only in the backlog (e.g., N1.1's lifecycle delegation procs, N1.2's lifecycle pattern correction). v4 deletes the backlog entirely; all round-2 + round-3 findings are absorbed into the canonical sections (ADRs, cycle bodies, inventory table, slice plan, compatibility table) atomically. The only remaining deferral is the typed fixedpoint callback wrapper (N7.8) which is explicitly an escalation to a separate follow-on RFC per the standing directive on escalation.

**Round-2 + round-3 items absorbed into canonical sections in v4:**

- N1.1 lifecycle delegation procs — in N1.1 body.
- N1.2 lifecycle pattern (plain object + ref alias + `emitRefcountLifecycle`) — in N1.2 body.
- ADR-N0003 macro form — in ADR + N1.4 body (both synced in v4).
- ADR-N0004 push/pop callback fields, no GC_ref, final_eh multi-fire correction — in ADR.
- ADR-N0006 lifecycle table (plain object + ref alias for all ref-counted handles) — in ADR.
- ADR-N0007 gate naming (`z3Without*` for present-at-min, `z3With*` for forward-compat) — in ADR + compatibility table + each affected cycle.
- N1.7a/b parallel-landing — in inter-cluster ordering.
- N3.2 `mkBitVecFromBools` dropped — in N3.2 body.
- N6.1 deleted — replaced with "DELETED" notice; doc content folds into N10.4.
- N6.4b `getNumeralSignificandUint64` as `Option[uint64]` — in N6.4b body.
- N6.8/N6.9 reserved-cycle sections — to be removed (round 4 catch-up).
- N7.8 fixedpoint callback FFI rescoped to 4 actual functions — in N7.8 body.
- N8.4b GC_ref removed — in N8.4b body.
- N8.4d on_clause gate aligned to `z3WithoutOnClause` — in N8.4d body.
- N8.7 Simplifier lifecycle (`emitRefcountLifecycle`) + gate (`z3WithoutSimplifierObject`) — in N8.7 body.

**Remaining items targeted for round 4 catch-up** (NOT yet applied — implementer must reference round-3 review notes when implementing):

- N6.8/N6.9 section removal + cluster N6 count reconciliation (still says "9 cycles" in inventory, "7 cycles" in slice plan).
- N3.2 slice plan label still says `mkBitVecFromBools`.
- N1.6 slice plan label still says `ref object`.
- Cycle count irreconcilable across inventory/slice-plan/totals (~85 numbered vs 76 claimed).
- N5.5 `foldli` callback arg order citation against Z3 Python API.
- N7.4 `Z3AccessorDecl[T, Ret]` already exists at `datatypes.nim:149` — no new definition needed; cycle should cite.
- N10.5 `toReal` ambiguity (alias name collision between `toRealApprox` and `toRealOpt`).
- N4.4 editorial "except no" cleanup.
- `bvToInt` vs `toSbv` naming consistency resolution.
- N11.4 split into a/b; N11.7 `docs/THREADING.md` sweep extension.
- testMinimal per-cluster updates rather than batched at N11.7.

These are all clear-best fixes; round 4 absorbs them into the canonical sections.

---

## Round 3 launch contract

Round 3 verifies the v3 CRITICAL+HIGH fixes held AND finds what v3 introduced. Per `audit-cycle-pattern.md`, the loop terminates when a round finds 0 CRITICAL/HIGH. Round 1 had 8 CRIT + 23 HIGH; round 2 had 4 CRIT + 12 HIGH (44% reduction); round 3 target is 0 CRIT + 0 HIGH.

If round 3 finds 0 CRITICAL/HIGH, the RFC is ready for `/tdd` slices via `/loop`. If round 3 still finds significant CRITICAL/HIGH, the v3 edits introduced new failure modes (the same pattern v2 exhibited) and a round 4 is warranted with a focus on inspect-before-pessimizing verification of every new claim.

---

## Standing directive integration

Unchanged from v1, with added compliance notes:

- `complete-lib-not-consumer.md` — every audit finding + every round-1 surfaced gap is in scope. Single exception remains N7.8's typed wrapper (its own RFC) — explicitly escalated per the directive.
- `nim-z3-proptest-only-consumer.md` — breaking changes are fine. v2 hardens this by dropping the deprecation window per round-1 consensus.
- `audit-cycle-pattern.md` — round 1 ran 4 parallel lenses; v2 is the round-1-applied state; round 2 verifies and catches what round 1 missed.
- `inspect-before-pessimizing.md` — round 1 caught two inspect-failure cases in v1 (`Z3Float16`/`Z3Float128` already exist; `Z3RcfNum` has no inc_ref pair). v2's RFC text is sourced from verified header/source inspection.

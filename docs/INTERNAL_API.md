# Internal API

> **Audience: contributors.** Nim has no `internal` visibility — a
> symbol is either `*`-exported (visible everywhere) or private to its
> module. Several wrapper symbols are exported **only because sibling
> modules in `src/z3/` need them**; they are not part of the
> user-facing surface and may change without notice. This file is the
> canonical list. If you are writing user code that imports `z3`,
> nothing in this file is something you should call.
>
> See also: [GOTCHAS.md](GOTCHAS.md) (user-facing pitfalls),
> [PARITY.md](PARITY.md) (cross-family contract),
> [THREADING.md](THREADING.md) (per-thread isolation).

## Why this seam exists

Three patterns drive cross-module promotion:

1. **Constructor delegation.** Module B wants to build a typed handle
   from a raw FFI return — but the handle type lives in module A and
   the FFI proc returns from B's territory (`z3/solver` builds
   `Z3Solver` via `Z3_mk_solver`; `z3/tactic` builds `Z3Solver` via
   `Z3_mk_solver_from_tactic`). Module A exports `wrapX(ctx, raw)`
   so B (and only B) can construct one.

2. **Raw-handle access.** Module B's FFI call takes a raw handle (e.g.
   `Z3_tactic_cond(ctx, probe, ifT, elseT)` needs `RawZ3Tactic` for
   both `ifT` and `elseT`). The typed handle's `.raw` accessor is
   exported so B can extract the raw payload without poking at A's
   internals.

3. **Lifecycle / bootstrap hooks.** Module B has a use case that runs
   before any `Z3Context` exists (`z3/globalparams.setGlobalParam`)
   or wants to share lifecycle template machinery
   (`emitVarargsMonoid` in `z3/lifecycle`). Module A exports the hook
   so B can call it from the unusual context.

When a contribution can't fit one of these patterns, it usually
means the user-facing surface needs a new genuinely-public entry
point. **Promoting a private symbol is the right answer only when
the cross-module need is real and the call site is not user code.**

---

## The list

### Constructor delegates — `wrapX(ctx, raw)`

These build a refcount-managed typed handle from a freshly-returned
raw FFI value. The contract: the caller transfers ownership; the
`wrap*` proc takes responsibility for the initial `inc_ref` and
binding to `ctx`.

| Symbol | Module | Consumer modules | Why exported |
|---|---|---|---|
| `wrap*[T](ctx, raw): T` | `z3/lifecycle` | every typed-AST-family module | The unified-`wrap` generic over `Z3Term` — backbone of v0.3 step 1's lifecycle unification. |
| `wrapSolver*(ctx, raw): Z3Solver` | `z3/solver` | `z3/tactic` (`newSolverFromTactic` builds a `Z3Solver` from `Z3_mk_solver_from_tactic`) | Solvers can be constructed from multiple FFI routes; the delegate centralises the inc_ref + nil-check. |
| `wrapTactic*(ctx, raw): Z3Tactic` | `z3/tactic` | `z3/probe` (`condTactic` builds via `Z3_tactic_cond`) | v0.4 step 12 promotion. |
| `wrapModel*(ctx, raw): Z3Model` | `z3/model` | `z3/solver` (`model()`), `z3/optimize`, future `Z3FuncInterp` walkers | Models are constructed in three places; one delegate. |
| `wrapStats*(ctx, raw): Z3Stats` | `z3/stats` | `z3/solver` (`getStatistics`), `z3/optimize` | v0.4 step 8. |
| `wrapAstVector*(ctx, raw): Z3AstVector` | `z3/astvector` | `z3/solver` (`getUnsatCore`, `getConsequences`), `z3/io` (`parseSmt2String` results), `z3/fixedpoint` | v0.4 step 1's foundational handle. |
| `wrapProbe(ctx, raw): Z3Probe` | `z3/probe` | (private — same-module only) | v0.4 step 12. Was `*`-exported pre-v0.5.0 "for symmetry"; un-exported in the v0.5.0 audit because no cross-module consumer materialized and locking a no-consumer surface at v1.0 wasn't worth it. |
| `wrapParamDescrs*(ctx, raw): Z3ParamDescrs` | `z3/params` | `z3/solver` (`getParamDescrs`), `z3/tactic` (`getParamDescrs`), `z3/optimize` (`getParamDescrs`, v0.5.0 audit B3) | v0.5 step 6B. The handle lives in `z3/params` but the constructors live in `z3/solver` / `z3/tactic` / `z3/optimize` to keep dependency layering one-directional. |
| `decodeLBool*(r: Z3_lbool): Z3Status` | `z3/solver` | `z3/fixedpoint` (`query`, `queryRelations`), `z3/optimize` (`check`) | v0.5.0 medium-audit A1/A2. Z3's `Z3_lbool` is a C int whose API contract is values in `{-1, 0, 1}`; this helper decodes safely (case-on-ord) rather than `cast[Z3Status]` (which silently produces invalid enum values on out-of-range returns). Pre-audit, `getConsequences` / `fixedpoint.query` / `optimize.check` each open-coded the decode with `cast` in three different ways. |

### Raw-handle accessors — `.raw` / `.ctx`

These exist on every refcounted ref-handle type. They are exported so
sibling modules can extract the raw FFI payload for use in FFI calls
that the handle's home module doesn't wrap directly.

| Type | Accessors | Consumer modules | Why exported |
|---|---|---|---|
| `Z3Solver` | `raw*`, `ctx*` | `z3/tactic` (`Z3_mk_solver_from_tactic` needs `RawZ3Solver`), `z3/model` (eval paths) | Always exported (v0.1). |
| `Z3Tactic` | `raw*`, `ctx*` | `z3/probe` (`Z3_tactic_cond` arg list) | **v0.4 step 12 promotion.** |
| `Z3Goal` | `raw*`, `ctx*` | `z3/probe` (`Z3_probe_apply` needs `RawZ3Goal`) | **v0.4 step 12 promotion.** |
| `Z3FuncDecl` | `raw*`, `ctx*` | `z3/fixedpoint` (`Z3_fixedpoint_register_relation`, `Z3_fixedpoint_add_fact`) | **v0.4 step 5 promotion.** |
| `Z3FuncInterp` | `raw*`, `ctx*` | (currently only internal-to-`z3/funcdecl`; exported for symmetry) | v0.5 step 6A. |
| `Z3Model` | `raw*`, `ctx*` | `z3/funcdecl` (`Z3_model_get_func_interp` needs `RawZ3Model`) | Always exported. |
| `Z3Stats` | `raw*`, `ctx*` | (currently only internal; exported for symmetry) | v0.4 step 8. |
| `Z3AstVector` | `raw*`, `ctx*` | `z3/solver` (unsat-core iteration), `z3/io` (`parseSmt2*` paths) | v0.4 step 1. |
| `Z3Probe` | `raw*`, `ctx*` | `z3/probe` (internal); exported for symmetry | v0.4 step 12. |
| `Z3Fixedpoint` | `raw*`, `ctx*` | (currently only internal); exported for symmetry | v0.4 step 5. |
| `Z3Params` | `raw*`, `ctx*` | `z3/solver` / `z3/tactic` / `z3/optimize` / `z3/fixedpoint` / `z3/simplify` (`setParams` paths) | v0.2 step 8. |
| `Z3ParamDescrs` | `raw*`, `ctx*` | (currently only internal); exported for symmetry | v0.5 step 6B. |
| `Z3ParserContext` | `raw*`, `ctx*` | (currently only internal); exported for symmetry | v0.4 step 14. |

### Cross-cutting templates

These templates live in `z3/lifecycle` and are used by sibling modules
to share the recurring boilerplate of typed-family lifecycle, varargs
FFI calls, and `Z3Term`-generic operations.

| Symbol | Module | Consumer modules | Why exported |
|---|---|---|---|
| `emitTermLifecycle*` | `z3/lifecycle` | every typed value-family module | Generates `=destroy` / `=copy` / `=dup` hooks. Lifecycle unification v0.3 step 1. |
| `emitRefcountLifecycle*` | `z3/lifecycle` | every typed ref-handle module | Same pattern for `ref` types. |
| `termToSmt2*[T: Z3Term](v)` | `z3/ast` | every typed AST family's `$` overload | v0.5 step 3D body-level unification of `$` (`Nim 2 concept-constrained generics lose to system.$`; per-family overloads stay, body factored). |
| `naryFFICall*(ctx, raws, ffi)` | `z3/lifecycle` | the `emitVarargs*` template family | v0.5 step 2D core helper for n-ary FFI builders. |
| `emitVarargsRequired1Basis*` | `z3/lifecycle` | `z3/regex` | "≥1 required" pattern for `Z3Regex[Basis]`-shaped families. |
| `emitVarargsRequired1E*` | `z3/lifecycle` | `z3/sequence` | Same pattern for `Z3Seq[E]`-shaped families. |
| `emitVarargsMonoid*` | `z3/lifecycle` | `z3/boolean` | Empty-input identity pattern (`mkAnd` / `mkOr`). |
| `mkDistinct*[T: Z3Term]` | `z3/boolean` | every typed family (via the umbrella) | v0.5.0 medium audit B5 — collapsed `emitVarargsDistinctS` + `emitVarargsDistinctW` into one `[T: Z3Term]` generic. Lives in `z3/boolean` (not `z3/lifecycle`) because `Z3Bool` is defined in `z3/ast` which imports `z3/lifecycle` — the return type isn't visible upstream. |

### Per-context state — exported `Z3ContextOwn` fields

A handful of fields on `Z3ContextOwn` (the underlying object of
`Z3Context`) are `*`-exported so sibling modules can read/write
them; user code should never touch them directly.

| Symbol | Module | Consumer | Why exported |
|---|---|---|---|
| `Z3ContextOwn.datatypeRegistry*: Table[string, RawZ3Sort]` | `z3/context` | `z3/datatypes` (`declareDatatype[T]` writes; `sortOf[Z3DatatypeValue[T]]` reads) | Datatype sorts are made at runtime by `declareDatatype` and have no compile-time identity — `sortOf(_: typedesc[Z3DatatypeValue[T]], ctx)` needs a per-context lookup keyed by `$T`. The table lives on the context so it cleans up when the context dies. |

### Width-arithmetic helpers — `*Impl` procs in `z3/bitvec`

The width-typed BV operations (`extract[hi, lo]`, `concat[W1, W2]`,
`zeroExtend[N]`, `signExtend[N]`, `repeat[N]`) are user-facing
templates that compute the *result* width at the type level
(`extract(7, 0)` returns `Z3BitVec[hi - lo + 1]`, etc.). The
template needs to call a typed proc with the right static-int
arithmetic resolved; that proc is the `*Impl` companion.

| Symbol | Module | Consumer | Why exported |
|---|---|---|---|
| `extractImpl*[hi, lo, W: static int]` | `z3/bitvec` | the user-facing `extract` template (same module) | Template-to-typed-proc dispatch with static-int arithmetic resolved at the call site. |
| `concatImpl*[W1, W2: static int]` | `z3/bitvec` | the user-facing `concat` template | Same. |
| `zeroExtendImpl*[N, W: static int]` | `z3/bitvec` | the user-facing `zeroExtend` template | Same. |
| `signExtendImpl*[N, W: static int]` | `z3/bitvec` | the user-facing `signExtend` template | Same. |
| `repeatImpl*[N, W: static int]` | `z3/bitvec` | the user-facing `repeat` template | Same. |

These exist because Nim 2's static-int arithmetic in generic
return-type position needs a real proc declaration to substitute
into; the user-facing templates are wrappers that surface the
intended API name without the `Impl` suffix. **Users who find the
`*Impl` names in autocomplete should call the bare-name template
(`extract`, `concat`, etc.) instead.**

### Bootstrap + threading hooks

| Symbol | Module | Consumer modules | Why exported |
|---|---|---|---|
| `ensureLoaded*` | `z3/context` | `z3/globalparams` | **v0.4 step 13 promotion.** Library-load idempotent hook needed by `setGlobalParam` / `getGlobalParam` / `resetGlobalParams` which can run before any `Z3Context` is allocated. |
| `requireCurrentContext*` | `z3/context` | every typed-family module's ctx-less `mkXVar(name)` overload | Always exported. Raises `Z3InvalidUsageError` if no thread-current context is set. |
| `raiseZ3Error*(rawCtx, code)` | `z3/error` | every typed-family module's direct-raise sites | **v0.5 step 1 layering inversion.** Takes `RawZ3Context` not `Z3Context` so `z3/error` stays at a lower layer than `z3/context`. |
| `checkErr*(ctx, expr)` / `checkErrVoid*(ctx, expr)` | `z3/error` | every typed-family module's FFI-wrap site | The discipline backbone. `ctx: untyped` so the template body's `ctx.raw` access resolves at expansion site. |

---

## Invariants

For every symbol above:

- **User code MUST NOT call it.** The wrapper's user-facing surface is
  what's exported through the `z3` umbrella module's docs and tested
  against. These symbols are visible only because Nim's visibility
  model forces them to be; their signatures may change in any release.
- **Contributors adding a new public symbol that happens to match one
  of these names SHOULD use a different name.** The `wrap*` /
  `raw*` / `ctx*` / `emit*` namespaces are reserved for the
  internal-API patterns documented here.
- **If you find yourself needing to call one from user code, that's a
  signal the wrapper is missing a real public surface.** Open an issue;
  the fix is usually adding a typed wrapper around the call you wanted.

---

## When this list should grow

A new entry lands here when:

1. A sibling module needs functionality that genuinely doesn't fit any
   existing user-facing surface (e.g. constructor delegation from a
   different FFI entry point);
2. The functionality is **not** something user code would want; and
3. There is no clean refactor that would let the consumer avoid the
   need.

All three conditions must hold. If condition 2 fails ("this would also
be useful to users"), the right answer is a real public surface, not a
hidden-by-discipline promotion.

## When this list should shrink

An entry is removed when:

1. The consumer module's need can be satisfied by an existing
   user-facing surface; **or**
2. A refactor eliminates the cross-module dependency; **or**
3. The functionality is promoted to a genuinely-public surface (with
   documentation, tests, and a stability commitment).

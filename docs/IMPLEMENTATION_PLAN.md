# nim-z3 v2.x plan (live)

> **Status: live, promoted 2026-06-04** at the v2.0.0 tag. The
> v1.0 plan is archived at [docs/V0.6_PLAN.md](V0.6_PLAN.md)
> (v0.6 = v1.0.0). All prior-version plans remain archived under
> `docs/V0.N_PLAN.md`.

A type-safe, memory-safe, idiomatic Nim wrapper for the Z3 SMT
solver, post-2.0 stability era.

**Status (at v2.0.0)**: Completeness-pass release. 12 audit
clusters (N0–N11) closed. 11 new modules (`z3/sets`, `z3/astmap`,
`z3/uninterpretedval`, `z3/rcf`, `z3/algebraic`, `z3/spacer`,
`z3/simplifier`, `z3/propagator`, `z3/onclause`, `z3/order`,
`z3/logging`). 7 breaking renames. CRIT-1 (`bvToInt` W=63
sign-extension) fixed. Migration guide at
[`docs/MIGRATION-1.x-to-2.0.md`](MIGRATION-1.x-to-2.0.md).

## v1.0 deferrals — CLOSED in v2.0

The three capabilities deferred at v1.0.0 all landed in v2.0.0:

- **`Z3Set[E]` typed family** — DONE (`z3/sets`, N1.1).
- **`Z3_model_get_const_decls` / `Z3_model_get_func_decls`** —
  DONE (model-decl enumeration, N7.6).
- **`Z3_mk_seq_replace_all` / `_replace_re` / `_split_re`** —
  DONE (N5.7).

## Post-v2.0 live deferral list

No known additive gaps remain from the RFC-completeness audit. Any
future additions discovered post-2.0 will follow the SemVer rules
documented in README "## Stability".

## How patch / minor / major decisions are made post-2.0

- **Patch (2.0.x)**: bug fixes, internal refactors, doc updates,
  doc-rot purges. No public-surface changes.
- **Minor (2.x.0)**: additive only — new procs, new typed families,
  new feature flags. Every pre-existing call site continues to
  compile and behave identically.
- **Major (3.0.0+)**: breaking changes are batched and accompanied
  by a migration guide.

The boundary between "internal refactor" and "public-surface
change" is precisely the surface defined in README "## Stability"
— everything reachable from `import z3` plus the documented
`z3/<name>` submodule paths. `RawZ3*` C handles, `*Impl*`
width-arithmetic helpers, and the cross-module-internal seams in
`docs/INTERNAL_API.md` are explicitly NOT part of the public
surface.

## What lands next (v2.1.0 target)

No fixed schedule. The plan opens when a substantive new batch is
ready or when an external user files an issue that warrants a
minor bump. Until then this file stays as the stability anchor —
confirming that v2.0 is the current release and that any code
change either fits one of the SemVer categories above or needs
the major-bump treatment.

**v2.1.0 batch — typed fixedpoint callbacks.** RFC
[`docs/RFC-fixedpoint-callbacks.md`](RFC-fixedpoint-callbacks.md)
closes the one open item `docs/RFC-completeness.md` deferred out of
the v2.0.0 audit (§N7.8's typed-closure wrapper for
`Z3_fixedpoint_add_callback`'s Spacer export events). Adds
`z3/fixedpoint_callbacks` (`Z3FixedpointHandlers`/`setHandlers`/
`clearHandlers`/`hasHandlers`/`handlers`/`collectLemmas`/
`Z3LemmaLog`, gated `-d:z3WithoutFixedpointCallbacks`) and batches in
four latent-bug backfixes to shipped v2.0 code (propagator exception
wall; two ctx-ref lifecycle-template leak fixes; a hand-written
`=destroy` audit) — see CHANGELOG `[2.1.0]` for the full list. Typed
reduce callbacks (`reduceApp`/`reduceAssign`) are scoped out to v2.2;
the raw §N7.8 procs remain the reduce escape hatch in the meantime.

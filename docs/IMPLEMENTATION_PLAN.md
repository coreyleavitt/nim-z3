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

## What lands next

No fixed schedule. The plan opens when a substantive new batch is
ready or when an external user files an issue that warrants a
minor bump. Until then this file stays as the stability anchor —
confirming that **v2.2 is the current release** and that any code
change either fits one of the SemVer categories above or needs
the major-bump treatment.

**Shipped — v2.1.0, typed fixedpoint callbacks.** RFC
[`docs/RFC-fixedpoint-callbacks.md`](RFC-fixedpoint-callbacks.md)
closed the one open item `docs/RFC-completeness.md` deferred out of
the v2.0.0 audit (§N7.8's typed-closure wrapper for
`Z3_fixedpoint_add_callback`'s Spacer export events). Added
`z3/fixedpoint_callbacks` (gated `-d:z3WithoutFixedpointCallbacks`)
plus four latent-bug backfixes to shipped v2.0 code — see CHANGELOG
`[2.1.0]`.

**Shipped — v2.2.0, regex-index + multi-version.** RFC
[`docs/RFC-regex-index.md`](RFC-regex-index.md) (issue #2). Encoded
regex-position helpers (`matchStartsAt`/`containsRe`/`indexOfRe`), plus
single-build support for **Z3 4.13.x → 4.16.x** via softlink
version-compat (`z3Compat()`; see
[`docs/MULTI_VERSION.md`](MULTI_VERSION.md)). See CHANGELOG `[2.2.0]`.

**Deferred.** Regex-replace wrappers (`replaceRe`/`replaceReAll`) are not
shipped — Z3's solver can't reason about `str.replace_re{,_all}`; deferred
pending upstream Z3 (RFC-regex-index §7). Typed reduce callbacks
(`reduceApp`/`reduceAssign`) remain scoped out to a future minor; the raw
§N7.8 procs remain the reduce escape hatch. The 4.13–4.16 compat manifest
(`z3.compat.json`, adding `atAttested`) is pending an upstream softlink
enhancement for parameter-drifted symbols — see
`scratchpad/softlink-ground-truth-harvest-issue.md`.

# nim-z3 v1.x plan (live)

> **Status: live, promoted 2026-05-31** at the v1.0.0 tag. The
> v0.6 = v1.0.0 plan is archived at
> [docs/V0.6_PLAN.md](V0.6_PLAN.md). All prior-version plans
> remain archived under `docs/V0.N_PLAN.md`.

A type-safe, memory-safe, idiomatic Nim wrapper for the Z3 SMT
solver, post-1.0 stability era.

**Status (at v1.0.0)**: 1354 OKs across c + cpp backends (default
config) plus 18 OKs under the canonical full-`z3WithoutX`-flag
minimal-build verification. Zero failures. Every Z3 C-API
capability the audit cycle identified as user-facing-reachable is
exposed; the `[1.0.0]` CHANGELOG `Deferred to v1.x` subsection
lists the three known additive items for v1.1.

## Live deferral list

The v1.0.0 release intentionally defers three additive
capabilities (each has a documented workaround, so none blocks
adoption):

- **`Z3Set[E]` typed family** — set theory as sugar over
  `Z3Array[E, Z3Bool]`. ~60 LoC, zero new FFI.
- **`Z3_model_get_const_decls` / `Z3_model_get_func_decls`** —
  model-decl enumeration for inspecting all assignments in an
  arbitrary model (e.g., one loaded via `parseSmt2File`).
- **`Z3_mk_seq_replace_all` / `_replace_re` / `_split_re`** —
  multi-occurrence string operations. Existing `replace` is
  first-occurrence only (see GOTCHAS #19).

These will land as additive minor releases (likely v1.1.0).
Anything else discovered post-1.0 follows the SemVer rules
documented in README "## Stability".

## How patch / minor / major decisions are made post-1.0

- **Patch (1.0.x)**: bug fixes, internal refactors, doc updates,
  doc-rot purges. No public-surface changes.
- **Minor (1.x.0)**: additive only — new procs, new typed families,
  new feature flags. Every pre-existing call site continues to
  compile and behave identically.
- **Major (2.0.0+)**: breaking changes are batched and accompanied
  by a `docs/V2.0_PLAN.md` migration guide.

The boundary between "internal refactor" and "public-surface
change" is precisely the surface defined in README "## Stability"
— everything reachable from `import z3` plus the documented
`z3/<name>` submodule paths. `RawZ3*` C handles, `*Impl*`
width-arithmetic helpers, and the cross-module-internal seams in
`docs/INTERNAL_API.md` are explicitly NOT part of the public
surface.

## What lands next (v1.1.0 target)

No fixed schedule. The plan opens when a substantive batch of
v1.0 deferrals is ready or when an external user files an issue
that warrants a minor bump. Until then this file stays as the
stability anchor — confirming that v1.0 is the current target and
that any code change either fits one of the SemVer categories
above or needs the major-bump treatment.

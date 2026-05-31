# nim-z3 v0.6 plan = v1.0.0 tag (live)

> **Status: live, promoted 2026-05-31** after the v0.5.0 tag shipped.
> The previous live plan (v0.5 — the 1.0-readiness polish release) is
> archived at [docs/V0.5_PLAN.md](V0.5_PLAN.md). When v0.6 = v1.0.0
> ships, this file is archived to `docs/V0.6_PLAN.md` and the
> wrapper enters its post-1.0 stability era.

A type-safe, memory-safe, idiomatic Nim wrapper for the Z3 SMT solver.

**Status (at plan-promotion time)**: v0.5 shipped 2026-05-31 with
**1262 OKs** (default config) plus **18 OKs** for `nimble
testMinimal` across both backends, zero failures, every §1 goal of
both v0.4 (contract completion) and v0.5 (1.0-readiness polish) landed.
The "every Z3 C-API capability is reachable" claim is now literal
(the three v0.4 §8b asterisks closed in v0.5 step 6); the typed-error
hierarchy is in place (v0.5 step 4); cross-family parity is unified
under the `Z3Term` and `Z3Renderable` concepts (v0.5 step 3); the
docs catalog (`GOTCHAS.md`, `INTERNAL_API.md`, `PARITY.md`,
`THREADING.md`, `MINIMAL_BUILD.md`) is complete; feature-flag
minimal-build story ships (v0.5 step 10).

**Audience**: future-me, future contributors, anyone wondering how
v0.5.0 became v1.0.0.

## What changes between v0.5 and v0.6 (= v1.0.0)

**Nothing functional.** v0.6 is the v1.0 tag — a release whose only
deliverable is:

1. The version bump in `z3.nimble` (0.5.0 → 1.0.0)
2. A `CHANGELOG.md` entry that summarises what v0.5 already
   delivered as the v1.0 surface
3. A README "Stability" statement committing to semver going forward
4. Archive promotion (this file → `docs/V0.6_PLAN.md`; new
   `docs/IMPLEMENTATION_PLAN.md` skeleton for post-1.0 v1.x work)
5. An annotated `v1.0.0` git tag

The framing from v0.5 §9 holds:
- **v0.4** = "what 1.0 is" (contract completion)
- **v0.5** = "the polish that makes 1.0 stable"
- **v0.6** = **"the commitment"** (this release)

No new code. No new tests. No new docs (beyond the changelog +
stability statement). The wrapper at v0.5.0 IS what 1.0 looks like.

## 1. Goals

1. **Tag v1.0.0.** The annotated git tag is the deliverable.
2. **Update `z3.nimble` version** from `0.5.0` to `1.0.0`.
3. **`CHANGELOG.md` entry** for `[1.0.0]` summarising the cumulative
   v0.4 + v0.5 surface as the inaugural stable release.
4. **README "Stability" section** committing to:
   - SemVer enforcement post-1.0: breaking changes only on major
     bumps (`2.0.0`, …).
   - The public surface is what `import z3` re-exports (i.e., the
     "always-on core" plus non-`z3WithoutX`-gated theory modules);
     anything in `src/z3/internal_*` / docs/INTERNAL_API.md is not
     part of the stability commitment.
5. **Archive promotion** per the v0.2 / v0.3 / v0.4 / v0.5 precedent.

## 2. Non-goals

- **No new features.** Anything that would add a typed family, a
  new module, a new FFI surface, or change behaviour is deferred to
  a post-1.0 v1.x release.
- **No refactors.** v0.5 closed every surface-quality goal; nothing
  in the codebase needs touching between v0.5.0 and v1.0.0.
- **No new tests.** The 1262 + 18 OKs from v0.5 are the v1.0
  baseline.

## 3. Risks

### Tagging discipline

The only meaningful risk is the tag itself: if v1.0.0 is tagged and a
semver-breaking change is needed within hours / days, the wrapper has
a credibility problem. Mitigation: v0.5's audit (§8b) confirmed every
§1 goal landed, every spec correction was resolved, and zero items
rolled to v0.6. The "release v1.0.0 is just v0.5.0 plus a version
bump" framing means there's no integration risk between v0.5.0 and
v1.0.0 — if v0.5.0's tests + examples + minimal-build verification
all pass, v1.0.0 inherits that confidence directly.

### Post-1.0 v1.x scope

Some items deferred from v0.4 / v0.5 (advanced Fixedpoint surface,
`Z3AstMap`, `Z3FuncInterp` tabular extraction is already in v0.5 but
advanced query paths could grow, `Z3Float16` / `Z3Float128`
structured extraction with no Nim-native type) are legitimate v1.x
candidates. None block 1.0. Documenting them as "post-1.0" rather
than "in the next minor release" gives the project room to choose
when to grow the surface vs. when to focus on bug-fix releases.

## 4. Phasing — what ships when

### v0.6 = v1.0.0

A single commit:

1. **Archive plan** — `docs/IMPLEMENTATION_PLAN.md` (this file) copied
   to `docs/V0.6_PLAN.md` with the archived-preamble shape every prior
   archive used.
2. **Promote a v1.x skeleton to IMPLEMENTATION_PLAN.md** — minimal
   stub explaining "post-1.0 work happens on v1.x branches; major
   features in 2.x."
3. **Version bump** in `z3.nimble`: 0.5.0 → 1.0.0.
4. **CHANGELOG entry** for `[1.0.0]` summarising the cumulative
   v0.4 + v0.5 surface as the inaugural stable release.
5. **src/z3.nim module header** updated from "v0.5 shipped" to
   "v1.0.0 — stable release."
6. **README "Stability" section** added, "Design" section's archive
   list extended with `V0.6_PLAN.md`.
7. **Annotated `v1.0.0` git tag** with the cumulative-history
   commit message shape.

### Post-1.0 v1.x

If post-1.0 work is needed (a bug-fix release, an additive feature
release), the `docs/IMPLEMENTATION_PLAN.md` skeleton becomes a real
plan; the chronology rotation resumes (`V0.7` / `V1.1` / etc.).

## 5. Implementation sequence

A single step:

1. **v1.0.0 release** — the single commit described in §4 + the
   annotated tag.

## 6. Risks specific to v0.6

See §3. The only risk is tagging discipline; mitigated by v0.5's §8b
audit confirming zero rollforward.

## 7. Open questions

None. Every v0.5 open question (§7-1 through §7-10 in
[V0.5_PLAN.md](V0.5_PLAN.md)) was resolved during v0.5.

## 8. Deferred from v0.6

*(empty until the first deferral surfaces — which would only happen
if v1.0.0 needs a follow-up patch release before the chronology
resumes.)*

## 9. Closing note

v0.5 closed with: "v0.5.0 → v1.0.0 with a version-only delta." v0.6
honours that commitment. The wrapper's design has been validated
across v0.1 (core), v0.2 (theory expansion), v0.3 (architectural
unification + theory completion), v0.4 (contract completion), and
v0.5 (1.0-readiness polish). v1.0 is the public commitment that
this surface is what users get.

If reading this, future-me, after v0.6 = v1.0.0 has shipped:
archive this file to `docs/V0.6_PLAN.md`, write a minimal
`docs/IMPLEMENTATION_PLAN.md` for post-1.0 v1.x work (which may be
empty for months at a time), and update the README's "Design"
section to point at all six archives — V0.1, V0.2, V0.3, V0.4,
V0.5, V0.6 — the historical record of how the wrapper got to 1.0
and what stability looks like on the other side.

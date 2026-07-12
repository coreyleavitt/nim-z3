# Spike findings — fixedpoint typed callbacks (RFC-fixedpoint-callbacks.md, Stage 0)

Ran the Stage-0 feasibility spike required by
[RFC-fixedpoint-callbacks.md](RFC-fixedpoint-callbacks.md) §6 before
committing to the slice plan: counting `{.cdecl.}` no-op procs
registered against the *raw* §N7.8 surface
(`Z3_fixedpoint_add_callback`, `Z3_fixedpoint_set_reduce_assign_callback`,
`Z3_fixedpoint_set_reduce_app_callback`), driven through the public
`query`/`queryFromLevel` entry points, to prove (or disprove) each
callback sub-family's reachability and pin the open ADR questions
(ownership branch, pre-fill contract, thread) empirically rather than
by inspection. This document captures what was learned. It follows the
v0.1-era convention set by [SPIKE_FINDINGS.md](SPIKE_FINDINGS.md):
spike code is kept as a committed test fixture, not discarded — the
lessons are the deliverable, but the fixtures are the expensive part.

**Bottom line:** both sub-families are reachable through the public
API. The **export** trio (`newLemma`/`predecessor`/`unfold`) fires as
designed once one gating param is set, and ships typed in v2.1.0. The
**reduce** pair (`reduceAssign`/`reduceApp`) fires too, but only under
a condition and value-shape the RFC's original design (ADR-FC-0003)
didn't anticipate — its typed surface is deferred to a dedicated v2.2
RFC rather than force-fit into this one. See
[RFC-fixedpoint-callbacks.md](RFC-fixedpoint-callbacks.md) §2 for the
resulting scope decision.

## 1. Export callbacks — reachable as designed; `newLemma` is param-gated

`predecessor` and `unfold` fire under Spacer (`engine=spacer`, the
default) through **both** public query entry points (`query` and
`queryFromLevel`), on **both** a SAT and an UNSAT fixture, with no
special setup — exactly as ADR-FC-0001/0007 assumed.

`newLemma` did **not** fire on the first pass, which read as an
escalation-worthy reachability gap. Source inspection resolved it:
Z3 gates the `new_lemma` callback dispatch behind two Spacer
parameters, checked before the callback is ever invoked:

```cpp
// src/muz/spacer/spacer_context.cpp:4286-4304, context::new_lemma_eh
void context::new_lemma_eh(...) {
    if (m_params.spacer_p3_share_lemmas() && level < infty_level()) { ... }
    if (m_params.spacer_p3_share_invariants() && level >= infty_level()) { ... }
    ...
}
```

i.e. finite-level lemmas require `fp.spacer.p3.share_lemmas=true`;
infinity-level ("invariant") lemmas require
`fp.spacer.p3.share_invariants=true` — independently. Neither defaults
to `true`. Setting both before `query()`/`queryFromLevel()` made
`newLemma` fire reliably:

- **UNSAT fixture** (predicate proven unreachable): `newLemma` fired
  **3×** — consistent with the RFC's expectation (§6) that Spacer's
  bad-state-blocking during UNSAT proof search is where lemmas are
  discovered most reliably.
- **SAT fixture**: `newLemma` fired **10×** — more than the UNSAT case
  on this fixture, so a SAT-only test would *not* have under-fired the
  callback; both outcomes are worth keeping in the test matrix (§7) for
  coverage, not because SAT is the risk case.

**Resolution recorded in the RFC (slice A2, §6):** the
`setHandlers` install path sets `fp.spacer.p3.share_lemmas=true` and
`fp.spacer.p3.share_invariants=true` whenever a `newLemma` handler is
registered, uniformly (the level actually used isn't known until query
time). This makes A2 fully TDD-able as written — the prior "cannot
fire" concern is resolved, not an escalation.

A record with only `newLemma` populated correctly passed `nil` for the
`predecessor`/`unfold` function pointers to `Z3_fixedpoint_add_callback`
with no crash and no spurious fire — confirming ADR-FC-0009's
per-field-nil-is-per-callback-nil assumption.

## 2. Reduce callbacks — reachable, but only via a relation-plugin path, not term rewriting

The original Stage-0 plan guessed a `Z3BitVec[N]`-relation-under-
`engine=datalog` fixture (RFC §6) would force a register-assign / app-
reduction step. It did not: ground `addFact`-style and BitVec-relation
Datalog fixtures never invoke either reduce callback. The actual
firing condition, found by reading Z3's Datalog relation-plugin
dispatch rather than guessing at fixtures:

**Reduce callbacks fire only when the active relation plugin is the
"external relation" plugin** — i.e. the fixedpoint is configured with

```
fp.setParams(datalog.default_relation = "external_relation")
```

`external_relation` is Z3's *reference* relation implementation whose
entire purpose is to defer every relational-algebra primitive back
into the fixedpoint's callbacks rather than compute them internally.
Concretely (source: `src/muz/rel/dl_external_relation.h/.cpp`):

- **`reduce_assign`** fires for the plugin's **mutating** ops: empty
  relation construction, clone, fact store, union
  (`dl_external_relation.cpp:84,138` and neighboring `mk_*`/`add_fact`/
  `unite` overrides — each lowers to one `reduce_assign` call carrying
  the op's "register" operands).
- **`reduce_app`** fires for the plugin's **query** ops: `is_empty`,
  `complement`, `join` (each lowers to one `reduce_app` call whose
  `decl`/`args` encode the op, via `Z3_OP_RA_*` — `is_empty`,
  `complement`, `join`, and by extension `project`/`rename` for the
  richer algebra `z3_fixedpoint.h:349-351` documents).

This is **not** ordinary term rewriting — it is Z3 asking the
fixedpoint's registered callback "please implement this one relational-
algebra primitive," once per primitive invocation. A user who wants
`reduceApp`/`reduceAssign` to fire is, in effect, implementing a
pluggable Datalog storage/evaluation backend, not observing/rewriting
terms in a running query.

### AST identity and ownership — the values are real, and Z3 owns `res`

The reduce callbacks' `decl`/`args`/`res` are **not** opaque or
synthetic — they are real `ast_manager` ASTs, specifically fresh
0-arity "register" consts the `external_relation` plugin mints to name
each relation instance (`dl_external_relation.cpp:84,138`;
`z3_fixedpoint.h:349-351` documents the register-const convention).
They decode and render (`$`) exactly like any other `Z3AnyAst` would.

The `res` out-param's ownership — the question ADR-FC-0003 spent most
of its length hedging into branches (a)/(b) — is **settled by source,
not by experiment**:

```cpp
// src/api/api_datalog.cpp:76-89 (roughly)
Z3_ast Z3_API Z3_fixedpoint_reduce_app_dummy... /* callback trampoline */
    ...
    // caller-supplied res is inc_ref'd and rooted by the API layer
    // itself once the user's C callback returns, unconditionally.
```

Z3's C API layer `inc_ref`s and **permanently roots** whatever the
registered C callback wrote into `res`, immediately after the callback
returns, regardless of what the callback itself did. That means:

- A typed shim does **not** need to `inc_ref` before writing `res[]`
  — the API layer's own inc_ref covers it. ADR-FC-0003's ownership
  branch (a)/(b) fork is **moot**: there is no "does Z3 take an extra
  ref on top of ours" ambiguity, because the shim never needs to add
  one in the first place.
- `reduce_assign` has **no writable AST out-param at all** — it is
  pure notification (`inArgs`/`outArgs` in, nothing returned), so no
  ownership question arises for it either.

**The spike's earlier crash (pre-source-read) was a semantic bug, not
UB.** An early no-op-`reduceApp`-returning-`none` run crashed inside
Z3 — initially read as a pre-fill/UB hazard (RFC §4, "none/pre-fill
contract"). Root cause on inspection: the throwaway shim reused a
stale register identity across two different relation instances (a
register-const minted for relation A written into `res` while
processing relation B's op) — a **register-identity bug in the spike
code**, not an uninitialized-memory or refcount defect in Z3's API. `res`
*is* safe to leave untouched on `none`; Z3 does not read garbage.

### Verdict

A safe, correct, useful typed wrapper for `reduceApp`/`reduceAssign` is
**feasible, medium effort** — but it is a **relation-algebra op-kind
dispatcher** (`Z3_OP_RA_IS_EMPTY`/`JOIN`/`COMPLEMENT`/`PROJECT`/`RENAME`
→ typed variant handling), not the generic
`reduceApp(decl, args) -> Option[Z3AnyAst]` shape ADR-FC-0003 designed.
That is a materially different, larger design problem than "one more
closure field," so it is **deferred to a dedicated v2.2 RFC**
(see [RFC-fixedpoint-callbacks.md](RFC-fixedpoint-callbacks.md) §2,
ADR-FC-0003 marked SUPERSEDED/DEFERRED). It stays available today at
the raw §N7.8 surface (`setReduceAssignCallback`/`setReduceAppCallback`,
`fixedpoint.nim:312-352`).

## 3. Same-thread confirmation

Both sub-families fire **synchronously on the calling query thread**:
a throwaway shim recorded its own thread id and compared it against
the `query`/`queryFromLevel` caller's — they matched on every fire, for
every callback, on both entry points. Fixedpoint gives the same
no-cross-thread guarantee `z3/propagator` already documents for
`check()`. Feeds `THREADING.md`'s new "callback threading" section
(RFC C3).

## 4. Z3 4.16.0 — no help, stay pinned on 4.15.0

Re-ran both halves of the spike against a Z3 4.16.0 build to see if the
newer release changes either callback family's behavior (e.g. relaxes
the `external_relation` requirement, or removes `newLemma`'s param
gate). It does not — 4.16.0 is **behaviorally identical** to 4.15.0 for
both sub-families. No motivation to move off the pinned 4.15.0.

For the record, the 4.15.0 → 4.16.0 FFI delta (`ffi.nim` is
hand-maintained, not generated) is trivial: `Z3_mk_set_has_size` is
removed, and `Z3_fpa_get_numeral_sign`'s out-param changes from `int*`
to `bool*`. The Spacer and fixedpoint headers relevant to this RFC
(`z3_fixedpoint.h`, the Spacer callback entry points) are **byte-
identical** between the two versions.

## 5. Files in this spike

- Throwaway counting-shim harnesses for both sub-families, driven
  against Spacer/Datalog fixtures under `query` and `queryFromLevel`;
  not yet committed as `tests/tfixedpoint_fixtures.nim` (RFC §6 — that
  promotion happens when Stage A/B slices land, not at spike time).
- Z3 source read for the citations above:
  `src/muz/spacer/spacer_context.cpp` (`new_lemma_eh`),
  `src/muz/rel/dl_external_relation.h`/`.cpp`, `src/api/api_datalog.cpp`,
  `src/api/z3_fixedpoint.h`.

## 6. Cost / value assessment

**Bugs prevented:** the reduce half in particular — building B1-B3 as
originally scoped (`reduceApp(decl, args) -> Option[Z3AnyAst]` against
a guessed BitVec-relation fixture) would have shipped a typed API that
**silently never fires** for any ordinary use (no test would catch it,
since the guessed fixture doesn't exercise the real firing path
either), and would have baked in a wrong signature that a v2.2 redesign
would then have to break. Reading Z3 source before writing the ADR's
"final" signature saved both a shipped-dead-on-arrival API and a
future breaking change.

**Architectural confidence:** high for the export trio (ships as
designed, one param-gate fix). Medium-high for reduce: reachable and
well-understood now, but correctly scoped as its own RFC rather than
squeezed into this one's slice plan.

**Recommendation:** proceed with v2.1.0 as scoped in
[RFC-fixedpoint-callbacks.md](RFC-fixedpoint-callbacks.md) §2 (export
trio + scaffold only); open a v2.2 RFC for the reduce
relation-algebra dispatcher once there's demand, using ADR-FC-0003 and
§2 of this document as its starting point.

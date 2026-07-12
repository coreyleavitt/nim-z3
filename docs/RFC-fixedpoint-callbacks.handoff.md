# nim-z3 fixedpoint typed callback API — handoff

- **Stage:** **4 (CODE REVIEW) — FIX LOOP AT FLOOR (2026-07-12).** Round 1: 5 reviewers →
  1 HIGH (H1, confirmed) + 9 Medium + 10 Low. Fixed through Medium (mandate); round-2 re-review
  (correctness/security + design + propagator/CI) surfaced 0 Crit/High/Med — **floor reached.**
  Round-2 design nits (3 Low one-liners) folded in. Remaining Lows (L1-L10) deliberately left per
  mandate. All fixes green both backends; H1 fix valgrind-clean + re-review-confirmed sound.
  **⚠ STILL ALL UNCOMMITTED.** Prior stage line retained below.
- **(prior)** **3 (TDD) COMPLETE — ALL v2.1.0 SLICES IMPLEMENTED (2026-07-11).**
  Stage D done+signed-off; Stage 0 spike done+escalation-resolved; Stage A (A0/A1/A2+redesign/A3)
  done; Stage C (C1 a/b/c/d, C2, C3) done. Stage B (reduce typed API) DEFERRED to a dedicated
  v2.2 RFC. v2.1.0 ships: typed export callbacks (newLemma/predecessor/unfold + box/scaffold)
  on a lazy-activation architecture, collectLemmas/Z3LemmaLog, the interrupt→zsUnknown fix,
  the -d:z3WithoutFixedpointCallbacks gate, and full docs.
- **Resume:** **→ Stage 4 (code review).** Run `/code-review docs/RFC-fixedpoint-callbacks.md`
  (or `/code-review ultra` for the branch). ⚠ ALL WORK IS UNCOMMITTED — the whole RFC lives in
  the working tree (no commits made per standing order). Consider committing the completed
  stages before/at review (Corey's call). A `/compact` is safe here — this handoff has full state.
- **Round:** 2 done (architect). Stage-4 review not started.

## ⛔ STAGE-0 ESCALATION (2026-07-11) — 3 wrong-spec findings, loop PAUSED
The Stage-0 feasibility spike (subagent, 137 tool-uses, ~29 min, Z3 4.15.0)
proved that three assumptions baked into the RFC are empirically FALSE. Per the
standing orders (spec assumptions are escalations, not edits) and the RFC's own
Stage-0 contingency clause (§ line 864: "if a sub-family cannot be fired … STOP
and escalate … the RFC scope must shrink or add a lower-level driver"), the grind
is PAUSED for Corey's scope decision. Spike probes preserved in `scratchpad/spike_q*.nim`.

**FINDING 1 — `newLemma` non-firing → RESOLVED (2026-07-11): it's PARAM-GATED, not
dead.** Original symptom: `newLemma` fired 0× in the Stage-0 spike while
`predecessor`/`unfold` fired fine. ROOT CAUSE (source-confirmed, Z3
`spacer_context.cpp:4286-4304` `context::new_lemma_eh`): the callback dispatch loop
is SKIPPED unless `m_params.spacer_p3_share_lemmas()` (finite-level lemmas) or
`spacer_p3_share_invariants()` (infinity-level) is true — defaults false
(`fp_params.pyg:169-170`). `predecessor_eh`/`unfold_eh` have no such gate → they
always fired. **FIX (wrapper-side, no Z3 patch, works on 4.15.0):** set
`fp.spacer.p3.share_lemmas=true` (+ `share_invariants=true` for oo-level) before the
query. Verified: `newLemma` then fires 3× (UNSAT fixture) / 10× (SAT).
⇒ **A2 is fully TDD-able AS SPECCED** — `setHandlers`/`addCallback` install path
should set these params (or document that the caller must). Probe:
`scratchpad/spike_q1c_p3share.nim`.
SECONDARY ROUTE (bonus, already wrapped): `fp.getNumLevels`/`fp.getCoverDelta`
(fixedpoint.nim:190-205) recover the final inductive invariant per level post-query
with NO callback — good "give me the invariant after the fact" story, but final-state
not a stream, so complementary to (not a replacement for) the live callback. Probe:
`scratchpad/spike_q3_postquery.nim`.

**FINDING 2 — reduce callbacks only fire via an UNDOCUMENTED plugin protocol,
NOT term rewriting (blocks B2/B3, invalidates ADR-FC-0003's narrative).**
`set_reduce_assign`/`set_reduce_app` fire **0×** for ordinary relational joins or
arithmetic under Datalog's default `pentagon` relation backend. They fire ONLY when
`p.set("datalog.default_relation", "external_relation")` (undocumented; found via
`fp.getHelp()`), and then only for the external-relation plugin's OWN bookkeeping ops
(`empty`/`clone`/`store`/`union` for reduce_assign; `is_empty`/`complement`/`join`
for reduce_app, over an opaque `Table`/Relation sort). We found NO recipe that fires
reduce for the RFC's assumed case ("rewrite an interpreted-function application like
`x+1` during normal rule evaluation"). **ADR-FC-0003's typed signature
`reduceApp(decl: Z3AnyFuncDecl, args: seq[Z3AnyAst]): Option[Z3AnyAst]` is modelled on
a scenario that does not occur.** B2/B3 must be re-scoped against the actual
external-relation protocol (opaque-sort, advanced escape hatch) OR shipped raw-only.

**FINDING 3 — reduceApp `res[]` ownership branch UNRESOLVED (was meant to be pinned
here).** Pre-fill contract is clean: `res` is NOT pre-initialised — a reduce_app that
returns without writing `res` = UB (crash/hang); always write on `some`. But the
(a)-vs-(b) ownership pick is contradictory: `bare` (no inc_ref) crashes instantly;
`transfer` (net refcount 1 = ADR branch (a)) ALSO crashes instantly; `wrapdrop`
(refcount→0 = the "naive bug") does NOT crash. Confounded by the opaque-sort plugin
context (Finding 2) — the "no crash" is really "plugin search runs forever on an
unconstrained fresh value", not a verified-correct completion. **Recommend defaulting
to branch (a) (explicit inc_ref; worst case a leak, not a UAF) with a documented
caveat, and treating it as unresolved pending Z3 source inspection or an ordinary-sort
firing recipe.** Not independently decidable until Finding 2's scope is settled.

**CLEAN findings (no escalation):**
- Q4 same-thread: **YES** — caller tid 95 == callback tid 95; callbacks are
  synchronous on the query thread. Feeds THREADING.md (C3). Solid.
- predecessor + unfold: fire reliably both entry points, SAT+UNSAT → **A3 is a go.**

**RECOMMENDED SCOPE (my read, for Corey to accept/override):**
1. **Ship the fireable half.** A0/A1 (box+scaffold+setHandlers) + A3 (predecessor+
   unfold) proceed as written — real, TDD-able typed callbacks. Q4 thread note lands.
2. **`newLemma`, `reduceApp`, `reduceAssign` → typed field kept but documented as
   "not fireable on Z3 4.15.0 via the public query surface" + raw escape hatch.**
   Keeps the record complete and forward-compatible without shipping tests that can't
   go green. (Alt: drop them from the typed API entirely — cleaner surface, but loses
   the "complete lib" goal and forward-compat.)
3. **Re-scope B2/B3 (or cut them):** if reduce callbacks stay in scope, they need an
   architect round to redesign the typed API around the external-relation plugin
   protocol (opaque Table/Relation sorts) — that's a materially different, advanced
   API than ADR-FC-0003 describes. My lean: **cut reduce from v2.1.0 typed scope**,
   ship raw-only, revisit in a dedicated RFC if there's demand — the plugin protocol
   is niche and its value contract is undocumented.
4. Before finalizing, optionally spot-check `newLemma`/reduce against a newer Z3 (but
   ffi.nim is pinned to 4.15.0 — 4.15.8/4.16 need an ffi regen first, out of scope).

## INVESTIGATION UPDATE (2026-07-11) — Corey said "both go"
Findings 1's resolution above (param gate) already de-escalates A2. Two more probes ran:
- **ffi.nim regen scoping (DONE):** ffi.nim is HAND-maintained (no generator). Newest
  target = **Z3 4.16.0** (cached at `~/.cache/nim-z3-test/z3-latest`). Delta 4.15.0→4.16.0
  is TRIVIAL: only 2 symbols break (`Z3_mk_set_has_size` removed; `Z3_fpa_get_numeral_sign`
  `int*`→`bool*`), NEITHER on the fixedpoint path. **Spacer/fixedpoint headers are
  byte-identical 4.15.0↔4.16.0** → the newer-Z3 check needs NO ffi edits: compile against
  4.15.0 headers, run against 4.16.0 `libz3.so` (split-mount). For a permanent dual-version
  ffi it's MODERATE (the fpa `int*`→`bool*` is a real ABI change needing a `-d:` flag;
  precedent: the `z3WithSeqReplaceAll` gated blocks). Full delta table in subagent report.
- **4.16.0 callback check (DONE):** split-mount (4.15.0 headers + 4.16.0 libz3, +
  comment-out of the absent `Z3_mk_set_has_size`) confirmed runtime `Z3 4.16.0`.
  Result: **4.16.0 changes NOTHING for either escalation.** newLemma still 0× WITHOUT
  the p3 param (spike didn't set it; source gate is identical); predecessor/unfold fire;
  reduce still fires ONLY under `external_relation`, 0× under default pentagon relation.
  ⇒ **No reason to move off the pinned 4.15.0.** newLemma is solved by the param
  (version-independent); reduce is a version-independent feature mismatch. Experiment
  edits reverted (`git checkout ffi.nim sets.nim`).

**REMAINING OPEN (still needs Corey): Finding 2 (reduce = external-relation plugin
protocol, not term rewriting).** Finding 1 CLOSED (param). **Finding 3 now RESOLVED
(see below).** Scope question narrows to: what to do with `reduceApp`/`reduceAssign`.

## FINDING 3 RESOLVED + reduce wrapper FEASIBILITY (2026-07-11, Z3 source dig)
Reverse-engineered the external-relation contract from Z3 z3-4.15.0 source
(`src/muz/rel/`, `src/api/api_datalog.cpp`). Verdict: **SAFE-USABLE-WRAPPER-FEASIBLE**
— Corey's "make it safe at the wrapper level" instinct was correct.
- **The "opaque Table" values are NOT opaque** — they're genuine `ast_manager`-owned
  `expr` nodes: fresh 0-arity uninterpreted constants ("registers"), real `Z3_ast`
  handles (`dl_external_relation.cpp:84,138`; `z3_fixedpoint.h:349-351`). Fully
  memory-safe to introspect (`Z3_get_sort`/`to_string`/`get_decl_kind`). They're
  identity tokens only; actual relation content lives in a wrapper-side map keyed by
  `Z3_get_ast_id`.
- **Finding 3 (res ownership) RESOLVED = Z3 auto-owns; callback must NOT pre-inc_ref.**
  `api_datalog.cpp:76-89`: Z3 assigns the returned `expr*` into an `expr_ref` (inc_ref)
  AND pushes it to `m_trail` (permanent root) the instant the callback returns. So the
  callback just returns a valid live `Z3_ast`; no ref bookkeeping needed. `reduce_assign`
  has NO writable AST out-param at all (pure dictionary mutation on identity keys → zero
  refcount surface). **The Stage-0 spike's crash/"ran forever" was a SEMANTIC
  register-identity bug (collapsing distinct relation states onto one fresh-const),
  NOT a UB/ownership bug.** So ADR-FC-0003's ownership-branch worry is moot for this path.
- **A safe, genuinely-usable typed API is buildable, MEDIUM effort:** model `Table` over
  existing `AstRef` machinery; per-`Fixedpoint` registry `AstId→RelationData` with a
  teardown finalizer; dispatch `reduce_app` on `Z3_get_decl_kind` over the documented
  `Z3_OP_RA_IS_EMPTY/JOIN/COMPLEMENT/PROJECT/RENAME` (`z3_api.h:787-836`), `reduce_assign`
  on `STORE/EMPTY/CLONE/UNION/WIDEN/FILTER/…`. No `cast`/unsafe anywhere. It IS the full
  "typed programmable Datalog relation-backend" API (Option B), now shown feasible+safe.
- **BUT:** it's a real subsystem (13 RA op-kinds + registry + param decoding + finalizer),
  its own architect round, and it targets the de-emphasized Datalog relational engine
  (Spacer/CHC is the modern path; the export callbacks we ship already serve Spacer).
  ⇒ Decision is now pure VALUE/TIMING, not feasibility. **Recommend: ship the 4 working
  typed callbacks in v2.1.0; spin the reduce relation-backend API into its OWN dedicated
  RFC (proper design treatment) rather than raw-only-forever or bloating v2.1.0.**
  Corey to confirm: (A) defer reduce to its own RFC [rec] / (B) expand v2.1.0 now /
  (C) raw-only permanently.
- **Regression sweep DONE (2026-07-11, Z3 4.15.0) — CLEAN.** 136 test files, 130
  pass / 6 fail; all 6 pre-existing & unrelated to the fix. Sibling `wrapAstVector`
  valgrind audit: all 6 accessors CLEAN (0 invalid access, 0 definitely/indirectly
  lost). No regressions, no new memory-safety findings. `tast_introspect` +
  `tmodel_enum` (both failed on old 4.13.4 sweep) now PASS.
  **Pre-existing failures (OUT OF SCOPE for this RFC — do not fix under D):**
  `tffi`/`tversion` (Z3 "Z3 4.15.0.0" prefix vs `startsWith("4.")`); `tgoal_introspect`
  (compile error line 111: test calls `assertConstraint(Z3Goal,…)` but tactic.nim only
  exposes `add(Z3Goal, Z3Bool)` — a real test/source naming drift worth a future issue);
  `tdoc_audit`/`torphan_audit`/`trunnable_audit` (meta-audits: bare `X.nim` backtick refs,
  `talgebraic_bounds.nim` unlisted in nimble test task, `algebraic.nim` missing
  runnableExamples). None touch the runtime/memory surface the fix changed.

## D3 REF-HANDLE FIX — SHIPPED & PROVEN (2026-07-11, Z3 4.15.0)
The principled fix landed (uncommitted, in tree). Three coordinated edits:
1. **`src/z3/lifecycle.nim` `emitRefcountLifecycle`:** re-applied the D3 `ctx`
   ARC-ref release (after the raw dec_ref) — the ref-handle analogue of
   `termDestroy`'s value-type release; every ref-handle now frees its owning
   context ref. ALSO taught the template to honor an optional `borrowed: bool`
   field via `when compiles(v.borrowed)`: borrowed handles skip the raw dec_ref
   (Z3 owns them, frees via `Z3_del_context`). Generic — any `*Own` type can now
   opt into borrow semantics just by declaring the field.
2. **`src/z3/astvector.nim`:** added `borrowed: bool` to `Z3AstVectorOwn` +
   `wrapAstVectorBorrowed*` (no inc_ref; sets borrowed=true; still holds+releases
   the ctx ARC ref so the owning context outlives the handle).
3. **`src/z3/model.nim` `sortUniverse`:** now `wrapAstVectorBorrowed(m.ctx, raw)`,
   dropped the compensating `Z3_ast_vector_dec_ref`. Doc rewritten to state the
   real ownership (Z3 keeps the vector; caller must NOT free it).

**PROOF (all on Z3 4.15.0, `nim c --mm:orc -d:useMalloc`):**
- `tmodel_enum` (sortUniverse path): 13/13 [OK], **Invalid read/write = 0** (was the
  2841-invalid-read SIGSEGV), definitely+indirectly lost = 0. The 2841 "errors" in
  valgrind's ERROR SUMMARY are now all "possibly lost" (Z3's live-context arena via
  interior pointers — the test keeps contexts alive to exit; `--error-exitcode=99`
  counts possibly-lost). NOT memory errors.
- `td3_ctx_release` valgrind: **definitely lost 0, indirectly lost 0, Invalid r/w 0.**
- `td3_ctx_release -d:z3CtxDestroyCount`: **counting hook = exactly 2N** →
  `Z3ContextOwn.=destroy` fires the right number of times (no leak, no double-free) —
  the classification-immune proof the ref-handle ctx-release works.
- Former crashers all green: `tast_introspect` 12 OK (globalParamDescrs was
  4.13.4-only, gone on 4.15.0), `ttranslate` 6 OK, `tsolver` 23 OK.
- Sibling `wrapAstVector` accessor audit (getUnsatCore/trail/units/parseFromString/
  algebraicGetPoly/subresultants/keys): running in background subagent — theory is
  they return FRESH result vectors (not internally-aliased like sortUniverse) so are
  safe; tsolver teardown already crash-free. Confirm via the sweep's Invalid-read check.

**HARNESS:** reconstructed `scratchpad/nimz3.sh` (was wiped) — runs against Z3 4.15.0
mounted from `~/.cache/nim-z3-test/z3-4150` over `/opt/z3`; ffi.nim uses `dynlib "z3"`
so only `LD_LIBRARY_PATH=/opt/z3/bin` matters at runtime (no compile-time -I/-l needed).
milpa `~/.cache/milpa` mounted at same absolute host path (symlinks are absolute).
Image rebuild with 4.15.0 baked is now OPTIONAL (mount-over works); do it before CI.

## Stage-3 progress
- [x] **D2 — context `=destroy` registry release (ADR-FC-0011).** DONE.
  `context.nim` `=destroy` now releases `datatypeRegistry`/`uninterpretedRegistry`
  unconditionally (param → `var`), before the `borrowed` check. lifecycle.nim doc
  warning added. New test `tests/tcontext_registry.nim` wired into `test` + `valgrind`
  tasks. **Verified:** isolated uninterpreted-only teardown → `definitely lost: 0`
  under `-d:useMalloc`; both backends green; no `tcontext` regression.

## ESCALATION (loop paused) — valgrind harness is blind to Nim-side leaks
The D2 audit exposed that the committed `nimble valgrind` task runs **without
`-d:useMalloc`**, so valgrind's malloc-based leak-check cannot see ANY Nim-side
leak (Nim's default allocator is mmap/arena). Empirically: the exact D2 bug shows
`0 lost` without useMalloc vs `262,152→0` with it. Consequences:
- The RFC's D2/D3/A0/C1 "valgrind proves definitely-lost:0" RED is **not achievable
  in the committed harness as-is** (wrong baked-in assumption → escalation).
- Turning ON `-d:useMalloc` reveals **pre-existing Nim leaks**: `tdatatypes` 416 B
  (the `Z3ConstructorDeclOwn[T].=destroy` in datatypes.nim:173 never releases its
  `ctx` — same ADR-FC-0011 class, hand-written destructor NOT covered by D3's
  template fix); `tcontext_registry` 32 B (same datatypes bug via its dtCtx).
- D3-class template ctx-leak shows as **"still reachable"** (not "definitely lost")
  on single-context fixtures (`tsolver`/`tmodel` = 0) → definitely-lost gate is the
  wrong instrument for it; D3 needs the **counting-hook** proof the RFC already lists.
- **Recommendation (leading option A):** add `-d:useMalloc` to the valgrind harness
  now (makes the whole audit sound), batch a new slice **D4** to fix
  `Z3ConstructorDeclOwn` (+ audit sibling hand-written destructors: funcdecl types,
  Z3FixedpointOwn), and reword RFC §7/D2/D3 RED to specify `-d:useMalloc` + counting
  hooks where "still reachable" applies. Grows v2.1.0 scope → needs Corey's sign-off.
  Alt B: keep harness as-is, prove RFC's own leaks via dedicated useMalloc leak-tests
  + counting hooks, file datatypes.nim leak as a separate issue.

- **Resume after decision:** continue Stage 3 —
  `/loop implement the next unimplemented RFC slice with /tdd, following the standing rules;
  after each slice report one progress line; stop when every slice is implemented`
  (good `/compact` point first). Suggested order: D2→D3→D1 (backfixes, de-risk destructor) →
  Stage 0 spike → A0/A1 → A2/A3 → B1/B2/B3 → C1/C2/C3.

## Fork RESOLVED (§11a) — author chose Option A (batch)
Systemic `ctx`-field leak (probe FACT A): `emitRefcountLifecycle`'s custom `=destroy` leaks the
`ctx` ref on ALL ~15 handle types. **Batched** as ADR-FC-0012 + slice D3 (extend the template to
release `ctx` after raw dec_ref; valgrind proof across Z3Solver/Z3Model). Z3FixedpointOwn carries
the same discipline by hand (it's off the template due to cbBox).

## Round-2 probe (scratchpad/probe2.nim, uncommitted) — both facts CONFIRMED
- FACT A: plain `ref` field leaked by custom `=destroy` (ctx released 0×) → systemic leak real.
- FACT B: `ref object of RootObj` reclaimed deterministically on scope exit under ORC →
  A0 collection test uses a counting `=destroy` on FixedpointCtxBox, asserts on scope exit
  (no legacy `new(x,finalizer)` needed).

RFC: [docs/RFC-fixedpoint-callbacks.md](RFC-fixedpoint-callbacks.md)
Source: `RFC-completeness.md` §N7.8. Target release: **v2.1.0** (additive).

## Test harness (Stage-3 discovery — reused by every slice)
nim is Docker-only (image `ghcr.io/coreyleavitt/nim:2.2.10`, openSUSE/zypper) and
has **no z3**. Built a reusable image **`nim-z3-test:latest`** = that image + Z3
4.13.4 baked at `/opt/z3` (`C_INCLUDE_PATH`/`LD_LIBRARY_PATH` set) + valgrind 3.27.
Helper: **`scratchpad/nimz3.sh {c|cpp|nimble|valgrind|raw} <args>`** — mounts the
repo + `~/.cache/milpa` (so nim.cfg `_deps` symlinks resolve). Verified: functional
`nim c -r` AND the valgrind gate (`definitely lost: 0 bytes`) both work. Baseline
`tcontext` valgrinds clean because its fixture leaves the registries empty — exactly
why the ADR-FC-0011 bug hides. (Rebuild image via `scratchpad/imgctx/Dockerfile`;
z3 tarball cached at `~/.cache/nim-z3-test/z3`.)

## Architect round 1 — done (4 lenses: depth, breadth, design, feasibility)
Consolidated ~30 findings; applied all clear-best fixes to the RFC. Key changes:
- **CRITICAL fixes applied:** reduceApp `res[]` refcount ownership-transfer
  (inc_ref before return, ADR-0003); mandatory shim exception wall + `{.raises:[].}`
  (ADR-0001); `cbBox` GC seam — `RootRef` erasure + explicit `=destroy` drop
  (ADR-0002); init ordering pinned — direct FFI, unconditional init first, checkErr
  (new ADR-0008); Stage 0 feasibility spike now GATES the slice plan (no test in
  repo proves ANY callback fires today).
- **HIGH:** `Z3RawFuncDecl`→ erased-typed `Z3AnyFuncDecl` (was 3 inconsistent
  names; opaque raw contradicted the RFC's own motivation); raw/typed mutual
  exclusion (new ADR-0009); engine/handler coupling documented.
- **Design/ergonomics:** `installHandlers`→`setHandlers` (sibling parity w/
  setParams) + `clearHandlers`/`hasHandlers`/`collectLemmas`; `FixedpointCbBox`→
  `FixedpointCtxBox`.
- **Module placement resolved:** field+accessors+lifecycle in always-on
  fixedpoint.nim; all callback code in gated `z3/fixedpoint_callbacks`; one-way
  import; `Z3AnyFuncDecl` in funcdecl_types.nim.
- **Harness corrections:** ORC-leak-counter harness doesn't exist → use
  GC_fullCollect + add to `nimble valgrind` subset; `testMinimal`→ tspacer-style
  same-file skip-suite; C3 doc list expanded (THREADING.md, GOTCHAS.md, PARITY
  handler-record exemption category).
- All 4 prior open questions resolved into ADRs.

## §11 fork — RESOLVED: author chose BATCH IN
Both pre-existing v2.0 latent bugs are now batched into this RFC (ADR-FC-0010,
ADR-FC-0011; Stage D slices D1/D2):
1. propagator shim exception wall (D1).
2. context.nim:107 =destroy Table-field leak — **CONFIRMED by probe**
   (Nim 2.2.10 --mm:orc: user =destroy skips field destruction; untouched
   Table[string,ref] ref values destroyed 0×, not 2×). Probe also hardens
   ADR-FC-0002 (cbBox would leak identically). Probe kept at
   scratchpad/probe.nim (not committed).

## Other decision surfaced (not blocking, recommended-and-applied)
- `Z3AnyFuncDecl` is a NEW always-on public type (small, reusable, mirrors
  Z3AnyAst). Applied as bar-correct; flag if you'd rather keep scope to raw handle.

## Slices (defined in RFC §6 — none implemented; Stage 0 spike gates Stage A/B)
- [~] **Stage 0 — spike DONE, ESCALATED (see ⛔ block at top).** Export: predecessor+
      unfold FIRE (both entry points, SAT+UNSAT); **newLemma NEVER fires**. Reduce: fires
      ONLY via undocumented `datalog.default_relation=external_relation` plugin protocol,
      NOT term rewriting → ADR-FC-0003 premise false. Ownership branch unresolved (default
      (a) recommended). Same-thread: YES (tid 95==95). Fixtures in `scratchpad/spike_q*.nim`
      (promote the export/thread ones once scope is fixed). **AWAITING COREY'S SCOPE CALL.**
- [x] **A0 DONE (2026-07-11)** box+RootRef field+hand-written =destroy (replaces fixedpoint.nim:76 emit call)+collection proof (FACT B).
  New module `src/z3/fixedpoint_callbacks.nim` (`FixedpointCtxBoxObj = object of RootObj` holding `ctx`; `ref` alias `FixedpointCtxBox`; gated counting `=destroy` under `-d:z3FpBoxDestroyCount`). fixedpoint.nim: `cbBox: RootRef` field + `cbBoxRef`/`cbBoxRef=` INTERNAL_API accessors; hand-written `=destroy(var Z3FixedpointOwn)` (dec_ref raw → drop cbBox → release ctx). New test `tests/tfixedpoint_ctxbox.nim` wired into test+valgrind tasks. PROOF: counter delta exactly N=25 after N fp drops, 0 while rooted+GC_fullCollect; valgrind `definitely lost: 0`; tfixedpoint{,_extra,_callbacks} regression-green. (cpp backend has a pre-existing unrelated z3.h include-path gap — confirmed on unmodified main.)
- [x] **A1 DONE (2026-07-11)** handlers type+gate+setHandlers+inQuery guard via withInQuery choke point (query/queryRelations/queryFromLevel).
  fixedpoint.nim: `inQuery` field + `inQuery*` accessor + `template withInQuery*` choke point, routed through query/queryRelations (fixedpoint.nim) AND queryFromLevel (spacer.nim). fixedpoint_callbacks.nim (now gated `when not defined(z3WithoutFixedpointCallbacks)`): `Z3FixedpointHandlers` (newLemma/predecessor/unfold — reduce cut); box extended with `handlers` field + `=destroy(b.handlers)` (signature now `var`); `setHandlers` (assert not inQuery → alloc+root box → init-first, ADR-FC-0008; add_callback registration marked TODO for A2/A3), `handlers()`, `hasHandlers`, `clearHandlers` (mutates box in place, never nils cbBox — ADR-FC-0008 invariant). New test `tests/tfixedpoint_handlers.nim` (5/5 green) wired into test+valgrind. PROOF: valgrind `definitely lost: 0`; gate-strip `-d:z3WithoutFixedpointCallbacks` compiles+passes (13/13); regressions green (tfixedpoint{,_extra,_callbacks,_ctxbox}, tspacer).
  **SPEC FIX (clear-best mechanism correction, applied to RFC ADR-FC-0005 ~line 554):** RFC said `when defined(debug)` for the guard gate — but Nim never auto-defines `debug`, so that token = permanently dead guard under every build the project runs (A1 empirically confirmed: guard test failed under the literal spec). Corrected to `when not defined(release)` in code + RFC — realizes the RFC's stated intent ("release builds pay nothing") verbatim. Design intent unchanged; only the Nim idiom fixed. Flag if Corey wants the guard gated differently.
- [x] **A2 DONE (2026-07-11) newLemma — but ⛔ ESCALATED (engine-coupling wrong-spec, see below).**
  `newLemmaShim {.cdecl.}` (recover box → `wrap[Z3AnyAst](box.ctx, lemma)` → dispatch under try/except CatchableError wall, no currentBox threadvar per ADR-FC-0007). setHandlers now: when `newLemma != nil` sets `fp.spacer.p3.share_lemmas`+`share_invariants` then `Z3_fixedpoint_add_callback(box, newLemmaShim, nil, nil)`. New test `tests/tfixedpoint_newlemma.nim` (6/6 green) wired into test+valgrind. PROOF: UNSAT count=3 level=1 render=`(=> query!0 false)`; SAT count=10; negative control 0; valgrind `definitely lost: 0`; regressions+gate-strip green (12/12).
  **OPEN NOTE #1 RESOLVED:** share_lemmas is callback-gate-ONLY — with no callback, params on-vs-off give bit-identical Z3Status + all decision stats (SPACER-num-lemmas/conflicts/decisions/propagations); only memory-bookkeeping counters differ (noise). ⇒ auto-set in setHandlers KEPT (clean+ergonomic).
  **FINDING 2 (pre-existing, A2-unrelated, flag as follow-on ticket):** a small "definitely lost" leak reproduces when `registerRelation` runs against *repeated fresh* Z3Contexts in a tight loop (datalog engine, 0 quantifiers, 0 callback code — bisected orthogonal to A2). Not present when a context is reused. Leak-proof test works around by sharing one ctx across N iters (still exercises N fresh fp/setHandlers/query). Probe: `scratchpad/spike_a2_newctx_leak.nim`.
  **⛔ FINDING 1 — WRONG-SPEC (engine coupling), AWAITING COREY:** RFC claims installing an export handler under a non-Spacer engine is "a silent no-op **at the Z3 level**" (RFC lines 148-149, 655-657, 852-853). EMPIRICALLY FALSE: `Z3_fixedpoint_add_callback` RAISES `Z3OperationError`/`Z3_EXCEPTION` ("add_lemma_exchange_callbacks is not supported for datalog") when engine != spacer — including the un-set `auto-config` default (resolves to a concrete non-spacer engine by registration time). A hard raise breaks A1's already-shipped engine-agnostic install path (tfixedpoint_handlers installs newLemma before any engine is chosen) and makes install order-dependent. **RESOLVED → A2 RE-ARCHITECTED to lazy activation; ADR-FC-0008 install-time registration SUPERSEDED (see the "A2 lazy-activation redesign" block below).**

  **### A2 lazy-activation redesign (2026-07-11) — ADR-FC-0008 install-time registration SUPERSEDED.**
  Root cause: `setHandlers` fused *intent-recording* (store closures — engine-agnostic, always safe) with *Z3-activation* (`add_callback` — gated on engine==spacer AT CALL TIME). Eager+swallow had a LATENT CORRECTNESS BUG: `setHandlers` → `setParams(engine=spacer)` → `query` silently produced a DEAD handler (add_callback raised under the default engine, was swallowed, never registered → never fired even under spacer). New design:
  - `setHandlers` = pure intent-recording: alloc+root box, `Z3_fixedpoint_init` (engine-agnostic — only pins state, does NOT touch/lock the engine), done. Never raises on engine grounds, fully install-order-independent.
  - **Lazy activation at the query choke point via a proc-var hook seam** (dependency-inversion twin of the `cbBox: RootRef` data seam): always-on fixedpoint.nim declares `var exportActivateHook*: proc(fp){.nimcall,raises:[].}` (nil unless gated module compiled in); `withInQuery` fires it (covers query/queryRelations/queryFromLevel). Gated fixedpoint_callbacks.nim defines `activateExportCallbacks` + assigns the hook at module-init. Under `-d:z3WithoutFixedpointCallbacks` → hook nil → zero cost.
  - `FixedpointCtxBoxObj` gained `exportActivated: bool` — latch registration at-most-once, set true ONLY on successful add_callback (non-spacer branch leaves it false so a later query can retry — though see engine-lock below).
  - **Engine detection:** no clean Z3 API to read the resolved engine (params write-only; descrs are schema). So `activateExportCallbacks` uses a NARROW `except Z3OperationError` around exactly the add_callback call — SOUND because Z3 source (`muz/base/dl_engine_base.h` default `add_callback` = pure `throw`) proves that call's ONLY failure mode is the engine-support check (masks nothing). Now at query time (engine final), not install time → order-correct. share_lemmas/share_invariants params also only set here, only under the newLemma-present path.
  - **Z3 PLATFORM CONSTRAINT discovered (documented for C3/GOTCHAS, not a fork): engine is LOCKED one-shot** at first engine-touch (`dl_context.cpp ensure_engine`); a later `setParams(engine=…)` is a silent Z3-level no-op. So "retry across a mid-life engine switch" is physically impossible — the impossible retry-test was replaced with an achievable at-most-once idempotency test. This is WHY lazy works: init defers first engine-touch to query time, after the user has chosen the engine.
  - **Optional C-stage enhancement (now more motivated by engine-lock):** a debug-only note / queryable "export handlers installed but engine=<x> (locked) can't fire them" at activation time — actionable since the engine is final+locked. Additive C3 polish, not blocking.
  PROOF: order-independence test count 0 (eager, RED) → ≥1 (lazy, GREEN); idempotency (2nd query same fp fires again, no double-register); spacer-first UNSAT≈3/SAT≈10 still green; negative control 0; datalog/unset no-raise; valgrind `definitely lost: 0`; gate-strip compiles+passes+hook nil; regressions green. Probe: `scratchpad/spike_a2redesign_engine_lock.nim`.
- [x] **A3 DONE (2026-07-11) predecessor+unfold — STAGE A COMPLETE.** `predecessorShim`/`unfoldShim` (payload-free `{.cdecl.}`, nil-guard + exception wall, no threadvar per ADR-FC-0007). `activateExportCallbacks` generalized: gate now fires if ANY of newLemma/predecessor/unfold set (was newLemma-only — wrongly skipped predecessor/unfold-only installs); `add_callback` passes each shim conditionally (typed-nil for absent); share_lemmas param stays newLemma-only (predecessor/unfold not param-gated). Tests folded into `tests/tfixedpoint_newlemma.nim` (13 total OK: 5 A2 + 2 redesign + 5 A3 + leak). PROOF: predecessor-only fires (RED 0→GREEN ≥1), unfold-only fires, all-three one query (newLemma=3 predecessor=4 unfold=1 UNSAT), selective-nil no spurious fire/crash; valgrind `definitely lost: 0`; gate-strip green; regressions green.
  **⇒ v2.1.0 typed export surface COMPLETE: newLemma + predecessor + unfold + box/scaffold, all on lazy-activation. Remaining: Stage C (C1/C2/C3). Stage B deferred v2.2. Stage D done.**
- [ ] B1 decodeAstArray + ADR-0007 ctx verification  · [ ] B2 reduceAssign  · [ ] B3 reduceApp+ownership (fresh AND echo-arg; ASAN proof)
- [x] **C1 COMPLETE (2026-07-11)** — C1a (stable-box+dormant+mixing) + C1b(b) (collectLemmas/compose) + C1(d) (interrupt) all done.  — [x] **C2 DONE (2026-07-11) minimal-build gate.** Umbrella export in z3.nim (`when not defined(z3WithoutFixedpointCallbacks): import/export fixedpoint_callbacks`, mirroring propagator/spacer). Skip-suite guards on all 4 gated test files (tfixedpoint_ctxbox/handlers/newlemma/typed_callbacks — `when defined(...): skip-suite else: real suites`, tspacer pattern). tminimal.nim compiles() scope check (probe `(var h: Z3FixedpointHandlers)` — RED-proven: removing umbrella export fails the flag-off `check compiles`). CI (ci.yaml): added z3WithoutFixedpointCallbacks + z3WithoutPropagator + z3WithoutSpacer matrix rows (closed pre-existing propagator/spacer gap) + folded into "everything off" combo + NEW distinct job `gate-fixedpoint-callbacks-skip-suite` compiling tfixedpoint_typed_callbacks.nim under the flag on both backends. PROOF: all 4 files normal-PASS/gated-SKIP (both c+cpp), tminimal both ways (compiles true/false), combined-off PASS, full regression green; ci.yaml valid YAML (4 jobs parse).  · [x] **C3 DONE (2026-07-11) docs — FINAL SLICE.** All 9 targets: fixedpoint_callbacks.nim threading-contract docstring; z3.nim layered entry (v2.1); PARITY.md new §3 handler-record exemption (covers Z3PropagatorHandlers + Z3FixedpointHandlers); INTERNAL_API.md cbBox/exportActivateHook seam; THREADING.md "callback threading" section (same-thread tid==tid); GOTCHAS.md #20-23 (mixing/engine-coupling/dormant/interrupt); MINIMAL_BUILD.md z3WithoutFixedpointCallbacks + FIXED stale z3WithoutFixedpoint dead-ref@143; tfixedpoint_callbacks.nim raw-header updated; CHANGELOG [2.1.0]. Bonus: RFC-completeness §N7.8 marked resolved, IMPLEMENTATION_PLAN note. Every claim verified vs shipped source. Smoke: tfixedpoint_callbacks 7/7, tminimal 10/10 green.
  - [x] **C1(d) DONE (2026-07-11, Corey approved Option 1: fix in wrapper layer).** Ground truth: `Solver.reasonUnknown()` after interrupt == `"interrupted"` (matches shipped docstring+RFC — NO correction needed; the FFI-level `"canceled"` string is only the detection discriminator). FIX (always-on): shared template `runCancelableFixedpointQuery*` (fixedpoint.nim) used by query/queryRelations/queryFromLevel(spacer.nim) — catches `Z3OperationError` where `code==Z3_EXCEPTION and "canceled" in msg` (narrow discriminator `isZ3QueryCancellation`; genuine Z3_EXCEPTIONs re-raise) → returns zsUnknown + sets new always-on `lastQueryCanceled: bool` field (reset each query); `getReasonUnknown` returns "interrupted" when set. Now uniform with Solver. Un-parked the (d) tests. PROOF: abort query + queryFromLevel → zsUnknown/"interrupted"/fireCount 1 (<natural 3); non-cancellation query still zsUnsat/count 3/unflagged; genuine Z3OperationError (unregistered relation) still propagates; valgrind definitely-lost 0; tinterrupt + full fixedpoint/spacer regression green both backends; gate-strip green. NOTE: a subagent `git stash` momentarily reverted uncommitted work — caught + restored, no loss (see below). **⚠ ALL WORK STILL UNCOMMITTED — consider committing completed stages to de-risk (Corey's call; standing order = commit only when asked).**
  - [x] **C1a DONE (2026-07-11) stable-box fix + dormant/re-install (a) + mixing-hazard (c).** **CRITICAL correctness fix:** A1's `setHandlers` allocated a NEW box + re-rooted on every call → after a query activated box1 (Z3 holds box1's `state` ptr via add_callback, no deregister), a 2nd `setHandlers` dropped box1's only root → ORC freed it → Z3 fired shims on freed box1 = **UAF (SIGSEGV, proven pre-fix)**. FIX (ADR-FC-0008 stable-box): first `setHandlers` allocates+roots+inits; subsequent calls REUSE the box, mutate `box.handlers` in place (no realloc/re-root/re-init, `exportActivated` untouched) → sticky shims read live handlers → nil = dormant-not-deregistered. Mixing guard (ADR-FC-0009): debug-only `rawCbUsed` field on Z3FixedpointOwn + `assertRawCbSurfaceOk` on the 4 raw §N7.8 procs (assert `cbBoxRef.isNil`), `setHandlers` asserts `not rawCbUsed` (+ existing `not inQuery`); `when not defined(release)`. New test `tests/tfixedpoint_typed_callbacks.nim` (7 tests, RFC's canonical integration file — C1b/C2 extend it) wired into test+valgrind. PROOF: dormancy RED=SIGSEGV→GREEN clean; stable-box same-ptr; swap fires new handler; mixing i/ii trip AssertionDefect, iii no false-positive; valgrind definitely-lost 0, 0 invalid-writes (1 invalid-read is pre-existing libz3 spacer::pob_queue::reset artifact, identical on baseline); regressions+gate-strip green. Also fixed `scratchpad/nimz3.sh` to set CPLUS_INCLUDE_PATH (cpp-backend z3.h gap).
  - [x] **C1b(b) DONE (2026-07-11) collectLemmas + Z3LemmaLog + accumulation/compose.** `Z3LemmaLog* = ref object(entries: seq[(lemma: Z3AnyAst, level: uint)])` + `items`/`len`; `collectLemmas*(fp, base=default): Z3LemmaLog` — composes (base.newLemma called first then append; base.predecessor/unfold passed through), installs via setHandlers. Entries survive query AND clearHandlers (independent Z3AnyAst inc_ref copies). Tests in tfixedpoint_typed_callbacks.nim: accumulation log.len==N (cross-checked counter), compose-with-predecessor (log fills + pred fires), compose-with-newLemma (base-first ordering). PROOF: valgrind definitely-lost 0 (only the known libz3 pob_queue::reset invalid-read); both backends green; gate-strip green.
  - [ ] **⛔ C1b(d) BLOCKED — abort-via-interrupt is a WRONG-SPEC finding, AWAITING COREY.** RFC C1(d) (line 1108-1113) AND the pre-existing shipped `Z3Context.interrupt()` docstring (context.nim:267-270, v2.0.0) both claim interrupting an in-flight `fixedpoint.query`/`queryFromLevel` returns `zsUnknown` + `getReasonUnknown=="interrupted"` (like Solver.check). EMPIRICALLY FALSE (probes spike_c1b_abort{,2}.nim): calling `ctx.interrupt()` from a newLemma handler makes `Z3_fixedpoint_query`/`_from_lvl` set Z3_EXCEPTION ("canceled") MID-CALL → `checkErr` RAISES `Z3OperationError` before decodeLBool → the query never returns a Z3Status; getReasonUnknown reads "ok". Structurally unlike Z3_solver_check (which returns L_UNDEF gracefully — tinterrupt.nim confirms). Spacer/Datalog cancellation = thrown C++ exception, not early return. **This is a pre-existing v2.0 doc-vs-reality bug, surfaced (not caused) by C1(d).** Fix touches ALWAYS-ON query/queryRelations (fixedpoint.nim) + queryFromLevel (spacer.nim) for ALL callers → a real design decision on stable code, escalated. OPTIONS: (1) wrapper compensates — catch Z3OperationError/code==Z3_EXCEPTION/"canceled" in the 3 query procs → translate to zsUnknown + synthesize "interrupted" reason (e.g. lastInterrupted flag feeding getReasonUnknown); matches documented contract, uniform w/ Solver, makes the RFC's "sanctioned abort channel" actually work. (2) correct the docs — fix interrupt() docstring + RFC C1(d) to the real contract (raises Z3OperationError/"canceled"), write abort tests as `expect Z3OperationError` + code==Z3_EXCEPTION + bounded fireCount. **My rec: (1)** — best-in-class uniform interrupt contract, fixes a shipped doc bug, correct placement (query-level always-on, callback module stays clean); it's the "fix it ourselves" path. (d) abort tests are HELD OUT of the suite (documented comment at tfixedpoint_typed_callbacks.nim:269-291), tree stays green. C2/C3 remain after (d) resolves.
- [x] **D1 DONE** propagator exception wall — try/except+finally on all 9 cdecl shims (currentBox restored on raise); `fresh` empty-handlers fallback; `raises:[]` on 9 handler fields; forced `raises:[]`+FFI-swallow on registerCb/consequence/nextSplit/propagateConflict; new test tpropagator_exception_wall.nim; tpropagator{,_advanced,_ffi} green both backends. (cast idiom: `{.cast(raises: []).}` not `[CatchableError]`.)  · [x] **D2 DONE** context =destroy field-leak (verified 0-lost under useMalloc)
- [x] **D3 DONE (2026-07-11) — ref-handle release SHIPPED via borrowed-vector fix.**
  See "D3 REF-HANDLE FIX — SHIPPED & PROVEN" section at top. The long forensic
  history below is retained for the record; its "DEFERRED"/"escalated" states are
  SUPERSEDED. Value-type (termDestroy) release was already correct.
- [~] ~~D3 PARTIAL — ref-handle release REVERTED, escalated.~~ (SUPERSEDED) Value-type
  (`termDestroy`) ctx-release KEPT (proven correct, leak→0, no double-free). The
  ref-handle (`emitRefcountLifecycle`) ctx-release **double-frees the context** in ARC
  move-optimized paths (`model.translate`, `globalParamDescrs` manager-singleton) →
  SIGSEGV in `Z3_del_context` (caught by full sweep: tmodel_enum crash, tast_introspect
  pd.len==0). Bisected: disabling ONLY that release fixes both; `var` param makes it worse.
  A subagent's attempted fix (GC_ref+copyMem across 16 wrap constructors + a leaky
  special-case + a dubious "Z3 4.13.4 heap-corruption" claim) was REJECTED as
  non-PhD-CS/unsafe and fully reverted (12 files → HEAD, lifecycle.nim → pre-hack).
  Current tree: emitRefcountLifecycle ctx-release removed (commented, DEFERRED note in
  lifecycle.nim); tast_introspect/tmodel_enum/ttranslate green again. **The pre-existing
  ref-handle ctx-ref leak (v2.0) is now UNFIXED — deferred pending Corey's decision.**
  TODO after decision: relax `tests/td3_ctx_release.nim` (its ref-handle assertion now
  leaks) to value-type-only, or implement a principled ref-handle fix.
  **DECISION (Corey): Option B — invest in the CORRECT best-in-class PhD-level ref-handle
  fix now (NOT GC_ref/copyMem).** Next step: establish ARC ground-truth via a minimal
  probe (does a custom `=destroy` on a ref-POINTEE object suppress field destruction, or
  double-destroy under move-through-param?), then implement the clean ARC ownership
  pattern for the ~15 `emitRefcountLifecycle` Own types. Probe: `scratchpad/probe3.nim`.
  **KEY probe3 finding: the basic release pattern is CORRECT in isolation** — scenarios
  A–D all pass (leak without release; exactly-one-release with it; correct through
  move-through-param; correct with threadvar+2-contexts; correct with shared context).
  ⇒ The bug is NOT the release mechanism (so the prior GC_ref/copyMem hack solved the
  WRONG problem — FORBIDDEN going forward). The real defect is live-Z3-specific:
  suspect destruction ORDER (Z3_del_context firing while the context still has live Z3
  child objects), the manager-global paramdescrs singleton, or borrowed contexts.
  Fix delegated to a background subagent (constrained: no GC_ref/copyMem/special-cases;
  reproduce-with-real-Z3-first). td3_ctx_release ref-handle assertion to be restored once fixed.
  **ROOT CAUSE FOUND (2nd subagent, rigorous, evidence-backed; NO fix shipped — tree left
  at clean DEFERRED baseline, verified green):** the ref-handle ctx-release is blocked by
  **Z3 4.13.4-side object-lifetime coupling**, NOT a nim-z3/ARC bug (raw-FFI harness in all
  4 teardown orderings passed → rules out ARC/ordering). Two accessors return objects whose
  lifetime is secretly tied to the *originating* context: (1) `Z3_model_get_sort_universe`
  (model.nim sortUniverse) — dec_ref'ing the returned ast_vector to 0 then `Z3_del_context`
  → Z3 reads freed memory (valgrind 2841 invalid-reads; skipping the compensating dec_ref
  eliminates ALL, proving the trigger). (2) `Z3_get_global_param_descrs` — the "manager-global
  singleton" is tied to whichever context first fetched it; freeing that context poisons it
  process-wide (keep-ctx1-alive → later len=23; free ctx1 → len=0). Invisible while contexts
  leak (pre-D3), live once teardown is deterministic (D3).
  **⇒ Corey's Option-B premise (a clean nim-z3 fix exists) is FALSE. Re-escalated.** Options:
  (1) file upstream / verify vs newer Z3; (2) narrow documented per-call-site mitigations
  (needs sign-off, violates "no special-cases"); (3) keep DEFERRED (current baseline).
  Also spot-check other wrapAstVector accessors (getUnsatCore, parseFromString) before revisiting.
  **DECISION (Corey, 2026-07-11): make it work — build/test against LATEST Z3 first.**
  KEY: the repo targets **Z3 4.15** (RFC-completeness.md:418 "Z3 4.15.0", :892 "v4.15"), but the
  test harness image `nim-z3-test:latest` was built with **Z3 4.13.4** — OLDER than target. The
  sortUniverse/globalParamDescrs context-coupling bug may be a 4.13.4-specific defect fixed in 4.15.
  RESUME PLAN: (1) re-provision Z3 4.15.x (download release; rebuild `scratchpad/imgctx/Dockerfile`
  → `nim-z3-test:latest`); (2) re-apply the D3 ref-handle `=destroy(v.ctx)` in lifecycle.nim
  (currently DEFERRED at ~line 199) + restore td3_ctx_release ref-handle assertion; (3) re-run the
  hard gate (tmodel_enum, tast_introspect, ttranslate, td3_ctx_release valgrind, full subset). If
  green on 4.15 → D3 ships complete. If still crashing → the bug is version-independent; revisit
  narrow mitigations or upstream. Corey's Q re "patched version": the `2.2.10-patched` in the image
  is a **Nim compiler** patch (different layer), NOT a Z3 patch — unrelated to this Z3 C-API bug.
  ⚠️ Also fixes the pre-existing tffi/tversion failures (4.13.4 returned "Z3 4.13.4.0").
  **PRIOR Z3-4.15 BUGS (git history) — the project targets 4.15 with wrapper-side workarounds:**
  (a) 3936066 defineFun/defineRecFun stack-args SIGSEGV; (b) 54d5e10 arith/boolean vararg-array
  stack-args SIGSEGV; (c) **b2442e7 sortUniverse: `Z3_mk_const`+uninterpreted-sort+`Z3_mk_distinct`
  under `Z3_mk_context_rc` → sort-mismatch SIGSEGV** (worked around with `loadSmt2String`; already in
  tmodel_enum). Corey's "patched Z3 bug" ≈ this class. **This session's bug is DIFFERENT/adjacent:**
  a *teardown* use-after-free (`Z3_del_context` re-touching a freed `Z3_model_get_sort_universe`
  vector / global-param-descrs singleton), vs those *construction-time* SIGSEGVs. NO Z3 *source*
  patch/fork found on disk (searched /home/corey, toolchain image uses stock 4.13.4 / distro z3-devel).
  → Before re-testing D3, use the Z3 version/patched-build Corey actually runs (target is 4.15.x).
  **FFI DRIFT FINDING:** nim-z3's `src/z3/ffi.nim` is INCOMPATIBLE with Z3 4.15.8 / 4.16.0 —
  `Z3_mk_set_has_size` was REMOVED from Z3 (not in libz3 at all) and `Z3_fpa_get_numeral_sign`
  param3 changed `int*`→`bool*`. So the project is pinned to **Z3 4.15.0 exactly** (where ffi.nim
  matches; matches the b2442e7 "confirmed on 4.15.0.0"). My 4.13.4 harness was TOO OLD; 4.15.8/4.16
  are TOO NEW (won't compile). **D3 must be tested against Z3 4.15.0.** (Separate future concern:
  ffi.nim needs a regen to support modern Z3 — out of scope for this RFC.)
  **VERDICT on Z3 4.15.0 (ffi.nim compiles cleanly — 4.15.0 IS the pinned target):**
  - `globalParamDescrs` bug: **GONE — was 4.13.4-specific.** tast_introspect passes + valgrind-clean.
  - `sortUniverse`-teardown bug: **REPRODUCES (version-independent, real).** `Z3_model_get_sort_universe`
    ast_vector dec_ref'd to 0, then `Z3_del_context` `~context()` re-reads the freed 40-byte block →
    SIGSEGV (valgrind Invalid-read confirmed). td3_ctx_release valgrind CLEAN with release applied.
  **⇒ D3 collapses to ONE fix.** PRINCIPLED FIX PLAN (Corey wants it fixed):
  1. Re-apply the D3 ref-handle ctx-release in emitRefcountLifecycle (makes contexts deterministically
     freeable — the whole point).
  2. Fix ownership of context-owned objects: `Z3_model_get_sort_universe`'s ast_vector is
     **owned by Z3 (context/model), NOT independently freeable** — its wrapper must NOT dec_ref it
     to zero before context death (proven: "skip the compensating dec_ref → all invalid-reads vanish").
     Model as a **borrowed** ast_vector (analogue of `wrapContextBorrowed`): its `=destroy` skips the
     dec_ref; Z3 frees it via `Z3_del_context`. Find sortUniverse's inc/compensating-dec in model.nim.
  3. AUDIT sibling `wrapAstVector` accessors (getUnsatCore, parseFromString, etc.) for the same hazard
     (do the "skip compensating dec_ref → invalid-reads vanish?" test on each).
  4. Restore td3_ctx_release ref-handle assertion; verify FULL gate green on **Z3 4.15.0**.
  **HARNESS FIX NEEDED:** rebuild `nim-z3-test:latest` with **Z3 4.15.0** (currently bakes 4.13.4 — WRONG
  target). 4.15.0 dir downloaded at `~/.cache/nim-z3-test/z3-4150` (or z3-latest). NOT 4.15.8/4.16 (ffi drift).
  NOT the GC_ref/copyMem hack. tffi/tversion still fail on 4.15.0 (pre-existing "Z3 " version-prefix, unrelated).
- [x] ~~D3 DONE~~ (superseded by the PARTIAL entry above) — both templates release ctx
  post-dec_ref (lifecycle.nim only + gated `z3CtxDestroyCount` counter in context.nim).
  RED→GREEN: ref-handle 6160→0, value-type 4200→0; counting hook = 2*N (threadvar-swap
  dummy ctx, correct). Full valgrind subset (12) clean, no double-free; termCopy/termDup
  unchanged & verified balanced. High-risk regression (ttranslate/parity, tscratch_ctx,
  tpropagator[_advanced], toptimize, tquantifier) all green on c. New test td3_ctx_release.nim.
  (Full `nimble test` running in background → scratchpad/fulltest.log — check before Stage-D signoff.)
- [x] **D4 DONE (ADR-FC-0013)** — fixed datatypes.nim Z3ConstructorDeclOwn (ctx+cname+accessorsFD);
  added `-d:useMalloc` to z3.nimble valgrind task; strengthened tcontext_registry to tear down
  both ctxs. Full valgrind subset (11 tests) all `definitely lost: 0`. Other 13 value-type hooks
  audited: their unreleased ctx is the termDestroy leak → folded into D3 (above).

## Open A2-time notes (flagged by the RFC-revision subagent — resolve when building A2)
1. **`share_lemmas` auto-set vs document-caller.** The RFC now has `setHandlers`' install
   path auto-set `fp.spacer.p3.share_lemmas=true` (+ `share_invariants=true`) so `newLemma`
   fires. VERIFY at A2: does setting `spacer.p3.share_lemmas` change *solving behavior* in
   single-solver (non-portfolio) mode, or does it ONLY gate the callback? If it's callback-gate-
   only → auto-set is clean+ergonomic (keep). If it perturbs results → switch to "document that
   the caller must set it" (don't silently mutate an unrelated solver param). Corey's decision
   text allowed either reading; subagent picked auto-set as more testable. Quick empirical check
   (diff query results/stats with the param on vs off, no callback) settles it.
2. **`Z3AnyFuncDecl` deferred with reduce.** Since `reduceApp` was its only consumer, the
   revision removed `Z3AnyFuncDecl` from v2.1.0 shipped-symbol lists (§5/§8/§9/§10, ADR-FC-0006),
   marked "deferred to v2.2", not deleted. Reasonable (no consumer in 4-callback scope). If you'd
   rather keep it as a general reusable public type now (it mirrors `Z3AnyAst`), say so at A1.

## Key decisions (cumulative)
- ADR-0002: root box on Z3Fixedpoint via erased RootRef (not returned handle,
  not pointer). Explicit destructor required (custom =destroy replaces field-wise).
- ADR-0003: reduceApp → Option[Z3AnyAst] + inc_ref ownership transfer; decl =
  Z3AnyFuncDecl (carries .ctx → solves 0-arity context access).
- ADR-0008: setHandlers calls FFI directly; init unconditional+first; checkErr all.
- ADR-0007: no currentBox threadvar (every handler gets ctx via its typed args).
- Scope: all 5 callbacks typed (complete-lib-not-consumer). Raw §N7.8 = escape hatch.
- **R2 ADR-0003 (CRITICAL correction): Z3AnyFuncDecl IS refcounted** (incRefFD/decRefFD via
  Z3_func_decl_to_ast; =destroy/=copy/=dup; toAnyFuncDecl/wrapAnyFuncDecl inc_ref). Round-1
  "borrowed, no bookkeeping" was a UAF hazard — verified false vs funcdecl_types.nim:41-62.
- **R2 ADR-0005: 3rd query entry point** queryFromLevel (spacer.nim:56) → all via `withInQuery` choke point.
- **R2 §5 design:** `handlers()` read-back (hasHandlers = sugar); collectLemmas COMPOSES (base param) +
  returns named `Z3LemmaLog` (not raw ref seq); newLemma `level: uint` (was int, truncation); flat
  record KEPT (nested split can't remove runtime no-op; propagator parity).
- **R2 ADR-0001:** reduceApp exception wall encloses post-closure inc_ref+res write.
- **R2 ADR-0003:** ownership branches (a)/(b) pre-sketched → Stage 0 is a binary pick.
- **R2 clearHandlers invariant:** never nil cbBoxRef (box stays live for fp lifetime; ADR-0008).
- **R2 abort channel:** ctx.interrupt() documented + tested (C1d) — no new API.

## Review ledger (Stage 4 — round 1 complete, awaiting Corey's fix mandate)
Round 1: 5 sonnet reviewers (correctness, security/memory, design, quality, test-coverage).
Crux memory-safety paths (RootRef seam, sticky-box, =destroy completeness, borrowed-vector
teardown, exception walls) all traced CLEAN by security+correctness. No Critical. One HIGH
(confirmed empirically + by code read). Root of H1/M1/M2/M3 is one design seam: the
lazy-activation latch registers a fixed shim-signature at first query and can never expand it.

| id | sev | finding | status | proof / reason |
|----|-----|---------|--------|----------------|
| H1 | H   | Latent-registration: a handler field nil at first activation, set non-nil by a later setHandlers, never fires (exportActivated latches; Z3 slot stays nil). GOTCHAS §22 documents the opposite as safe. | **fixed** | H1 fix: always register all 3 shims + always set share_lemmas at 1st activation; shims read live handlers. RED→GREEN test in tfixedpoint_newlemma.nim ("H1: nil→non-nil via later setHandlers fires"); round-2 re-review CONFIRMED-SOUND, valgrind definitely-lost:0 both backends |
| M1 | M   | No API to query whether handlers are actually LIVE. Same root as H1. | **fixed** | added handlersActive*(fp) over exportActivated; GOTCHAS #21 rewritten; test in tfixedpoint_handlers.nim |
| M2 | M   | Z3LemmaLog silently stops growing after a later setHandlers/clearHandlers. | **fixed** | doc caveats on Z3LemmaLog/collectLemmas + combine idiom; GOTCHAS #22 corrected |
| M3 | M   | Weak `count >= 1` assertions where exact fire count is known. | **fixed** | pinned exact counts newLemma=3/predecessor=4/unfold=1 (empirically observed, 0 variance both backends) in tfixedpoint_newlemma.nim |
| M4 | M   | collectLemmas ordering test tautological (count-only). | **fixed** | rewrote to record log.len at base-fire → asserts [0,1,2]; swap-falsification verified (probe_m4_swap) |
| M5 | M   | Only 2 of 9 propagator exception-wall shims have a runtime raise proof. | **fixed** | +7 tests (all 9 shims); round-2 live falsification: stripping each wall crashes its named test; propagator.nim byte-identical restored |
| M6 | M   | leak/UAF proofs never run in CI. | **fixed** | ci.yaml: extended asan job (+4 fixedpoint/leak tests) + new counting-hooks job (z3FpBoxDestroyCount/z3CtxDestroyCount, both backends); defines gate real asserts (verified) |
| M7 | M   | clearHandlers / nil-box / no-handlers paths under-tested. | **fixed** | +6-test suite in tfixedpoint_typed_callbacks.nim (in-query guard, double-clear, no-box, dormancy-through-clearHandlers, safe defaults, boxRef.isNil query) |
| M8 | M   | Stale forward-ref comment "C2 will add a skip-suite". | **fixed** | comment corrected to describe the present skip-suite |
| M9 | M   | Composition only a one-off inside collectLemmas. | **fixed** | extracted combine*(base, extra); collectLemmas uses it; M9 order/passthrough tests |
| R2 | L   | Round-2 design nits: hasHandlers→handlersActive one-directional; combine(a,b) param naming; GOTCHAS #21 self-contradictory phrasing. | **fixed** | folded inline: hasHandlers docstring cross-ref; combine renamed base/extra; GOTCHAS #21 softened to "no *automatic* signal…" — green both backends |
| L1 | L   | newLemmaShim missing the `box != nil` guard its siblings have. | **fixed** | added `box != nil and` guard; all 3 shims uniform; green both backends |
| L2 | L   | `except Exception` (vs CatchableError) in new =destroy paths swallows Defects. | **fixed** | narrowed handlers/closure-field release to CatchableError; kept `except Exception` ONLY on the compiler-forced ctx-release + tightened doc; lifecycle/fixedpoint/datatypes sites already correctly split |
| L3 | L   | Redundant double-dispatch through assertRawCbSurfaceOk (mismatched procName). | **fixed** | private `initRawState` helper: each entry asserts once w/ its own procName, sets rawCbUsed once; guard behavior unchanged |
| L4 | L   | Stale RFC top-of-doc status banner. | **fixed** | banner → implemented / Stage-4-at-floor, links handoff ledger |
| L5 | L   | Mixing/inQuery guards are release-stripped asserts. | **wontfix (by-design)** | deliberate ADR-FC-0005 (release pays nothing; matches propagator inQuery); catches dev-time misuse, not attacker input. Flagged to Corey; not reversing an ADR silently |
| L6 | L   | Cross-thread setHandlers-during-query torn read in release. | **fixed (doc)** | THREADING.md note: fp handler set must not be mutated cross-thread during a query (same one-context-one-thread contract; guard is dev-only). No code change — unsupported by Z3's own contract |
| L7 | L   | uint `level` unsigned-arithmetic footgun. | **wontfix (by-design)** | deliberate RFC §5 (signed int truncates above int32.high; matches propagator idx:uint). Flagged to Corey |
| L8 | L   | datatypes constructor-descriptor Z3-native leak on error path. | **fixed** | try/finally + delConstructors/delConstructorLists helpers across single + arities 2-8 + N-ary; cleanup runs on success AND exception |
| L9 | L   | Only 1 of 4 gated test files compiled under the gate flag in CI. | **fixed** | gate-skip-suite job → matrix over all 4 gated files, both backends; YAML valid; local skip-run verified |
| L10| L   | Untested edges: Z3LemmaLog empty-case, re-entrant fp access, Defect-in-shim. | **fixed** | 3 new suites: empty log; read-only re-entrant fp access (zsUnsat); CatchableError-wall swallow (cast-smuggled) + Defect-aborts documented (intentionally not caught) |

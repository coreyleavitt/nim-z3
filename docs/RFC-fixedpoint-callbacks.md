# RFC — nim-z3 fixedpoint typed callback API

> **Status: implemented (targeting v2.1.0).** Stage 3 (TDD) is complete —
> all v2.1.0 slices (Stage 0, A, C, D) are implemented and green on both
> backends; Stage B (reduce callbacks) is deferred to a dedicated v2.2
> RFC. Stage 4 (code-review fix loop) is at floor as of 2026-07-12: round
> 1 found 1 High + 9 Medium + 10 Low, fixed through Medium; round 2
> re-review surfaced 0 Crit/High/Med. See
> [RFC-fixedpoint-callbacks.handoff.md](RFC-fixedpoint-callbacks.handoff.md)
> for the live stage ledger. Escalated from [RFC-completeness.md](RFC-completeness.md)
> §N7.8 as the "only escalation" in the v2.0 completeness pass.
> Governed by `complete-lib-not-consumer.md`: the raw pointer surface
> shipped in v2.0; this RFC adds the typed-closure layer so the
> fixedpoint callback family reaches parity with the propagator family
> (`z3/propagator`, ADR-N0004).
>
> Target release: **v2.1.0** (additive-only minor bump — every
> existing call site keeps compiling; see IMPLEMENTATION_PLAN "How
> patch / minor / major decisions are made post-2.0").
>
> **Stage-0 spike outcome / scope resolution (this revision — Corey,
> RFC owner).** The Stage-0 feasibility spike ran; findings are recorded
> in [SPIKE_FINDINGS-fixedpoint.md](SPIKE_FINDINGS-fixedpoint.md).
> **v2.1.0 ships the three typed Spacer export callbacks** — `newLemma`,
> `predecessor`, `unfold` — plus the box/scaffold/`setHandlers`
> machinery that installs them (§2, §5, Stage A/C below). **The reduce
> pair (`reduceApp`/`reduceAssign`) is cut from v2.1.0's typed scope**:
> the spike found they fire only under a custom Datalog relation plugin
> (`datalog.default_relation=external_relation`), not ordinary term
> rewriting, and that a correct typed surface is an op-kind-dispatch
> design (ADR-FC-0003, now marked SUPERSEDED/DEFERRED) — a bigger,
> separate design problem. Reduce is deferred to a dedicated **v2.2
> RFC**; it remains available today at the existing v2.0 **raw**
> surface (§N7.8 `setReduceAssignCallback`/`setReduceAppCallback`,
> `fixedpoint.nim:312–352`), untouched here. Stage B is removed from
> this RFC's slice plan accordingly. Separately, the Stage-0 spike
> **resolved** the `newLemma` escalation: it is param-gated
> (`fp.spacer.p3.share_lemmas`/`share_invariants`,
> `spacer_context.cpp:4286–4304`) and fires once those params are set —
> A2 is fully TDD-able as written (see A2 below).
>
> **Round-2 changelog** (what this revision fixed): corrected
> ADR-FC-0003 — `Z3AnyFuncDecl` **is** refcounted (func_decls carry a
> real Z3 refcount via `Z3_func_decl_to_ast`; the round-1 "borrowed, no
> bookkeeping" claim was a use-after-free hazard for a storable always-on
> value type); added the missing **third query entry point** `queryFromLevel`
> to the `inQuery` guard (ADR-FC-0005); tightened the reduce-app exception
> wall to enclose the post-closure ownership transfer (ADR-FC-0001);
> `newLemma` `level` → `uint` (was signed `int`, truncation on 32-bit);
> pinned `clearHandlers`' box-liveness invariant (ADR-FC-0002); added a
> `handlers()` read-back so `collectLemmas` **composes** with `setHandlers`
> and returns a named `Z3LemmaLog` (was an unprecedented raw `ref seq`);
> documented `ctx.interrupt()` as the sanctioned abort-from-handler channel;
> reframed the Stage 0 Datalog-fixture half as open-ended research (no repo
> recipe exists) and promoted the spike to a committed helper; re-mechanised
> the A1 collection proof and B3 ownership proof (probe-confirmed: RootObj
> collected on scope exit; ASAN, not `GC_fullCollect`, catches the value-type
> UAF); re-scoped the CI gate (the `gate-flags` job only runs `tminimal.nim`).
> **Resolved (§11a):** the `ctx`-field leak is **systemic** across ~15
> `emitRefcountLifecycle` handle types (probe-confirmed FACT A), not the two
> sites ADR-FC-0011 assumed — the author chose to **batch the library-wide
> template fix** (ADR-FC-0012, slice D3).
>
> **Round-1 changelog** (what this revision fixed): resolved the
> `cbBox` cross-module/GC seam (ADR-FC-0002 + new ADR-FC-0008), added
> the reduce-app refcount-ownership transfer (ADR-FC-0003), mandated a
> shim exception wall (ADR-FC-0001), pinned init ordering + `checkErr`
> (ADR-FC-0008), added the raw/typed mutual-exclusion contract
> (ADR-FC-0009), replaced the opaque `RawZ3FuncDecl` decl with an
> erased-typed `Z3AnyFuncDecl` (ADR-FC-0003), added a **Stage 0
> feasibility spike** gating the whole slice plan, and corrected the
> test-harness references in §6/§7. The one escalated decision (§11)
> was resolved by the author: **batch** the two pre-existing v2.0
> latent-bug fixes into this RFC — now ADR-FC-0010 (propagator
> exception wall) and ADR-FC-0011 (context `=destroy` field leak,
> **confirmed by probe** — see §11), with Stage D slices.

---

## 1. Motivation

Z3's fixedpoint (Datalog / Spacer-CHC) engine exposes five C
callbacks. v2.0 §N7.8 shipped them at the **raw** surface only —
`init`, `setReduceAssignCallback`, `setReduceAppCallback`,
`addCallback` in `fixedpoint.nim:312–352`, taking a bare
`state: pointer` plus `{.cdecl.}` function pointers. A user who wants
to react to a new Spacer lemma today must:

- write a `{.cdecl.}` proc by hand,
- marshal `state: pointer` back to a Nim object themselves (no GC
  rooting help — a dropped ref is a use-after-free),
- decode `Z3_ast const[]` arrays and `RawZ3FuncDecl` from raw
  pointers,
- manage the `res: ptr RawZ3Ast` out-param of the reduce-app callback
  (including its cross-ABI refcount ownership — a latent UAF, see
  ADR-FC-0003).

Every **other** callback family in nim-z3 (the theory propagator)
hides all of this behind a record of Nim closures. `z3/propagator`
proved the pattern: a `Z3PropagatorHandlers` record of `{.closure.}`
procs, a GC-rooted `PropagatorCtxBox` cast to Z3's `user_data`, C-ABI
shims that recover the box and dispatch to the closures with **typed**
`Z3AnyAst` arguments. This RFC ports that pattern to fixedpoint —
**and closes two latent bugs the propagator pattern carries** (no
exception wall across the C-ABI boundary; a custom-`=destroy` field
that ORC never releases). Those are called out where they arise and
summarised in §11.

**Non-goal restatement (why this is its own RFC):** §N7.8 flagged
that fixedpoint callbacks fire in Datalog-engine-internal contexts
whose state-capture and multi-callback-batching story differ enough
from the propagator to merit separate design discussion. That
discussion is this document.

## 2. Scope

**In scope — three of Z3's five fixedpoint callbacks get a typed
surface for v2.1.0** (the Spacer export trio), together with the
box/scaffold/`setHandlers` install machinery that carries them; the
reduce pair is deferred — see below:

| Raw C fn | Typed handler field | Engine | Shape | v2.1.0 status |
|---|---|---|---|---|
| `Z3_fixedpoint_set_reduce_assign_callback` | `reduceAssign` | Datalog | in-args + out-args, no return | **DEFERRED to v2.2** — raw surface only (§N7.8) |
| `Z3_fixedpoint_set_reduce_app_callback` | `reduceApp` | Datalog | in-args → **optional replacement AST** | **DEFERRED to v2.2** — raw surface only (§N7.8) |
| `Z3_fixedpoint_add_callback` → new-lemma | `newLemma` | Spacer | `(lemma, level)` observe | **shipping** |
| `Z3_fixedpoint_add_callback` → predecessor | `predecessor` | Spacer | observe (no args) | **shipping** |
| `Z3_fixedpoint_add_callback` → unfold | `unfold` | Spacer | observe (no args) | **shipping** |

**Reduce pair deferred to v2.2 (resolved this revision).** The Stage-0
feasibility spike (§6; findings in
[SPIKE_FINDINGS-fixedpoint.md](SPIKE_FINDINGS-fixedpoint.md)) found the
reduce callbacks fire only under a narrow, non-obvious condition
(`datalog.default_relation=external_relation`, driving a custom
relation-plugin's algebra ops — not ordinary term rewriting) and that
the values Z3 passes are better modeled as op-kind-dispatched
relation-algebra operands (`Z3_OP_RA_IS_EMPTY`/`JOIN`/`COMPLEMENT`/
`PROJECT`/`RENAME`, …) than the `reduceApp(decl, args) -> Option`
shape ADR-FC-0003 designed around. A typed "programmable Datalog
relation-backend" API for `reduceApp`/`reduceAssign` is real and
feasible but is its own design problem — out of scope for v2.1.0.
**v2.1.0 therefore ships only the typed Spacer export trio**
(`newLemma`, `predecessor`, `unfold`) plus the box/scaffold/
`setHandlers` machinery, and defers the reduce pair to a dedicated
**v2.2 RFC**. The reduce pair remains available today at the existing
v2.0 **raw** surface (§N7.8 `setReduceAssignCallback`/
`setReduceAppCallback` in `fixedpoint.nim:312–352`), untouched by this
RFC — do not touch or remove those procs. ADR-FC-0003 is retained below,
annotated **SUPERSEDED/DEFERRED**, as the source-verified starting
point for that future RFC; Stage B (§6) is removed from this RFC's
slice plan for the same reason.

The **Engine** column stays load-bearing for the shipped surface too:
the export callbacks fire only under Spacer (the default engine) —
installing a handler while `engine=datalog` is a silent no-op, a
genuine gotcha surfaced in the API docstring (ADR-FC-0009) and tested
(§7).

`Z3_fixedpoint_init` is **not** part of the typed surface — it is an
internal step the installer performs (it binds the box as `state`).
It remains available at the raw surface for advanced users, subject to
the mutual-exclusion contract in ADR-FC-0009.

**Also in scope (batched per §11):** two **pre-existing v2.0 latent
bugs** this review uncovered — the propagator's missing shim exception
wall (ADR-FC-0010) and `Z3ContextOwn`'s `=destroy` field leak
(ADR-FC-0011, probe-confirmed). Backfixed here rather than tracked
separately, per the author's decision.

**Out of scope (this RFC):** any change to the raw §N7.8 procs (they
stay as the escape hatch — parity with how `z3/propagator` never
removed the raw `Z3_solver_propagate_*` FFI entries); and the reduce
pair's typed surface (`reduceApp`/`reduceAssign` — deferred to a
dedicated v2.2 RFC, per above). No new Z3 FFI entries — all four
functions + five typedefs already exist in `ffi.nim` (v2.0 §N7.8).

## 3. Background: the two callback sub-families differ

The reduce callbacks and the export callbacks are **not** symmetric,
and the asymmetry drives the design:

- **Reduce callbacks** (`reduceAssign`, `reduceApp`) fire inside the
  **relational / Datalog** engine. They receive a func-decl (the
  relation) and `Z3_ast const[]` argument arrays. `reduceApp`
  additionally has a **non-const out-param** `res: ptr RawZ3Ast` — the
  callback may *rewrite* the application by filling it (with the
  refcount-ownership caveat in ADR-FC-0003). These are transformation
  hooks.

- **Export callbacks** (`newLemma`, `predecessor`, `unfold`) fire
  inside the **Spacer / CHC** engine. They are **observation** hooks:
  `newLemma` sees a lemma AST and its induction level; `predecessor`
  and `unfold` take no payload. None returns anything.

Consequently the reduce callbacks need a richer marshalling contract
(array decode + optional out-param with ownership transfer) than the
propagator's uniformly read-only callbacks; the export callbacks are
strictly simpler.

## 4. Architecture Decision Records

### ADR-FC-0001 — Mirror the propagator box/shim pattern, **plus a mandatory exception wall**

**Decision.** Adopt the `z3/propagator` architecture in structure:

- `Z3FixedpointHandlers` — a record of `{.closure.}` procs, one per
  callback, all optional (nil ⇒ that C callback is not registered).
  Each proc field carries `{.raises: [].}` so the compiler rejects a
  provably-raising closure at the assignment site (defense in depth).
- `FixedpointCtxBox` — a heap-allocated `ref object of RootObj`
  holding the handlers + the owning `Z3Context`. Erased to `RootRef`
  when stored on `Z3Fixedpoint` (ADR-FC-0002); recovered in every shim
  via `cast[FixedpointCtxBox](state)`.
- C-ABI `{.cdecl.}` shim procs — one per callback — that recover the
  box, wrap raw handles into typed values, and dispatch to the closure.

**Mandatory exception wall (round-1 fix — CRITICAL).** Every shim
**must** wrap the closure dispatch in
`try: ... except CatchableError: <safe fallback>`. A Nim exception
unwinding out of a `{.cdecl.}` frame directly into Z3's C++ call stack
is undefined behavior (neither setjmp/longjmp nor `--exceptions:cpp`
unwinding is defined across a foreign `{.cdecl.}` boundary invoked from
C). Safe fallback per callback: `reduceApp` returns without writing
`res` (no rewrite); every other shim is a no-op. The `{.raises: [].}`
constraint is compile-time defense; the `try/except` is the runtime
wall — both ship. (This is *stricter* than `propagator.nim`, whose
shims have no wall — see §11.)

**Wall scope for `reduceApp` (round-2 fix).** `reduceApp` is the only
shim with work *after* the closure returns — the `Z3_inc_ref` +
`res[]`-write of ADR-FC-0003. The `try/except` boundary must enclose
**that post-closure ownership transfer too**, not just the closure
call. If the `inc_ref`/write path itself raises (e.g. a `SoftlinkError`
from the FFI wrapper, or a defensive check on `ast.raw`), the "no
rewrite" fallback must still hold — an unwind out of the one shim that
does post-dispatch work is exactly the UB this ADR forecloses. So the
shim is `try: (dispatch; if some: inc_ref; write res) except: (leave res
untouched)`, one wall around the whole body.

**Rationale.** The box/shim structure is the proven pattern
(ADR-N0004, shipped and tested in v2.0); consistency means a
contributor who understands `propagator.nim` understands this module
for free. The exception wall is where we deliberately *improve* on the
pattern rather than copy a latent bug.

**Consequence.** The module reuses `wrap[Z3AnyAst]`, the
`RawZ3Ast → Z3AnyAst` bridge, and the `.cdecl` shim discipline
established in `propagator.nim`, adding the wall.

### ADR-FC-0002 — Root the box **on `Z3Fixedpoint`** via an erased `RootRef` field, with an explicit destructor

**Decision.** Store the box on `Z3FixedpointOwn` as a **type-erased,
ORC-traced** `RootRef` field, exposed to the callback module through
promoted internal accessors:

```nim
# fixedpoint.nim (always-on module)
Z3FixedpointOwn = object
  raw: RawZ3Fixedpoint
  ctx: Z3Context
  cbBox: RootRef            # nil until setHandlers; ORC-traced; roots the box

proc cbBoxRef*(fp: Z3Fixedpoint): RootRef {.inline.} = fp.cbBox        # INTERNAL_API
proc `cbBoxRef=`*(fp: Z3Fixedpoint, r: RootRef) {.inline.} = fp.cbBox = r
```

`setHandlers(fp, handlers)` allocates a `FixedpointCtxBox` (a
`ref object of RootObj`, defined in the gated callback module),
assigns it through `fp.cbBoxRef =`, and registers the C callbacks. The
box then lives exactly as long as `fp` — which is exactly as long as
any `fp.query(...)` that fires the callbacks.

**Why `RootRef`, not the concrete type, and not `pointer` (round-1
fix — CRITICAL).** Three constraints collide:
1. The field must live on `Z3FixedpointOwn` in the **always-on**
   `fixedpoint.nim` (rooting-on-`fp` is the whole ADR).
2. The box type belongs in the **gated** callback module (its handlers
   reference the typed-callback surface).
3. If (1) imports (2) for the concrete type name, the two modules form
   a **circular import** (the propagator avoids this only because its
   box and owner live in one file).

`cbBox: RootRef` breaks the cycle: the always-on file names only
`RootRef` (a `system` type); the gated module defines
`FixedpointCtxBox = ref object of RootObj` and casts through `RootRef`
at the boundary. A naive `cbBox: pointer` would compile but is
**wrong**: ORC does not trace a `pointer`, so the box would neither be
rooted (defeating the ADR) nor collected (leaking). `RootRef` is a
genuine traced ref — rooting and cleanup both work.

**Why not the `onclause.nim` pattern (round-2 note).** The repo has a
*third* box-rooting precedent besides `propagator.nim`'s handle field:
`onclause.nim:100–116` roots via a module-level
`{.threadvar.} Table[uint, seq[Box]]` keyed by the solver's raw pointer,
which sidesteps the circular-import problem entirely (it touches no
always-on type). It is rejected here because that table only grows —
there is no per-`fp` eviction point, so it would leak one box per
fixedpoint for the process lifetime. Rooting on `fp` via `RootRef` ties
box lifetime to `fp` exactly, with no global registry to prune.

**The destructor is NOT free (round-1 fix — CRITICAL).**
`emitRefcountLifecycle` (`lifecycle.nim:159`) generates a custom
`=destroy` touching only `raw`/`ctx`. A user-defined `=destroy`
*replaces* the compiler's field-wise destructor — it does **not**
augment it — so a third field is never released. **This is empirically
confirmed** (round-1 probe, Nim 2.2.10 + `--mm:orc`): an object with a
custom `=destroy` touching only one field destroyed the `ref` values in
an untouched `Table` field **0 times, not 2** — a hard leak. (This same
probe is what confirms ADR-FC-0011's context bug.) Z3FixedpointOwn's
destructor must therefore **explicitly** drop `cbBox` (set it to `nil`,
letting ORC dec the ref and collect the box).

**Mechanism — hand-write, decided (round-2).** Replace
`fixedpoint.nim:76`'s one-line `emitRefcountLifecycle(Z3FixedpointOwn,
Z3_fixedpoint_dec_ref)` with a hand-written `Z3FixedpointOwn.=destroy`
(mirroring `Z3ContextOwn`'s existing hand-rolled one at
`context.nim:107`): `dec_ref` the raw fixedpoint **first** (it needs
`ctx.raw`), then drop `cbBox`, then — see the systemic note below —
the `ctx` ref. Order matters: releasing `ctx` before the raw `dec_ref`
would read a nil'd field. This is scoped to the one type; the
*library-wide* variant (extending `emitRefcountLifecycle` itself) is the
escalated §11 decision, because the `ctx`-field leak it fixes is
**systemic** (probe FACT A: a plain `ref` field is skipped by a custom
`=destroy` exactly as a `Table` field is), affecting all ~15
`emitRefcountLifecycle` handle types — not just `cbBox`.

**A1's collection test — mechanism pinned (round-2, probe FACT B).** The
round-1 draft said "finalizer / weak-probe count," but Nim's legacy
`new(x, finalizer)` binds at allocation and can't attach to the
`FixedpointCtxBox(...)` construction `setHandlers` uses. Probe FACT B
settled the needed fact: a `ref object of RootObj` is reclaimed
**deterministically on scope exit** under `--mm:orc` (destroyed before
any `GC_fullCollect`). So the test attaches a counting **hand-written
`=destroy` on `FixedpointCtxBox`'s concrete type**, drops the last `fp`
reference, and asserts the counter incremented — proving the box is
**collected when `fp` dies**, not merely "non-nil while `fp` is alive."
A trailing `GC_fullCollect()` stays as belt-and-suspenders (a closure
capturing back to the box could form a cycle that defers reclamation to
the collector).

**Rationale for rooting on `fp` at all.** `newPropagator` returns a
`Z3Propagator` the caller must keep alive; dropping it collects the box
mid-`check()` → UAF, a documented footgun. Fixedpoint callbacks are
conceptually "installed **on** the fixedpoint"; Z3 threads the state
through `fp` internally with no separate handle. Rooting on `fp`
removes the footgun (no second object to drop). The discoverability a
returned handle would give (uninstall, "are handlers installed") is
restored explicitly via `clearHandlers`/`hasHandlers` (§5) — so we keep
the ADR win without losing the affordance.

### ADR-FC-0003 — Reduce-app: `Option[Z3AnyAst]` return **with ownership transfer**; erased-typed `Z3AnyFuncDecl` for `decl` — **SUPERSEDED / DEFERRED to v2.2**

> **Status (this revision): SUPERSEDED / DEFERRED.** The Stage-0 spike
> (§6; [SPIKE_FINDINGS-fixedpoint.md](SPIKE_FINDINGS-fixedpoint.md))
> found the design below rests on a wrong premise — reduce is not a
> general term-rewrite hook, and the `res` ownership question this ADR
> spends most of its length resolving is **moot**. The reduce pair does
> **not** ship typed in v2.1.0 (§2); this ADR is kept, unedited below,
> as the source-verified starting point for the dedicated **v2.2 RFC**.
> Source-verified facts for that future RFC, recorded here and in
> `SPIKE_FINDINGS-fixedpoint.md`:
> - The reduce values are **real `ast_manager` ASTs** — fresh, 0-arity
>   "register" consts — **not opaque handles**
>   (`dl_external_relation.cpp:84,138`, `z3_fixedpoint.h:349–351`).
> - **Z3 auto-`inc_ref`s and permanently roots** the `res` the callback
>   returns (`api_datalog.cpp:76–89`) — no caller refcount bookkeeping
>   is needed. This makes the **ownership branch (a)/(b) question below
>   MOOT**: there is no "does Z3 take its own ref on top of ours"
>   ambiguity to resolve: the API layer, not the shim, owns `res`.
> - The real typed API shape is **op-kind dispatch** over
>   `Z3_OP_RA_IS_EMPTY` / `JOIN` / `COMPLEMENT` / `PROJECT` / `RENAME`,
>   etc. — not the generic `reduceApp(decl, args) -> Option[Z3AnyAst]`
>   signature this ADR designed. A correct typed wrapper is a
>   relation-algebra dispatcher, a materially different (and larger)
>   design than "one more closure field."
> - Verdict: a safe, usable typed wrapper is **feasible (medium
>   effort)**, deferred to the v2.2 RFC rather than designed here.
> - `Z3AnyFuncDecl` (the erased func-decl type this ADR introduces for
>   `decl`) has no other v2.1.0 consumer once reduce is deferred — it,
>   too, moves to the v2.2 RFC (see §5, §8, §9 for the resulting
>   surface trims).
>
> The original (round-1/round-2) decision, evidence, and rationale
> follow unchanged, for reference.

**Decision — return contract.** Model the reduce-app out-param as a
return value:

```nim
reduceApp*: proc(decl: Z3AnyFuncDecl, args: seq[Z3AnyAst]):
              Option[Z3AnyAst] {.closure, raises: [].}
```

`none` ⇒ leave `res` untouched (Z3 keeps the default application).
`some(ast)` ⇒ the shim writes `ast.raw` into `res[]`. `reduceAssign`
has no out-param and is pure notification:

```nim
reduceAssign*: proc(decl: Z3AnyFuncDecl,
                    inArgs, outArgs: seq[Z3AnyAst]) {.closure, raises: [].}
```

**Ownership transfer (round-1 fix — CRITICAL).** `wrap[Z3AnyAst]`
`inc_ref`s on construction and `Z3AnyAst`'s `=destroy` `dec_ref`s on
scope exit. If the shim does `res[] = ast.raw` and returns, the local
`Option[Z3AnyAst]` is destroyed **at shim return**, `dec_ref`-ing the
AST — potentially to refcount 0 — before Z3's C++ caller reads `res[]`
back. For a freshly-built term whose only holder was our `wrap`, that
is a dangling pointer handed into the engine. The shim **must**
`Z3_inc_ref(ctx.raw, ast.raw)` before returning, transferring one
reference to Z3. Whether Z3 then takes its own reference (making our
extra `inc_ref` a leak) or assumes ownership of ours is **an unverified
Z3 contract** — the Stage 0 spike (§6) pins it empirically before B3 is
built, and the answer is recorded as a concrete ADR line then.

**Both branches are pre-sketched so Stage 0 is a binary pick, not a
fresh design (round-2 fix).** (a) *Z3 takes ownership of our transferred
ref* → the design above stands unchanged: shim `inc_ref`s once before
writing `res[]`, hands that ref to Z3, keeps none. (b) *Z3 takes its own
ref on top of ours when it reads `res[]`* → then our extra `inc_ref`
leaks one ref per fire; the fix is to treat the write as a **borrow, not
a transfer** — the shim writes `res[] = ast.raw` **without** the extra
`inc_ref`, relying on the caller-visible `Option`'s ref to keep the AST
alive across the C-side read (which happens synchronously, before the
shim returns and the local `Option` is destroyed). Stage 0 picks (a) or
(b) by observing the AST's refcount after a fired rewrite; B3 implements
the chosen branch. Either way the answer is one line, not a redesign.

**Echo-input replacement path (round-2 note).** A handler may return
`some(args[i])` (echo an input) rather than a freshly-built term. That
is a *distinct* refcount path from the fresh-term case: `args[i]`
already carries the `decodeAstArray` `wrap` ref, which is `dec_ref`ed
when the local `args` seq dies at shim exit; under branch (a) the
explicit transfer `inc_ref` is what survives into Z3. The net is
correct, but B3 tests **both** paths (fresh term and echoed arg) because
an off-by-one in the transfer logic could pass one and fail the other.

**`none`/pre-fill contract (round-1 fix — HIGH).** "Leave `res`
untouched" assumes Z3 pre-populates `res` with the default application
before invoking the callback. If Z3 leaves `res` uninitialized, a
`none` return reads garbage. The Stage 0 spike verifies this (register
a no-op `reduceApp` returning `none`; diff the query result against a
no-callback run) before B3.

**Decision — `decl` type (round-1 fix — HIGH, resolves prior open
question).** `decl` is an **erased-typed** `Z3AnyFuncDecl`, a new
always-on handle mirroring `Z3AnyAst`:

```nim
# funcdecl_types.nim (always-on) — general, reusable
type Z3AnyFuncDecl* = object
  raw*: RawZ3FuncDecl
  ctx*: Z3Context
# Refcounted — see below. Emitted like Z3AnyAst's lifecycle, but through
# incRefFD/decRefFD (which route via Z3_func_decl_to_ast), NOT a plain
# Z3_inc_ref, because func_decls refcount through their AST projection:
proc `=destroy`(d: Z3AnyFuncDecl)            # decRefFD(d.ctx, d.raw)
proc `=copy`(dst: var Z3AnyFuncDecl, src: Z3AnyFuncDecl)  # dec old, inc new
proc `=dup`(src: Z3AnyFuncDecl): Z3AnyFuncDecl            # incRefFD
proc `$`*(d: Z3AnyFuncDecl): string          # via Z3_get_decl_name → string
proc `==`*(a, b: Z3AnyFuncDecl): bool         # raw-pointer identity
proc toAnyFuncDecl*[A, R](d: Z3FuncDecl[A, R]): Z3AnyFuncDecl  # inc_refs
proc wrapAnyFuncDecl*(ctx: Z3Context, raw: RawZ3FuncDecl): Z3AnyFuncDecl  # inc_refs
```

The prior provisional pick — raw `RawZ3FuncDecl` "plus existing
untyped introspection procs" — **contradicts the RFC's own
motivation** (§1 exists to stop users decoding `RawZ3FuncDecl` by
hand) and rests on introspection helpers that **do not exist** in
`funcdecl.nim` today. It also mixed abstraction levels within one
signature (`args` typed as `Z3AnyAst`, `decl` fully raw).
`Z3AnyFuncDecl` erases the static `A, R` (the callback has none) while
staying typed and renderable, lets a user dispatch by relation
(`if decl == edgeRel.toAnyFuncDecl(): ...` — the dominant real use),
and — critically — **carries `.ctx`**, which is how a handler for a
0-arity relation (empty `args`) obtains a context to build a
replacement AST (resolves round-1 Depth #7).

**`Z3AnyFuncDecl` IS refcounted (round-2 fix — CRITICAL).** The round-1
draft claimed func_decls are "borrowed… so `Z3AnyFuncDecl` needs no
refcount bookkeeping." That is **false and a UAF hazard**, verified
against source: `funcdecl_types.nim:41–62` already refcounts func_decls
through `incRefFD`/`decRefFD` (`Z3_func_decl_to_ast` + the AST
`inc_ref`/`dec_ref` pair), and `Z3FuncDeclOwn` has a `=destroy` that
calls `decRefFD` — func_decls are first-class refcounted here, exactly
like `Z3AnyAst`. A general, storable, always-on `toAnyFuncDecl` doing a
bare field copy with no `inc_ref` would dangle the moment the source
`Z3FuncDecl` (possibly the last strong ref) is destroyed —
`let d = mkFuncDecl(...).toAnyFuncDecl()` frees the decl out from under
`d`. So `Z3AnyFuncDecl` **must** carry the same `=destroy`/`=copy`/`=dup`
discipline as `Z3AnyAst`, built on the existing `incRefFD`/`decRefFD`
(not a plain `Z3_inc_ref` — the refcount routes through the AST
projection). `toAnyFuncDecl`/`wrapAnyFuncDecl` `inc_ref` on construction;
the reduce shims wrap `decl` via `wrapAnyFuncDecl` (symmetric with how
`decodeAstArray` wraps `args`). Inside a shim the extra ref is harmless
(Z3 owns the relation for the callback's dynamic extent); the discipline
is what makes the value **safe to store past the callback**, which is the
whole point of a public value type.

**Rationale.** An `Option[Z3AnyAst]` return is idiomatic "maybe produce
a value" and keeps the raw `ptr RawZ3Ast` out-param inside the shim.
Alternatives (echo-input-for-no-change; explicit Keep/Replace variant)
are strictly worse: there is no single "input" AST to echo (the input
is `(decl, args)`), and `Option` already *is* the Keep/Replace variant
with idiomatic call sites.

### ADR-FC-0004 — Array decode helper shared across reduce shims — **DEFERRED to v2.2 (reduce-only; not built in v2.1.0)**

> **Status (this revision): DEFERRED.** `decodeAstArray` exists solely
> to decode the reduce shims' `Z3_ast const[]` argument arrays. Checked
> against §3: **no export callback takes an AST array** —
> `newLemma(lemma: Z3AnyAst, level: uint)` takes a single AST,
> `predecessor`/`unfold` take no payload at all. So this helper carries
> **nothing forward** into Stage A; it is cut wholesale alongside Stage
> B (§6) and is not implemented in v2.1.0. Kept below, unedited, as
> reference for the v2.2 RFC (see B1's disposition note in §6).

**Decision.** Both reduce shims decode a `Z3_ast const[]` (passed as
`pointer` per the §N7.8 const-qualification note) into `seq[Z3AnyAst]`
via one internal helper:

```nim
proc decodeAstArray(ctx: Z3Context, p: pointer, n: cuint): seq[Z3AnyAst]
```

casting `p` to `ptr UncheckedArray[RawZ3Ast]` and `wrap`-ing each
element. Empty (`n == 0`) yields `@[]` without dereferencing `p`.

**Rationale.** DRY across the two reduce shims and one audited place to
get the `UncheckedArray` cast + bounds right — echoing the
RFC-completeness "5 hand-written copies = 5× maintenance surface"
lesson (line 64).

### ADR-FC-0005 — Registration only **outside** an active query, with a hard debug guard

**Decision.** `setHandlers`/`clearHandlers` must be called **outside**
an active query. Enforce with a concrete mechanism, not an honor-system
note: add a debug-only `inQuery: bool` to `Z3FixedpointOwn`, set on
query entry and cleared in a `finally` (surviving Z3-side exceptions),
and `assert not fp.inQuery` at the top of `setHandlers`.

**All *three* query entry points must be instrumented (round-2 fix —
HIGH).** `fixedpoint.nim` has two (`query`, `queryRelations`), but
`z3/spacer.nim:56` defines a **third** — `queryFromLevel` (Spacer's
iterative-deepening `Z3_fixedpoint_query_from_lvl`), which is arguably
the *most* natural driver of the export callbacks this RFC targets.
Instrumenting only the first two would leave a guard that looks
comprehensive but silently readmits the stale-`state` UAF during a
`queryFromLevel`. To avoid enumerating (and later forgetting) call
sites, expose a single internal choke point in `fixedpoint.nim` —
`template withInQuery(fp; body)` that sets/clears the flag in a
`finally` — and route all three queries (including `spacer.nim`'s, which
already imports `z3/fixedpoint` one-directionally, so no cycle) through
it. Stage 0 and §7 exercise `queryFromLevel`, not just `query`.

**Rationale.** Swapping the box while Z3 holds a raw `state` pointer
into the old one dangles — and it is precisely ADR-FC-0008's
stale-`state` hazard. This invariant most needs a hard guard; a debug
assertion is cheap and *improves* on the propagator's unenforced
`clearSubBoxes` contract. `when not defined(release)`-gated so release
builds pay nothing. (Round-2/A1 correction: the draft said `when
defined(debug)`, but Nim never auto-defines `debug` — nothing in this
project's build passes `-d:debug`, so that token would make this guard
permanently dead code under every build the project actually runs
[empirically confirmed at A1]. `when not defined(release)` is the Nim
idiom that realizes the *stated* intent — active by default, stripped
under `-d:release`/`-d:danger`.)

### ADR-FC-0006 — Module placement + gating (resolves prior open question)

**Decision.** Split by the constraint that forced ADR-FC-0002:

- **Always-on `fixedpoint.nim`** gains only: the `cbBox: RootRef`
  field, its `cbBoxRef` accessors, the debug `inQuery` guard, and the
  extended `=destroy`. No typed-callback code, no `Option`, no handler
  types — minimal-build stays truly minimal.
- **New gated module `z3/fixedpoint_callbacks`** (behind
  `-d:z3WithoutFixedpointCallbacks`) holds everything else:
  `FixedpointCtxBox`, `Z3FixedpointHandlers`, the shims, `setHandlers`,
  `clearHandlers`, `hasHandlers`, `collectLemmas`. It imports
  `fixedpoint.nim` **one-directionally** (no cycle, per ADR-FC-0002).
- `Z3AnyFuncDecl` **DEFERRED to v2.2** (this revision): it was slated for
  always-on `funcdecl_types.nim` (small, general, reusable — not gated),
  but its only v2.1.0-scoped consumer was the reduce shims' `decl`
  parameter (ADR-FC-0003, now superseded/deferred). With reduce cut,
  v2.1.0 has no typed-callback use for it, so it is not built here — it
  moves to the v2.2 RFC alongside ADR-FC-0003.

**Gating flag phrasing.** `-d:z3WithoutFixedpointCallbacks` is
**undefined by default**, so the typed surface **ships by default**;
defining the flag strips it. (Matches the `z3WithoutPropagator`
convention — the earlier "default ON" wording was backwards.)

**Engine gating — no cascade needed.** The export callbacks are
Spacer-only *at runtime*, but the module has **no compile dependency**
on `z3/spacer` (it calls `Z3_fixedpoint_add_callback` FFI directly, not
spacer symbols). So `-d:z3WithoutSpacer` does not break this module;
the export handlers simply never fire when Spacer is absent — which is
the same runtime engine-coupling documented in ADR-FC-0009. No gating
cascade; the coupling is a documented runtime property, not a build
constraint.

### ADR-FC-0007 — No thread-local `currentBox`

**Decision.** Do **not** add a `{.threadvar.} currentBox`. The
propagator needs it only so `consequence`/`nextSplit` can recover a
context inside a callback that has no context parameter. The fixedpoint
callbacks need no re-entrant Z3 calls: observers (`predecessor`,
`unfold`) build nothing; `newLemma`'s `lemma: Z3AnyAst` carries `.ctx`;
`reduceApp`/`reduceAssign`'s `decl: Z3AnyFuncDecl` carries `.ctx` (and
so does any non-empty `args[i]`). Every handler that needs a context
has one **through its typed arguments** — so the user-facing API is
sufficient without exposing the internal box. (Round-1 note: this is
verified at **Slice B1**, before B2/B3 build on the assumption, not
left as an implementation-time footnote.)

### ADR-FC-0008 — `setHandlers` calls the FFI directly, with pinned init ordering and `checkErr`

**Decision.** `setHandlers` calls the raw `Z3_fixedpoint_*` FFI
**directly** (not through the raw §N7.8 Nim wrappers), in this exact
order:

1. `fp.ctx.checkErrVoid Z3_fixedpoint_init(fp.ctx.raw, fp.raw, boxPtr)`
   — **unconditional**, once, first. `boxPtr` is the current box.
2. Then, conditionally, the reduce registrations (only if that handler
   is non-nil): `set_reduce_assign_callback`, `set_reduce_app_callback`.
3. Then, if any export handler is non-nil, one
   `add_callback(fp, boxPtr, newLemmaEh?, predecessorEh?, unfoldEh?)`
   with `nil` for absent handlers.

Every FFI call is wrapped in `fp.ctx.checkErrVoid` (round-1 fix —
matches every other proc in `fixedpoint.nim`/`spacer.nim`; the raw
§N7.8 layer's skipping of `checkErr` is a known narrow gap not
propagated here).

**Why direct, not via the raw wrappers (round-1 fix — CRITICAL).** The
raw `setReduceAssignCallback`/`setReduceAppCallback` each call
`fp.init(state)` internally. Composing `setHandlers` from them would
call `Z3_fixedpoint_init` two or three times per install. Worse, the
reduce callbacks share a **single** Z3-side `state` slot: on a
re-install that changes only export handlers (both reduce handlers
nil), skipping the reduce registrations would skip `init`, leaving the
C-side `state` pointing at the **old** box (which ADR-FC-0002 may now
collect) → the next reduce fire dereferences freed memory. Calling
`init` unconditionally first pins `state` to the current box on every
install regardless of which handlers are populated.

### ADR-FC-0009 — Raw and typed surfaces are mutually exclusive per `fp`

**Decision.** Document (module docstring + GOTCHAS.md) and, in debug
builds, assert that once `setHandlers` has been called on an `fp`, the
raw §N7.8 procs (`fp.init`, `fp.setReduceAssignCallback`,
`fp.addCallback`, …) must **not** be called on that same `fp`, and vice
versa. Calling raw `fp.init(other)` after `setHandlers` overwrites the
Z3-side `state` the typed shims recover via `cast[FixedpointCtxBox]` →
type-confusion/UAF on the next fire. A test demonstrates the hazard so
it is known, not silent.

**Engine coupling (documented, not enforced).** `setHandlers`'
docstring states that reduce handlers fire only under
`engine=datalog` and export handlers only under `engine=spacer`
(the default). Installing a handler for the inactive engine is a
silent no-op; §7 tests this explicitly rather than leaving it implicit.

### ADR-FC-0010 — Backfix: propagator shim exception wall (pre-existing v2.0 bug)

**Decision.** Add the same `try/except CatchableError` wall
(ADR-FC-0001) to every existing `z3/propagator` shim
(`propagatorPushShim`/`Pop`/`Fresh`/`Fixed`/`Final`/`Eq`/`Diseq`/
`Created`/`Decide`, `propagator.nim:103–203`), and add `{.raises: [].}`
to the `Z3PropagatorHandlers` closure fields. A raising user closure
today unwinds out of a `{.cdecl.}` frame into Z3's C++ stack — the same
UB class this RFC walls off for fixedpoint.

**Rationale.** Batched per §11. Independent of the new surface but the
same defect; fixing both in one release keeps the callback-shim
discipline uniform. Safe fallback per shim mirrors ADR-FC-0001 (no-op;
`fresh` returns a nil/empty sub-box). Compatibility: pure bugfix, no
signature change (the `{.raises: [].}` addition can only reject a
provably-raising closure at assignment — a compile error the caller
fixes by handling their own exceptions, which they must anyway).

### ADR-FC-0011 — Backfix: `Z3ContextOwn` `=destroy` field leak (pre-existing v2.0 bug, **probe-confirmed**)

**Decision.** Extend `Z3ContextOwn`'s hand-written `=destroy`
(`context.nim:107`) to release its GC-managed `Table` fields
(`datatypeRegistry`, `uninterpretedRegistry`) on **all** paths —
including the `borrowed` early-return (the tables are Nim-side storage
we own even when Z3 owns the underlying context). Mechanism: explicit
`` `=destroy`(c.datatypeRegistry) `` / `reset(...)` for each, before/independent
of the `borrowed` check.

**Evidence.** The round-1 probe (Nim 2.2.10, `--mm:orc`) confirms a
user `=destroy` skips field destruction entirely — the `Table`'s
backing storage and `string` keys leak on every context teardown. The
`RawZ3Sort` *values* are borrowed raw pointers (no Z3-side leak), but
the Nim-side table storage is genuinely lost. `tcontext`'s valgrind run
passes today only because its fixture never populates the registries.

**Rationale.** Batched per §11. Also add a one-line warning to
`emitRefcountLifecycle`'s doc comment (`lifecycle.nim`): *any* `OwnT`
that moves off the default field-wise destructor must hand-release
**every** GC-managed field — the template's generated `=destroy` will
silently leak it.

**Round-2 correction — the leak is systemic, and `ctx` is NOT exempt.**
The round-1 rationale here claimed the fix at "the two known sites +
`cbBox` cover every current instance," treating a `ctx`/`raw`-only
destructor as safe. **Probe FACT A (round-2) disproves that:** a plain
`ref` field is skipped by a custom `=destroy` exactly as a `Table` field
is (the `ctx` ref was released **0×**). So `emitRefcountLifecycle`'s
generated `=destroy` (`lifecycle.nim:159–168`), which touches only
`v.raw` (via `decRefSym(v.ctx.raw, v.raw)`) and never releases `v.ctx`,
**leaks its `ctx` reference on every teardown** — across **all ~15**
`emitRefcountLifecycle` handle types (`Z3SolverOwn`, `Z3ModelOwn`,
`Z3OptimizeOwn`, `Z3FixedpointOwn`, `Z3TacticOwn`, … — verified against
source). It is masked today only because typical programs keep one
context alive for their whole run; a program creating many short-lived
contexts leaks each one. Extending the template to release `ctx` (after
the raw `dec_ref`, which needs `ctx.raw`) is the thorough fix — the
option round-1 deferred as "touches ~10 call sites." Whether to do that
**library-wide fix in this RFC** or scope it to a follow-up is the one
genuine fork this round surfaces — see §11 (escalated).

### ADR-FC-0012 — Backfix: systemic `ctx`-ref leak in `emitRefcountLifecycle` (round-2, author chose "batch in")

**Decision.** Extend `emitRefcountLifecycle` (`lifecycle.nim:159–168`)
so its generated `=destroy` releases the `ctx: Z3Context` ref **after**
the raw `dec_ref` (which needs `ctx.raw`). This fixes all ~15
ref-handle types (`Z3SolverOwn`, `Z3ModelOwn`, `Z3OptimizeOwn`,
`Z3FixedpointOwn`, `Z3TacticOwn`, `Z3GoalOwn`, `Z3ApplyResultOwn`,
`Z3StatsOwn`, `Z3ProbeOwn`, `Z3AstVectorOwn`, `Z3ParamsOwn`,
`Z3ParamDescrsOwn`, `Z3AstMapOwn`, `Z3ParserContextOwn`,
`Z3SimplifierOwn`) in one central place. Sketch:

```nim
proc `=destroy`(v: OwnT) {.raises: [].} =
  try:
    if not v.raw.isNil and v.ctx != nil and not v.ctx.raw.isNil:
      decRefSym(v.ctx.raw, v.raw)
  except CatchableError: discard
  `=destroy`(v.ctx)      # round-2: release the ctx ref the old body leaked
```

**Evidence.** Probe FACT A (Nim 2.2.10, `--mm:orc`): a plain `ref`
field is skipped by a custom `=destroy` exactly as a `Table` field is
(the `ctx` ref was released **0×**). The old one-field body therefore
leaked `ctx` on every teardown of every one of those types — masked only
because most programs keep one long-lived context.

**Interaction with `Z3FixedpointOwn` (ADR-FC-0002).** `Z3FixedpointOwn`
moves *off* `emitRefcountLifecycle` to a hand-written `=destroy` (it has
the extra `cbBox` field). That hand-written destructor follows the same
order: `dec_ref` raw → drop `cbBox` → release `ctx`. So the template fix
covers the other ~14 types; `Z3FixedpointOwn` carries the identical
discipline by hand.

**Rationale.** Batched per §11a (author's decision). Same root cause as
ADR-FC-0011, now proven systemic. A single localized template edit with
centrally-controlled ordering is lower-risk and more uniform than 15
hand-writes, and is strictly correct: releasing a handle's own `ctx` ref
can never prematurely free a context another live handle still holds
(that holder keeps its own ref). Supersedes ADR-FC-0011's deferred
"note-not-fix" for the template; ADR-FC-0011's doc-warning stays as the
tripwire for *future* extra GC-managed fields the template can't know
about. Slice D3.

**Round-3 / Stage-3 scope correction — the term template leaks `ctx`
too.** D4's audit (ADR-FC-0013) confirmed the leak is NOT confined to
`emitRefcountLifecycle`. `termDestroy` (`lifecycle.nim:110`), the
`=destroy` body used by **every value family** (`Z3Ast`, `Z3BitVec`,
`Z3Fp`, `Z3Array`, `Z3Seq`, `Z3Set`, `Z3Regex`, `Z3UninterpretedVal`,
`Z3RcfNum`, `Z3Pattern`, …), also touches only `v.raw` and never
releases `v.ctx: Z3Context`. Every value object therefore leaks the one
`ctx` reference its construction/`=dup` added — the most numerous
instance of the class (one per Int/Bool/BV/… ever built). Reads as
*still reachable* on single-context programs, but inflates the context
refcount so it can never reach zero. **D3's fix must extend to
`termDestroy` as well** (release `v.ctx` after the raw `dec_ref`), and
must keep `termCopy`/`termDup` ctx-balanced (they already reassign
`dst.ctx`/`result.ctx`, which ARC ref-counts — verify no double-release
empirically). So D3 covers BOTH lifecycle templates, not just the
ref-handle one.

### ADR-FC-0013 — Valgrind harness must use `-d:useMalloc`; audit + fix all hand-written `=destroy` for the leak class (Stage-3 discovery)

**Decision.** (1) Add `-d:useMalloc` to the `nimble valgrind` task's
compile line (and the dev `nimz3.sh valgrind` helper). (2) Audit **every**
hand-written `=destroy` hook in `src/z3/*.nim` (18 of them) for the
ADR-FC-0011 leak class — a custom destructor that fails to release a
GC-managed field it owns (esp. `ctx: Z3Context` and refcounted handles) —
and fix each. Slice **D4**.

**Evidence (Stage-3, empirical).** Nim's default allocator is an
mmap/arena allocator; valgrind's `--leak-check` works at `malloc`
granularity and therefore **cannot see any Nim-side leak** without
`-d:useMalloc`, which routes Nim allocations through the system `malloc`.
The committed `valgrind` task omits the flag, so its entire subset has
been blind to Nim-side wrapper leaks — the exact bug this RFC targets.
Measured on the D2 registry bug: `definitely lost: 0` without the flag
vs. `262,152 → 0` (before → after fix) with it. Enabling the flag also
surfaced a **pre-existing** instance of the leak class:
`Z3ConstructorDeclOwn[T].=destroy` (`datatypes.nim:173`) dec-refs its
func_decls but never releases its own `ctx` field — `tdatatypes` leaks
**416 B**; it is a hand-written destructor and thus **not** covered by
ADR-FC-0012's `emitRefcountLifecycle` template fix.

**Instrument note.** A leaked `ctx` **ref** on a handle whose context is
still otherwise alive shows up as *still reachable*, not *definitely
lost* (e.g. `tsolver`/`tmodel` read 0 even pre-D3, because their fixtures
keep one long-lived context). So the definitely-lost gate proves the
*table/allocation* leaks (D2, D4) but is the wrong instrument for the
*systemic ctx-ref* leak (D3) — that one is proven by the **counting
`=destroy` hook** (drop the handle **and** the caller's context binding,
assert the context's own `=destroy` fires; probe FACT B). Both proofs
run under `-d:useMalloc`.

**Rationale.** Consistent with §11/§11a's decision to batch this exact
bug class. A proof harness structurally blind to Nim-side leaks is
worthless for an RFC whose whole subject is Nim-side ctx/table leaks;
`-d:useMalloc` is the standard Nim+valgrind pairing. Corey signed off on
the scope growth (harness change + D4) in Stage 3.

## 5. Public API (proposed surface)

**Reduce fields cut from v2.1.0 (this revision).** `reduceAssign`/
`reduceApp` are **not** part of the `Z3FixedpointHandlers` shipped in
v2.1.0 — deferred to the v2.2 RFC per ADR-FC-0003
(SUPERSEDED/DEFERRED, §4) and §2. The raw §N7.8
`setReduceAssignCallback`/`setReduceAppCallback` remain the surface for
reduce until then.

```nim
type
  Z3FixedpointHandlers* = object
    newLemma*:     proc(lemma: Z3AnyAst, level: uint) {.closure, raises: [].}
      ## Spacer engine only. A discovered lemma at induction `level`.
      ## `level` is `uint` (Z3 gives `cuint`; a signed `int` would
      ## truncate to negative above int32.high on 32-bit — matches
      ## propagator.nim's `uint` for cuint-sourced counters).
    predecessor*:  proc() {.closure, raises: [].}   ## Spacer only.
    unfold*:       proc() {.closure, raises: [].}   ## Spacer only.

  Z3LemmaLog* = ref object
    ## Growing log of discovered lemmas (returned by `collectLemmas`).
    ## Named, iterable type rather than a bare `ref seq` — the codebase
    ## returns plain `seq[T]` everywhere else; a rooted, growing handle
    ## is the one place a `ref` is warranted, so give it a name that
    ## documents itself and can gain fields without a breaking change.
    entries*: seq[tuple[lemma: Z3AnyAst, level: uint]]
iterator items*(l: Z3LemmaLog): tuple[lemma: Z3AnyAst, level: uint]
proc len*(l: Z3LemmaLog): int

proc setHandlers*(fp: Z3Fixedpoint, handlers: Z3FixedpointHandlers)
  ## Install typed closures on `fp` (replaces any previously installed
  ## set — wholesale, not merged). Allocates a GC-rooted box held by
  ## `fp`, calls Z3_fixedpoint_init, and registers only the non-nil
  ## callbacks. Export handlers fire only under engine=spacer, the
  ## default (silent no-op under engine=datalog). (Reduce handlers are
  ## not part of this v2.1.0 record — see the raw §N7.8 procs.)
  ## Call OUTSIDE an active query (ADR-FC-0005). Do not mix with the
  ## raw §N7.8 procs on the same fp (ADR-FC-0009).
  ## No ctx-less overload: `fp` already carries its context, exactly
  ## like `setParams` (PARITY §1.4 governs mk* constructors, not this).
  ## To abort a running query FROM a handler, call `fp.ctx.interrupt()`
  ## (the sanctioned same-thread interrupt — makes the in-flight
  ## query/queryFromLevel return `zsUnknown`/`"interrupted"`); the
  ## exception wall (ADR-FC-0001) means a handler must NOT signal via
  ## `raise`.

proc handlers*(fp: Z3Fixedpoint): Z3FixedpointHandlers
  ## The currently-installed handler set (a default all-nil object if
  ## none). The box already holds this value to dispatch, so exposing it
  ## is free and strictly more informative than a bool. `hasHandlers`
  ## and `collectLemmas`-composition are both defined in terms of it.

proc clearHandlers*(fp: Z3Fixedpoint)
  ## Remove installed handlers (installs an all-nil set; the sticky
  ## C-level registrations become dormant via the shim nil-check —
  ## Z3 has no deregister call). Safe outside a query.
  ## INVARIANT (ADR-FC-0008): this must NOT drop `fp`'s box to nil — the
  ## box stays live and reachable for `fp`'s whole lifetime regardless of
  ## handler contents, because the C-side `state` registrations are
  ## sticky. Implemented by mutating the existing box's handler set in
  ## place (or re-running the `setHandlers` init-first path), never by
  ## `fp.cbBoxRef = nil`.

proc hasHandlers*(fp: Z3Fixedpoint): bool
  ## True if any handler field is currently non-nil. Sugar over
  ## `handlers()` (`fp.handlers.newLemma != nil or …`).

proc collectLemmas*(fp: Z3Fixedpoint,
                    base = default(Z3FixedpointHandlers)): Z3LemmaLog
  ## Convenience: installs a `newLemma` handler that appends every
  ## discovered lemma to the returned `Z3LemmaLog` (read after query()).
  ## COMPOSES with the general surface: pass a `base` handler set and
  ## `collectLemmas` chains its lemma-appender AFTER `base.newLemma`
  ## (if any) and copies base's other fields through unchanged — so
  ## "collect lemmas AND run a predecessor handler" is one call, not a
  ## hand-rolled record. Still a single box per `fp` (ADR-FC-0002): the
  ## returned log is rooted by both the box's closure capture and the
  ## caller's binding.
```

Naming: `setHandlers`/`clearHandlers`/`hasHandlers` mirror the
same-file sibling `setParams` (existing-handle + config in, mutate,
`void` out) rather than the cross-module `newPropagator` — the closer
analogy. `hasHandlers`/`handlers` return-by-value; the mutators return
`void` (matching every `fixedpoint.nim` mutator: `addRule`,
`registerRelation`, `setParams`).

**Flat record over a Datalog/Spacer split (round-2 design decision;
now moot for v2.1.0's 3-field record, kept for the v2.2 RFC).** The
original five fields (now three, reduce deferred — see above) could be
grouped into `datalog*` / `spacer*` sub-records to make the engine
partition structurally visible. Kept **flat**: the `engine=` selector
is a *runtime* string param, so nesting would not turn the silent-no-op
footgun into a type error (only docs + the §7 no-op test can) — it
would only add a layer of nesting (`handlers.spacer.newLemma`) while
diverging from the shipped flat `Z3PropagatorHandlers`. Flat + per-field
docstrings + the no-op test is the right point on the curve; a
contributor who knows the propagator record reads this one unchanged.
**When reduce ships (v2.2), the split-vs-flat question becomes live
again** — re-evaluate it against the by-then two-engine, five-field
record rather than assuming flat still wins.

## 6. Stage → slice breakdown (Stage 1 deliverable)

**v2.1.0 slice roadmap (this revision):** Stage 0 → A0 → A1 → A2 → A3
→ C (+ Stage D, independent/parallelizable). **Stage B (reduce) is cut
from this RFC's scope** — deferred to a dedicated v2.2 RFC, per §2 and
ADR-FC-0003 (SUPERSEDED/DEFERRED). It is kept below as the historical
spike plan / a starting point for that future RFC, marked accordingly.

**Stage 0 (feasibility spike — GATES the whole plan; round-1
addition).** Before any slice is committed, prove — with counting
`{.cdecl.}` no-op procs on the *raw* surface — that each sub-family
actually fires through the public API. **Not throwaway (round-2 fix):**
the spike's *fixtures* are the expensive, hard-won artifact (esp. the
Datalog one below) and B1–C1's RED tests all need them, so promote the
fixture code into a committed test helper (`tests/tfixedpoint_fixtures.nim`
or similar) that later slices import — mirroring the v0.1 precedent in
`docs/SPIKE_FINDINGS.md` (spike code kept, not discarded). Findings
(ownership branch, pre-fill, thread) are pinned by folding the concrete
answer directly into the relevant ADR's prose and adding a
`docs/SPIKE_FINDINGS-fixedpoint.md` entry — the same convention round 1
used for the destructor probe (result embedded in ADR-FC-0002; no fresh
architect round required).

- Export callbacks: register `add_callback` against a Spacer fixture
  (the `tspacer.nim`-style unary-predicate + inductive-rule) under
  `engine=spacer`, driven through **both `query` and `queryFromLevel`**
  (the third entry point, ADR-FC-0005). Include **at least one UNSAT
  query** (a predicate proven unreachable), not only a SAT witness:
  `newLemma` fires most reliably while Spacer is *blocking a bad state*
  during UNSAT proof search, so a SAT-only fixture risks under-firing it
  and a false-negative escalation. Assert `newLemma`/`predecessor`/
  `unfold` fire ≥ 1× each. *(The existing raw test only ever ran the
  trio under `engine=datalog`, where it cannot fire — so A2/A3 have
  zero prior evidence, not just B2/B3.)*

**Reduce sub-family — spike ran; result is DEFERRED to v2.2 (resolved
this revision).** Findings are recorded in
[SPIKE_FINDINGS-fixedpoint.md](SPIKE_FINDINGS-fixedpoint.md): reduce
fires only under `datalog.default_relation=external_relation` for a
custom relation plugin's algebra ops — not the `Z3BitVec[N]`-relation
guess below, and not ordinary term rewriting — so the typed reduce API
is a bigger design problem (op-kind dispatch, not `(decl, args)`) than
ADR-FC-0003 assumed. The two bullets below are kept as the historical
spike plan / record of what was tried, for the v2.2 RFC's benefit;
**Stage B (reduce shims, below) is cut from v2.1.0.**

- Reduce callbacks (**HIGHEST-UNCERTAINTY item — open-ended, do not
  time-box like the export half**): register `set_reduce_assign`/
  `set_reduce_app` under `engine=datalog` against a relation whose
  evaluation forces a register-assign / app-reduction step (not a ground
  `addFact`). **No repo recipe exists** — verified: the only relational
  join fixture (`tfixedpoint.nim:25–53`, edge/path) runs under Spacer,
  and the only `engine=datalog` fixture (`tfixedpoint_extra.nim:67–99`)
  is exactly the ground-`addFact` case that will *not* fire reduce. The
  Datalog engine wants finite-domain sorts. Starting guess (not a
  validated recipe): the `tfixedpoint.nim:25–53` edge/path structure
  swapped to `Z3BitVec[N]` relations under `fp.engine=datalog`. Assert
  ≥ 1× fire.
- Pin the reduceApp `res[]` **ownership branch (a) vs (b)** and the
  pre-fill contract (ADR-FC-0003) empirically here — observe the
  rewritten AST's refcount to pick the branch.
- **Same-thread check (round-2):** record the calling thread id inside a
  throwaway shim and compare against the `query`/`queryFromLevel`
  caller's — verify the engine fires callbacks synchronously on the
  query thread (propagator documents this for `check()`; fixedpoint
  never has). Feeds the THREADING.md note (C3).

**Contingency (escalation trigger):** if a sub-family cannot be fired
through the public `query`/`queryRelations`/`queryFromLevel` surface in
the shipped Z3 build, STOP and escalate — the affected slices are not
TDD-able as written and the RFC scope must shrink (ship the fireable
half; document the other as raw-only) or add a lower-level driver.

**Resolved this revision.** The spike ran and both forks landed without
invoking this contingency as an open escalation: **A2/A3** (export) are
TDD-able as written — `newLemma`'s apparent no-fire was a missing param
(`fp.spacer.p3.share_lemmas`/`share_invariants`), not a reachability gap
(see A2 below); **B2/B3** (reduce) *did* fire, but only under a
narrow, non-obvious condition that makes the originally-designed typed
signature wrong — so rather than "shrink to raw-only," the resolution
is the scope decision in §2: ship the fireable, correctly-designable
half (export) now, and defer reduce's typed design to v2.2 rather than
force it into this RFC's slice plan.

### Stage A — Box + scaffold + export callbacks

*(A1 was one over-loaded slice in round 1 — module + box + field +
accessors + destructor + inQuery guard + setHandlers + gating + the
plan's hardest test. Split in round 2 into A0 — the box/field/destructor
and its collection proof, which gates on the FACT-B mechanism — and A1 —
the setHandlers/init/guard wiring.)*

- **A0 — box + field + destructor + collection proof.** Create
  `z3/fixedpoint_callbacks` with `FixedpointCtxBox` (`ref object of
  RootObj`), add the `cbBox: RootRef` field + `cbBoxRef` accessors on
  `Z3FixedpointOwn`, and **replace `fixedpoint.nim:76`'s
  `emitRefcountLifecycle(Z3FixedpointOwn, …)` call with a hand-written
  `=destroy`** (dec_ref raw → drop `cbBox` → release `ctx`, matching
  ADR-FC-0012's order), per ADR-FC-0002. **RED:** a hand-written counting
  `=destroy` on `FixedpointCtxBox`'s concrete type increments exactly
  once when the last `fp` reference drops (probe FACT B: RootObj is
  reclaimed on scope exit under ORC), and the box **survives** a
  `GC_fullCollect` while `fp` is alive — proving the ADR-FC-0002
  rooting+cleanup pair. Uses no `new(x, finalizer)` (can't attach to
  `FixedpointCtxBox(...)` construction).
- **A1 — handlers type + gating + setHandlers + inQuery guard.**
  `Z3FixedpointHandlers`, the `-d:z3WithoutFixedpointCallbacks` gate, the
  debug `inQuery` guard threaded through the `withInQuery` choke point
  (ADR-FC-0005, covering `query`/`queryRelations`/`queryFromLevel`), and
  a `setHandlers` that allocates + roots the box (A0's field) and calls
  `Z3_fixedpoint_init` first (ADR-FC-0008 ordering). **RED:**
  `setHandlers(fp, Z3FixedpointHandlers())` runs; `hasHandlers`/
  `handlers()` reflect it; `setHandlers` during an active query trips the
  debug assert.
- **A2 — `newLemma`.** Shim (with exception wall) + `add_callback`
  registration. **Escalation resolved (this revision):** Z3 gates
  `new_lemma` callback dispatch behind Spacer params —
  `fp.spacer.p3.share_lemmas` for finite-level lemmas,
  `fp.spacer.p3.share_invariants` for infinity-level ones
  (source-verified: `spacer_context.cpp:4286–4304`,
  `context::new_lemma_eh`). The Stage-0 spike's initial no-fire result
  was this missing param, not a reachability gap. `setHandlers`' install
  path therefore sets **both** `share_lemmas=true` and
  `share_invariants=true` whenever a `newLemma` handler is registered
  (covers finite- and infinity-level lemmas uniformly, since the level
  actually used isn't known until query time) — making **A2 fully
  TDD-able as written**. **RED:** the Stage-0 Spacer fixture invokes the
  closure with a non-nil `Z3AnyAst` lemma (renders via `$`) and a
  plausible `level`; counter ≥ 1.
- **A3 — `predecessor` + `unfold`.** Remaining export shims through the
  same `add_callback`; nil handler ⇒ nil fptr to Z3. **RED:** each fires
  ≥ 1× on the fixture; a record with only `newLemma` set passes `nil`
  for the other two (no crash, no spurious fire).

### Stage B — Reduce callbacks (Datalog) — **REMOVED from v2.1.0, deferred to a dedicated v2.2 RFC**

**Cut, this revision (§2, ADR-FC-0003).** The Stage 0 spike confirmed
reduce fires (gated on `datalog.default_relation=external_relation`,
a narrower and different condition than the fixture guess in Stage 0's
bullets above), but that the correct typed shape is an op-kind
dispatcher, not the `(decl, args)` signature B1–B3 were slated to
build. B1/B2/B3 below are **not implemented in v2.1.0**; kept as the
historical slice plan / a starting point for the v2.2 RFC.

**B1 disposition — cut wholesale, nothing folded into Stage A.**
`decodeAstArray` (ADR-FC-0004) and its threadvar-free check are
**reduce-only** — confirmed against §3: the export callbacks' payloads
are `(lemma: Z3AnyAst, level: uint)` for `newLemma` and no payload at
all for `predecessor`/`unfold`; none touches a `Z3_ast const[]`. So B1
carries nothing forward into A3 or elsewhere in Stage A; it is cut
alongside B2/B3, not kept/folded.

- **B1 — `decodeAstArray` + threadvar-free verification.** The array
  decoder (ADR-FC-0004) **and** the ADR-FC-0007 check that a handler
  builds a replacement AST from `decl.ctx`/`args[i].ctx` alone.
  **RED:** unit-decode of 0-, 1-, N-length raw arrays → correct
  `seq[Z3AnyAst]` (`$` per element; `@[]` for n=0 without deref).
- **B2 — `reduceAssign`.** Shim + registration. **RED:** a Datalog step
  invokes the closure with the expected `decl` identity
  (`decl == relation.toAnyFuncDecl()`) and decoded in/out seqs.
- **B3 — `reduceApp` + ownership transfer.** Shim writes `res[]` only on
  `some`, per the Stage-0-chosen ownership branch (ADR-FC-0003), with the
  exception wall enclosing the transfer (ADR-FC-0001). **RED, two cases:**
  (i) `none` leaves the application unchanged; (ii) `some(fresh)` — a
  term with 0 external refcount built inside the closure — *and*
  `some(args[i])` — echoing an input arg (a distinct refcount path) —
  both rewrite correctly. **Proof mechanism (round-2 fix):** the
  premature-free is a *value-type* ARC race resolved inside
  compiler-generated glue with no Nim-code window to force GC between
  "closure returns" and "shim returns" — so `GC_fullCollect()` is the
  wrong tool here (it's right for A0's `ref`/cycle proof, not this). Add
  `tfixedpoint_typed_callbacks` to the **ASAN CI job** (`ci.yaml:184–192`,
  which today lists `tcontext`/`tast`/… but not this file): a missing
  `inc_ref` is a genuine use-after-free ASAN catches deterministically —
  a far stronger proof than a mistimed collect.

### Stage C — Integration, lifecycle, docs

- **C1 — re-install / dormant / mixing / abort / compose.** (a)
  Re-install with a handler set to `nil` ⇒ that handler stops firing
  (dormant-not-deregistered). (b) Accumulation via `collectLemmas`:
  query fires `newLemma` N>1×, assert the returned `Z3LemmaLog` has N
  correctly-typed entries after `query()`; also assert `collectLemmas(fp,
  base = <set with a predecessor handler>)` **composes** — both the
  lemma log fills *and* the base handler fires (design read-back). (c)
  Mixing hazard (ADR-FC-0009): calling a raw §N7.8 proc after
  `setHandlers` is caught by the debug assert / demonstrably documented.
  (d) Abort-from-handler: a `newLemma` handler that calls
  `fp.ctx.interrupt()` makes the in-flight `query`/`queryFromLevel`
  return
  `zsUnknown`/`reasonUnknown == "interrupted"` within a bounded number of
  further fires (the sanctioned abort channel — verifies interrupt is
  polled between callback firings within one query). **RED:** all four.
  GC-safety uses `GC_fullCollect()` around boundaries and adds
  `tfixedpoint_typed_callbacks` to the `nimble valgrind` subset (a
  one-line addition; the RFC's earlier "ORC leak counters" harness does
  not exist).
- **C2 — minimal-build gate.** Follow the `tspacer.nim` same-file
  `when defined(z3WithoutFixedpointCallbacks): suite ... skip()`
  pattern (**not** `testMinimal`, a different flag family). **CI
  mechanism corrected (round-2):** the `gate-flags` job
  (`.github/workflows/ci.yaml:97–136`) only ever compiles+runs
  `tests/tminimal.nim` per matrix row — adding a
  `-d:z3WithoutFixedpointCallbacks` row therefore tests *nothing* about
  the new gated module unless `tminimal.nim` references its symbols, and
  does **not** satisfy §7's "compiles + skips cleanly" for the new test
  file itself. So C2 does two concrete things, not a "one-line matrix
  add": (a) add scope-hiding `compiles()`/`when` checks for the new
  public symbols to `tminimal.nim` (proves the gated surface truly
  vanishes), and (b) add a distinct CI step that compiles
  `tests/tfixedpoint_typed_callbacks.nim` under
  `-d:z3WithoutFixedpointCallbacks` and asserts the skip-suite path. This
  also closes the standing `z3WithoutPropagator`/`z3WithoutSpacer` gap
  (neither is in the gate matrix today).
- **C3 — docs.** Module docstring (pattern + ADR pointers +
  propagator's gcsafe/no-cross-thread note restated); `z3.nim`
  layered-architecture entry (parallel to `z3.nim:269`); **PARITY.md**
  new "handler-record pattern" exemption category (retroactively
  covering `Z3PropagatorHandlers`, which PARITY.md omits today);
  **INTERNAL_API.md** note for the `cbBoxRef` seam; **THREADING.md**
  new "callback threading" section (covers propagator + fixedpoint —
  currently neither is documented there — records the Stage-0 same-thread
  finding); **GOTCHAS.md** entries for the mixing hazard, engine
  coupling, and dormant-not-deregistered semantics; **MINIMAL_BUILD.md**
  — document the new `-d:z3WithoutFixedpointCallbacks` flag in the
  flag/combo tables **and fix the pre-existing stale `-d:z3WithoutFixedpoint`
  reference at MINIMAL_BUILD.md:143** (that flag exists nowhere in
  `src/`; fixedpoint is always-on core — a real dead-doc reference one
  row from where the similarly-named new flag lands, a genuine
  reader-collision risk); update the header docstring of the existing
  raw test `tests/tfixedpoint_callbacks.nim:6–8` (drops "typed wrappers
  explicitly deferred", points at the new file); CHANGELOG `[2.1.0]`;
  and mark §N7.8 "deferred to follow-on RFC" **resolved** in
  `RFC-completeness.md` + `IMPLEMENTATION_PLAN.md`.

### Stage D — Batched v2.0 latent-bug backfixes (independent; parallelizable with Stage A/B)

- **D1 — propagator exception wall (ADR-FC-0010).** Add the
  `try/except` wall to all nine propagator shims + `{.raises: [].}` on
  the handler fields. **RED:** a propagator handler that raises does not
  crash / does not unwind into Z3; `check()` completes and the raise is
  swallowed by the wall (assert via a flag the except-branch sets).
- **D2 — context `=destroy` field release (ADR-FC-0011).** Extend
  `Z3ContextOwn`'s destructor; add the `emitRefcountLifecycle` doc
  warning. **RED:** a regression test that populates
  `datatypeRegistry`/`uninterpretedRegistry` (declare a datatype +
  an uninterpreted sort), drops the context, and shows no leak — add
  a **registry-populating** context test to the `nimble valgrind`
  subset (the existing `tcontext` fixture leaves them empty, which is
  why the bug hid). The round-1 standalone probe becomes this test's
  basis. **The valgrind subset must build with `-d:useMalloc`
  (ADR-FC-0013)** or the leak is invisible. **DONE** (verified: isolated
  uninterpreted-only teardown → `definitely lost: 0` under useMalloc).

- **D3 — systemic ctx-release in BOTH lifecycle templates (ADR-FC-0012,
  Stage-3 scope correction).** Extend `emitRefcountLifecycle`'s generated
  `=destroy` (the ~15 ref-handle types) **and** `termDestroy` (every
  value family) to release `ctx` after the raw `dec_ref`; verify
  `termCopy`/`termDup` stay ctx-balanced (no double-release). Supersede
  ADR-FC-0011's deferred note. **RED:** a
  regression test that creates a handle (e.g. a `Z3Solver`) against a
  context, drops **both** the handle and the caller's context binding,
  and shows the context is actually freed. **Prove via a counting
  `=destroy` hook** (assert the context's own destructor fires), *not*
  the definitely-lost gate — a leaked ctx ref on an otherwise-live
  context reads as *still reachable*, not *definitely lost*
  (ADR-FC-0013). Run across a couple of representative handle types
  (`Z3Solver`, `Z3Model`). Land alongside D1/D2.

- **D4 — audit + fix all hand-written `=destroy` for the leak class;
  enable `-d:useMalloc` in the valgrind harness (ADR-FC-0013).** Add
  `-d:useMalloc` to `z3.nimble`'s `valgrind` task (and `nimz3.sh`).
  Audit all 18 hand-written `=destroy` hooks in `src/z3/*.nim`; fix each
  that fails to release a GC-managed field it owns. Confirmed instance:
  `Z3ConstructorDeclOwn[T].=destroy` (`datatypes.nim:173`) must release
  its `ctx`. **RED:** `tdatatypes` (and the datatype half of
  `tcontext_registry`, once its `dtCtx` is torn down — now possible
  post-fix) report non-zero `definitely lost` under `-d:useMalloc`
  before the fix, `0` after. Strengthen `tcontext_registry` to tear down
  **both** contexts. Land alongside D1/D2/D3.

These four slices touch only shipped v2.0 code, share nothing with
Stage A–C, and can land first (D2/D3/D4 de-risk the destructor pattern
the new `cbBox` field depends on).

## 7. Testing strategy

- New `tests/tfixedpoint_typed_callbacks.nim` (beside the raw
  `tests/tfixedpoint_callbacks.nim`).
- **Export** tests drive the Stage-0-validated Spacer fixture under
  `engine=spacer`, through **both `query` and `queryFromLevel`**, and
  include **a SAT and an UNSAT query** (the latter exercises the
  bad-state-blocking path where `newLemma` fires most reliably).
- **Reduce tests — DEFERRED to v2.2** alongside Stage B (§6, ADR-FC-0003);
  not part of `tests/tfixedpoint_typed_callbacks.nim` for v2.1.0.
- **Lifecycle** (A0/C1): `GC_fullCollect()` between install and query
  proves rooting; a **counting `=destroy` on `FixedpointCtxBox`** proves
  collection on `fp` death (probe FACT B — deterministic on scope exit).
- **Leak proofs & instrument (ADR-FC-0013).** All valgrind runs build
  with **`-d:useMalloc`** — without it valgrind cannot see Nim-side
  leaks (Nim's default allocator is mmap/arena). Use the definitely-lost
  gate for **allocation/table** leaks (D2, D4); use a **counting
  `=destroy` hook** for **ctx-ref** leaks (D3), which read as *still
  reachable* rather than *definitely lost* when the context is otherwise
  alive.
- **Accumulation** (C1): the primary motivating scenario — `collectLemmas`
  fills a `Z3LemmaLog`, assert N typed entries post-`query()`; plus the
  **compose** case (`collectLemmas(fp, base = …)` fills the log *and*
  runs `base`'s handlers).
- **Engine no-op**: install export handlers (e.g. `newLemma`) under
  `engine=datalog`, assert zero fires — documenting the silent coupling.
  (The symmetric reduce-under-`engine=spacer` case is deferred with
  Stage B.)
- **Outcome coverage**: assert callbacks behave correctly when the query
  returns SAT, UNSAT, *and* UNKNOWN — not only the SAT witness path.
- **Abort channel** (C1): `fp.ctx.interrupt()` from inside a handler ⇒
  query returns `zsUnknown`/`"interrupted"`.
- **Mixing hazard** (C1): raw proc after `setHandlers` trips the debug
  assert.
- **Exception wall**: a handler that raises does not crash the process /
  does not unwind into Z3 (assert the wall swallows it, query completes).
  (`reduceApp`'s post-closure-transfer wall extension is deferred with
  B3/ADR-FC-0003 — no v2.1.0 shim does post-dispatch work.)
- **Ownership (B3) — DEFERRED to v2.2** alongside Stage B; no v2.1.0
  shim has an ownership-transfer out-param to prove.
- **Gate** (C2): the new symbols vanish under
  `-d:z3WithoutFixedpointCallbacks` (`compiles()` check) and the test
  file compiles+skips cleanly under the flag.
- Every callback asserts **both** that it fired (counter) **and** that
  its typed payload is correct (`decl` identity / `$` render), never
  just "no crash."

## 8. Compatibility & release

- **Additive-only.** No existing symbol changes signature. New symbols
  behind a default-shipped flag; new always-on additions are
  `Z3LemmaLog` and the internal `cbBoxRef`/`inQuery`/`withInQuery`
  seams. (`Z3AnyFuncDecl` — ADR-FC-0003's fresh, refcounted value
  type — is **deferred to v2.2** with the reduce pair; it has no
  v2.1.0 consumer.) → **v2.1.0** minor bump.
- **Systemic `ctx`-leak fix (ADR-FC-0012, batched per §11a):** extending
  `emitRefcountLifecycle` to release `ctx` is a pure bugfix — no
  signature change on any of the ~15 handle types; the only behavioral
  delta is that a handle's teardown now correctly drops its context
  reference (a context held only by dropped handles is freed sooner,
  never later). CHANGELOG `[2.1.0]` lists it under "Fixed."
- Raw §N7.8 surface untouched (escape hatch preserved; mutual-exclusion
  documented per ADR-FC-0009).
- **Batched backfixes (ADR-FC-0010/0011)** are pure bugfixes to shipped
  v2.0 code — no public signature change. The only observable delta is
  `{.raises: [].}` on the propagator handler fields, which can reject a
  provably-raising closure at compile time; that is a correctness
  tightening, not a runtime break, and any such caller was already at
  UB risk. CHANGELOG `[2.1.0]` lists them under "Fixed."
- Migration guide: none needed. CHANGELOG `[2.1.0]` documents the typed
  surface and the two backfixes, and points here.

## 9. PARITY.md status

`Z3FixedpointHandlers` / `FixedpointCtxBox` match **neither** PARITY §1
(`Z3Term`: no `raw`/`ctx`) **nor** §2 (ref handles carrying `raw*`/
`ctx*`). They are a **handler-record pattern**, PARITY-exempt — as is
the already-shipped `Z3PropagatorHandlers` (which PARITY.md currently
neither lists nor exempts). C3 adds this category to PARITY.md,
retroactively covering both. (`Z3AnyFuncDecl` would be a value handle
(`raw*`/`ctx*`, `$`, `==`) getting the standard §2 treatment — but it
is **deferred to v2.2** with the reduce pair, ADR-FC-0003, so it is not
part of this RFC's PARITY.md update.)

## 10. Open questions (resolved this round)

All four prior open questions are now resolved in the ADRs:
1. `decl` type → `Z3AnyFuncDecl` (ADR-FC-0003) — moot for v2.1.0: `decl`
   only appears in the deferred reduce signatures, so this question
   carries over to the v2.2 RFC rather than resolving here.
2. Module vs gated block + cbBox seam → split placement + `RootRef`
   (ADR-FC-0002, ADR-FC-0006).
3. `currentBox` threadvar → not needed; verified at **A2** for v2.1.0's
   shipped surface (`newLemma`'s `lemma.ctx`; `predecessor`/`unfold`
   need no context at all) rather than B1, which is deferred
   (ADR-FC-0007).
4. Datalog (and Spacer) reachability → **Stage 0 spike ran and settled
   both** (§6, `SPIKE_FINDINGS-fixedpoint.md`): Spacer export callbacks
   are reachable and ship in v2.1.0; Datalog reduce callbacks are
   reachable too, but only under a narrow condition that reframes the
   typed design — resolved as a scope decision (defer to v2.2, §2)
   rather than an escalation.

## 11. Batched v2.0 backfixes (resolved — author chose "batch in")

Round 1 flagged **two latent issues this RFC designs around for the new
surface that also exist in already-shipped v2.0 code**. The author's
decision was to **batch both into this v2.1.0 RFC** (ADR-FC-0010,
ADR-FC-0011; Stage D slices):

- **Exception wall (→ ADR-FC-0010).** `propagator.nim`'s shims dispatch
  user closures with no `try/except` across the `{.cdecl.}` boundary; a
  raising handler is the same UB class this RFC walls off.
- **Custom-`=destroy` field leak (→ ADR-FC-0011) — CONFIRMED.** The
  round-1 probe (Nim 2.2.10, `--mm:orc`) settled the version-sensitive
  question: a user-defined `=destroy` skips field destruction entirely
  (an untouched `Table[string, ref]` field's `ref` values were
  destroyed **0×, not 2×**). `Z3ContextOwn`'s `=destroy`
  (`context.nim:107`) touches only `raw`/`cfg`, so its
  `datatypeRegistry`/`uninterpretedRegistry` table storage leaks on
  every context teardown; `tcontext`'s valgrind pass is an artifact of
  its fixture never populating those tables.

The same probe result also hardened ADR-FC-0002 (the new `cbBox` field
would leak identically without an explicit destructor drop) — so the
backfix and the new feature share one root cause, which is the strongest
argument for the batch: one fix pattern, three sites (context tables,
propagator wall's sibling, and the new `cbBox`).

### 11a. Round-2 escalation — the `ctx`-field leak is **systemic** (RESOLVED — author chose "batch in", Option A → ADR-FC-0012, slice D3)

Round 2 (probe FACT A) established that the same custom-`=destroy`
mechanism leaks **plain `ref` fields**, not just `Table` fields — and
that `emitRefcountLifecycle`'s generated `=destroy` never releases the
`ctx: Z3Context` ref it holds. This is **not** the two isolated sites
ADR-FC-0011 assumed: it affects **all ~15** `emitRefcountLifecycle`
handle types (`Z3SolverOwn`, `Z3ModelOwn`, `Z3OptimizeOwn`,
`Z3FixedpointOwn`, `Z3TacticOwn`, `Z3GoalOwn`, `Z3ApplyResultOwn`,
`Z3StatsOwn`, `Z3ProbeOwn`, `Z3AstVectorOwn`, `Z3ParamsOwn`,
`Z3ParamDescrsOwn`, `Z3AstMapOwn`, `Z3ParserContextOwn`,
`Z3SimplifierOwn`), each leaking its context reference on teardown
(masked only because most programs keep one long-lived context).

**The fork (needs the author's scope/risk call):**

- **Option A — batch the systemic fix now.** Extend
  `emitRefcountLifecycle` to release `ctx` (after the raw `dec_ref`),
  fixing every handle type uniformly in one central place. *Pro:* retires
  the entire bug class the RFC's own analysis surfaced; a template fix is
  actually lower-risk and more uniform than 15 hand-written destructors;
  correct-by-construction for future handle types. *Con:* grows an
  already-3-backfix RFC; adds a valgrind/ASAN proof obligation across a
  few representative handle types; touches every ref-handle teardown in
  the library (though the change is one localized template edit).
- **Option B — scope it out.** Fix only `Z3FixedpointOwn`'s own `ctx`
  release (already required by A0's hand-written destructor) + keep the
  ADR-FC-0011 corrected doc-warning, and file the library-wide
  `emitRefcountLifecycle` fix as a separate follow-up (mirroring how
  §N7.8 itself was deferred). *Pro:* keeps v2.1.0 tightly scoped to the
  feature + the two already-agreed backfixes. *Con:* knowingly ships a
  systemic leak the RFC has now proven and documented.

**Recommendation: Option A (batch the template fix).** The fix is a
single localized edit to `emitRefcountLifecycle` with centrally
controlled ordering (lower risk than the per-type hand-writes already in
scope), it is the same root cause the author already chose to batch
twice, and it is strictly correct (releasing a handle's own `ctx` ref can
never prematurely free a context another live handle still holds). But
because it materially widens the release's test surface across ~15 types,
the batch-vs-defer call is the author's — hence escalated rather than
applied.

### 11b. Abort-from-handler channel (resolved — documented, no new API)

Round 2 noted the RFC solved "a handler must not raise" but never "a
handler wants to stop the query." The answer needs no new surface:
`Z3Context.interrupt()` (`context.nim:248`, already the documented
cross-thread exception to the no-reentrant-Z3-calls rule) makes an
in-flight query return `zsUnknown`/`"interrupted"`. It is now documented
as the sanctioned abort channel in `setHandlers`' docstring (§5) and
tested from inside a handler (C1(d), §7) — the one open question being
whether Z3 polls the interrupt flag *between callback firings within one
query*, which C1(d) verifies empirically.

## 12. References

- `docs/RFC-completeness.md` §N7.8 (escalation source), ADR-N0004
  (propagator pattern this parallels).
- `src/z3/propagator.nim` (reference box/shim/GC-rooting discipline).
- `src/z3/fixedpoint.nim:304–352` (raw §N7.8 surface being wrapped);
  `src/z3/lifecycle.nim:159` (`emitRefcountLifecycle`); `context.nim:107`.
- `src/z3/ffi.nim:366–406, 1319–1353` (FFI typedefs + fn decls);
  `ffi.nim:45` (`RawZ3FuncDecl`).
- `src/z3/funcdecl_types.nim:41–62` (`incRefFD`/`decRefFD` — the
  func_decl refcount discipline `Z3AnyFuncDecl` must follow, ADR-FC-0003).
- `src/z3/spacer.nim:56` (`queryFromLevel` — the third query entry point,
  ADR-FC-0005); `src/z3/context.nim:248` (`interrupt` — abort channel);
  `src/z3/onclause.nim:100–116` (rejected table-keyed rooting pattern).
- `.github/workflows/ci.yaml:97–136` (`gate-flags` job — runs only
  `tminimal.nim`), `:184–192` (ASAN job — B3's UAF proof).
- `tests/tfixedpoint_callbacks.nim:6-8,81-89` (raw test proving zero
  firing; header docstring to update), `tests/tspacer.nim` (Spacer
  fixture to reuse), `tests/tfixedpoint.nim:25–53` (edge/path join —
  Datalog-fixture starting point), `tests/tfixedpoint_extra.nim:67–99`
  (ground-`addFact` Datalog case that will *not* fire reduce).
- **No prior-art bindings:** Z3Py's `Fixedpoint` and the OCaml bindings
  do not wrap this callback family — this surface is C-only, so Stage 0's
  empirical spike is the only ground-truth source (a future reader need
  not go looking for a reference binding).
- `docs/PARITY.md`, `docs/INTERNAL_API.md`, `docs/THREADING.md`,
  `docs/GOTCHAS.md`, `nim-z3.nimble` (`valgrind` task).
- [`docs/SPIKE_FINDINGS-fixedpoint.md`](SPIKE_FINDINGS-fixedpoint.md)
  (this revision — Stage-0 spike results: export-callback firing incl.
  the `newLemma` param gate, reduce's `external_relation` condition and
  AST-identity/ownership facts, same-thread confirmation, Z3 4.16.0
  parity check).

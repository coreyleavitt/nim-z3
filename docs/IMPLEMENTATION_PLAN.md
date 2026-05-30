# nim-z3 v0.4 plan (live)

A type-safe, memory-safe, idiomatic Nim wrapper for the Z3 SMT solver.

**Status**: planning. v0.3 shipped 2026-05-30 — see [`V0.3_PLAN.md`](V0.3_PLAN.md) for the archived plan that drove it (the architectural unification via `Z3Term`, the Char / String / Seq / Regex / FP / FuncDecl theory families, solver-tactic bridges, the `z3/sortdispatch` mixin-based consolidation, and the v0.3-era §8 deferral ledger + §8b pre-tag audit). This document is the live plan for v0.4, starting from a working v0.3 base (**890 OKs across `nim c` + `nim cpp`, zero failures**).

**Audience**: future-me, future contributors, anyone deciding whether v0.4's surface fits their use case.

## How this plan is being built

This is a **rollforward-only stub** at v0.3-tag time. The v0.2 → v0.3 pattern was: the v0.3 plan was written all at once before step 1, then steps executed against it. The v0.3 → v0.4 pattern starts differently because we genuinely don't know yet which of the rolled-forward items is the most important user-driven trigger. **Concrete §1 goals and §4/§5 step sequence will be written once one of the following surfaces as a real use case:**

- A consumer with a need for one of the v0.3 deferrals below, OR
- An architectural finding from real usage that forces a v0.4-shaped change, OR
- A new Z3 capability we want to wrap (a Z3 release between v0.3 and v0.4 that adds something we want).

Until then this document is the inventory below, and the rotation rules from the v0.2 / v0.3 closing notes.

## Rolled forward from v0.3 (the §8b "rolled to v0.4" inventory)

Every item carries a **what / why / trigger** triple. The trigger names the condition that should bump the item from "inventory" to "scoped v0.4 step":

### Real Z3 capabilities we deliberately didn't wrap in v0.3

- **`Z3Fixedpoint` — Horn-clause solving.** §1 goal 8 in V0.3_PLAN. No real-user trigger surfaced during v0.3; the surface is substantial (datalog rules, queries, the `Z3_fixedpoint_*` API family). **Trigger**: a Horn-clause verification or program-analysis-via-CHCs use case.
- **`Z3_solver_get_unsat_core`** — extract the minimal set of asserted constraints whose conjunction is unsat. Natural follow-up to setting `unsat_core=true` via the v0.3-step-8 `setParams` bridge. Needs the `Z3_ast_vector_*` surface (which already partly exists for goals). **Trigger**: a debugging-shaped consumer wants to know which assertions caused unsat.
- **`Z3_solver_get_proof`** — proof-term extraction. Even richer than unsat-core because the result is an AST in Z3's proof-rule grammar. **Trigger**: a proof-checker / proof-export consumer.
- **`Z3_solver_get_param_descrs`** — per-solver param-schema introspection (key names, types, doc strings). Would let a tool author build a config UI / validator. **Trigger**: a tooling consumer.
- **`Z3_func_interp` tabular extraction** — entries + else-value iteration of an uninterpreted function's interpretation under a model. `evalAt(m, f, args)` covers the "value at point" use case (v0.3 step 7); the full table is for tools that want to enumerate the model's complete function definition. **Trigger**: a consumer that needs the whole table.
- **`Z3Char` BV interop** (`Z3_mk_char_to_bv` / `_from_bv`) — char ↔ BV bit-pattern round-trip. Needs the runtime `:char-width` Z3 parameter threaded through + cross-module visibility between `z3/char` and `z3/bitvec`. **Trigger**: a string + BV mixed-theory use case (e.g. parsing a binary protocol containing strings).
- **`Z3DatatypeValue[T]` as a `sortdispatch` element type** — would let `Z3Array[Z3Int, Z3DatatypeValue[Foo]]`, `Z3Seq[Z3DatatypeValue[Foo]]`, `Z3FuncDecl[(Z3DatatypeValue[Foo],), Z3Bool]` etc. construct. Datatype sorts are made at runtime by `declareDatatype` and held on the decl, so `sortOf(_: typedesc[Z3DatatypeValue[T]], ctx)` needs a runtime decl-table lookup keyed by `T`'s marker type. The mechanism deserves its own design pass — the rest of `sortdispatch` is purely compile-time. **Trigger**: a user wanting datatype-keyed arrays or datatype-typed sequence elements.
- **`Z3Float128` / `Z3Float16` structured extraction** — `toFloat32` / `toFloat64` round-trip every binary32 / binary64 bit pattern, including NaN payloads. The wider FP types have no Nim-native receiver type; `toIeeeBv` is the escape hatch. A "give me the (sign, exponent, mantissa) triple" extractor surface would let users do their own decoding without going through BV. **Trigger**: a quad-precision / half-precision consumer.
- **Epsilon-bound `Z3Real` extraction** — Z3's optimisation can produce values like `1/2 + ε`. `Z3_get_numeral_double` only handles numerals so `toRealApprox` raises on epsilon-bound values. **Trigger**: a numerical-optimisation consumer that needs finite values from epsilon outputs.
- **`replace-all` on `Z3String`** — Z3 doesn't ship a primitive. Idiomatic path is regex composition. **Trigger**: someone wanting the convenience helper.

### Quality-of-life / docs items rolled forward

- **`{.optional.}` softlink declarations** for any Z3 4.13+-only symbol the wrapper picks up in v0.4. v0.3 didn't add any; v0.4 might. **Trigger**: first Z3-version-gated symbol.
- **Carry-forward CI work** ([#1](https://github.com/coreyleavitt/nim-z3/issues/1)) — macOS / aarch64 rows, `nim doc` Pages, valgrind, differential testing against the `z3` CLI. Same blocker as v0.2 / v0.3: the upstream private-dep blocker on `coreyleavitt/milpa` + `coreyleavitt/proptest`. **Trigger**: those repos go public (or a deploy key / PAT lands).
- **Differential testing against Python `z3`**. Non-goal as of v0.3. **Trigger**: explicit decision to ship it as a v0.4 goal.

### Out of scope for the wrapper — redirected, not deferred

These belong in sibling packages (`nim-z3-tools` / `nim-z3-viz`) — flagged in v0.3 §8 "Scope discipline":

- DOT / GraphViz AST export
- SMT-LIB pretty-printer beyond Z3's built-in
- An interactive REPL
- SMT-COMP driver
- AST query DSL

If you're starting v0.4 and one of these has a real consumer, the right move is **a separate repo** that depends on `nim-z3` — not adding it to the wrapper.

## §8 Deferred from v0.4 (running list, populated as work happens)

Same append-only format as v0.1 §18, v0.2 §8, v0.3 §8. Format: **what**, **why**, **where it goes** (v0.5 / dropped / sibling-package).

*(empty until the first deferral surfaces.)*

---

## Closing note

v0.1 / v0.2 / v0.3 each followed the same rotation pattern: live plan at `IMPLEMENTATION_PLAN.md`, archived plan at `V0.{N}_PLAN.md`, README "Design" section links all of them, `CHANGELOG.md` has the per-release diff. When v0.4 ships: archive this file to `docs/V0.4_PLAN.md`, write a fresh `docs/IMPLEMENTATION_PLAN.md` for v0.5, update the README's "Design" section to point at all four archives. Same pattern, same discipline.

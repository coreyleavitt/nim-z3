# RFC: regex-index + `replace_re_all` (issue #2)

> **Status:** Stage 3 (rfc-flow). Target release **v2.2.0**
> (additive minor; every pre-existing call site still compiles).
> Consumer: proptest symbolic-execution slice **B1** (regex `find` /
> `replaceRe` / `replaceAll` over patterns). Tracking issue: #2.
>
> **Scope expansion (2026-07-17, Corey):** the softlink v0.7/v0.8
> releases were shipped to enable *clean multi-version Z3 support*; that
> workstream is folded into this one flow (not a separate RFC) — see
> **§6**. Net RFC = regex-index/replace surface (§3–§5) **+**
> version-compat plumbing (§6). Still v2.2.0, still additive.
>
> **Descope (2026-07-22, Corey):** `replaceRe` / `replaceReAll`
> (`str.replace_re{,_all}`, §4.3) are **NOT shipped**. Implementation
> testing on a fully capable runtime (Z3 4.16.0) showed Z3's solver
> returns `unknown` on `str.replace_re{,_all}` for even fully concrete
> inputs (probed both directions; contrast `str.replace_all`, which it
> decides) — so the wrappers build correct terms no solver query can
> reason about, and the `smtValid`-based tests fail on every runtime.
> The FFI decls and `-d:z3WithSeqReplaceRe{,All}` flags were removed;
> deferred pending upstream Z3 decidability. What ships from this RFC:
> the **regex-index helpers** (`matchStartsAt`/`containsRe`/`indexOfRe`,
> §3–§4.2, decidable) **+** multi-version compat (§6). §4.3 and the
> `replace_re_all` half of the title are superseded by this note.

## 1. Motivation

proptest's symex engine defers slice **B1** — modelling Nim's
`re.find(s, pat)` (leftmost match *position*) and `re.replace` /
`replaceAll` over *patterns* — because Z3 has no regex-index
primitive. This RFC gives nim-z3 the minimal, honest surface that
unblocks B1 while leaving the bound-vs-degrade *policy* to the
consumer (proptest owns that; nim-z3 owns the primitive + the
soundness caveat).

Two distinct gaps (issue #2):

1. **No regex-index op in Z3.** The vendored `z3_api.h` has
   `Z3_mk_seq_index` (fixed-substring needle) and `Z3_mk_seq_in_re`
   (whole-string boolean), but **no `Z3_mk_seq_indexof_re`**. So
   "position of the first *pattern* match" has no native op — it must
   be *encoded* from primitives nim-z3 already wraps.
2. **`replace_re_all` is not wrapped** (and `replace_re` /
   `replace_all` are already `-d`-gated because they are absent from
   some Z3 distributions). `Z3_mk_seq_replace_re_all` has no FFI
   declaration in `ffi.nim` today.

## 2. The invariant this RFC deliberately crosses

Every proc in `sequence.nim` and `regex.nim` today is a **strict 1:1
wrapper** over exactly one native Z3 op — the doc-string is literally
`## SMT (<native_op> ...)`. There is *zero* precedent for a composite /
encoded helper.

`indexOfRe` has **no native op**, so it is nim-z3's **first encoded
operation** — a term built from other wrappers, carrying its own
soundness/termination contract rather than delegating semantics to
Z3. This RFC treats that crossing explicitly:

- Encoded helpers are documented as **encodings**, *not* with the
  `## SMT (op ...)` form. Their doc-string leads with a fixed marker
  that structurally mirrors the 1:1 form so the two styles stay
  grep-distinguishable, then states the exact term and the soundness
  precondition. **Template (durable precedent — this is the first
  encoded helper; copy this shape):**

  ```nim
  proc foo*(...) =
    ## Encoded (no native op): `<the exact term this expands to>`.
    ## <one-line semantics>.
    ## Sound iff <precondition>. Caveats: <ε / clamping / bound>.
  ```
- We ship the honest QF **building block** (`matchStartsAt`) as a
  first-class primitive so the encoding's soundness reasoning lives in
  one place and consumers can compose their own policy on top of a
  sound predicate rather than re-deriving it.

*(Decision, 2026-07-12, Corey: ship both the `matchStartsAt` primitive
and the `indexOfRe` convenience — see §4.1/§4.2.)*

## 3. Surface (what ships)

| symbol | kind | flag | native op |
|---|---|---|---|
| `matchStartsAt` | QF predicate (encoded from 1:1 wrappers) | none | — (composition) |
| `containsRe` | QF predicate, sound **and** complete (encoded) | none | — (composition) |
| `indexOfRe` | bounded-unroll convenience (encoded) | none | — (composition) |
| `replaceReAll` | strict 1:1 wrapper | `-d:z3WithSeqReplaceReAll` | `Z3_mk_seq_replace_re_all` |

All three land in `src/z3/regex.nim` (they bridge `Z3Seq`/`Z3Regex`
and sit beside the existing `matches` / `replaceRe`). The first two are
unconditional (they use only already-shipped ops); `replaceReAll` is
gated like its siblings.

## 4. Design

### 4.1 `matchStartsAt` — the honest QF primitive

"A match of `re` **starts at** position `i`" is quantifier-free for a
concrete-or-symbolic `i`:

```
matchStartsAt(s, re, i)
  :=  matches( substr(s, i, len(s) - i),  concat(re, mkRegexFull[Z3Seq[E]](s.ctx)) )
```

i.e. "the suffix of `s` at `i` begins with something in `re`." `concat(re,
Σ*)` is "has a prefix in `L(re)`" — mathematically `s' ∈ L(concat(A,B)) ⟺
∃ split s' = p⧺q, p∈L(A), q∈L(B)`. The `Σ*` tail is
`mkRegexFull[Z3Seq[E]]` — a shipped 1:1 wrapper over the single native op
`Z3_mk_re_full` (`regex.nim:73-78`), denoting exactly the full language
over the basis. Do **not** build it as `star(mkRegexAllChar())`: that
denotes the same language but asks Z3's automata engine to construct a
Kleene-star closure and re-simplify, where `mkRegexFull` is one direct op.
Built entirely from already-shipped 1:1 wrappers (`substr`, `len`,
`matches`, `concat`, `mkRegexFull`), returns `Z3Bool`. Pure, QF,
composable — no quantifier, no hang.

**Context threading (implementation-binding):** the internal
`mkRegexFull` call MUST be the `ctx`-explicit form
`mkRegexFull[Z3Seq[E]](s.ctx)`, never the zero-arg ambient-context
convenience. Every composite in `sequence.nim`/`regex.nim` threads
`a.ctx`/`r.ctx` explicitly; the ambient `requireCurrentContext()` path
would mix ASTs across contexts when the caller's current context differs
from `s`'s, which is undefined behaviour in Z3. The explicit generic
argument `[Z3Seq[E]]` is also required — `Basis` cannot be inferred from a
zero-arg call.

```nim
proc matchStartsAt*[E](s: Z3Seq[E], re: Z3Regex[Z3Seq[E]], i: Z3Int): Z3Bool =
  ## Encoded (no native op): `matches(substr(s, i, len(s) - i),
  ## concat(re, mkRegexFull[Z3Seq[E]](s.ctx)))`.
  ## True iff the suffix of `s` at `i` begins with something in `L(re)`.
  ## Sound and total (no bound). Caveat: for a nullable `re` it is
  ## identically `true` at every `i` (see below) — exclude ε for Nim
  ## `find` semantics.
proc matchStartsAt*[E](s: Z3Seq[E], re: Z3Regex[Z3Seq[E]], i: int): Z3Bool {.inline.}
```

Throughout these caveats, "`re` is nullable" / "`isNullable(re)`" is
mathematical shorthand for `ε ∈ L(re)`; there is no `isNullable` proc in
nim-z3, and this RFC does not add one. The concrete Nim expression a test
or caller uses to decide it is `matches(mkSeqEmpty[E](s.ctx), re)`
(does the empty sequence match `re`?).

**Caveats (doc-comment):**
- **ε-match (nullable `re` ⇒ degenerate everywhere, not just at the
  boundary):** if `re` is nullable then, as *languages*,
  `L(concat(re, Σ*)) = L(re)·Σ* = Σ*` — because `ε ∈ L(re)` gives
  `{ε}·Σ* = Σ* ⊆ L(re)·Σ* ⊆ Σ*·Σ* = Σ*`. So `matchStartsAt(s, re, i)`
  is identically `true` for **every** `i` — in range or out, regardless
  of `s`'s content — whenever `re` is nullable. This is a fact about the
  concatenation, not a `substr`-clamping artifact: the empty prefix
  `p = ε` is always a valid decomposition witness. (This "always true"
  fact is what the `indexOfRe` guard in §4.2 is built on; the
  `substr`-boundary reasoning below is only the special case that matters
  when reasoning about `indexOfRe`'s bounded-`i` domain.) Callers wanting
  Nim's non-ε `find` semantics should exclude ε (intersect against
  `complement(mkRegex(""))` or use a non-nullable `re`).
- **out-of-range `i` (non-nullable `re`):** `substr` (`seq.extract`)
  clamps out-of-range offsets/lengths to the empty sequence — by Z3's
  `seq.extract` semantics the result is empty iff `offset < 0` ∨
  `offset ≥ len(s)` ∨ `length ≤ 0`. So at `i < 0` or `i > len(s)` the
  suffix is `ε` and `matchStartsAt` equals `ε ∈ L(re)` (i.e.
  `isNullable(re)`), which for a non-nullable `re` is `false`.
  Documented, not guarded. *(This exact boundary formula is the
  load-bearing SMT-LIB `seq.extract` fact under both this caveat and the
  §4.2 guard; slice 1 pins it with a direct `substr` boundary test, not
  only the composed `matchStartsAt` tests.)*

### 4.1a `containsRe` — the sound-and-complete existence predicate

"Does a match of `re` occur *anywhere* in `s`?" needs no position, so —
unlike `indexOfRe` — it needs no bound and carries **no soundness
caveat**. It is exact:

```
containsRe(s, re)  :=  matches( s, concat( mkRegexFull[Z3Seq[E]](s.ctx),
                                           re,
                                           mkRegexFull[Z3Seq[E]](s.ctx) ) )
```

i.e. `s ∈ Σ*·L(re)·Σ*` — `s` has *some* substring in `L(re)`. Built from
the same shipped 1:1 wrappers (`matches`, `concat`, `mkRegexFull`),
returns `Z3Bool`. Sound **and** complete for any `s` (concrete or
symbolic, any length) — the property `indexOfRe` cannot offer because a
*position* answer needs unrolling but an *existence* answer does not.

```nim
proc containsRe*[E](s: Z3Seq[E], re: Z3Regex[Z3Seq[E]]): Z3Bool =
  ## Encoded (no native op): `matches(s, concat(mkRegexFull[Z3Seq[E]](s.ctx),
  ## re, mkRegexFull[Z3Seq[E]](s.ctx)))`.
  ## True iff some substring of `s` is in `L(re)`. Sound **and** complete
  ## for any `s` (no bound). Nullable `re` ⇒ trivially `true`.

proc contains*[E](s: Z3Seq[E], re: Z3Regex[Z3Seq[E]]): Z3Bool {.inline.} =
  ## `re in s` sugar — aliases `containsRe(s, re)`. Overloads the existing
  ## `sequence.contains(a, sub: Z3Seq[E])` on the second parameter's type,
  ## so `re in s` / `re notin s` work via Nim's `in`/`notin` desugaring
  ## (`x in y` ≡ `contains(y, x)`). `containsRe` stays the canonical,
  ## grep-able, documented name.
```

Useful to consumers as a cheap, complete guard: proptest can assert
`containsRe` (or its negation) before paying for a bounded `indexOfRe`
unroll. Same context-threading rule as §4.1 (thread `s.ctx` explicitly).
ε-caveat: if `re` is nullable, `containsRe` is trivially `true` (the
empty substring matches) — expected, and callers exclude ε the same way
as for `matchStartsAt`.

**Rejected alternative (stated so a future contributor doesn't "unify"
it with `indexOfRe`):** `containsRe` could have been a bounded disjunction
`⋁_{i∈[0,bound]} matchStartsAt(s, re, i)` mirroring `indexOfRe`'s shape.
Rejected: that would *lose completeness* (a real match past `bound` is
missed) for no gain, since the `Σ*·L(re)·Σ*` encoding is both sound and
complete *and* cheaper to state (no unroll). Existence needs no position,
so it needs no bound.

### 4.2 `indexOfRe` — bounded-unroll convenience

Leftmost `find` needs `∃ fi. matchStartsAt(s,re,fi) ∧ ∀ j<fi.
¬matchStartsAt(s,re,j)`. The `∀ j<fi` universal at *symbolic* length
is the G4 quantifier class Z3 diverges on — a hang we hard-forbid
shipping. So `indexOfRe` takes an explicit integer **`bound`** and
unrolls the leftmost search into a finite `ite`-chain, testing
positions in *increasing* order so leftmost-minimality falls out of
the chain order — **no quantifier**:

```
indexOfRe(s, re, start, bound)
  := ite(g(0),      0,
     ite(g(1),      1,
     ...
     ite(g(bound),  bound,
        -1)...))              where  g(i) := (mkInt(i) >= start)
                                            ∧ (mkInt(i) <= len(s))
                                            ∧ matchStartsAt(s, re, i)
```

Built by folding `i` from `bound` down to `0`. Handles a symbolic
`start` via the `i >= start` guard. Fully QF; returns `Z3Int`.

**The `i <= len(s)` conjunct is load-bearing, not cosmetic.** Without
it, `indexOfRe` can return a *wrong positive index* (not merely a `-1`
false negative), breaking its advertised contract. Concretely: with a
nullable `re` and `start > len(s)`, `matchStartsAt(s,re,i)` is `true`
for every `i ≥ len(s)` (§4.1 ε domain), so `g(i)` fires at some `i`
past the end of `s` and the term returns that out-of-content position
with full confidence — exactly the failure a "scan for next match"
loop hits when it bumps `start` past a match. The `i ≤ len(s)`
conjunct clamps every candidate to a real position, making `indexOfRe`
sound **by construction for any `start`**, at the cost of one extra
`Z3Int` comparison (`len(s)` is already materialised inside
`matchStartsAt`). Still QF, no new term class.

```nim
type MatchBound* = distinct Natural
  ## The unroll bound for `indexOfRe`. A distinct type (not bare `int`)
  ## so it cannot be confused with `start`: a transposed
  ## `indexOfRe(s, re, myBound, myStart)` fails to compile, and a
  ## negative *literal* bound is unconstructible (compile error).
proc matchBound*(n: Natural): MatchBound {.inline.} = MatchBound(n)
  ## Constructor — `indexOfRe(s, re, matchBound(64))` reads unambiguously.
  ## Spelled `matchBound` (not the generic word `bound`) to avoid
  ## shadowing under `import z3` and to stay close to the `mk*`/type-named
  ## constructor family.

proc indexOfRe*[E](s: Z3Seq[E], re: Z3Regex[Z3Seq[E]],
                   start: Z3Int, bound: MatchBound): Z3Int =
  ## Encoded (no native op): increasing-order `ite`-chain over
  ## `i ∈ [0, bound]`, `ite(g(i), i, …, -1)`, `g(i) := (i ≥ start) ∧
  ## (i ≤ len(s)) ∧ matchStartsAt(s, re, i)`.
  ## Models Nim's `re.find(s, pat)` — leftmost match *position*, or `-1`.
  ## Unconditionally sound (never a false positive); **complete iff
  ## len(s) ≤ bound** (see contract below). `O(bound)` `ite` nodes.
proc indexOfRe*[E](s: Z3Seq[E], re: Z3Regex[Z3Seq[E]],
                   start: int, bound: MatchBound): Z3Int {.inline.}
proc indexOfRe*[E](s: Z3Seq[E], re: Z3Regex[Z3Seq[E]],
                   bound: MatchBound): Z3Int {.inline.}   ## start = 0
```

**Companion — the safe path made easy.** The soundness precondition
(`len(s) ≤ bound`) is otherwise prose the caller must remember. Pair
the primitive with a one-liner so asserting the obligation is a proc,
not a memory test:

```nim
proc boundHolds*[E](s: Z3Seq[E], b: MatchBound): Z3Bool {.inline.} =
  ## The obligation `indexOfRe` needs discharged for *completeness*:
  ## `len(s) <= b`. Named as a proposition (not `require*`, which in this
  ## codebase means "raises now" — this returns an *unasserted* `Z3Bool`).
  ## Assert it yourself alongside the matching `indexOfRe` call:
  ## `solver.add s.boundHolds(b)`. **The `s` here must be the same
  ## sequence passed to `indexOfRe(s, re, b)`** — nothing type-level ties
  ## them, so asserting the bound for an unrelated sequence silently
  ## defeats the contract.
  s.len <= mkInt(s.ctx, int(Natural(b)))
```

**Correctness contract (doc-comment, load-bearing):**
- **Unconditionally sound; complete iff `len(s) ≤ bound`.** These are
  two distinct properties and the distinction is load-bearing (the RFC
  uses "sound" and "complete" precisely — cf. §4.1a). *Soundness* (never
  a wrong positive index) holds for **any** `bound`, because the round-1
  `i ≤ len(s)` guard clamps every candidate to a real position.
  *Completeness* (never a spurious `-1`) is what needs `len(s) ≤ bound`:
  if the actual string is longer than `bound`, a match at a position
  `> bound` is missed and the term yields `-1` — the *only* remaining
  failure mode, and it is a false negative, never a false positive. The
  caller MUST constrain `len(s) ≤ bound` (or pass a `bound` ≥ the model's
  max length) to get completeness. This is the bound-vs-degrade seam:
  **proptest** decides whether to assert the bound (sound + complete, QF)
  or degrade to `sxUnknown` at symbolic length — nim-z3 ships the always-
  sound primitive and the honest completeness precondition.
- **`start` range is unrestricted** — the `i ≤ len(s)` guard makes any
  `start` sound. `start < 0` behaves as `start = 0` (the `i ≥ start`
  conjunct is then vacuous at `i = 0`). `start > len(s)` yields `-1`
  (no position `≤ len(s)` is also `≥ start`), which is the correct
  answer, not the pre-fix spurious hit.
- **ε ⇒ `max(0, start)` *only when* `max(0, start) ≤ min(len(s),
  bound)`.** For nullable `re`, the leftmost sound position is
  `max(0, start)` — but only if it is reachable: if `start > bound` or
  `start > len(s)`, no `g(i)` fires and the term is `-1`.
- **Negative bounds: compile error for literals, `RangeDefect` for
  computed values.** `MatchBound = distinct Natural` rejects a negative
  *literal* at compile time (`matchBound(-1)` fails to compile via Nim's
  constant-folded range check). A bound computed at runtime — e.g.
  `matchBound(someInt)` — instead gets `Natural`'s automatic range check,
  raising `RangeDefect` on a negative value (and, under `-d:danger`,
  that check is elided — a perf-build caveat worth knowing, since
  solvers are a perf-sensitive context). So this is an ergonomics/DRY
  win over the hand-written `loop`/`power` `doAssert` style (the check is
  auto-inserted, not a universal *compile-time* guarantee): fully static
  for the literal `matchBound(n)` form every example here uses, runtime-
  checked for computed values.
- **Why `bound` is `MatchBound`, not `Z3Int`** (breaking the codebase's
  usual `int`/`Z3Int` pairing convention, deliberately): `bound` drives
  the *unroll count* — the number of `ite` nodes emitted at
  term-construction time — so it must be a construction-time Nim value,
  not a symbolic `Z3Int`. Stated so a future contributor doesn't "fix"
  the asymmetry by adding a `Z3Int` overload.
- Term size is `O(bound)` `ite` nodes each wrapping a `matchStartsAt`
  membership — cost grows linearly in `bound`. Documented so callers
  size `bound` deliberately. Implementation note: hoist the
  loop-invariant `concat(re, mkRegexFull[Z3Seq[E]](s.ctx))` subterm
  once (a private `matchStartsAtWith(s, matchRe, i)` helper) rather than
  rebuilding it per `i` — saves `O(bound)` redundant FFI round-trips.
- **Rejected alternative — balanced `ite` tree.** The chain is built in
  increasing linear order so leftmost-minimality falls out of the order
  (§4.2 opening). A balanced-tree disjunction shape would keep term
  *size* `O(bound)` (same `matchStartsAt` leaf count) while dropping
  *depth* from `O(bound)` to `O(log bound)`. Rejected for this RFC:
  marginal depth win, real construction complexity, and leftmost-order
  is trivial to reason about; revisit only if `bound ≫ 200` becomes a
  real workload.

### 4.3 `replaceReAll` — 1:1 gated wrapper

```nim
when defined(z3WithSeqReplaceReAll):
  proc replaceReAll*[E](a: Z3Seq[E], pattern: Z3Regex[Z3Seq[E]],
                        replacement: Z3Seq[E]): Z3Seq[E]
    ## SMT `(seq.replace_re_all a pattern replacement)`. Replaces every
    ## non-overlapping match of `pattern`. Requires
    ## `-d:z3WithSeqReplaceReAll`; `Z3_mk_seq_replace_re_all` is absent
    ## from Z3 builds before ~4.15.5 (package-dependent).
```

FFI declaration mirrors the existing `z3WithSeqReplaceRe` gate in
`ffi.nim:3115`. Purely additive. The C signature is confirmed
`Z3_ast Z3_mk_seq_replace_re_all(Z3_context c, Z3_ast s, Z3_ast re,
Z3_ast dst)` — identical `(c, s, re, dst)` arg order to the already-
wrapped `Z3_mk_seq_replace_re`. Confirmed **absent** in Z3 4.15.0 and
the repo's `_audit_headers/z3_api.h`; **present** from ~4.15.8/4.16.0,
corroborating the ~4.15.5 claim.

## 5. Docs / housekeeping

- **Doc-rot fix #1:** `IMPLEMENTATION_PLAN.md:26-27` claims N5.7 landed
  `replace_all` / `replace_re` / `split_re` as DONE in v2.0; in fact
  all are `-d`-gated and `replace_re_all` / `split_re` are not in
  `ffi.nim`. Correct the claim (state they are gated, and that
  `replace_re_all` lands here in v2.2).
- **Doc-rot fix #2:** `IMPLEMENTATION_PLAN.md`'s "What lands next
  (v2.1.0 target)" section still describes v2.1.0 as *forthcoming*, but
  v2.1.0 has already shipped (`CHANGELOG.md` has a full `[2.1.0]`;
  latest commit `8076500` is the v2.1.0 feature). Slice 4 must close
  v2.1.0 out (mark DONE / summarise what shipped) **before** layering
  v2.2.0 framing on top — otherwise the plan doc carries two rot spots.
- **GOTCHAS.md #19 cross-ref:** gotcha #19 currently promises the v1.x
  release will surface `replaceAll` / `replaceRegex` / `splitRegex` as
  *first-class* wrappers. That is stale (they are `-d`-gated, and
  `splitRegex` never shipped and isn't planned). Slice 4 corrects this
  cross-reference too.
- **New GOTCHAS entry — the `indexOfRe` completeness trap:** calling
  `indexOfRe(s, re, matchBound(N))` *without* also asserting
  `s.boundHolds(matchBound(N))` is a **silent** under-covering — no compile
  error, no runtime error, just false `-1`s for any model where
  `len(s) > N`. This is exactly the Symptom/Cause/Wrapper-behaviour/
  What-you-should-do shape GOTCHAS.md catalogs, and is materially higher-
  severity than #19's stale-doc note. Slice 4 adds it as the next
  numbered entry (e.g. #21), cross-referencing `boundHolds`.
- **`regex.nim` module docstring (slice 1):** the file header (currently
  just the decidability caveat) says nothing about the fact that some
  procs below are *encoded compositions*, not 1:1 native-op wrappers — the
  architecturally-significant first this RFC introduces (§2). Slice 1 adds
  a short "## Encoded helpers" paragraph to the module docstring pointing
  at the `## Encoded (no native op):` marker convention, so a reader
  scanning top-down (not just per-proc) discovers the distinction. (PARITY.md
  and INTERNAL_API.md need **no** change — `MatchBound` is a plain
  `distinct Natural` with no `.raw`/`.ctx`, so it is not a `Z3Term` value
  family and no new cross-module private seam is promoted.)
- **Build-flag matrix:** one consolidated table of the **three** seq/
  regex `-d` flags (`z3WithSeqReplaceAll`, `…ReplaceRe`, `…ReplaceReAll`
  — there is no fourth; `split_re` is unwrapped and out of scope, §7)
  with the native op each needs and the min Z3 version. Lands in
  **`MINIMAL_BUILD.md`** (already the systematic build-flag reference,
  with a gate-flag combination table and the `z3Without*` semantics),
  with a one-line cross-reference added from `GOTCHAS.md` #19 — not the
  reverse.
- **CI caveat (state in the flag-matrix section):** the CI matrix pins
  Z3 4.10.2–4.13.4, none of which carry any of the three gated ops, so
  `-d:z3WithSeqReplaceReAll` and its new test suite — like its existing
  `ReplaceAll`/`ReplaceRe` siblings — are **not** exercised by CI today;
  they compile-run only when a contributor builds against a capable Z3
  (≥ ~4.15.8). Pre-existing gap; slice 3 inherits it and must not imply
  the gated test adds live CI coverage.
- **Version decision (resolved, not deferred):** bump `nim-z3.nimble`
  straight `2.0.0` → `2.2.0`. The nimble field is treated as "current
  version"; `CHANGELOG.md` is the historical record of what shipped at
  each tag (the v2.1.0 nimble bump was skipped — this bump reconciles
  it). Add CHANGELOG `[2.2.0]`.

**Implementation prerequisite (both slices 1 & 2):** `regex.nim`
currently imports only `ffi, context, error, ast, sortdispatch, chars,
sequence, strings` — none re-export `mkInt` (`builder`), `ite`
(`boolean`), or Z3Int `-`/`>=`/`<=` (`arith`) that the encodings need.
Add `import ./builder, ./boolean, ./arith` to `regex.nim` **first**
(verified no import cycle: those three depend only on
ffi/context/error/sort/ast/lifecycle, none of which import `regex.nim`).
Otherwise slice 1's first compile fails with "undeclared identifier".

1. **`matchStartsAt` + `containsRe`** — both predicates + the
   `matchStartsAt` `int` overload + the `contains(s, re)` `in`-sugar
   overload in `regex.nim`, plus the "## Encoded helpers" module-docstring
   paragraph (§5); tests in a new `tregex_index.nim`: `matchStartsAt`
   concrete leftmost-vs-not positions, no-match, **ε-match at *every*
   position** (nullable `re` ⇒ identically `true`, not just at the
   boundary — §4.1), out-of-range `i` (`i > len(s)` with a *non-nullable*
   `re` ⇒ `false`; the nullability side expressed concretely as
   `matches(mkSeqEmpty[E](ctx), re)`, since there is no `isNullable`
   proc); `containsRe` present / absent / substring-not-prefix (a match
   not at position 0, proving it differs from `matchStartsAt(·,·,0)`) /
   ε ⇒ trivially true; **a `re in s` / `re notin s` sugar test** (the new
   `contains` overload resolves and agrees with `containsRe`); **and a
   non-`Char` basis case** (`Z3Seq[Z3Int]`, mirroring `tregex.nim`'s
   existing "non-string basis" suite) for each, to lock in the
   `[E]`-genericity. A `containsRe` **completeness** test over a
   *symbolic* `s` (free `mkStringVar`, `checkSat`) — the property
   `indexOfRe` can't match. **Plus one direct `substr` boundary test**
   (`tsequence.nim` or `tregex_index.nim`) pinning the load-bearing
   `seq.extract` formula against live Z3 — `offset == len(s)` with
   positive length ⇒ empty; negative length (in-range offset) ⇒ empty —
   since no existing test asserts it and both this slice and the §4.2
   guard rest on it. Unconditional (no flag). *No deps.*
2. **`indexOfRe`** — bounded `ite`-chain encoding (with the `i ≤ len(s)`
   guard, §4.2) + overloads; tests: leftmost among multiple matches,
   `start` offset skips earlier match, `-1` when only match is beyond
   `bound`, symbolic `start`, ε ⇒ `max(0,start)` (and ε with
   `start > bound` ⇒ `-1`), soundness under asserted `len(s) ≤ bound`
   (via the `boundHolds` companion), a **`MatchBound` misuse check**
   (a transposed `(bound, start)` call and a negative bound both fail
   to compile — a `reject`/`compiles()` test), and the **regression test
   for the critical bug: nullable `re` with `start > len(s)` ⇒ `-1`,
   never a spurious positive index**. At least one test must exercise
   the *symbolic* path the primitive exists for — free `mkStringVar` +
   `mkIntVar`, assert a constraint, `checkSat`, and **read the returned
   index back from the model** (a pure ground `smtValid` suite would
   pass even against a subtly-wrong-under-free-`i` encoding). Add one
   large-`bound` case (e.g. 200) confirming the term stays linear and
   the solver returns promptly. Also: a **`matchBound(0)` single-position
   case** (the chain degenerates to `ite(g(0), 0, -1)` — catches a fold
   base-case off-by-one that only shows at the smallest unroll); a
   **`boundHolds` standalone + boundary test** (`smtValid(s.boundHolds(
   matchBound(N)))` at `len(s) == N` exactly, and its negation satisfiable at
   `len(s) == N+1` — pins `≤` vs `<` in the one-line body); a
   **hoisting cross-consistency test** (for concrete `s`/`re`/small
   `bound`, `indexOfRe(s, re, 0, bound) == i₀` iff `matchStartsAt(s, re,
   i₀)` and `¬matchStartsAt(s, re, j)` for all `j < i₀` — closes the gap
   between the private hoisted `matchStartsAtWith` path and the public
   `matchStartsAt` without exporting the helper); and a **cross-primitive
   consistency test** (under `len(s) ≤ bound`: `indexOfRe ≥ 0 ⇒
   containsRe`; and `¬containsRe ⇒ indexOfRe == -1` for any bound —
   catches a basis-sort mismatch between the two shared encodings).
   *Depends on slice 1.*
3. **`replaceReAll`** — FFI decl behind `-d:z3WithSeqReplaceReAll`
   (`ffi.nim`) + gated wrapper (`regex.nim`) + gated tests in
   `tseq_replace.nim` (every-occurrence replace, no-op when pattern
   absent). *Independent of 1/2.* **Run note:** the default
   `nim-z3-test:latest` image bakes Z3 4.13.4, which lacks
   `Z3_mk_seq_replace_re_all` — the gated test compiles but can only be
   run green against libz3 ≥ ~4.15.8. Reuse the split-mount technique
   (compile vs. old headers, run vs. newer `libz3.so` via
   `LD_LIBRARY_PATH`) documented in
   `docs/RFC-fixedpoint-callbacks.handoff.md`; newer tarballs already
   cached under `~/.cache/nim-z3-test/z3-latest`.
4. **Docs + version** — build-flag matrix (`MINIMAL_BUILD.md`),
   `IMPLEMENTATION_PLAN` doc-rot fixes #1 & #2, GOTCHAS #19 cross-ref,
   CHANGELOG `[2.2.0]`, nimble version bump `2.0.0` → `2.2.0`. *Docs
   only; do last.*

## 6. Multi-version Z3 compat (folded in, 2026-07-17)

**Goal.** nim-z3 loads and runs cleanly against **Z3 4.15 and 4.16**
(and, via the compat manifest, degrades honestly across the 4.10+ range
it advertises), using softlink v0.8.0's version-compat machinery. This
is orthogonal to the regex surface but shares the release; it also
unblocks slice-3's green *run* (needs a runtime lib that carries
`Z3_mk_seq_replace_re_all`).

### 6.1 Drift audit (subagent-verified, 2026-07-17)

Of the **676** Z3 symbols `ffi.nim` declares, only **5** drift across
4.15.0 → 4.16.0:

| symbol | drift | disposition |
|---|---|---|
| `Z3_mk_seq_replace_all` / `_re` / `_re_all` | **added** in 4.16 | ✅ already `{.optional, prototype.}` (slice 3) |
| `Z3_mk_set_has_size` | **removed** in 4.16 (declared plain/required) | `{.optional.}` → absence ⇒ `lrOkPartial` (context.nim already tolerates), classified `mrExpected` via manifest |
| `Z3_fpa_get_numeral_sign` | param **`int*` → `bool*`** | **drift-refusal** (resolved below) |

So "clean multi-version support" = **2 symbol fixes + version-compat
plumbing**, not a broad rewrite.

### 6.2 Resolved: `Z3_fpa_get_numeral_sign` drift → accept drift-refusal

The one genuinely-tricky symbol: its out-param changed width
(`int*`→`bool*`). Options were (a) **accept softlink's drift-refusal** —
`loadZ3()` refuses to bind the ABI-drifted symbol on whichever version
it drifted from, reports `mrDriftRefused`, and the fn is simply
unavailable there; (b) **dual-ABI** — declare the superset `ptr cint`,
read the low byte, suppress refusal via `-d:softlinkNoDriftRefusal`.

**Decision (2026-07-17): (a) accept drift-refusal.** It is
memory-safe and honest by construction, and `Z3_fpa_get_numeral_sign`
is a rarely-used FP-sign-introspection call. Dual-ABI reintroduces
exactly the silent-corruption trust hole softlink's drift-refusal was
built to close, for a fn no consumer has asked for on both versions. If
that changes, dual-ABI is a clean future follow-up (no API break).

### 6.3 Slices (appended to the grind)

- **Slice 4 — load against 4.16.** `{.optional, prototype.}` on
  `Z3_mk_set_has_size` (prototype so it also compiles against 4.16
  headers, which lack it — same pattern as the seq_replace family). This
  is the *only* required-symbol-missing blocker to loading against 4.16.
  Test: full `loadZ3()` succeeds against the **4.16.0** runtime lib
  (`lrOkPartial`) *and* the **4.15.0** lib, via the split-mount harness.
  Unblocks slice-3's run. **Note:** `Z3_fpa_get_numeral_sign` still
  binds *by name* on 4.16 with its drifted ABI here — softlink can't
  detect that drift until the version probe (slice 5) + manifest
  (slice 6) exist, so its safe **drift-refusal** lands in slice 6, not
  here. Sequenced gap, not an oversight.
- **Slice 5 — version probe.** Ensure `Z3_get_full_version` /
  `Z3_get_version` are wrapped; add a `versionProbe` so softlink knows
  the runtime version; expose it (thin `z3Version()` accessor). Test:
  reads `4.15.*` vs `4.16.*` correctly against both libs.
- **Slice 6 — compat manifest.** Run `softlink_harvest` over a Z3
  header corpus (4.10 … 4.16) → commit `z3.compat.json`; attach via
  `compatManifest "z3.compat.json"`. Test: `z3Compat()` report is
  well-formed and classifies `set_has_size`/fpa/`seq_replace*` with the
  expected `Attestation`/`MissingReason`. **Infra note:** fetching the
  4.10–4.14 headers is the main new work; `softlink_harvest` needs
  Nim ≥ 2.2.8.
- **Slice 7 — docs** (was slice 4). Flag matrix → `MINIMAL_BUILD.md`;
  new `MULTI_VERSION.md` (supported range + degrade table from the
  manifest); doc-rot fixes; GOTCHAS #19 + #21; CHANGELOG `[2.2.0]`;
  nimble `2.0.0 → 2.2.0`.

## 7. Non-goals

- **No `replaceRe` / `replaceReAll`** (`str.replace_re{,_all}`) — descoped
  during implementation (see the Descope note at the top). Z3's solver returns
  `unknown` on these for concrete inputs, so a wrapper is un-testable/un-usable
  via the solver; deferred pending upstream Z3. §4.3 is superseded.
- No `∀`-quantified symbolic-length `find` (hang-forbidden). Symbolic
  length is the consumer's degrade-to-`sxUnknown` decision.
- No `split_re` wrapper (separate gap; out of scope for #2).
- **No `lastIndexOfRe`** (the regex analog of `sequence.lastIndexOf`)
  and **no `matchEndsAt`** (the mirror of `matchStartsAt`). Both are
  natural siblings but neither is needed by consumer B1
  (`find`/`replace`/`replaceAll`); excluded deliberately, not by
  oversight. If a consumer needs them later, they follow the same
  encoded-helper pattern established here.
- **No public hoisted/batch position-tester.** `matchStartsAtWith` (§4.2)
  — the `concat(re, Σ*)`-hoisting helper — stays **private**. A consumer
  wanting a *different* unrolling policy than `indexOfRe`'s leftmost chain
  (all match positions, incremental bound-raising, …) would otherwise
  either re-derive the hoisting or eat the `O(bound)` redundant-FFI cost
  `indexOfRe` avoids. Excluded here as YAGNI for B1; if exposed later it
  should be a batch API (`positions: openArray[int] → seq[Z3Bool]`), not
  raw `matchStartsAtWith`, so the `matchRe == concat(re, Σ*)` invariant
  stays nim-z3-internal rather than becoming consumer-visible encoding
  knowledge (§2 says nim-z3 owns that).
- If/when Z3 exposes a native regex-index op, wrap it 1:1 and have
  `indexOfRe` prefer it — a future minor, not this RFC.

## 8. References

- Issue #2 (this repo).
- proptest RFC: `docs/symex/RFC-phase16-language-fragments.md` §B1.
  **Open cross-check with proptest (non-blocking):** B1's stub lists the
  first-occurrence `replaceRe` as "already wrapped," but Nim's
  `std/re.replace(s, pat, by)` replaces **all** matches by default (there
  is no first-occurrence-only variant in `std/re`). So B1 may need *only*
  `replaceReAll`, and the gated `replaceRe` may be inventory bookkeeping,
  not a live call site. This RFC ships `replaceReAll` either way (it is
  the genuinely-missing op), so this doesn't gate the RFC — but confirm
  with proptest whether `replaceRe` is load-bearing for B1 before relying
  on it there.
- nim-z3: `src/z3/regex.nim` (`matches`/`concat`/`star`/`replaceRe`),
  `src/z3/sequence.nim` (`substr`/`len`/`indexOf`/`contains`), `src/z3/ffi.nim`
  (gated FFI pattern at `3105-3118`).

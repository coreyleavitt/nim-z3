## `z3/regex` — SMT-LIB regular expressions.
##
## A `Z3Regex[Basis]` is a regular language over the basis sequence
## sort. `Basis` is any sequence-shaped Z3 type with a `sortOf`
## overload — both `Z3String` (= `Z3Seq[Z3Char]`) and arbitrary
## `Z3Seq[E]` qualify, since `regexSort[Basis]` routes through
## `sortOfType[Basis]`.
##
## ## Decidability caveat
##
## Regex membership (`matches`) plus string equality is decidable for
## the regular fragment but **may run for a long time** in adversarial
## cases (large counted repetitions, intersections that produce
## exponential DFAs). Treat `zsUnknown` as a possible solver outcome.
##
## ## Encoded helpers
##
## Most procs here are strict 1:1 wrappers over a single native Z3 op
## (doc-string `## SMT (<op> ...)`). A few — `matchStartsAt`,
## `containsRe` — have **no native op**: they are terms built from
## other 1:1 wrappers, carrying their own soundness/completeness
## contract rather than delegating semantics to Z3. Their doc-strings
## lead with the `## Encoded (no native op): <term>.` marker instead,
## so the two styles stay grep-distinguishable.
##
## ## `find`-style queries: prefer `indexOfReChecked`
##
## `indexOfRe` (leftmost-match position, or `-1`) is sound for any
## `bound` but *complete* only if the searched sequence's length is
## bounded — a caller-side obligation (`boundHolds`) that nothing
## type-level ties to the `indexOfRe` call it protects. Asserting the
## bound for the wrong sequence silently defeats the contract (see
## GOTCHAS #24). `indexOfReChecked` bundles the two into one result
## built from a single `s`, closing that gap — reach for it first;
## `indexOfRe` + `boundHolds` remain available for advanced composition
## (deferred or disjunctive assertion of the bound).

import ./ffi, ./context, ./error, ./ast, ./sortdispatch, ./chars, ./sequence, ./strings,
       ./builder, ./boolean, ./arith
export chars

# ============================================================================
# Z3Regex[Basis] — phantom-typed value family
# ============================================================================

type
  Z3Regex*[Basis] = object
    ## Regular language over `Basis`. `Basis` is any sequence-shaped
    ## Z3 type: `Z3String`, or any `Z3Seq[E]`.
    raw*: RawZ3Ast
    ctx*: Z3Context

proc `=destroy`[Basis](r: Z3Regex[Basis]) {.raises: [].} =
  termDestroy(r, Z3_dec_ref)
proc `=copy`[Basis](dst: var Z3Regex[Basis], src: Z3Regex[Basis]) {.raises: [].} =
  termCopy(dst, src, Z3_dec_ref, Z3_inc_ref)
proc `=dup`[Basis](src: Z3Regex[Basis]): Z3Regex[Basis] {.raises: [].} =
  termDup(result, src, Z3_inc_ref)

# ============================================================================
# Basis-sort dispatch
# ============================================================================
#
# Delegates to `sortOfType[Basis]` — works for `Z3Seq[E]` (which
# subsumes `Z3String = Z3Seq[Z3Char]` via alias). v0.3 step 9 routed
# through the central `z3/sortdispatch` mechanism.

proc basisSort[Basis](ctx: Z3Context): RawZ3Sort =
  when Basis is Z3Seq:
    sortOfType[Basis](ctx)
  else:
    {.error: "Z3Regex basis: must be a Z3Seq[E] (= Z3String for E = Z3Char). " &
             "Got an unsupported basis type.".}

# ============================================================================
# Constructors
# ============================================================================

proc mkRegex*[E](ctx: Z3Context, s: Z3Seq[E]): Z3Regex[Z3Seq[E]] =
  ## Singleton regex matching exactly the sequence `s`. SMT
  ## `(seq.to.re s)`. For `Z3String` (= `Z3Seq[Z3Char]`) this matches
  ## the singleton string language; for any `Z3Seq[E]` it matches the
  ## singleton sequence language over the element sort.
  wrap[Z3Regex[Z3Seq[E]]](ctx,
    ctx.checkErr Z3_mk_seq_to_re(ctx.raw, s.raw))
proc mkRegex*[E](s: Z3Seq[E]): Z3Regex[Z3Seq[E]] =
  mkRegex(s.ctx, s)

proc mkRegexEmpty*[Basis](ctx: Z3Context): Z3Regex[Basis] =
  ## Regex matching nothing (`re.none`). The empty language.
  let sort = ctx.checkErr Z3_mk_re_sort(ctx.raw, basisSort[Basis](ctx))
  wrap[Z3Regex[Basis]](ctx, ctx.checkErr Z3_mk_re_empty(ctx.raw, sort))
proc mkRegexEmpty*[Basis](): Z3Regex[Basis] =
  mkRegexEmpty[Basis](requireCurrentContext())

proc mkRegexFull*[Basis](ctx: Z3Context): Z3Regex[Basis] =
  ## Regex matching every sequence over the basis (`re.all`).
  let sort = ctx.checkErr Z3_mk_re_sort(ctx.raw, basisSort[Basis](ctx))
  wrap[Z3Regex[Basis]](ctx, ctx.checkErr Z3_mk_re_full(ctx.raw, sort))
proc mkRegexFull*[Basis](): Z3Regex[Basis] =
  mkRegexFull[Basis](requireCurrentContext())

proc mkRegexAllChar*[Basis](ctx: Z3Context): Z3Regex[Basis] =
  ## Regex matching any single basis element (`re.allchar`). For
  ## strings, that's any single codepoint. Named `mkRegexAllChar` to
  ## distinguish from `mkRegexFull` (which matches every sequence).
  let sort = ctx.checkErr Z3_mk_re_sort(ctx.raw, basisSort[Basis](ctx))
  wrap[Z3Regex[Basis]](ctx, ctx.checkErr Z3_mk_re_allchar(ctx.raw, sort))
proc mkRegexAllChar*[Basis](): Z3Regex[Basis] =
  mkRegexAllChar[Basis](requireCurrentContext())

# ============================================================================
# Membership
# ============================================================================

proc matches*[Basis](s: Basis, r: Z3Regex[Basis]): Z3Bool =
  ## SMT `(seq.in.re s r)`. True iff `s` is in the language of `r`.
  wrap[Z3Bool](s.ctx, s.ctx.checkErr Z3_mk_seq_in_re(s.ctx.raw, s.raw, r.raw))

# ============================================================================
# Unary combinators
# ============================================================================

proc star*[Basis](r: Z3Regex[Basis]): Z3Regex[Basis] =
  ## `r*` — zero or more repetitions.
  wrap[Z3Regex[Basis]](r.ctx, r.ctx.checkErr Z3_mk_re_star(r.ctx.raw, r.raw))

proc plus*[Basis](r: Z3Regex[Basis]): Z3Regex[Basis] =
  ## `r+` — one or more repetitions.
  wrap[Z3Regex[Basis]](r.ctx, r.ctx.checkErr Z3_mk_re_plus(r.ctx.raw, r.raw))

proc option*[Basis](r: Z3Regex[Basis]): Z3Regex[Basis] =
  ## `r?` — zero or one occurrence.
  wrap[Z3Regex[Basis]](r.ctx, r.ctx.checkErr Z3_mk_re_option(r.ctx.raw, r.raw))

proc complement*[Basis](r: Z3Regex[Basis]): Z3Regex[Basis] =
  ## `re.comp r` — the complement language (every sequence NOT in r).
  wrap[Z3Regex[Basis]](r.ctx, r.ctx.checkErr Z3_mk_re_complement(r.ctx.raw, r.raw))

# ============================================================================
# N-ary combinators
# ============================================================================
#
# Z3's `re_concat`, `re_union`, `re_intersect` are varargs at the C
# level — we expose them as varargs at the Nim level too.

# `Z3Regex[Basis]` carries a phantom basis-sort parameter — its varargs
# bodies match the "≥1 required, singleton short-circuit" shape from
# `lifecycle.emitVarargsRequired1`. We instantiate the template once
# per FFI symbol; the per-`Basis` generic falls out of the family type
# in the template body.

emitVarargsRequired1Basis(concat,    Z3Regex[Basis], Z3_mk_re_concat)
emitVarargsRequired1Basis(union,     Z3Regex[Basis], Z3_mk_re_union)
emitVarargsRequired1Basis(intersect, Z3Regex[Basis], Z3_mk_re_intersect)

# ============================================================================
# Counted repetition + ranges
# ============================================================================

proc loop*[Basis](r: Z3Regex[Basis], lo, hi: int): Z3Regex[Basis] =
  ## `r{lo,hi}` — between `lo` and `hi` (inclusive) repetitions.
  doAssert lo >= 0 and hi >= lo,
    "Z3Regex.loop: require 0 <= lo <= hi"
  wrap[Z3Regex[Basis]](r.ctx,
    r.ctx.checkErr Z3_mk_re_loop(r.ctx.raw, r.raw, cuint(lo), cuint(hi)))

proc power*[Basis](r: Z3Regex[Basis], n: int): Z3Regex[Basis] =
  ## `r^n` — exactly `n` repetitions.
  doAssert n >= 0, "Z3Regex.power: require n >= 0"
  wrap[Z3Regex[Basis]](r.ctx,
    r.ctx.checkErr Z3_mk_re_power(r.ctx.raw, r.raw, cuint(n)))

proc range*(lo, hi: Z3String): Z3Regex[Z3String] =
  ## Char-range regex `[lo-hi]`. SMT `(re.range lo hi)`. Z3 requires
  ## `lo` and `hi` to be single-codepoint `Z3String` values — the
  ## endpoints of the codepoint range.
  ##
  ## **Why string-typed and not `Z3Char`-typed**: SMT-LIB-2.6 declares
  ## `re.range` as `(String String) RegEx String`, and Z3's polymorphic
  ## sort-checker enforces that contract — passing `Z3Char` operands
  ## raises a sort mismatch at solver time. The string values must
  ## additionally be built via `Z3_mk_lstring` (the
  ## length-prefixed form used by our `mkString`); the legacy
  ## `Z3_mk_string` path trips a separate internal assertion in
  ## 4.13.x.
  wrap[Z3Regex[Z3String]](lo.ctx,
    lo.ctx.checkErr Z3_mk_re_range(lo.ctx.raw, lo.raw, hi.raw))

proc range*(ctx: Z3Context, lo, hi: string): Z3Regex[Z3String] =
  ## Ergonomic overload — lifts one-character Nim strings to single-
  ## codepoint `Z3String` values. Both endpoints must be exactly one
  ## ASCII codepoint (`"a"`, `"z"`). For multi-byte codepoints, build
  ## the endpoints with `mkString` and call the `Z3String`-typed
  ## overload above.
  doAssert lo.len == 1 and hi.len == 1,
    "Z3Regex.range(string, string): both endpoints must be one ASCII codepoint"
  range(mkString(ctx, lo), mkString(ctx, hi))

proc range*(lo, hi: string): Z3Regex[Z3String] =
  range(requireCurrentContext(), lo, hi)

# Pretty-print (v0.5 step 3D)

proc `$`*[Basis](r: Z3Regex[Basis]): string = termToSmt2(r)
  ## SMT-LIB rendering of the regex AST.

# ============================================================================
# Cross-theory: regex-based sequence replacement (N5.4)
# ============================================================================
#
# Lives here (regex.nim) rather than sequence.nim because `Z3Regex[Basis]`
# is defined here; sequence.nim is lower in the import DAG and cannot
# import regex.nim without creating a cycle.

# ============================================================================
# Encoded (non-1:1) helpers — regex position/existence predicates
# ============================================================================
#
# RFC-regex-index.md §2: nim-z3's first *encoded* operations — terms
# built from other 1:1 wrappers, carrying their own soundness contract
# rather than delegating semantics to a single native Z3 op. Their
# doc-strings lead with `## Encoded (no native op): <term>.` rather
# than the `## SMT (<op> ...)` form used everywhere else in this file,
# so the two styles stay grep-distinguishable.

proc matchStartsAtWith[E](s: Z3Seq[E], matchRe: Z3Regex[Z3Seq[E]], i: Z3Int): Z3Bool =
  ## Private hoisting helper for `indexOfRe` (not exported — RFC §7 non-
  ## goals). Callers pass a pre-built `matchRe = concat(re,
  ## mkRegexFull[Z3Seq[E]](s.ctx))` computed ONCE and reused across every
  ## `i` in the unroll, instead of rebuilding that loop-invariant `concat`
  ## subterm (and paying its FFI cost) at each of the `O(bound)` positions.
  ## Otherwise identical to `matchStartsAt`: `matches(substr(s, i, len(s) -
  ## i), matchRe)`.
  matches(substr(s, i, s.len - i), matchRe)

proc matchStartsAt*[E](s: Z3Seq[E], re: Z3Regex[Z3Seq[E]], i: Z3Int): Z3Bool =
  ## Encoded (no native op): `matches(substr(s, i, len(s) - i),
  ## concat(re, mkRegexFull[Z3Seq[E]](s.ctx)))`.
  ## True iff the suffix of `s` at `i` begins with something in `L(re)`.
  ## Sound and total (no bound). Caveat: for a nullable `re` it is
  ## identically `true` at every `i` (see below) — exclude ε for Nim
  ## `find` semantics.
  matchStartsAtWith(s, concat(re, mkRegexFull[Z3Seq[E]](s.ctx)), i)

proc matchStartsAt*[E](s: Z3Seq[E], re: Z3Regex[Z3Seq[E]], i: int): Z3Bool {.inline.} =
  ## `int` overload — lifts `i` via `mkInt` then delegates.
  matchStartsAt(s, re, mkInt(s.ctx, i))

proc containsRe*[E](s: Z3Seq[E], re: Z3Regex[Z3Seq[E]]): Z3Bool =
  ## Encoded (no native op): `matches(s, concat(mkRegexFull[Z3Seq[E]](s.ctx),
  ## re, mkRegexFull[Z3Seq[E]](s.ctx)))`.
  ## True iff some substring of `s` is in `L(re)`. Sound **and** complete
  ## for any `s` (no bound). Nullable `re` ⇒ trivially `true`.
  matches(s, concat(mkRegexFull[Z3Seq[E]](s.ctx), re, mkRegexFull[Z3Seq[E]](s.ctx)))

proc contains*[E](s: Z3Seq[E], re: Z3Regex[Z3Seq[E]]): Z3Bool {.inline.} =
  ## `re in s` sugar — aliases `containsRe(s, re)`. Overloads the existing
  ## `sequence.contains(a, sub: Z3Seq[E])` on the second parameter's type,
  ## so `re in s` / `re notin s` work via Nim's `in`/`notin` desugaring
  ## (`x in y` ≡ `contains(y, x)`). `containsRe` stays the canonical,
  ## grep-able, documented name.
  containsRe(s, re)

# ============================================================================
# indexOfRe — bounded-unroll `find` convenience (RFC-regex-index.md §4.2)
# ============================================================================

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
  ##
  ## Low-level primitive: the caller must separately discharge
  ## completeness with `s.boundHolds(bound)` on the SAME `s`, and
  ## nothing type-level enforces that. **Prefer `indexOfReChecked`**,
  ## which bundles both from a single `s`; reach for this one only for
  ## advanced composition (e.g. deferring or disjoining the bound
  ## obligation separately from the index term).
  let matchRe = concat(re, mkRegexFull[Z3Seq[E]](s.ctx))
  result = mkInt(s.ctx, -1)
  for i in countdown(int(Natural(bound)), 0):
    let ii = mkInt(s.ctx, i)
    let g = (ii >= start) and (ii <= s.len) and matchStartsAtWith(s, matchRe, ii)
    result = ite(g, ii, result)

proc indexOfRe*[E](s: Z3Seq[E], re: Z3Regex[Z3Seq[E]],
                   start: int, bound: MatchBound): Z3Int {.inline.} =
  ## `int` overload — lifts `start` via `mkInt` then delegates.
  indexOfRe(s, re, mkInt(s.ctx, start), bound)

proc indexOfRe*[E](s: Z3Seq[E], re: Z3Regex[Z3Seq[E]],
                   bound: MatchBound): Z3Int {.inline.} =
  ## `start = 0` convenience overload.
  indexOfRe(s, re, mkInt(s.ctx, 0), bound)

proc boundHolds*[E](s: Z3Seq[E], b: MatchBound): Z3Bool {.inline.} =
  ## The obligation `indexOfRe` needs discharged for *completeness*:
  ## `len(s) <= b`. Named as a proposition (not `require*`, which in this
  ## codebase means "raises now" — this returns an *unasserted* `Z3Bool`).
  ## Assert it yourself alongside the matching `indexOfRe` call:
  ## `solver.add s.boundHolds(b)`. **The `s` here must be the same
  ## sequence passed to `indexOfRe(s, re, b)`** — nothing type-level ties
  ## them, so asserting the bound for an unrelated sequence silently
  ## defeats the contract.
  ##
  ## Low-level primitive, paired with `indexOfRe`. **Prefer
  ## `indexOfReChecked`**, which builds this from the same `s` it indexes
  ## automatically, so the pairing can't drift. Use this directly only
  ## when `indexOfReChecked`'s one-`completeIf`-per-call shape doesn't
  ## fit — e.g. asserting the bound disjunctively or at a different point
  ## in the proof than the index term.
  s.len <= mkInt(s.ctx, int(Natural(b)))

# ============================================================================
# indexOfReChecked — the bundled, hard-to-misuse `indexOfRe` entry point
# ============================================================================
#
# H1: `indexOfRe` + `boundHolds` are sound primitives, but nothing ties
# the `s` passed to one to the `s` passed to the other — asserting the
# bound for an unrelated sequence silently defeats completeness (GOTCHAS
# #24). `IndexOfReResult` captures `s` exactly once and derives both
# fields from it, so that misuse is no longer representable through this
# entry point.

type IndexOfReResult*[E] = object
  index: Z3Int        ## the leftmost-match position term (or -1), from `indexOfRe`.
  completeIf: Z3Bool  ## discharge with `solver.add(r.completeIf)` to make
                      ## the `-1` answer trustworthy (`len(s) <= bound`,
                      ## built from the SAME `s` as `index`).

func index*[E](r: IndexOfReResult[E]): Z3Int = r.index
  ## The leftmost-match position term (or -1), as computed by `indexOfRe`.
func completeIf*[E](r: IndexOfReResult[E]): Z3Bool = r.completeIf
  ## Discharge with `solver.add(r.completeIf)` to make the -1 ("no match")
  ## answer trustworthy (see `indexOfReChecked`).
  ##
  ## The fields backing these accessors are intentionally NOT exported:
  ## the only way to build an `IndexOfReResult` is `indexOfReChecked`,
  ## which captures `s` exactly once — so the mismatched-`s` misuse this
  ## type exists to prevent (H1) is not representable even by a caller
  ## hand-assembling the object.

proc indexOfReChecked*[E](s: Z3Seq[E], re: Z3Regex[Z3Seq[E]],
                          start: Z3Int, bound: MatchBound): IndexOfReResult[E] =
  ## Encoded (no native op): `IndexOfReResult[E](index: indexOfRe(s, re,
  ## start, bound), completeIf: s.boundHolds(bound))` — the same `s` backs
  ## both fields, by construction.
  ##
  ## **The recommended, safe entry point** for `find`-style queries: it
  ## bundles the completeness obligation with the index term so they
  ## can't be asserted about two different sequences by accident (the
  ## trap `indexOfRe` + `boundHolds` leave open — see their doc-strings
  ## and GOTCHAS #24). `result.index` is unconditionally sound on its
  ## own; assert `solver.add(result.completeIf)` to additionally make a
  ## `result.index == -1` query mean "no match anywhere" rather than "no
  ## match in `[0, bound]`".
  ##
  ## `indexOfRe` / `boundHolds` stay available as lower-level primitives
  ## for advanced composition — e.g. asserting the bound disjunctively,
  ## or deferring it to a different point in the proof than where the
  ## index term is built.
  IndexOfReResult[E](index: indexOfRe(s, re, start, bound),
                      completeIf: s.boundHolds(bound))

proc indexOfReChecked*[E](s: Z3Seq[E], re: Z3Regex[Z3Seq[E]],
                          start: int, bound: MatchBound): IndexOfReResult[E] {.inline.} =
  ## `int` overload — lifts `start` via `mkInt` then delegates.
  indexOfReChecked(s, re, mkInt(s.ctx, start), bound)

proc indexOfReChecked*[E](s: Z3Seq[E], re: Z3Regex[Z3Seq[E]],
                          bound: MatchBound): IndexOfReResult[E] {.inline.} =
  ## `start = 0` convenience overload.
  indexOfReChecked(s, re, mkInt(s.ctx, 0), bound)

# Regex-replace: `replaceRe` / `replaceReAll` (`Z3_mk_seq_replace_re{,_all}`).
#
# Both build CORRECT terms — Z3's string solver just can't currently decide
# `str.replace_re` / `str.replace_re_all` even for fully concrete inputs
# (unlike `str.replace_all`, which it decides). Their contract is TERM
# CONSTRUCTION / SMT-LIB export, not solver-decidability: use them to build
# constraints or export SMT-LIB, but expect `smtValid`/`check()` to answer
# `zsUnknown` rather than proving concrete equalities. See
# docs/RFC-regex-index.md §7 and GOTCHAS #19, #24. Plain `Z3Seq.replaceAll`
# (non-regex, decidable) stays available unconditionally behind its own gate.

when defined(z3WithSeqReplaceRe):
  proc replaceRe*[E](a: Z3Seq[E], pattern: Z3Regex[Z3Seq[E]],
                     replacement: Z3Seq[E]): Z3Seq[E] =
    ## SMT `(seq.replace_re a pattern replacement)`. Replaces the first
    ## substring of `a` matching `pattern` with `replacement`.
    ##
    ## Requires `-d:z3WithSeqReplaceRe`. The underlying C function
    ## `Z3_mk_seq_replace_re` is absent from some Z3 distributions and
    ## from every Z3 build before ~4.15.8.
    ##
    ## Raises `Z3FeatureUnavailableError` if `Z3_mk_seq_replace_re` is not
    ## available on the loaded libz3. There is no honest "unavailable"
    ## `Z3Seq[E]` to degrade to, so this raises rather than returning a
    ## term that would silently mean something else. Check
    ## `Z3_mk_seq_replace_reAvailable()` first to avoid this exception.
    ##
    ## **Solver-opacity caveat:** the returned term is a CORRECT encoding
    ## of `str.replace_re`, but Z3's solver returns `unknown` — not `sat`
    ## or `unsat` — on `str.replace_re` constraints even for fully
    ## concrete `a` / `pattern` / `replacement`. Use this to build
    ## constraints or emit SMT-LIB; do not expect `smtValid` or `check()`
    ## to decide equalities/inequalities over the result.
    if not Z3_mk_seq_replace_reAvailable():
      raise newException(Z3FeatureUnavailableError,
        "Z3_mk_seq_replace_re is not available on the loaded Z3 " &
        z3Compat().runtimeVersion &
        " (added ~4.15.8; absent below). Check " &
        "Z3_mk_seq_replace_reAvailable() before calling replaceRe.")
    let raw = a.ctx.checkErr Z3_mk_seq_replace_re(a.ctx.raw, a.raw,
                                                   pattern.raw, replacement.raw)
    wrap[Z3Seq[E]](a.ctx, raw)

when defined(z3WithSeqReplaceReAll):
  proc replaceReAll*[E](a: Z3Seq[E], pattern: Z3Regex[Z3Seq[E]],
                        replacement: Z3Seq[E]): Z3Seq[E] =
    ## SMT `(seq.replace_re_all a pattern replacement)`. Replaces every
    ## non-overlapping substring of `a` matching `pattern` with
    ## `replacement`.
    ##
    ## Requires `-d:z3WithSeqReplaceReAll`. The underlying C function
    ## `Z3_mk_seq_replace_re_all` is absent from some Z3 distributions and
    ## from every Z3 build before ~4.15.8.
    ##
    ## Raises `Z3FeatureUnavailableError` if `Z3_mk_seq_replace_re_all` is
    ## not available on the loaded libz3. There is no honest "unavailable"
    ## `Z3Seq[E]` to degrade to, so this raises rather than returning a
    ## term that would silently mean something else. Check
    ## `Z3_mk_seq_replace_re_allAvailable()` first to avoid this exception.
    ##
    ## **Solver-opacity caveat:** the returned term is a CORRECT encoding
    ## of `str.replace_re_all`, but Z3's solver returns `unknown` — not
    ## `sat` or `unsat` — on `str.replace_re_all` constraints even for
    ## fully concrete `a` / `pattern` / `replacement`. Use this to build
    ## constraints or emit SMT-LIB; do not expect `smtValid` or `check()`
    ## to decide equalities/inequalities over the result.
    if not Z3_mk_seq_replace_re_allAvailable():
      raise newException(Z3FeatureUnavailableError,
        "Z3_mk_seq_replace_re_all is not available on the loaded Z3 " &
        z3Compat().runtimeVersion &
        " (added ~4.15.8; absent below). Check " &
        "Z3_mk_seq_replace_re_allAvailable() before calling replaceReAll.")
    let raw = a.ctx.checkErr Z3_mk_seq_replace_re_all(a.ctx.raw, a.raw,
                                                       pattern.raw, replacement.raw)
    wrap[Z3Seq[E]](a.ctx, raw)

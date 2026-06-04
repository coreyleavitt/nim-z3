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

import ./ffi, ./context, ./error, ./ast, ./sortdispatch, ./chars, ./sequence, ./strings
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

when defined(z3WithSeqReplaceRe):
  proc replaceRe*[E](a: Z3Seq[E], pattern: Z3Regex[Z3Seq[E]],
                     replacement: Z3Seq[E]): Z3Seq[E] =
    ## SMT `(seq.replace_re a pattern replacement)`. Replaces the first
    ## occurrence of a substring matching `pattern` in `a` with
    ## `replacement`.
    ##
    ## Requires `-d:z3WithSeqReplaceRe`. The underlying C function
    ## `Z3_mk_seq_replace_re` is absent from some Z3 distributions
    ## (e.g. the openSUSE Tumbleweed 4.15.0-1.3 package).
    let raw = a.ctx.checkErr Z3_mk_seq_replace_re(a.ctx.raw, a.raw,
                                                   pattern.raw, replacement.raw)
    wrap[Z3Seq[E]](a.ctx, raw)

## `z3/regex` — SMT-LIB regular expressions.
##
## A `Z3Regex[Basis]` is a regular language over the basis sequence
## sort. For v0.3 step 4 the only `Basis` we know how to construct
## sorts for is `Z3String`; step 5 (sequences) will generalise this to
## `Z3Regex[Z3Seq[E]]` by widening `regexSort[Basis]`. The phantom
## parameter exists today so that generalisation costs nothing at the
## call site.
##
## ## Decidability caveat
##
## Regex membership (`matches`) plus string equality is decidable for
## the regular fragment but **may run for a long time** in adversarial
## cases (large counted repetitions, intersections that produce
## exponential DFAs). Treat `zsUnknown` as a possible solver outcome.

import ./ffi, ./context, ./ast, ./sortdispatch, ./char, ./seq, ./string
export char

# ============================================================================
# Z3Regex[Basis] — phantom-typed value family
# ============================================================================

type
  Z3Regex*[Basis] = object
    ## Regular language over `Basis`. `Basis` is a typedesc of a
    ## sequence-shaped Z3 type (today: `Z3String`; v0.3 step 5:
    ## `Z3Seq[E]`).
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

proc mkRegexAll*[Basis](ctx: Z3Context): Z3Regex[Basis] =
  ## Regex matching any single basis element (`re.allchar`). For
  ## strings, that's any single codepoint.
  let sort = ctx.checkErr Z3_mk_re_sort(ctx.raw, basisSort[Basis](ctx))
  wrap[Z3Regex[Basis]](ctx, ctx.checkErr Z3_mk_re_allchar(ctx.raw, sort))
proc mkRegexAll*[Basis](): Z3Regex[Basis] =
  mkRegexAll[Basis](requireCurrentContext())

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

template emitNary(name, ffi: untyped) =
  proc name*[Basis](rs: varargs[Z3Regex[Basis]]): Z3Regex[Basis] =
    doAssert rs.len >= 1,
      "Z3Regex." & astToStr(name) & " requires at least one argument"
    if rs.len == 1:
      return rs[0]
    var raws = newSeq[RawZ3Ast](rs.len)
    for i, r in rs:
      raws[i] = r.raw
    wrap[Z3Regex[Basis]](rs[0].ctx, rs[0].ctx.checkErr ffi(
      rs[0].ctx.raw, cuint(raws.len),
      cast[ptr UncheckedArray[RawZ3Ast]](addr raws[0])))

emitNary(concat, Z3_mk_re_concat)
emitNary(union, Z3_mk_re_union)
emitNary(intersect, Z3_mk_re_intersect)

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

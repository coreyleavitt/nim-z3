## `z3/seq` — SMT-LIB Sequence theory.
##
## `Z3Seq[E]` is a finite sequence whose elements have AST family `E`.
## Z3 defines `String = (Seq Char)`, so `Z3String = Z3Seq[Z3Char]`
## (alias in `z3/string`); everything generic here is automatically
## available on strings too.
##
## Phantom design parallels `Z3Array[Key, Val]` and `Z3Regex[Basis]`:
## the typedesc generic carries the element identity, lifecycle hooks
## delegate to the unified templates, and every constructor goes
## through `wrap[Z3Seq[E]]` for the refcount discipline.
##
## ## Decidability caveat
##
## Z3's sequence solver is incomplete in general (the same caveat as
## strings — strings are sequences). Treat `zsUnknown` as a possible
## outcome for non-trivial sequence proof obligations.

import ./ffi, ./context, ./ast, ./bitvec, ./char, ./builder

# ============================================================================
# sortOfType extension for Z3Char + Z3Seq[E]
# ============================================================================
#
# This module's own `sortOfTypeSeq[E]` covers the cases Z3Seq needs at
# construction time. The full unified sortOfType (with array-side
# cases) lives in `z3/array`; future v0.3 step that introduces a
# central dispatcher can collapse the two. For now the duplication is
# scoped to a single recursion step.

proc sortOfTypeSeq*[E](ctx: Z3Context): RawZ3Sort

# ============================================================================
# Z3Seq[E] — phantom-typed value family
# ============================================================================

type
  Z3Seq*[E] = object
    ## Finite sequence of `E`-typed elements. Value-typed; lifecycle
    ## via the step-1 unified templates.
    raw*: RawZ3Ast
    ctx*: Z3Context

proc `=destroy`[E](s: Z3Seq[E]) {.raises: [].} =
  termDestroy(s, Z3_dec_ref)
proc `=copy`[E](dst: var Z3Seq[E], src: Z3Seq[E]) {.raises: [].} =
  termCopy(dst, src, Z3_dec_ref, Z3_inc_ref)
proc `=dup`[E](src: Z3Seq[E]): Z3Seq[E] {.raises: [].} =
  termDup(result, src, Z3_inc_ref)

# Dispatch needs to know element sorts. v0.3 step 5 wires Z3Int /
# Z3Real / Z3Bool / Z3BitVec[W] / Z3Char / nested Z3Seq[E']; widen
# alongside future families. Z3Array / Z3DatatypeValue are reachable
# in principle but live in their own modules and aren't needed for
# step 5.

proc sortOfTypeSeq*[E](ctx: Z3Context): RawZ3Sort =
  when E is Z3Int:
    ctx.checkErr Z3_mk_int_sort(ctx.raw)
  elif E is Z3Real:
    ctx.checkErr Z3_mk_real_sort(ctx.raw)
  elif E is Z3Bool:
    ctx.checkErr Z3_mk_bool_sort(ctx.raw)
  elif E is Z3BitVec:
    ctx.checkErr Z3_mk_bv_sort(ctx.raw, cuint(E.W))
  elif E is Z3Char:
    ctx.checkErr Z3_mk_char_sort(ctx.raw)
  elif E is Z3Seq:
    # Nested seq: recurse on the inner element type.
    let inner = sortOfTypeSeq[E.E](ctx)
    ctx.checkErr Z3_mk_seq_sort(ctx.raw, inner)
  else:
    {.error: "Z3Seq: unsupported element type. Supported: Z3Int, Z3Real, " &
             "Z3Bool, Z3BitVec[W], Z3Char, Z3Seq[E'] (nested). " &
             "Z3Array / Z3DatatypeValue elements land if needed; ask.".}

# ============================================================================
# Construction
# ============================================================================

proc mkSeqEmpty*[E](ctx: Z3Context): Z3Seq[E] =
  ## Empty sequence `(seq.empty (Seq E))`.
  let elem = sortOfTypeSeq[E](ctx)
  let seqSort = ctx.checkErr Z3_mk_seq_sort(ctx.raw, elem)
  wrap[Z3Seq[E]](ctx, ctx.checkErr Z3_mk_seq_empty(ctx.raw, seqSort))
proc mkSeqEmpty*[E](): Z3Seq[E] =
  mkSeqEmpty[E](requireCurrentContext())

proc mkSeqUnit*[E](ctx: Z3Context, e: E): Z3Seq[E] =
  ## Singleton sequence `(seq.unit e)` — element type inferred from
  ## the argument.
  wrap[Z3Seq[E]](ctx, ctx.checkErr Z3_mk_seq_unit(ctx.raw, e.raw))
proc mkSeqUnit*[E](e: E): Z3Seq[E] {.inline.} =
  mkSeqUnit(e.ctx, e)

proc mkSeqVar*[E](ctx: Z3Context, name: string): Z3Seq[E] =
  ## Free sequence variable. Element type comes from the typedesc
  ## generic.
  let elem = sortOfTypeSeq[E](ctx)
  let seqSort = ctx.checkErr Z3_mk_seq_sort(ctx.raw, elem)
  let sym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)
  wrap[Z3Seq[E]](ctx, ctx.checkErr Z3_mk_const(ctx.raw, sym, seqSort))
proc mkSeqVar*[E](name: string): Z3Seq[E] =
  mkSeqVar[E](requireCurrentContext(), name)

# ============================================================================
# Equality
# ============================================================================

proc `==`*[E](a, b: Z3Seq[E]): Z3Bool =
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_eq(a.ctx.raw, a.raw, b.raw))

proc `!=`*[E](a, b: Z3Seq[E]): Z3Bool =
  let eq = a == b
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_not(a.ctx.raw, eq.raw))

# ============================================================================
# Element extraction
# ============================================================================

proc nth*[E](s: Z3Seq[E], index: Z3Int): E =
  ## SMT `(seq.nth s i)` — the element at `index`. Out-of-range indices
  ## produce an unspecified value (the SMT-LIB underspecification).
  wrap[E](s.ctx, s.ctx.checkErr Z3_mk_seq_nth(s.ctx.raw, s.raw, index.raw))

proc `[]`*[E](s: Z3Seq[E], index: Z3Int): E {.inline.} =
  ## `s[i]` aliases `nth(s, i)` — matches Nim's seq-indexing idiom.
  nth(s, index)

# ============================================================================
# Sequence ops — generic over E
# ============================================================================

proc len*[E](a: Z3Seq[E]): Z3Int =
  ## SMT `(seq.len a)` — element count.
  wrap[Z3Int](a.ctx, a.ctx.checkErr Z3_mk_seq_length(a.ctx.raw, a.raw))

proc concat*[E](xs: varargs[Z3Seq[E]]): Z3Seq[E] =
  ## SMT `(seq.++ x1 x2 ...)`. Requires ≥1 argument.
  doAssert xs.len >= 1, "Z3Seq.concat requires at least one argument"
  if xs.len == 1:
    return xs[0]
  var raws = newSeq[RawZ3Ast](xs.len)
  for i, x in xs:
    raws[i] = x.raw
  wrap[Z3Seq[E]](xs[0].ctx, xs[0].ctx.checkErr Z3_mk_seq_concat(
    xs[0].ctx.raw, cuint(raws.len),
    cast[ptr UncheckedArray[RawZ3Ast]](addr raws[0])))

proc `&`*[E](a, b: Z3Seq[E]): Z3Seq[E] {.inline.} =
  ## Two-arg concat sugar mirroring Nim's `seq` concat.
  concat(a, b)

proc at*[E](a: Z3Seq[E], index: Z3Int): Z3Seq[E] =
  ## SMT `(seq.at a i)` — single-element sub-sequence. Distinct from
  ## `nth(a, i)` which returns the element directly.
  let raw = a.ctx.checkErr Z3_mk_seq_at(a.ctx.raw, a.raw, index.raw)
  wrap[Z3Seq[E]](a.ctx, raw)

proc substr*[E](a: Z3Seq[E], offset, length: Z3Int): Z3Seq[E] =
  ## SMT `(seq.extract a offset length)`. Out-of-range offsets /
  ## lengths yield the empty sequence.
  let raw = a.ctx.checkErr Z3_mk_seq_extract(a.ctx.raw, a.raw, offset.raw, length.raw)
  wrap[Z3Seq[E]](a.ctx, raw)

proc contains*[E](a, sub: Z3Seq[E]): Z3Bool =
  ## SMT `(seq.contains a sub)`.
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_seq_contains(a.ctx.raw, a.raw, sub.raw))

proc startsWith*[E](a, prefix: Z3Seq[E]): Z3Bool =
  ## SMT `(seq.prefixof prefix a)`. Argument order matches Nim's
  ## `strutils.startsWith(s, prefix)`.
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_seq_prefix(a.ctx.raw, prefix.raw, a.raw))

proc endsWith*[E](a, suffix: Z3Seq[E]): Z3Bool =
  ## SMT `(seq.suffixof suffix a)`.
  wrap[Z3Bool](a.ctx, a.ctx.checkErr Z3_mk_seq_suffix(a.ctx.raw, suffix.raw, a.raw))

proc indexOf*[E](a, sub: Z3Seq[E], start: Z3Int): Z3Int =
  ## SMT `(seq.indexof a sub start)`. Returns the 0-based position of
  ## the first occurrence of `sub` in `a` starting at `start`, or `-1`
  ## if not found.
  let raw = a.ctx.checkErr Z3_mk_seq_index(a.ctx.raw, a.raw, sub.raw, start.raw)
  wrap[Z3Int](a.ctx, raw)

proc indexOf*[E](a, sub: Z3Seq[E]): Z3Int {.inline.} =
  indexOf(a, sub, mkInt(a.ctx, 0))

proc replace*[E](a, old, new: Z3Seq[E]): Z3Seq[E] =
  ## SMT `(seq.replace a src dst)`. First-occurrence semantics.
  let raw = a.ctx.checkErr Z3_mk_seq_replace(a.ctx.raw, a.raw, old.raw, new.raw)
  wrap[Z3Seq[E]](a.ctx, raw)

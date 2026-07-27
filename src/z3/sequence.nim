## `z3/sequence` — SMT-LIB Sequence theory.
##
## `Z3Seq[E]` is a finite sequence whose elements have AST family `E`.
## Z3 defines `String = (Seq Char)`, so `Z3String = Z3Seq[Z3Char]`
## (alias in `z3/strings`); everything generic here is automatically
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

import ./ffi, ./context, ./error, ./ast, ./builder, ./sortdispatch, ./model

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

# Step 9 sortOf overload — recurses via `sortOfType[E]` (template with
# `mixin sortOf`). Any element type with a `sortOf` overload in scope
# at the instantiation site is accepted; nested Z3Seq[Z3Seq[...]],
# Z3Seq[Z3Array[K, V]], Z3Seq[Z3Fp[E,S]], etc. all flow through.
proc sortOf*[E](_: typedesc[Z3Seq[E]], ctx: Z3Context): RawZ3Sort {.inline.} =
  ctx.checkErr Z3_mk_seq_sort(ctx.raw, sortOfType[E](ctx))

# ============================================================================
# Construction
# ============================================================================

proc mkSeqEmpty*[E](ctx: Z3Context): Z3Seq[E] =
  ## Empty sequence `(seq.empty (Seq E))`.
  let seqSort = sortOf(Z3Seq[E], ctx)
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
  let seqSort = sortOf(Z3Seq[E], ctx)
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

proc nth*[E](s: Z3Seq[E], index: int): E {.inline.} =
  ## `int` overload — lifts `index` via `mkInt` then delegates.
  nth(s, mkInt(s.ctx, index))

proc `[]`*[E](s: Z3Seq[E], index: Z3Int): E {.inline.} =
  ## `s[i]` aliases `nth(s, i)` — matches Nim's seq-indexing idiom.
  nth(s, index)

proc `[]`*[E](s: Z3Seq[E], index: int): E {.inline.} =
  ## `int` overload of `s[i]` — lifts `index` via `mkInt`.
  nth(s, index)

# ============================================================================
# Sequence ops — generic over E
# ============================================================================

proc len*[E](a: Z3Seq[E]): Z3Int =
  ## SMT `(seq.len a)` — element count.
  wrap[Z3Int](a.ctx, a.ctx.checkErr Z3_mk_seq_length(a.ctx.raw, a.raw))

proc `$`*[E](a: Z3Seq[E]): string = termToSmt2(a)
  ## SMT-LIB rendering of the sequence AST.

proc evalSeqLen*[E](m: Z3Model, a: Z3Seq[E],
                    modelCompletion = true): int64 {.inline.} =
  ## Shorthand for `m.eval(a.len, modelCompletion).toInt64` — extract
  ## the integer length of `a` under the model. **v0.5 step 3.**
  ## Frequent in tests, since "is this sequence of the right length?"
  ## is one of the most common SMT-LIB sequence queries.
  m.eval(a.len, modelCompletion).toInt64

proc evalSeq*(m: Z3Model, a: Z3Seq[Z3Int],
              modelCompletion = true): seq[int64] =
  ## Extract the concrete integer sequence assigned to `a` under `m`.
  ## Returns a Nim `seq[int64]` by evaluating `a`, reading its length
  ## via `evalSeqLen`, then extracting each element with `nth(...).toInt64`.
  ##
  ## Requires the model to fully determine `a` (i.e. `a` is
  ## model-completed or concretely constrained). **N5.7.**
  let evaled = m.eval(a, modelCompletion)
  let n = m.eval(evaled.len, modelCompletion).toInt64
  result = newSeq[int64](int(n))
  for i in 0 ..< int(n):
    result[i] = m.eval(nth(evaled, i), modelCompletion).toInt64

# `concat` — SMT `(seq.++ x1 x2 ...)`. Requires ≥1 argument;
# singleton input returns the input unchanged. Generated by
# `lifecycle.emitVarargsRequired1E`.
emitVarargsRequired1E(concat, Z3Seq[E], Z3_mk_seq_concat)

proc `&`*[E](a, b: Z3Seq[E]): Z3Seq[E] {.inline.} =
  ## Two-arg concat sugar mirroring Nim's `seq` concat.
  concat(a, b)

proc at*[E](a: Z3Seq[E], index: Z3Int): Z3Seq[E] =
  ## SMT `(seq.at a i)` — single-element sub-sequence. Distinct from
  ## `nth(a, i)` which returns the element directly.
  let raw = a.ctx.checkErr Z3_mk_seq_at(a.ctx.raw, a.raw, index.raw)
  wrap[Z3Seq[E]](a.ctx, raw)

proc at*[E](a: Z3Seq[E], index: int): Z3Seq[E] {.inline.} =
  ## `int` overload — lifts `index` via `mkInt` then delegates.
  at(a, mkInt(a.ctx, index))

proc substr*[E](a: Z3Seq[E], offset, length: Z3Int): Z3Seq[E] =
  ## SMT `(seq.extract a offset length)`. Out-of-range offsets /
  ## lengths yield the empty sequence.
  let raw = a.ctx.checkErr Z3_mk_seq_extract(a.ctx.raw, a.raw, offset.raw, length.raw)
  wrap[Z3Seq[E]](a.ctx, raw)

proc substr*[E](a: Z3Seq[E], offset, length: int): Z3Seq[E] {.inline.} =
  ## `int` overload — lifts both `offset` and `length` via `mkInt`.
  substr(a, mkInt(a.ctx, offset), mkInt(a.ctx, length))

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

proc indexOf*[E](a, sub: Z3Seq[E], start: int): Z3Int {.inline.} =
  ## `int` overload — lifts `start` via `mkInt` then delegates.
  indexOf(a, sub, mkInt(a.ctx, start))

proc indexOf*[E](a, sub: Z3Seq[E]): Z3Int {.inline.} =
  indexOf(a, sub, mkInt(a.ctx, 0))

proc replace*[E](a, old, new: Z3Seq[E]): Z3Seq[E] =
  ## SMT `(seq.replace a src dst)`. First-occurrence semantics.
  let raw = a.ctx.checkErr Z3_mk_seq_replace(a.ctx.raw, a.raw, old.raw, new.raw)
  wrap[Z3Seq[E]](a.ctx, raw)

proc lastIndexOf*[E](a, sub: Z3Seq[E]): Z3Int =
  ## SMT `(seq.last_indexof a sub)`. Returns the 0-based position of
  ## the last occurrence of `sub` in `a`, or `-1` if not found.
  let raw = a.ctx.checkErr Z3_mk_seq_last_index(a.ctx.raw, a.raw, sub.raw)
  wrap[Z3Int](a.ctx, raw)

when defined(z3WithSeqReplaceAll):
  proc replaceAll*[E](a, old, new: Z3Seq[E]): Z3Seq[E] =
    ## SMT `(seq.replace_all a src dst)`. All-occurrences semantics —
    ## replaces every non-overlapping occurrence of `old` in `a` with `new`.
    ##
    ## Requires `-d:z3WithSeqReplaceAll`. The underlying C function
    ## `Z3_mk_seq_replace_all` is absent from some Z3 distributions
    ## (e.g. the openSUSE Tumbleweed 4.15.0-1.3 package) and from every
    ## Z3 build below 4.16 (the symbol was added at 4.16).
    ##
    ## Raises `Z3FeatureUnavailableError` if `Z3_mk_seq_replace_all` is not
    ## available on the loaded libz3. There is no honest "unavailable"
    ## `Z3Seq[E]` to degrade to, so this raises rather than returning a
    ## term that would silently mean something else. Check
    ## `Z3_mk_seq_replace_allAvailable()` first to avoid this exception.
    if not Z3_mk_seq_replace_allAvailable():
      raise newException(Z3FeatureUnavailableError,
        "Z3_mk_seq_replace_all is not available on the loaded Z3 " &
        z3Compat().runtimeVersion &
        " (added at 4.16; absent below). Check " &
        "Z3_mk_seq_replace_allAvailable() before calling replaceAll.")
    let raw = a.ctx.checkErr Z3_mk_seq_replace_all(a.ctx.raw, a.raw, old.raw, new.raw)
    wrap[Z3Seq[E]](a.ctx, raw)


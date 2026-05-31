## `z3/introspect` — structural introspection of ASTs and sorts.
##
## v0.4 step 2's central addition. AST introspection (kind / app
## decomposition / numeral-string extraction) and sort introspection
## (kind / parameter extractors) ship together because they're duals
## of the same capability: programmatic structural walking of Z3
## values.
##
## ## The erased AST handle
##
## `Z3AnyAst` is a value-typed handle for an AST whose typed family
## isn't compile-time known. It's the return type of `getAppArg`
## (recursive sub-term access) and the parameter type of `unpackApp`.
## It satisfies the `Z3Term` concept so every `Z3Term`-generic
## operation (the v0.3 step-1 unified surface + step 2's
## `getAstKind` / `getSort` / etc.) works on it.
##
## Round-trip from typed family:
##
## ```nim
## let typed: Z3Int = mkInt(42)
## let erased: Z3AnyAst = toAnyAst(typed)
## let back: Z3Int = asZ3Int(erased)   # runtime sort check
## ```
##
## The lifters `asZ3X` runtime-check the sort + parameters and raise
## `Z3Error` (`Z3_INVALID_USAGE`) on mismatch. v0.5 step 3 refines to
## a typed `Z3SortError` subclass.
##
## ## The two kind enums
##
## - `Z3AstKind` mirrors Z3's `Z3_ast_kind` (akNumeral, akApp, akVar,
##   akQuantifier, akSort, akFuncDecl, akUnknown). Distinguishes
##   between "is this a literal", "an application of some function",
##   "a quantifier", etc.
## - `Z3SortKind` mirrors Z3's `Z3_sort_kind` (skInt, skBool, skReal,
##   skBitVec, skArray, skDatatype, skRelation, skFiniteDomain, skFp,
##   skRoundingMode, skSeq, skRegex, skChar, skTypeVar,
##   skUninterpreted, skUnknown). All 16 entries — including the
##   research-grade Relation / FiniteDomain / TypeVar — for
##   completeness with Z3's API.

import ./ffi, ./context, ./error, ./ast, ./bitvec, ./char, ./fp, ./sequence, ./string, ./regex, ./sortdispatch

# ============================================================================
# Z3AstKind / Z3SortKind — Nim-side enums
# ============================================================================

type
  Z3AstKind* = enum
    akNumeral     ## A literal value (`mkInt(42)`, `mkBool(true)`, …).
    akApp         ## An application of a function decl (`a + b`,
                  ## `not x`, `f(a, b)`, …).
    akVar         ## A bound variable (de-Bruijn index in a quantifier
                  ## body).
    akQuantifier  ## A `forall` / `exists` / `lambda` AST.
    akSort        ## A sort handle wrapped as an AST.
    akFuncDecl    ## A function decl wrapped as an AST.
    akUnknown     ## Z3 couldn't classify the AST (rare).

  Z3SortKind* = enum
    skUninterpreted  ## A user-declared opaque sort.
    skBool           ## `Bool`.
    skInt            ## `Int`.
    skReal           ## `Real`.
    skBitVec         ## `(_ BitVec W)`.
    skArray          ## `(Array K V)`.
    skDatatype       ## A declared inductive datatype.
    skRelation       ## `Z3_relation_sort` — research-grade.
    skFiniteDomain   ## `Z3_finite_domain_sort` — research-grade.
    skFp             ## `(_ FloatingPoint E S)`.
    skRoundingMode   ## SMT-LIB `RoundingMode` sort (`Z3RoundingMode`).
    skSeq            ## `(Seq E)` (also covers `String = (Seq Char)`).
    skRegex          ## `(RegEx Basis)`.
    skChar           ## Unicode character.
    skTypeVar        ## A polymorphic type variable.
    skUnknown        ## Z3 couldn't classify the sort.

proc toZ3AstKind(k: Z3AstKindFFI): Z3AstKind {.inline.} =
  case k
  of Z3_NUMERAL_AST: akNumeral
  of Z3_APP_AST: akApp
  of Z3_VAR_AST: akVar
  of Z3_QUANTIFIER_AST: akQuantifier
  of Z3_SORT_AST: akSort
  of Z3_FUNC_DECL_AST: akFuncDecl
  of Z3_UNKNOWN_AST: akUnknown

proc toZ3SortKind(k: Z3SortKindFFI): Z3SortKind {.inline.} =
  case k
  of Z3_UNINTERPRETED_SORT: skUninterpreted
  of Z3_BOOL_SORT: skBool
  of Z3_INT_SORT: skInt
  of Z3_REAL_SORT: skReal
  of Z3_BV_SORT: skBitVec
  of Z3_ARRAY_SORT: skArray
  of Z3_DATATYPE_SORT: skDatatype
  of Z3_RELATION_SORT: skRelation
  of Z3_FINITE_DOMAIN_SORT: skFiniteDomain
  of Z3_FLOATING_POINT_SORT: skFp
  of Z3_ROUNDING_MODE_SORT: skRoundingMode
  of Z3_SEQ_SORT: skSeq
  of Z3_RE_SORT: skRegex
  of Z3_CHAR_SORT: skChar
  of Z3_TYPE_VAR: skTypeVar
  of Z3_UNKNOWN_SORT: skUnknown

# ============================================================================
# Z3AnyAst — runtime-erased AST handle
# ============================================================================

type
  Z3AnyAst* = object
    ## Value-typed handle for an AST whose typed family isn't
    ## compile-time known. Satisfies `Z3Term` (`raw` + `ctx` fields).
    raw*: RawZ3Ast
    ctx*: Z3Context

emitTermLifecycle(Z3AnyAst, Z3_dec_ref, Z3_inc_ref)

proc toAnyAst*[T: Z3Term](a: T): Z3AnyAst =
  ## Up-convert a typed AST to the erased form. inc_refs the underlying
  ## raw handle via the unified `wrap[Z3AnyAst]` template.
  wrap[Z3AnyAst](a.ctx, a.raw)

# ============================================================================
# AST introspection
# ============================================================================

proc getAstKind*[T: Z3Term](a: T): Z3AstKind {.inline.} =
  ## SMT `(get-ast-kind a)`. Identifies whether `a` is a literal,
  ## an application, a bound variable, a quantifier, etc.
  toZ3AstKind(Z3_get_ast_kind(a.ctx.raw, a.raw))

proc getSort*[T: Z3Term](a: T): RawZ3Sort {.inline.} =
  ## SMT `(get-sort a)`. Returns the raw sort handle. Pair with
  ## `getSortKind` for dispatch.
  a.ctx.checkErr Z3_get_sort(a.ctx.raw, a.raw)

proc getAppNumArgs*[T: Z3Term](a: T): int =
  ## Number of subterms in an `akApp` AST. Raises `Z3Error` if `a`
  ## isn't an application.
  doAssert getAstKind(a) == akApp,
    "getAppNumArgs: AST is not an application (kind = " & $getAstKind(a) & ")"
  let app = a.ctx.checkErr Z3_to_app(a.ctx.raw, a.raw)
  int(Z3_get_app_num_args(a.ctx.raw, app))

proc getAppDecl*[T: Z3Term](a: T): RawZ3FuncDecl =
  ## Function decl at the head of an `akApp` AST.
  doAssert getAstKind(a) == akApp,
    "getAppDecl: AST is not an application (kind = " & $getAstKind(a) & ")"
  let app = a.ctx.checkErr Z3_to_app(a.ctx.raw, a.raw)
  Z3_get_app_decl(a.ctx.raw, app)

proc getAppArg*[T: Z3Term](a: T, i: int): Z3AnyAst =
  ## i-th subterm of an `akApp` AST. Returned as `Z3AnyAst` because
  ## the typed family of the subterm isn't compile-time known.
  doAssert getAstKind(a) == akApp,
    "getAppArg: AST is not an application (kind = " & $getAstKind(a) & ")"
  let n = getAppNumArgs(a)
  doAssert i >= 0 and i < n,
    "getAppArg: index " & $i & " out of bounds [0, " & $n & ")"
  let app = a.ctx.checkErr Z3_to_app(a.ctx.raw, a.raw)
  let raw = Z3_get_app_arg(a.ctx.raw, app, cuint(i))
  wrap[Z3AnyAst](a.ctx, raw)

proc unpackApp*[T: Z3Term](a: T): tuple[decl: RawZ3FuncDecl, args: seq[Z3AnyAst]] =
  ## Full structural decomposition of an `akApp` AST. Returns the head
  ## decl + all subterms as a sequence of erased ASTs. Cleaner for
  ## recursive walks than `getAppDecl` + a loop over `getAppArg`.
  doAssert getAstKind(a) == akApp,
    "unpackApp: AST is not an application (kind = " & $getAstKind(a) & ")"
  let app = a.ctx.checkErr Z3_to_app(a.ctx.raw, a.raw)
  let n = int(Z3_get_app_num_args(a.ctx.raw, app))
  result.decl = Z3_get_app_decl(a.ctx.raw, app)
  result.args = newSeq[Z3AnyAst](n)
  for i in 0 ..< n:
    let raw = Z3_get_app_arg(a.ctx.raw, app, cuint(i))
    result.args[i] = wrap[Z3AnyAst](a.ctx, raw)

proc getNumeralString*[T: Z3Term](a: T): string =
  ## SMT `(get-numeral-string a)`. Works on any AST that simplifies to
  ## a literal numeral (`Z3Int`, `Z3Real`, `Z3BitVec[W]`, `Z3Fp[E, S]`).
  ## Raises `Z3Error` for non-numerals.
  let s = Z3_get_numeral_string(a.ctx.raw, a.raw)
  let errCode = Z3_get_error_code(a.ctx.raw)
  if errCode != Z3_OK:
    raiseZ3Error(a.ctx.raw, errCode)
  $s

# ============================================================================
# Sort introspection
# ============================================================================

proc getSortKind*(ctx: Z3Context, s: RawZ3Sort): Z3SortKind {.inline.} =
  ## SMT `(get-sort-kind s)`. Identifies which sort family `s` belongs
  ## to (Int / Bool / BitVec / Array / Seq / Regex / Fp / Datatype /
  ## …).
  toZ3SortKind(Z3_get_sort_kind(ctx.raw, s))

proc bitVecWidth*(ctx: Z3Context, s: RawZ3Sort): int =
  ## Width of a `skBitVec` sort. Raises `Z3Error` if `s` isn't a BV.
  doAssert getSortKind(ctx, s) == skBitVec,
    "bitVecWidth: sort is not a BitVec (kind = " & $getSortKind(ctx, s) & ")"
  int(Z3_get_bv_sort_size(ctx.raw, s))

proc arrayKey*(ctx: Z3Context, s: RawZ3Sort): RawZ3Sort =
  ## Domain sort of a `skArray`.
  doAssert getSortKind(ctx, s) == skArray,
    "arrayKey: sort is not an Array (kind = " & $getSortKind(ctx, s) & ")"
  ctx.checkErr Z3_get_array_sort_domain(ctx.raw, s)

proc arrayRange*(ctx: Z3Context, s: RawZ3Sort): RawZ3Sort =
  ## Range sort of a `skArray`.
  doAssert getSortKind(ctx, s) == skArray,
    "arrayRange: sort is not an Array (kind = " & $getSortKind(ctx, s) & ")"
  ctx.checkErr Z3_get_array_sort_range(ctx.raw, s)

proc seqElement*(ctx: Z3Context, s: RawZ3Sort): RawZ3Sort =
  ## Element sort of a `skSeq` (or the underlying `Char` for a
  ## `String = Seq Char`).
  doAssert getSortKind(ctx, s) == skSeq,
    "seqElement: sort is not a Seq (kind = " & $getSortKind(ctx, s) & ")"
  ctx.checkErr Z3_get_seq_sort_basis(ctx.raw, s)

proc regexBasis*(ctx: Z3Context, s: RawZ3Sort): RawZ3Sort =
  ## Basis (the sequence-sort) of a `skRegex`.
  doAssert getSortKind(ctx, s) == skRegex,
    "regexBasis: sort is not a Regex (kind = " & $getSortKind(ctx, s) & ")"
  ctx.checkErr Z3_get_re_sort_basis(ctx.raw, s)

proc fpEbits*(ctx: Z3Context, s: RawZ3Sort): int =
  ## Exponent-bit count of a `skFp` sort.
  doAssert getSortKind(ctx, s) == skFp,
    "fpEbits: sort is not a Fp (kind = " & $getSortKind(ctx, s) & ")"
  int(Z3_fpa_get_ebits(ctx.raw, s))

proc fpSbits*(ctx: Z3Context, s: RawZ3Sort): int =
  ## Significand-bit count of a `skFp` sort (includes the implicit
  ## hidden bit per SMT-LIB convention).
  doAssert getSortKind(ctx, s) == skFp,
    "fpSbits: sort is not a Fp (kind = " & $getSortKind(ctx, s) & ")"
  int(Z3_fpa_get_sbits(ctx.raw, s))

proc datatypeName*(ctx: Z3Context, s: RawZ3Sort): string =
  ## Name of a `skDatatype` sort, as set by `declareDatatype`.
  doAssert getSortKind(ctx, s) == skDatatype,
    "datatypeName: sort is not a Datatype (kind = " & $getSortKind(ctx, s) & ")"
  $Z3_get_symbol_string(ctx.raw, Z3_get_sort_name(ctx.raw, s))

# ============================================================================
# Typed lifters from `Z3AnyAst` back to typed families
# ============================================================================
#
# Each lifter runtime-checks the AST's sort against the target type
# parameters; raises `Z3Error` (Z3_INVALID_USAGE) on mismatch with an
# informative message. v0.5 step 3 will refine to a typed
# `Z3SortError` subclass.

template raiseSortMismatch(expected: string, gotKind: Z3SortKind,
                           ctx: Z3Context) =
  var e = newException(Z3SortMismatchError,
    "Sort lift mismatch: expected " & expected &
    ", got AST of sort kind " & $gotKind & ".")
  e.code = Z3_INVALID_USAGE
  raise e

proc asZ3Int*(a: Z3AnyAst): Z3Int =
  let k = getSortKind(a.ctx, getSort(a))
  if k != skInt:
    raiseSortMismatch("Z3Int (skInt)", k, a.ctx)
  wrap[Z3Int](a.ctx, a.raw)

proc asZ3Real*(a: Z3AnyAst): Z3Real =
  let k = getSortKind(a.ctx, getSort(a))
  if k != skReal:
    raiseSortMismatch("Z3Real (skReal)", k, a.ctx)
  wrap[Z3Real](a.ctx, a.raw)

proc asZ3Bool*(a: Z3AnyAst): Z3Bool =
  let k = getSortKind(a.ctx, getSort(a))
  if k != skBool:
    raiseSortMismatch("Z3Bool (skBool)", k, a.ctx)
  wrap[Z3Bool](a.ctx, a.raw)

proc asZ3Char*(a: Z3AnyAst): Z3Char =
  let k = getSortKind(a.ctx, getSort(a))
  if k != skChar:
    raiseSortMismatch("Z3Char (skChar)", k, a.ctx)
  wrap[Z3Char](a.ctx, a.raw)

proc asZ3BitVec*[W: static int](a: Z3AnyAst): Z3BitVec[W] =
  let s = getSort(a)
  let k = getSortKind(a.ctx, s)
  if k != skBitVec:
    raiseSortMismatch("Z3BitVec[" & $W & "] (skBitVec)", k, a.ctx)
  let actualW = bitVecWidth(a.ctx, s)
  if actualW != W:
    var e = newException(Z3SortMismatchError,
      "BitVec width mismatch: expected Z3BitVec[" & $W &
      "], got Z3BitVec[" & $actualW & "].")
    e.code = Z3_INVALID_USAGE
    raise e
  wrap[Z3BitVec[W]](a.ctx, a.raw)

proc asZ3Fp*[E, S: static int](a: Z3AnyAst): Z3Fp[E, S] =
  let sort = getSort(a)
  let k = getSortKind(a.ctx, sort)
  if k != skFp:
    raiseSortMismatch("Z3Fp[" & $E & ", " & $S & "] (skFp)", k, a.ctx)
  let actualE = fpEbits(a.ctx, sort)
  let actualS = fpSbits(a.ctx, sort)
  if actualE != E or actualS != S:
    var e = newException(Z3SortMismatchError,
      "Fp width mismatch: expected Z3Fp[" & $E & ", " & $S &
      "], got Z3Fp[" & $actualE & ", " & $actualS & "].")
    e.code = Z3_INVALID_USAGE
    raise e
  wrap[Z3Fp[E, S]](a.ctx, a.raw)

proc asZ3Seq*[E](a: Z3AnyAst): Z3Seq[E] =
  let sort = getSort(a)
  let k = getSortKind(a.ctx, sort)
  if k != skSeq:
    raiseSortMismatch("Z3Seq[E] (skSeq)", k, a.ctx)
  # Element-sort verification: compare against sortOf[E].
  let elemSort = seqElement(a.ctx, sort)
  let expectedElemSort = sortOfType[E](a.ctx)
  # Z3 sorts are interned — same family + parameters → same handle.
  if cast[pointer](elemSort) != cast[pointer](expectedElemSort):
    var e = newException(Z3SortMismatchError,
      "Seq element sort mismatch.")
    e.code = Z3_INVALID_USAGE
    raise e
  wrap[Z3Seq[E]](a.ctx, a.raw)

proc asZ3Regex*[Basis](a: Z3AnyAst): Z3Regex[Basis] =
  let sort = getSort(a)
  let k = getSortKind(a.ctx, sort)
  if k != skRegex:
    raiseSortMismatch("Z3Regex[Basis] (skRegex)", k, a.ctx)
  wrap[Z3Regex[Basis]](a.ctx, a.raw)


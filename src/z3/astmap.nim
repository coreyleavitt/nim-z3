## `z3/astmap` — typed ref-handle for Z3's `Z3_ast_map` C type.
##
## A `Z3AstMap` is a mutable hash-map from Z3 AST terms to Z3 AST terms,
## managed by Z3 internally. The typical use-case is memoising
## term-to-term translations (e.g. variable substitution tables, expression
## caches in rewriting passes).
##
## ## Type
##
## `Z3AstMap` follows the same **plain-object + ref-alias** pattern as every
## other refcounted handle in this library (`Z3SolverOwn`/`Z3Solver*`,
## `Z3ModelOwn`/`Z3Model*`, `Z3AstVectorOwn`/`Z3AstVector*`, …):
##
## ```nim
## type
##   Z3AstMapOwn = object
##     raw: RawZ3AstMap
##     ctx: Z3Context
##   Z3AstMap* = ref Z3AstMapOwn
## ```
##
## Ref assignment (`let m2 = m1`) gives two handles to the same underlying
## Z3 map object — mutations via either handle are immediately visible
## through the other.
##
## ## Key / value types
##
## Both keys and values can be any `Z3Term` (the structural concept covering
## `Z3Int`, `Z3Bool`, `Z3BitVec[W]`, etc.). The map itself is sort-agnostic
## at the C level; the Nim API enforces term-ness at the call site only via
## the `Z3Term` constraint.
##
## ## `find` and the contains-then-find discipline
##
## `Z3_ast_map_find` is undefined behaviour when the key is absent. The
## wrapper always calls `contains` first and returns `none(V)` on a miss,
## so callers don't have to guard manually.

import std/options
import ./ffi, ./context, ./error, ./lifecycle, ./introspect, ./astvector
export options

# ============================================================================
# Z3AstMap — typed ref-handle
# ============================================================================

type
  Z3AstMapOwn = object
    raw: RawZ3AstMap
    ctx: Z3Context
  Z3AstMap* = ref Z3AstMapOwn

emitRefcountLifecycle(Z3AstMapOwn, Z3_ast_map_dec_ref)

# ============================================================================
# Constructor
# ============================================================================

proc wrapAstMap*(ctx: Z3Context, raw: RawZ3AstMap): Z3AstMap =
  ## Adopt a freshly-returned raw map handle. Raises `Z3Error` if nil.
  ## Public so future modules can wrap maps obtained from their own FFI paths.
  if raw.isNil:
    var e = newException(Z3InvalidUsageError,
      "Z3 returned a nil ast-map handle.")
    e.code = Z3_INVALID_USAGE
    raise e
  Z3_ast_map_inc_ref(ctx.raw, raw)
  Z3AstMap(raw: raw, ctx: ctx)

proc newAstMap*(ctx: Z3Context): Z3AstMap =
  ## Create a fresh empty AST map bound to `ctx`.
  ##
  runnableExamples:
    import z3
    let ctx = newContext()
    let m = newAstMap(ctx)
    doAssert m.len == 0
  wrapAstMap(ctx, ctx.checkErr Z3_mk_ast_map(ctx.raw))

# ============================================================================
# Mutation
# ============================================================================

proc insert*[K: Z3Term, V: Z3Term](m: Z3AstMap, k: K, v: V) =
  ## Insert or replace the mapping k→v. If k is already present the
  ## old value is overwritten; `len` does not increase.
  ##
  runnableExamples:
    import z3, std/options
    let ctx = newContext()
    let m = newAstMap(ctx)
    let k = mkIntVar(ctx, "x")
    let v = mkInt(ctx, 42)
    m.insert(k, v)
    doAssert m.len == 1
    doAssert m.find(toAnyAst(k), Z3Int).isSome
  m.ctx.checkErrVoid Z3_ast_map_insert(m.ctx.raw, m.raw, k.raw, v.raw)

proc erase*(m: Z3AstMap, k: Z3AnyAst) =
  ## Remove the entry for `k`. No-op if `k` is absent.
  m.ctx.checkErrVoid Z3_ast_map_erase(m.ctx.raw, m.raw, k.raw)

proc reset*(m: Z3AstMap) =
  ## Remove all entries. The map is reusable as if freshly constructed.
  m.ctx.checkErrVoid Z3_ast_map_reset(m.ctx.raw, m.raw)

# ============================================================================
# Query
# ============================================================================

proc contains*(m: Z3AstMap, k: Z3AnyAst): bool =
  ## True iff `k` is a key in the map.
  Z3_ast_map_contains(m.ctx.raw, m.raw, k.raw)

proc find*[V: Z3Term](m: Z3AstMap, k: Z3AnyAst, _: typedesc[V]): Option[V] =
  ## Look up `k` and return `some(value)` if present, `none(V)` otherwise.
  ## Uses contains-before-find to guard against Z3's undefined-behaviour
  ## path when `k` is absent.
  if not m.contains(k):
    return none(V)
  let rawV = m.ctx.checkErr Z3_ast_map_find(m.ctx.raw, m.raw, k.raw)
  some(wrap[V](m.ctx, rawV))

proc len*(m: Z3AstMap): int {.inline.} =
  ## Number of entries in the map.
  int(Z3_ast_map_size(m.ctx.raw, m.raw))

proc keys*(m: Z3AstMap): Z3AstVector =
  ## Return a fresh `Z3AstVector` containing all keys. The vector is
  ## independent of the map — mutations to the map after this call do not
  ## affect the returned vector.
  wrapAstVector(m.ctx, m.ctx.checkErr Z3_ast_map_keys(m.ctx.raw, m.raw))

# ============================================================================
# Pretty print
# ============================================================================

proc `$`*(m: Z3AstMap): string =
  ## Human-readable rendering of the map's contents.
  $Z3_ast_map_to_string(m.ctx.raw, m.raw)

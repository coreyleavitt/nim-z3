## `z3/stats` — typed key-value statistics handle.
##
## `Z3Stats` is the ref-typed Nim wrapper for Z3's `Z3_stats` opaque
## handle. Returned by `Z3Solver.getStatistics` (v0.4 step 8) and
## `Z3Fixedpoint.getStatistics` (closes the step-5 §8 deferral).
##
## Stats are a flat key-value table where keys are strings and values
## are either `uint` or `double`. The wrapper exposes:
##
## - **Uniform float view** — `len`, `keys()`, `[key]` returning
##   `float`. Covers the common "loop and print" / "lookup one
##   counter" use case.
## - **Typed access** — `getInt(key)`, `getFloat(key)`, `isInt(key)`
##   for callers who care about lossless extraction on huge uint
##   values (`uint` entries beyond float64's mantissa precision).
## - **Iteration** — `pairs(s)` yields `(key, value: float)` matching
##   Nim's `Table` iteration convention.
## - **Pretty** — `$s` renders Z3's multiline key/value listing.

import ./ffi, ./context, ./error, ./lifecycle
import std/math   # for NaN constant

# ============================================================================
# Z3Stats — typed ref-handle
# ============================================================================

type
  Z3StatsOwn = object
    raw: RawZ3Stats
    ctx: Z3Context
  Z3Stats* = ref Z3StatsOwn

emitRefcountLifecycle(Z3StatsOwn, Z3_stats_dec_ref)

proc wrapStats*(ctx: Z3Context, raw: RawZ3Stats): Z3Stats =
  ## Adopt a freshly-returned raw stats handle. Public so sibling
  ## modules (`z3/solver`, `z3/fixedpoint`) can wrap stats they
  ## obtain from their own FFI paths. Raises `Z3Error` if `raw` is
  ## nil.
  if raw.isNil:
    var e = newException(Z3Error, "Z3 returned a nil stats handle.")
    e.code = Z3_INVALID_USAGE
    raise e
  Z3_stats_inc_ref(ctx.raw, raw)
  Z3Stats(raw: raw, ctx: ctx)

proc raw*(s: Z3Stats): RawZ3Stats {.inline.} = s.raw
proc ctx*(s: Z3Stats): Z3Context {.inline.} = s.ctx

# ============================================================================
# Length + key enumeration
# ============================================================================

proc len*(s: Z3Stats): int {.inline.} =
  ## Number of entries.
  int(Z3_stats_size(s.ctx.raw, s.raw))

proc keys*(s: Z3Stats): seq[string] =
  ## Snapshot of all entry keys, in Z3's order.
  let n = s.len
  result = newSeq[string](n)
  for i in 0 ..< n:
    result[i] = $Z3_stats_get_key(s.ctx.raw, s.raw, cuint(i))

# ============================================================================
# Indexed lookup helpers (private — used by key-based access)
# ============================================================================

proc findIndex(s: Z3Stats, key: string): int =
  ## Linear scan — stats tables are small (~50 entries).
  let n = s.len
  for i in 0 ..< n:
    if $Z3_stats_get_key(s.ctx.raw, s.raw, cuint(i)) == key:
      return i
  -1

proc valueByIndex(s: Z3Stats, i: int): float =
  ## Uniform float view of the i-th entry (uint coerced to float).
  if Z3_stats_is_uint(s.ctx.raw, s.raw, cuint(i)):
    float(Z3_stats_get_uint_value(s.ctx.raw, s.raw, cuint(i)))
  elif Z3_stats_is_double(s.ctx.raw, s.raw, cuint(i)):
    float(Z3_stats_get_double_value(s.ctx.raw, s.raw, cuint(i)))
  else:
    NaN

# ============================================================================
# Key-based access
# ============================================================================

proc contains*(s: Z3Stats, key: string): bool {.inline.} =
  s.findIndex(key) >= 0

proc `[]`*(s: Z3Stats, key: string): float =
  ## Uniform float view. Raises `KeyError` if the key isn't present.
  let i = s.findIndex(key)
  if i < 0:
    raise newException(KeyError,
      "Z3Stats[]: key '" & key & "' not present. " &
      "Use `contains` first or iterate via `pairs`.")
  s.valueByIndex(i)

proc isInt*(s: Z3Stats, key: string): bool =
  ## True if `key`'s entry is a `uint` (Z3-side). Raises `KeyError`
  ## if absent.
  let i = s.findIndex(key)
  if i < 0:
    raise newException(KeyError,
      "Z3Stats.isInt: key '" & key & "' not present.")
  Z3_stats_is_uint(s.ctx.raw, s.raw, cuint(i))

proc getInt*(s: Z3Stats, key: string): int =
  ## Lossless extraction for `uint` entries. Raises `Z3Error` if the
  ## entry is `double`-typed.
  let i = s.findIndex(key)
  if i < 0:
    raise newException(KeyError,
      "Z3Stats.getInt: key '" & key & "' not present.")
  if not Z3_stats_is_uint(s.ctx.raw, s.raw, cuint(i)):
    var e = newException(Z3Error,
      "Z3Stats.getInt: key '" & key & "' is double-typed; use getFloat.")
    e.code = Z3_INVALID_USAGE
    raise e
  int(Z3_stats_get_uint_value(s.ctx.raw, s.raw, cuint(i)))

proc getFloat*(s: Z3Stats, key: string): float =
  ## Extraction for `double` entries. Coerces `uint` entries to
  ## float losslessly up to 2^53.
  let i = s.findIndex(key)
  if i < 0:
    raise newException(KeyError,
      "Z3Stats.getFloat: key '" & key & "' not present.")
  s.valueByIndex(i)

# ============================================================================
# Iteration
# ============================================================================

iterator pairs*(s: Z3Stats): tuple[key: string, value: float] =
  ## Yield each `(key, value)` pair in Z3's order, with `value` in
  ## the uniform float view. Convention matches `Table.pairs`.
  let n = s.len
  for i in 0 ..< n:
    yield ($Z3_stats_get_key(s.ctx.raw, s.raw, cuint(i)), s.valueByIndex(i))

# ============================================================================
# Pretty
# ============================================================================

proc `$`*(s: Z3Stats): string =
  ## SMT-LIB-shaped multiline rendering.
  $Z3_stats_to_string(s.ctx.raw, s.raw)

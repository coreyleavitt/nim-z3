# Migrating from nim-z3 1.x to 2.0

> **Audience:** consumers upgrading from nim-z3 1.x (v1.0.0) to 2.0.0.
> All breaking changes are hard breaks — no deprecation aliases were kept.
> See the CHANGELOG `[2.0.0]` entry for the full change log; this document
> focuses on the mechanical migration steps.

---

## Quick checklist

1. Update your `.nimble` or `milpa.kdl` pin: `nim-z3 = "2.0.0"`.
2. Apply the seven symbol renames below.
3. If you import submodules directly, note the new module additions.
4. Review the Z3 4.15 caveats section if you use uninterpreted sorts, FP
   numerals, or `Z3Optimize` with FP objectives.

---

## Breaking renames

All renames are hard breaks introduced in v2.0.0. The old names do not exist
as deprecated aliases — callers must update at upgrade time.

### N4.4 — `Z3Int.toInt` → `Z3Int.toInt64`

| | Symbol |
|---|---|
| **Old (1.x)** | `toInt(a: Z3Int): int` |
| **New (2.0)** | `toInt64(a: Z3Int): int64` |

The old `toInt` silently truncated on platforms where `int` is 32-bit.
`toInt64` makes the 64-bit contract explicit and raises `Z3OperationError`
when the AST is not a literal integer.

**Before:**
```nim
let v = m.eval(x).toInt        # 1.x
```

**After:**
```nim
let v = m.eval(x).toInt64      # 2.0
```

If you need an `int`, convert after extraction:
```nim
let v = int(m.eval(x).toInt64)
```

---

### N5.7 rename 1 — `strToInt` → `Z3String.toInt`

| | Symbol |
|---|---|
| **Old (1.x)** | `strToInt(s: Z3String): Z3Int` |
| **New (2.0)** | `toInt(s: Z3String): Z3Int` (UFSS: call as `s.toInt`) |

**Before:**
```nim
let i = strToInt(s)            # 1.x
```

**After:**
```nim
let i = s.toInt                # 2.0  — Z3String.toInt
```

---

### N5.7 rename 2 — `intToStr` → `Z3Int.toStr`

| | Symbol |
|---|---|
| **Old (1.x)** | `intToStr(i: Z3Int): Z3String` |
| **New (2.0)** | `toStr(i: Z3Int): Z3String` (UFSS: call as `i.toStr`) |

**Before:**
```nim
let s = intToStr(n)            # 1.x
```

**After:**
```nim
let s = n.toStr                # 2.0  — Z3Int.toStr
```

---

### N6.7 rename 1 — `mkNaN` → `mkFpNaN`

| | Symbol |
|---|---|
| **Old (1.x)** | `mkNaN[E, S](): Z3Fp[E, S]` |
| **New (2.0)** | `mkFpNaN[E, S](): Z3Fp[E, S]` |

**Before:**
```nim
let nan = mkNaN[11, 53]()      # 1.x
```

**After:**
```nim
let nan = mkFpNaN[11, 53]()    # 2.0
```

---

### N6.7 rename 2 — `mkInf` → `mkFpInf`

| | Symbol |
|---|---|
| **Old (1.x)** | `mkInf[E, S](negative = false): Z3Fp[E, S]` |
| **New (2.0)** | `mkFpInf[E, S](negative = false): Z3Fp[E, S]` |

**Before:**
```nim
let inf = mkInf[11, 53]()                     # 1.x
let negInf = mkInf[11, 53](negative = true)   # 1.x
```

**After:**
```nim
let inf    = mkFpInf[11, 53]()                  # 2.0
let negInf = mkFpInf[11, 53](negative = true)   # 2.0
```

---

### N6.7 rename 3 — `mkZero` → `mkFpZero`

| | Symbol |
|---|---|
| **Old (1.x)** | `mkZero[E, S](negative = false): Z3Fp[E, S]` |
| **New (2.0)** | `mkFpZero[E, S](negative = false): Z3Fp[E, S]` |

**Before:**
```nim
let z  = mkZero[8, 24]()                      # 1.x
let nz = mkZero[8, 24](negative = true)       # 1.x
```

**After:**
```nim
let z  = mkFpZero[8, 24]()                    # 2.0
let nz = mkFpZero[8, 24](negative = true)     # 2.0
```

---

### N6.7 rename 4 — `toFp(bv, _)` → `bvToFpBits`

The BV-reinterpretation form of `toFp` (bit-exact cast, no rounding mode)
has been renamed. The *lossy* form `toFp(rm, fp, typedesc)` (FP-to-FP with
rounding) keeps its name.

| | Symbol |
|---|---|
| **Old (1.x)** | `toFp[Bw, E, S](bv: Z3BitVec[Bw], _: typedesc[Z3Fp[E,S]]): Z3Fp[E,S]` |
| **New (2.0)** | `bvToFpBits[Bw, E, S](bv: Z3BitVec[Bw], _: typedesc[Z3Fp[E,S]]): Z3Fp[E,S]` |

**Before:**
```nim
let fp = toFp(bv, Z3Float64)   # 1.x — BV reinterpretation
```

**After:**
```nim
let fp = bvToFpBits(bv, Z3Float64)   # 2.0
```

The lossy conversion is unchanged:
```nim
let f64 = toFp(rmRNE(), f32, Z3Float64)   # still valid in 2.0
```

---

### N10.11 — `mkRegexAll` → `mkRegexAllChar`

| | Symbol |
|---|---|
| **Old (1.x)** | `mkRegexAll[Basis](): Z3Regex[Basis]` |
| **New (2.0)** | `mkRegexAllChar[Basis](): Z3Regex[Basis]` |

The rename makes the semantics explicit: this is the *single-character*
wildcard (`re.allchar` in SMT-LIB), not a "match everything" regex.

**Before:**
```nim
let dot = mkRegexAll[Z3String]()      # 1.x
```

**After:**
```nim
let dot = mkRegexAllChar[Z3String]()  # 2.0
```

---

## New modules in 2.0

The following modules were added in the 2.0.0 cycle. All are exported through
the `import z3` umbrella; direct submodule imports are also available.

| Module | Content |
|---|---|
| `z3/sets` | Typed `Z3Set[V]` — membership, union, intersection, difference, complement, subset |
| `z3/astmap` | `Z3AstMap` — mutable hash map keyed by `Z3Term` AST identity |
| `z3/uninterpretedval` | `Z3UninterpretedVal[S]` — marker-phantom values of a user-declared sort |
| `z3/rcf` | `Z3RcfNum` — real closed field numerals (`Z3_rcf_*`) |
| `z3/algebraic` | `Z3AlgebraicNum` — algebraic real arithmetic and subresultant polynomials |
| `z3/spacer` | `Z3Fixedpoint` SPACER extensions — predicate transformers, Horn clause queries |
| `z3/simplifier` | `Z3Simplifier` / `Z3SimplifierOwn` — named simplifier pipelines (Z3 ≥ 4.12) |
| `z3/propagator` | `Z3UserPropagator` — theory-propagation callbacks (push/pop/fresh + fixed/eq/diseq) |
| `z3/onclause` | `registerOnClause` — clause-learning notification callback |
| `z3/order` | `mkBoundedOrder` / `mkLinearOrder` — finite order axioms |
| `z3/logging` | `enableLog` / `appendLog` / `Z3LogAppendable` — Z3 interaction log control |

---

## Other notable additions in 2.0

- **`Z3Context.interrupt()`** — cross-thread cancellation of in-flight
  `check()` / `optimize.check()` / `fixedpoint.query()` (v1.0 HIGH #1).
- **`lambda[K, V](bound, body)`** — Z3 lambdas as first-class typed arrays.
- **`arrayDefault[K, V](a)`** — dual of `mkConstArray`.
- **`Z3Solver.checkWith(assumptions)`** — `Z3_solver_check_assumptions`
  wrapper.
- **`Z3Solver.getAssertions()`** — typed solver-state snapshot.
- **`Z3Solver.translate(target)`** — cross-context solver migration.
- **`astHash[T: Z3Term](a)`** — Z3-side structural-identity hash.
- **`Z3Fp.isFinite[E, S](x)`** — synthesised IEEE predicate
  (`not isNaN(x) and not isInf(x)`).
- Numerous BV, arith, string, sequence, FP, quantifier, and tactic
  completeness additions; see the CHANGELOG `[2.0.0]` entry for the full
  list.

---

## Z3 4.15 caveats

nim-z3 2.0.0 ships against **Z3 4.15.0**. Three known quirks affect specific
usage patterns; all are Z3 upstream issues, not wrapper bugs.

### Caveat 1 — `Z3_mk_const_array` rejects uninterpreted-sort domains

`Z3_mk_const_array` raises `invalid array sort definition, parameter is not
a sort` when the domain parameter is an uninterpreted sort. This means
`mkConstArray[Z3UninterpretedVal[S], V](value)` does not work.

**Workaround:** use `mkArrayVar[K, V]` to declare a symbolic array variable
instead of constructing one via `mkConstArray`. This path flows through
`sortOf[K, V]` → `sortOfType[K]` without touching `Z3_mk_const_array`.

### Caveat 2 — SIGSEGV with uninterpreted-sort constants under `Z3_mk_context_rc`

`Z3_mk_context_rc` (used by `newContext`) interacts badly with uninterpreted
sort constants in Z3 4.15: passing such constants to `Z3_mk_distinct`,
`Z3_mk_eq`, or `Z3_mk_app` causes a SIGSEGV. The bug affects both
`Z3_mk_const` and `Z3_mk_fresh_const`. It reproduces in pure C.

**Workaround:** construct uninterpreted-sort terms via
`loadSmt2String` / `Z3_parse_smtlib2_string` — that parse path is unaffected.
See `tests/tmodel_enum.nim` (`sortUniverse` test) for an example.

### Caveat 3 — FP objectives rejected at runtime by `Z3_optimize_maximize/minimize`

The C-level `Z3_optimize_maximize` / `Z3_optimize_minimize` accept any AST
but raise `Z3_EXCEPTION: Objective must be bit-vector, integer or real` when
the objective is a floating-point term. Z3 4.15 does not support FP
optimization.

**Effect:** the Nim overloads for `maximize`/`minimize` on `Z3Fp` terms
compile without error and dispatch correctly; callers receive
`Z3OperationError` at solve time.

**Workaround:** convert FP objectives to reals before optimizing, or avoid FP
optimization until Z3 adds native support.

---

## Proptest sync note

proptest is the only tracked consumer of nim-z3. The Lens 4 grep at the
2.0.0 tag found **none** of the renamed symbols (`mkNaN`, `mkInf`, `mkZero`,
`strToInt`, `intToStr`, `toFp(bv,_)`, `mkRegexAll`) in proptest's source
tree. The entire proptest migration delta is a single version-pin bump:

```kdl
# milpa.kdl (or .nimble)
# before:
nim-z3 "1.0.0"
# after:
nim-z3 "2.0.0"
```

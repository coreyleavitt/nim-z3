# Gotchas

> **Audience: users of nim-z3.** Pitfalls, quirks, and surface-visible
> wrapper choices that catch real users. Each entry follows the
> template:
>
> - **Symptom** — what you see / what surprised you
> - **Cause** — why it happens (Z3 behaviour, Nim quirk, IEEE rule, etc.)
> - **Wrapper behaviour** — what nim-z3 does about it
> - **What you should do** — actionable advice
>
> See also: [PARITY.md](PARITY.md) (cross-family contract for
> contributors), [INTERNAL_API.md](INTERNAL_API.md) (cross-module
> seams), [THREADING.md](THREADING.md) (per-thread isolation).

---

## Index

1. [Floating-point `==` uses IEEE semantics — NaN ≠ NaN](#1-floating-point--uses-ieee-semantics--nan--nan)
2. [Z3RoundingMode literals are procs, not enum values — `rmRNE()`](#2-z3roundingmode-literals-are-procs-not-enum-values--rmrne)
3. [`newContext()` auto-sets the current-context threadvar](#3-newcontext-auto-sets-the-current-context-threadvar)
4. [Quantifier without a trigger can hang the solver](#4-quantifier-without-a-trigger-can-hang-the-solver)
5. [`forall` returns a `Z3Bool` — assert it; don't ignore the result](#5-forall-returns-a-z3bool--assert-it-dont-ignore-the-result)
6. [Typed error hierarchy: catch the specific subclass, not just `Z3Error`](#6-typed-error-hierarchy-catch-the-specific-subclass-not-just-z3error)
7. [`getGlobalParam` returns the effective value, not "user-set"](#7-getglobalparam-returns-the-effective-value-not-user-set)
8. [`toSmt2Benchmark(status = "")` produces malformed SMT2](#8-tosmt2benchmarkstatus---produces-malformed-smt2)
9. [`Z3FuncInterp` entries can fold into the else-value](#9-z3funcinterp-entries-can-fold-into-the-else-value)
10. [`mkRegex` takes a `Z3String`, not a Nim `string`](#10-mkregex-takes-a-z3string-not-a-nim-string)
11. [`Z3_mk_re_range` takes `Z3String`, not `Z3Char`](#11-z3_mk_re_range-takes-z3string-not-z3char)
12. [`(char.to_bv (_ Char N))` doesn't fold to a BV numeral](#12-charto_bv-_-char-n-doesnt-fold-to-a-bv-numeral)
13. [Solver param `model = false` is silently ignored by Z3 4.13](#13-solver-param-model--false-is-silently-ignored-by-z3-413)
14. [`--threads:on` requires `{.gcsafe.}` on thread procs that call wrapper FFI](#14---threadson-requires-gcsafe-on-thread-procs-that-call-wrapper-ffi)

---

## 1. Floating-point `==` uses IEEE semantics — NaN ≠ NaN

**Symptom.** Your assertion `mkFloat32(NaN) == mkFloat32(NaN)` is
false. `not (x == x)` is sat for some `x`. Algebraic identities like
`x + 0.0 ≡ x` fail when `x` is NaN.

**Cause.** IEEE 754 specifies that NaN compares unequal to everything
including itself, and `+0.0 == -0.0` is true. This is what users of FP
code overwhelmingly want.

**Wrapper behaviour.** `==` and `!=` on `Z3Fp[E, S]` map to
`Z3_mk_fpa_eq`, **not** structural equality. This is the **only** typed
family where `==` diverges from structural identity — every other
family (`Z3Int`, `Z3BitVec[W]`, `Z3Array[K, V]`, `Z3Char`, `Z3Seq[E]`,
`Z3String`, `Z3Regex[B]`, `Z3DatatypeValue[T]`, `Z3RoundingMode`) uses
structural equality via `Z3_mk_eq`.

**What you should do.** When proving algebraic laws about FP code,
condition on `isFinite`: `forall x. (not isNaN(x)) and (not isInf(x))
implies law(x)`. See `examples/float_verification.nim` for the
canonical proof shape. For pointer-identity comparison on FP ASTs,
use `astEqual(a, b)`.

---

## 2. Z3RoundingMode literals are procs, not enum values — `rmRNE()`

**Symptom.** `fpAdd(rmRNE, a, b)` fails to compile with "expected
`Z3RoundingMode`, got `proc()`-like".

**Cause.** v0.5 step 2C consolidated the v0.3 dual representation
(`RoundingMode` Nim enum + `Z3RoundingMode` AST + `mkRoundingMode`
lifter) into a single typed family. The Nim enum was deleted; the
old enum values are now procs returning `Z3RoundingMode`.

**Wrapper behaviour.** `rmRNE()`, `rmRNA()`, `rmRTP()`, `rmRTN()`,
`rmRTZ()` are zero-argument procs (each also has a `(ctx)` form for
explicit-context callers). Call them with parentheses; the result is
a `Z3RoundingMode` AST you pass to `fpAdd` / `fpSub` / `sqrt` / etc.

**What you should do.** Source delta from pre-v0.5 code:

```diff
- let r = mkRoundingMode(rmRNE)        # pre-v0.5
- fpAdd(rmRNE, a, b)                   # pre-v0.5
+ fpAdd(rmRNE(), a, b)                 # v0.5+
+ fpAdd(rmRNE(a.ctx), a, b)            # v0.5+, explicit ctx
```

The infix operators `+ - * /` still default to round-nearest-ties-to-
even and don't take a rounding-mode argument — only the named
`fpAdd` / `fpSub` / `fpMul` / `fpDiv` / `sqrt` / `fma` /
`roundToIntegral` / `toSbv` / `toUbv` forms do.

---

## 3. `newContext()` auto-sets the current-context threadvar

**Symptom.** After creating two contexts in sequence, `currentContext()`
returns the second one. Code that operates implicitly against
"the current context" silently uses the wrong context.

**Cause.** `newContext()` writes the new context into the
`{.threadvar.}` `currentZ3Ctx` slot as a convenience for the common
single-context case (matches Python z3 ergonomics: builders pick up
the context automatically).

**Wrapper behaviour.** Documented in `z3/context` and
[THREADING.md](THREADING.md). The side effect is unconditional —
every `newContext()` call writes the slot.

**What you should do.** When creating a scratch context but wanting
to keep your primary context current, save and restore explicitly:

```nim
let primary = newContext()             # currentContext() == primary
let scratch = newContext()             # currentContext() == scratch (!)
setCurrentContext(primary)             # restored
# ...do work with primary as current...
withContext(scratch):                  # temporary swap
  # scratch is current here
# primary is current again here
```

The pattern is exercised in `tests/tconcurrency.nim`.

---

## 4. Quantifier without a trigger can hang the solver

**Symptom.** `forall(x, f(g(x)) == x)`-shaped assertions cause
`s.check()` to hang indefinitely (or return `zsUnknown` after a
timeout).

**Cause.** Z3 instantiates universally-quantified axioms via
*pattern-driven E-matching*. Without an explicit pattern (trigger),
Z3 falls back to MBQI (model-based quantifier instantiation) which
diverges on many natural shapes — particularly recursive
compositions of uninterpreted functions.

**Wrapper behaviour.** `forall(x, body)` passes no pattern by
default; Z3 picks a default trigger or falls back to MBQI. The
wrapper makes the explicit-pattern form available:

```nim
forall(x, body, patterns = @[mkPattern(f(x))])
```

**What you should do.** For any non-trivial axiom over uninterpreted
functions, supply an explicit trigger pattern. The pattern must
mention each bound variable at least once and should align with how
the axiom will be instantiated. See `tests/tquantifier.nim` for
worked examples; `examples/uninterpreted_axioms.nim` shows the
trigger-free case for trivially-decidable problems.

---

## 5. `forall` returns a `Z3Bool` — assert it; don't ignore the result

**Symptom.** `forall(x, x + 0 == x)` compiles, runs, and the solver
ignores it entirely.

**Cause.** `forall` builds an AST — a Z3 boolean expression. It does
not implicitly assert. Calling `forall` without doing anything with
its result is equivalent to writing `42` on a line by itself in C.

**Wrapper behaviour.** `forall[B1, …]` returns `Z3Bool`. The
`{.discardable.}` pragma is **not** applied — you'll get a Nim
warning if you discard the result.

**What you should do.** Always assert the quantifier:
`s.add forall(x, body)`. The same applies to `exists` and `mkPattern`.

---

## 6. Typed error hierarchy: catch the specific subclass, not just `Z3Error`

**Symptom.** Your `except Z3Error as e:` handler catches everything,
including errors you wanted to handle differently. `e.code` gives you
discrimination but `except` clauses can't filter on a field.

**Cause.** v0.5 step 4 introduced 12 typed subclasses of `Z3Error`
(see `z3/error.nim`). The base class still works as a catch-all, but
narrow handlers should target the specific subclass.

**Wrapper behaviour.** `raiseZ3Error` dispatches based on the Z3
error code:

| Code | Subclass |
|---|---|
| `Z3_SORT_ERROR` | `Z3SortMismatchError` |
| `Z3_IOB` | `Z3IndexOutOfBoundsError` |
| `Z3_INVALID_ARG` | `Z3InvalidArgError` |
| `Z3_PARSER_ERROR` / `Z3_NO_PARSER` | `Z3ParseError` |
| `Z3_INVALID_PATTERN` | `Z3InvalidPatternError` |
| `Z3_MEMOUT_FAIL` | `Z3MemoryError` |
| `Z3_FILE_ACCESS_ERROR` | `Z3FileError` |
| `Z3_INTERNAL_FATAL` | `Z3InternalError` |
| `Z3_INVALID_USAGE` | `Z3InvalidUsageError` |
| `Z3_DEC_REF_ERROR` | `Z3RefcountError` |
| `Z3_EXCEPTION` | `Z3OperationError` |

**Naming note:** `Z3SortMismatchError` (not `Z3SortError`) and
`Z3ParseError` (not `Z3ParserError`) because Nim's style-insensitive
identifier rules collide those names with the FFI enum values
(`Z3_SORT_ERROR` ≡ `z3sorterror`, `Z3_PARSER_ERROR` ≡ `z3parsererror`).

**What you should do.** Catch the specific subclass when your code
can recover from that kind:

```nim
try:
  discard parseSmt2String(ctx, untrusted)
except Z3ParseError:
  # malformed input — try a fallback parser
except Z3FileError:
  # file I/O failure
except Z3Error:
  # any other Z3 error — generic recovery
```

The base-class `except Z3Error` still catches every subclass via
inheritance.

---

## 7. `getGlobalParam` returns the effective value, not "user-set"

**Symptom.** `getGlobalParam("verbose")` returns `some("0")` even
though you never called `setGlobalParam("verbose", ...)`. You expected
`none(string)` to mean "not set."

**Cause.** Z3's `Z3_global_param_get` returns the **effective** value
of a known parameter — the current setting if overridden, otherwise
the built-in default. It returns `false` only for parameter names Z3
doesn't recognise.

**Wrapper behaviour.** `getGlobalParam(name): Option[string]` mirrors
the C API:
- `some(v)` — `name` is a parameter Z3 recognises; `v` is its
  effective value
- `none(string)` — `name` is **not** a parameter Z3 recognises

**What you should do.** If you need to track whether *you* (your
code) set a particular parameter, keep a shadow record on the caller
side — Z3 surfaces no signal that distinguishes "user set this" from
"built-in default."

---

## 8. `toSmt2Benchmark(status = "")` produces malformed SMT2

**Symptom.** `parseSmt2String(ctx, toSmt2Benchmark(f))` raises
`Z3ParseError`: "line 2 column 19: invalid command, argument(s)
missing".

**Cause.** Z3's `Z3_benchmark_to_smtlib_string` unconditionally emits
`(set-info :status <s>)`. When the status string is empty, the
emitted SMT2 contains `(set-info :status )` which is syntactically
invalid.

**Wrapper behaviour.** `toSmt2Benchmark` defaults `status =
"unknown"` (a valid SMT-LIB status value). The other three metadata
strings (`name`, `logic`, `attributes`) are properly omitted when
empty.

**What you should do.** Don't override `status` with an empty string.
If you don't have a meaningful status, leave the default
(`"unknown"`) or pass `"sat"` / `"unsat"` if you know it.

---

## 9. `Z3FuncInterp` entries can fold into the else-value

**Symptom.** You assert `f(0) == 7 and f(1) == 11`, extract the
`Z3FuncInterp`, and `fi.len` is `0` or `1` instead of the expected `2`.

**Cause.** Z3 chooses how to represent the model interpretation of
an uninterpreted function. It can store each `(args, value)`
constraint as an explicit entry **or** fold one into the else-value.
The choice is solver-internal and not part of any wire contract.

**Wrapper behaviour.** Surfaces what Z3 returns. `fi.len` reflects
the explicit-entry count; `fi.elseValue` is the fallback.

**What you should do.** Pin **semantic** properties (`evalAt(m, f,
args)` returns the right value), not **table shape** (`fi.len == N`).
Walk the entries via `fi[i]` for the explicit table; use
`evalAt(m, f, args)` to query any point regardless of whether the
solver folded it into the else. See `tests/tfuncinterp.nim` for the
canonical test discipline.

---

## 10. `mkRegex` takes a `Z3String`, not a Nim `string`

**Symptom.** `mkRegex("abc")` fails to compile with "expected
`Z3Seq[E]`, got `string`".

**Cause.** SMT-LIB's `(seq.to.re s)` builder operates on the typed
`Z3Seq[E]` family (specifically `Z3String = Z3Seq[Z3Char]`). The
wrapper preserves that signature.

**Wrapper behaviour.** `mkRegex[E](s: Z3Seq[E]): Z3Regex[Z3Seq[E]]`.
You must construct the string AST first.

**What you should do.** Lift the Nim string via `mkString`:

```nim
let r = mkRegex(mkString("abc"))   # Z3Regex[Z3String]
```

---

## 11. `Z3_mk_re_range` takes `Z3String`, not `Z3Char`

**Symptom.** `range(mkChar('a'), mkChar('z'))` fails to compile —
the wrapper's `range` proc only accepts `Z3String` operands.

**Cause.** SMT-LIB-2.6 declares `re.range` as `(String String) RegEx
String`. Z3's polymorphic sort-checker enforces that contract: passing
`Z3Char` operands raises a sort mismatch at solver time.

**Wrapper behaviour.** `range(lo, hi: Z3String): Z3Regex[Z3String]`.
The wrapper accepts only the SMT-LIB-correct type.

**What you should do.** Pass single-codepoint `Z3String` values:

```nim
let lowerCase = range(mkString("a"), mkString("z"))
```

There's also a string-typed convenience overload:

```nim
let lowerCase = range("a", "z")   # auto-lifts to one-char Z3String
```

---

## 12. `(char.to_bv (_ Char N))` doesn't fold to a BV numeral

**Symptom.** `evalUint(m, c.toBitVec)` raises `Z3InvalidUsageError`:
"AST `(char.to_bv (_ Char N))` does not reduce to a literal BV
numeral."

**Cause.** Z3's evaluator doesn't have a rewrite rule that folds
`Z3_mk_char_to_bv` applied to a literal `Z3Char` to a literal BV. The
expression evaluates to itself rather than to a numeral.

**Wrapper behaviour.** `toBitVec(c: Z3Char): Z3BitVec[18]` builds the
correct AST per the C API; the issue is downstream evaluator
limitations.

**What you should do.** For verification work, use `smtValid` against
an explicit BV literal instead of `evalUint`:

```nim
let lhs = mkChar('a').toBitVec
let rhs = mkBitVec[18](ord('a').uint32)
check smtValid(lhs == rhs)
```

The semantic equivalence holds regardless of whether Z3's evaluator
folds the expression.

---

## 13. Solver param `model = false` is silently ignored by Z3 4.13

**Symptom.** You set `model = false` to skip model construction;
`s.model()` still returns a model after a sat `check()`.

**Cause.** Z3 4.13.3 doesn't honour the `model` solver parameter —
the model is always available after sat. This is an upstream Z3
behaviour, not a wrapper bug.

**Wrapper behaviour.** Documented in `z3/solver`'s `setParams`
docstring. The wrapper passes `model = false` through to Z3 as
requested; Z3 ignores it.

**What you should do.** If you want to skip model retrieval for
performance, simply don't call `s.model()`. The `model = false`
parameter has no observable effect on Z3 4.13; the parameter
contract may be honoured in a later Z3 release.

---

## 14. `--threads:on` requires `{.gcsafe.}` on thread procs that call wrapper FFI

**Symptom.** Building with `--threads:on` (Nim 2's default for
`Thread` types) produces: "`body` is not GC-safe as it calls
`newContext`."

**Cause.** Z3's `Z3_set_error_handler` is a `{.cdecl.}` FFI call —
it doesn't touch Nim's heap. But the wrapper's `softlink` library
routes through a function pointer that Nim's safety analysis can't
see through, so it conservatively marks the call as GC-unsafe.

**Wrapper behaviour.** The FFI calls are genuinely GC-safe; the
classification is a conservative-analysis false positive. The
wrapper doesn't blanket-annotate every FFI proc as `gcsafe` because
doing so would suppress legitimate warnings elsewhere.

**What you should do.** Annotate thread procs with `{.gcsafe.}` (the
positive assertion) and wrap the FFI-calling block in
`{.cast(gcsafe).}:`:

```nim
proc workerBody(idx: int) {.thread, gcsafe.} =
  {.cast(gcsafe).}:
    let ctx = newContext()
    let s = newSolver()
    # ... rest of the worker ...
```

See `tests/tconcurrency.nim` for the canonical pattern.

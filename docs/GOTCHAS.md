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
15. [`interrupt(ctx)` is a cross-thread signal — same-thread calls are no-ops](#15-interruptctx-is-a-cross-thread-signal--same-thread-calls-are-no-ops)
16. [Z3 ASTs don't drop into `Table[K, V]` / `HashSet[T]` directly](#16-z3-asts-dont-drop-into-tablek-v--hashsett-directly)
17. [`getProof` returns nil unless the context was built with proofs enabled](#17-getproof-returns-nil-unless-the-context-was-built-with-proofs-enabled)
18. [`modelCompletion = false` evaluates unconstrained variables to themselves](#18-modelcompletion--false-evaluates-unconstrained-variables-to-themselves)
19. [`Z3Seq.replace` is first-occurrence only — not replace-all](#19-z3seqreplace-is-first-occurrence-only--not-replace-all)
20. [Mixing the raw §N7.8 fixedpoint callback procs with `setHandlers` trips a debug assert](#20-mixing-the-raw-n78-fixedpoint-callback-procs-with-sethandlers-trips-a-debug-assert)
21. [Fixedpoint export callbacks only fire under `engine=spacer`, and the engine locks at first use](#21-fixedpoint-export-callbacks-only-fire-under-enginespacer-and-the-engine-locks-at-first-use)
22. [`clearHandlers` doesn't deregister at the Z3 level — it just goes dormant](#22-clearhandlers-doesnt-deregister-at-the-z3-level--it-just-goes-dormant)
23. [Interrupting from inside a fixedpoint handler cancels the query gracefully](#23-interrupting-from-inside-a-fixedpoint-handler-cancels-the-query-gracefully)
24. [`indexOfRe(...) == -1` does not mean "no match" unless you bound the length](#24-indexofre--1-does-not-mean-no-match-unless-you-bound-the-length)

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
(see `z3/error.nim`); a 13th, `Z3FeatureUnavailableError`, was added
later for the multi-version compat story (below). The base class
still works as a catch-all, but narrow handlers should target the
specific subclass.

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

`Z3FeatureUnavailableError` is the odd one out: it has no `Z3ErrorCode`
counterpart and is never raised by `raiseZ3Error`. It's raised directly
by wrapper procs (`getNumeralSign`, `hasSize`, `replaceAll`) sitting atop
a `{.optional.}` FFI symbol, *before* the FFI call is attempted, when the
symbol is unavailable on the loaded libz3 — see
[docs/MULTI_VERSION.md](../docs/MULTI_VERSION.md) for the multi-version
compat story this supports.

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

---

## 15. `interrupt(ctx)` is a cross-thread signal — same-thread calls are no-ops

**Symptom.** You call `ctx.interrupt()` from the same thread that is
about to run `s.check()` and the check still runs to completion.

**Cause.** `Z3_interrupt` sets a cancellation flag on the context
that Z3's decision procedures poll at safe points *inside* the
running operation. The behaviour depends on when you set it:

- **During an in-flight operation (the intended use case).** A
  watchdog thread sets the flag; the running `check()` polls it
  at the next safe point and returns `zsUnknown`. This is the
  cross-thread cancellation guarantee the wrapper exposes.
- **Between operations.** Z3 auto-clears the flag at the start of
  most operations (the exact rule varies by Z3 version), so
  pre-setting it before a future `check()` is unreliable. Treat
  `interrupt` strictly as a *signal during* a running call, not
  as a latched "next call should fail" mode.

The cleanest mental model is: `interrupt` is a signal from one
thread to another, like `pthread_kill(thread, SIGUSR1)`. It only
has an addressee — the in-flight operation — when something is
actually running.

**Wrapper behaviour.** `Z3Context.interrupt` is the documented
exception to the one-context-one-thread discipline (see
`docs/THREADING.md`). The proc is `gcsafe` and safe to call from
any thread.

**What you should do.** Use `interrupt` exactly as you would use
cross-thread cancellation in Go or Rust: spawn a watchdog thread
that calls `ctx.interrupt()` when a timeout elapses or the user
hits Ctrl-C, while the main thread is in `s.check()`. See
`tests/tinterrupt.nim` for the canonical pattern.

If you need a single-thread timeout instead, set the `timeout`
param on `Z3Params` and pass it to `s.setParams(p)`; Z3's internal
timer polls the same cancellation hook.

---

## 16. Z3 ASTs don't drop into `Table[K, V]` / `HashSet[T]` directly

**Symptom.** `var t: Table[Z3Int, string]` fails with `type mismatch:
got 'Z3Bool' for 't.data[h].key == key' but expected 'bool'`.

**Cause.** Z3 typed ASTs overload `==` to return `Z3Bool` (SMT-level
semantic equality), so `s.add(x == y)` builds an SMT formula. But
`std/tables` and `std/sets` require `==(K, K): bool` (Nim-level
structural equality). The two contracts can't coexist on the same
type without breaking one of the canonical patterns; the wrapper
keeps `==: Z3Bool` because that's where the canonical use lies.

**Wrapper behaviour.** `astHash[T: Z3Term](a: T): uint` is the
exported structural-identity hash (it walks Z3's hashcons, so two
ASTs built from structurally-identical syntax share a hash). It is
*not* automatically registered as `hash[T: Z3Term]: Hash` because
that would only solve half the equation — `==` still returns the
wrong type for table use.

**What you should do.** Wrap the AST in a Nim `distinct` type whose
`==` uses `astEqual` (Z3-side raw-pointer identity, returning Nim
`bool`) and whose `hash` uses `astHash`. The wrapper procs must
live at module scope so std/tables finds them during generic
instantiation:

```nim
import std/[tables, hashes]
import z3

type Z3IntKey = distinct Z3Int
proc `==`(a, b: Z3IntKey): bool = astEqual(Z3Int(a), Z3Int(b))
proc hash(k: Z3IntKey): Hash = cast[Hash](astHash(Z3Int(k)))

var t: Table[Z3IntKey, string]
t[Z3IntKey(mkInt(1))] = "one"
```

See `tests/thash.nim` for the canonical pattern. The same shape
works for `HashSet[Z3IntKey]` and for any other typed family
(`distinct Z3BitVec[8]`, `distinct Z3Char`, …).

---

## 17. `getProof` returns nil unless the context was built with proofs enabled

**Symptom.** `s.getProof()` after a sat `check()` raises
`Z3InvalidUsageError: nil proof returned. Most likely cause: proof
generation wasn't enabled on the context.`

**Cause.** Z3 only assembles proof objects when the context was
built with the `proof` global param set to `true`. By default it
isn't — proof construction is expensive, so Z3 elides it unless you
opt in. `newContext()` with no params makes a proof-disabled
context, so the otherwise-correct `solver.add(...); s.check(); s.getProof()`
path returns nil at the last step.

**Wrapper behaviour.** The wrapper checks for nil at the FFI
boundary and raises the typed error. The error message names the
likely cause but doesn't spell out the fix.

**What you should do.** Pass `("proof", "true")` to `newContext`:

```nim
let ctx = newContext(("proof", "true"))
let s = newSolver()
s.add (x + y == mkInt(10)) and not (y == mkInt(10) - x)
doAssert s.check() == zsUnsat
let p = s.getProof()        # now returns a real Z3Proof
```

For the full proof-rule surface (42-entry `ProofRule` enum,
`unpackProof`), see `z3/proof`. Proofs are only meaningful after a
`zsUnsat` outcome; on `zsSat` Z3 has no proof to construct.

---

## 18. `modelCompletion = false` evaluates unconstrained variables to themselves

**Symptom.** `m.eval(x, modelCompletion = false).toInt` raises
`Z3InvalidUsageError: not a literal int` for a variable `x` the
solver didn't constrain.

**Cause.** With `modelCompletion = true` (the default), Z3 invents
a witness for every unconstrained variable so `eval` always returns
a literal. With `false`, the model **does not** complete: an
unconstrained variable evaluates *back to itself* (as an AST), and
downstream extractors like `toInt` / `toBool` fail because there's
no literal value to extract.

**Wrapper behaviour.** `eval[T]` returns whatever Z3 hands back —
typed correctly, but possibly still symbolic. The downstream
`toInt` raises because it expects a numeric literal.

**What you should do.** Pick your model-completion mode
deliberately:

- **Default (`modelCompletion = true`).** Use for "give me a
  concrete witness for every variable" workflows. Every `toInt` /
  `toBool` etc. will succeed.
- **`modelCompletion = false`.** Use when you specifically want to
  detect which variables the solver left free. After `eval`,
  call `astEqual(result, originalVar)` to test "did the model not
  pin this?" or `toIntOpt` to get a `none(int)` instead of an
  exception.

```nim
let yEval = m.eval(y, modelCompletion = false)
if astEqual(yEval, y):
  echo "y is unconstrained — model didn't pin a value"
else:
  echo "y = ", yEval.toInt
```

---

## 19. `Z3Seq.replace` is first-occurrence only — not replace-all

**Symptom.** `seq.replace(needle, repl)` modifies only the *first*
occurrence of `needle`, leaving subsequent matches untouched.
Surprising if you're coming from Nim's stdlib `strutils.replace`
(which is replace-all).

**Cause.** `Z3_mk_seq_replace` in Z3's C API replaces the first
match; Z3's replace-all surface is a separate FFI entry point.

**Wrapper behaviour.** `replace` faithfully wraps the
first-occurrence FFI. The contract matches Z3 / SMT-LIB, not Nim's
stdlib.

**What you should do.** For *literal* replace-all, v2.2.0 ships
`replaceAll` (opt-in `-d:z3WithSeqReplaceAll`; Z3 decides it). The
**regex** replace variants also ship opt-in: `replaceRe` (first match,
`-d:z3WithSeqReplaceRe`) and `replaceReAll` (all matches,
`-d:z3WithSeqReplaceReAll`), wrapping `str.replace_re{,_all}`. Both
build CORRECT terms, but **Z3's solver returns `unknown` — in both
directions — on `str.replace_re{,_all}` constraints even for fully
concrete inputs** (verified on Z3 4.16.0). Their contract is correct
*term construction* / SMT-LIB export, not solver-decidability: use them
to build constraints or emit SMT-LIB, not to `smtValid`/`check()` a
concrete equality over the result (see §7 of RFC-regex-index). For
regex-driven position/existence work that *is* decidable, use the
v2.2.0 regex-index helpers `indexOfRe` / `matchStartsAt` / `containsRe`
(see `z3/regex` and GOTCHAS #24); a regex replace-all can also be
encoded as a fixed-point loop over `indexOfRe` + `substr` if you need a
decidable substitute. Plain first-occurrence `replace` remains
always-on.

---

## 20. Mixing the raw §N7.8 fixedpoint callback procs with `setHandlers` trips a debug assert

**Symptom.** Calling `fp.init(...)` / `fp.setReduceAssignCallback(...)`
/ `fp.setReduceAppCallback(...)` / `fp.addCallback(...)` on a
`Z3Fixedpoint` that already has `setHandlers` installed on it (or
vice versa) fails an `assert` in non-release builds:
`"the typed setHandlers surface (z3/fixedpoint_callbacks) has already
been used on this fp — the raw and typed callback surfaces are
mutually exclusive per fp"`.

**Cause.** Both surfaces ultimately write the **same** Z3-side
`state` pointer / callback registration slot on the underlying
`Z3_fixedpoint` handle (`Z3_fixedpoint_init` and
`Z3_fixedpoint_add_callback` are shared plumbing). Using both on one
`Z3Fixedpoint` means the second surface silently overwrites what the
first one's `{.cdecl.}` shims depend on — type confusion (the raw
surface's `state` isn't a `FixedpointCtxBox`) or a use-after-free,
depending on call order (ADR-FC-0009).

**Wrapper behaviour.** Each of the four raw §N7.8 procs
(`init`/`setReduceAssignCallback`/`setReduceAppCallback`/
`addCallback`) asserts `fp.cbBoxRef.isNil` before running; `setHandlers`
asserts `not fp.rawCbUsed` before installing. Both guards are `when
not defined(release)`-gated — zero cost in `-d:release`/`-d:danger`
builds, and **not checked** there, so mixing the two surfaces in a
release build is silent undefined behavior rather than a caught
error.

**What you should do.** Pick one callback surface per `Z3Fixedpoint`
and stay on it for that handle's lifetime: the typed `setHandlers`
(newLemma/predecessor/unfold export events only — v2.1.0) or the raw
§N7.8 procs (needed today for `reduceApp`/`reduceAssign`, since the
typed reduce surface is deferred to v2.2). If you need both event
families, allocate two separate `Z3Fixedpoint` handles rather than
sharing one.

---

## 21. Fixedpoint export callbacks only fire under `engine=spacer`, and the engine locks at first use

**Symptom.** `fp.setHandlers(Z3FixedpointHandlers(newLemma: ...))`
compiles and runs with no error, but the handler never fires — even
though rules were added and `query` returned a result.

**Cause.** `newLemma`/`predecessor`/`unfold` are **Spacer-engine**
export events (`Z3_fixedpoint_add_callback`'s dispatch is a Spacer
feature; `bmc`/`datalog` don't call it). Registration happens
**lazily, at the first query** (not at `setHandlers` time — the
A2-redesign), because Z3 doesn't expose a way to read back which
engine `auto-config` resolved to ahead of time. If that first query
runs under a non-Spacer engine, registration is attempted, fails
silently (Z3 throws internally; the wrapper catches it), and — this
is the sharp edge — **Z3 permanently locks the fixedpoint's engine at
the first engine-touching operation**, so a later
`setParams(engine=spacer)` call on that *same* `fp`, issued after a
query has already run, cannot retroactively make export callbacks
start firing.

**Wrapper behaviour.** `setHandlers` is pure intent-recording — it
never raises on engine grounds and doesn't care about install order
relative to `setParams(engine=...)`. Activation retries automatically
on every query until it first succeeds (tracked by an internal
`exportActivated` latch), so `setHandlers` before **or** after
`setParams(engine=spacer)` both work, as long as the engine is
Spacer **before the first query on that `fp`**. There is no
*automatic* exception, warning, or thrown error signaling "this engine
doesn't support export callbacks" — the handler just never fires; the
one signal you can poll for it is `fp.handlersActive()` (below).

**What you should do.** Ensure Spacer is selected before the *first*
`query`/`queryRelations`/`queryFromLevel` call on any `fp` you intend
to install export handlers on:

```nim
let p = newParams()
p.set("engine", "spacer")   # the default, but make it explicit
fp.setParams(p)
```

If you need to verify callbacks are actually wired, don't rely on
`hasHandlers` (it only reports what you *installed*, not what Z3
*activated*) — call `fp.handlersActive()` instead: `true` once the
engine has actually accepted the callback registration (i.e. the
first query ran under Spacer), `false` if `setHandlers` was never
called or every query so far ran under a non-Spacer engine. It's a
direct query, not a hand-rolled fire-counter:

```nim
discard fp.query(...)
if not fp.handlersActive():
  echo "export callbacks never activated -- check fp's engine"
```

---

## 22. `clearHandlers` doesn't deregister at the Z3 level — it just goes dormant

**Symptom.** After calling `fp.clearHandlers()`, you'd expect Z3 to
stop calling back into the wrapper entirely. Internally, Z3 is still
invoking the `{.cdecl.}` shim on every event — it just does nothing
observable, because the shim's handler lookup comes back nil.

**Cause.** Z3's C API has no "deregister callback" call —
`Z3_fixedpoint_add_callback`'s registration, once made, is sticky for
the `Z3_fixedpoint` object's lifetime (ADR-FC-0008). There is no FFI
entry point to undo it.

**Wrapper behaviour.** `clearHandlers` resets the installed handler
set on `fp`'s box to all-`nil` **in place** — the box itself (and the
Z3-side `state` pointer into it) stays live for `fp`'s whole
lifetime. Each shim (`newLemmaShim`/`predecessorShim`/`unfoldShim`)
checks its handler field for `nil` on every fire and no-ops when it
is — so the *observable* effect matches "stopped," even though
nothing was deregistered at the Z3 level. Calling `setHandlers` again
later on the same `fp` reuses the same stable box and simply repopulates
the handler fields in place — at the Z3 level, this is still no
re-registration and no double-fire risk.

**Correction (this claim used to stop there and call it "always
safe" — that's incomplete).** "Repopulates" means **replaces
wholesale**, not merges: whatever closure was installed for a field
before `setHandlers`/`clearHandlers` runs is gone, not chained. Two
sharp edges follow from that:

- **M2 — a `Z3LemmaLog` from `collectLemmas` silently stops growing.**
  If you called `let log = fp.collectLemmas(...)` and are holding onto
  `log`, a *later* `setHandlers` or `clearHandlers` call on that same
  `fp` detaches `collectLemmas`' accumulator closure from the box — the
  log freezes at whatever it already collected. No error, no crash;
  entries already in the log stay valid and readable (they're
  independent `inc_ref`'d copies), but nothing new is appended. See
  `Z3LemmaLog`'s and `collectLemmas`' doc comments.
- **Also true as of the H1 fix:** a handler field that was `nil` at
  the time export callbacks first activated (see #21) and is later set
  non-nil via `setHandlers` **will** now start firing on the very next
  query — it is not stuck dormant forever the way a field that goes
  non-nil→nil is (see the symptom above). Don't assume "I already
  queried once, so my newly-added handler needs a fresh `fp`" — it
  doesn't; the existing box picks it up.

**What you should do.** Treat `clearHandlers`/installing `nil` fields
as "go quiet," not "release resources" — there's no cleanup to time
around it, and no way to shrink `fp`'s Z3-side footprint short of
dropping the whole `Z3Fixedpoint` handle. If you're cycling through
many handler configurations on one long-lived `fp`, `setHandlers`
in place is the intended pattern (and is what makes that stable-box
invariant load-bearing in the first place — see the module docstring
in `z3/fixedpoint_callbacks`). If you need to ADD a handler without
detaching something already installed (most importantly, a live
`Z3LemmaLog`), don't call `setHandlers`/`collectLemmas` with a fresh
handler set — fold the new handlers into what's already on `fp` with
`combine`:

```nim
let log = fp.collectLemmas()
# ...later, add a predecessor handler WITHOUT freezing `log`...
fp.setHandlers(combine(fp.handlers, Z3FixedpointHandlers(
  predecessor: proc() {.closure, raises: [].} = echo "predecessor fired")))
```

---

## 23. Interrupting from inside a fixedpoint handler cancels the query gracefully

**Symptom.** You want an escape hatch to abort a runaway
`fp.query(...)` from inside a `newLemma`/`predecessor`/`unfold`
handler — e.g. stop after N lemmas, or on a wall-clock budget checked
per-callback.

**Cause / wrapper behaviour.** Calling `fp.ctx.interrupt()` from
inside a handler is the **sanctioned abort channel** (RFC C1(d)).
Internally, Z3's Spacer/Datalog query loop reports cancellation very
differently from `Z3Solver.check()` — it throws a C++ exception
(surfaced as `Z3OperationError`/`Z3_EXCEPTION`, message `"canceled"`)
rather than returning gracefully. The wrapper's `query` /
`queryRelations` / `z3/spacer.queryFromLevel` all catch exactly that
narrow discriminator and translate it: the in-flight call returns
`zsUnknown`, and `fp.getReasonUnknown()` reads `"interrupted"` — the
same contract `Z3Solver.check()` gives you on interrupt, and the same
string `Z3Solver.reasonUnknown()` reports. Any other `Z3Error` (a
genuine internal fault, not a cancellation) is **not** swallowed by
this translation and still raises normally.

**What you should do.** Call `fp.ctx.interrupt()` from inside a
handler exactly as you would call it from a watchdog thread against a
`Z3Solver` (see [THREADING.md](THREADING.md)'s `interrupt` section) —
it's synchronous, same-thread, and takes effect at the next callback
firing or safe point, not necessarily instantly. After the call
returns, check `fp.getReasonUnknown() == "interrupted"` to
distinguish "I cancelled this" from a genuine `zsUnknown` (resource
limits, incompleteness).

---

## 24. `indexOfRe(...) == -1` does not mean "no match" unless you bound the length

**Symptom.** You assert `indexOfRe(s, re, matchBound(k)) == mkInt(-1)`
to mean "`re` does not occur in `s`", and the solver finds a model
where `s` clearly *does* contain a match — an apparent unsoundness.

**Cause.** `indexOfRe` (and the `matchStartsAt` it's built on) is a
**bounded encoding**, not a native Z3 operation. It unrolls the match
test over positions `i ∈ [0, bound]` as an `ite`-chain. It is
*unconditionally sound* — a returned index `≥ 0` is always a real
match — but it is *complete only if `len(s) ≤ bound`*. When the string
can be longer than `bound`, `-1` means "no match in `[0, bound]`", not
"no match anywhere": a match starting past `bound` is invisible to the
encoding, so `== -1` is satisfiable even though a longer `s` matches.

**What you should do.** If you rely on the `-1` (no-match) direction,
discharge the completeness obligation by also constraining the length:
`s.boundHolds(matchBound(k))` (i.e. `len(s) ≤ k`) asserts exactly what
`indexOfRe` needs to be complete. Assert it on the **same** `s` you
pass to `indexOfRe`. The positive direction (index `≥ 0` ⇒ real match)
needs no such guard. Note also the nullable-`re` caveat: for a `re`
that matches the empty string, `matchStartsAt` is trivially true at
every in-range position — see the `matchStartsAt` docstring in
`z3/regex`.

**Related but distinct opacity:** `indexOfRe`'s completeness trap above
is about a *bound* you must discharge; the opt-in `replaceRe` /
`replaceReAll` (`-d:z3WithSeqReplaceRe{,All}`, wrapping
`str.replace_re{,_all}`) have a different, more fundamental limit —
Z3's solver answers `unknown` (not `sat`/`unsat`) on those constraints
even for fully concrete inputs, with no bound that fixes it. Don't
reach for `replaceRe`/`replaceReAll` expecting `smtValid`/`check()` to
decide anything about the result; they're for term construction / SMT-
LIB export only. See GOTCHAS #19 and RFC-regex-index.md §7.

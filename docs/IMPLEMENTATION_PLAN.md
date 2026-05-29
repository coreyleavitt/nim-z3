# Implementation Plan — `nimlibs/z3`

A type-safe, memory-safe, idiomatic Nim wrapper for the Z3 SMT solver.

**Status**: planning, validated. The spike in `spike/spike.nim` confirmed every architectural assumption end-to-end (see [SPIKE_FINDINGS.md](SPIKE_FINDINGS.md) for what it proved). Two softlink bugs surfaced during the spike were fixed upstream ([coreyleavitt/softlink#11](https://github.com/coreyleavitt/softlink/issues/11), [#12](https://github.com/coreyleavitt/softlink/issues/12)) before this plan was finalised. Type idioms below are the **validated** versions; they're what the spike actually compiled and ran against Z3 4.13.3.

**Audience**: future-me, future contributors, anyone deciding whether this library fits their use case.

---

## 1. Goals and non-goals

### Goals (in priority order)

1. **Memory safety**. Z3 uses reference-counted C objects (`Z3_inc_ref` / `Z3_dec_ref`). The wrapper must make leaks, double-frees, and use-after-free *impossible* via the type system, not "rare with care."

2. **Type safety**. Z3's C API is dynamically sort-checked — passing a Bool where an Int is expected returns an error at runtime. The wrapper should use **phantom sort types** so the Nim compiler catches sort mismatches at compile time. Real cost; real value; consistent with the rest of nimlibs.

3. **Lifecycle correctness**. Z3 has parent-child relationships: ASTs live in contexts, models live in solvers, etc. The wrapper must enforce these via Nim's ref-and-=destroy machinery so child lifetimes are bounded by parents *by construction*.

4. **Idiomatic Nim**. `Option[T]` for sat/unsat/unknown, sumtypes for results, exceptions for unexpected errors, `=destroy` for resource discipline, `$` for pretty-printing.

5. **Multi-version Z3 support**. Z3's API evolves; some symbols are version-gated. softlink's optional-symbols feature lets us target a range (Z3 ≥ 4.10) with explicit per-symbol availability.

6. **Discoverable from `import z3`**. One top-level module re-exports the user-facing surface. Submodules organize implementation; users shouldn't have to know they exist.

7. **Documented, with examples**. Every public type and proc has a docstring; the README has runnable examples for the canonical use cases.

### Non-goals

- **Z3 internals** — we don't reimplement any solving logic. We wrap.
- **Higher-level constraint DSL** — that's a *consumer's* responsibility (proptest's `symex.nim` will build one). This library exposes raw Z3 capabilities.
- **A teaching tool** — the README links to Z3 documentation; we don't recreate Z3's tutorial.
- **Bindings for every Z3 API** — v0.1 covers core sort/AST/solver capabilities. Tactic combinators, fixedpoint, custom theories, parametric polymorphism over user datatypes — later versions.
- **CVC5 / Yices / MathSAT backends** — Z3 only. The "abstract over SMT solvers" pattern adds complexity without clear value; Z3 is dominant for our use cases.
- **Static linking as the default path** — see [LINKING.md](LINKING.md) (planned). Dynamic + softlink is the default; static may be a future opt-in (`-d:z3Static`).

---

## 2. The API at three layers

### Layer 1 — raw FFI (`z3/ffi.nim`)

Direct softlink `dynlib` block declaring Z3's C API. Opaque types use `bycopy importc` so Nim emits the proper Z3 typedef names; the procs match Z3's C signatures verbatim. **Not user-facing.**

**Validated** (spike confirmed compiles + runs against Z3 4.13.3):

```nim
# Excerpt — actual file will declare ~150-200 symbols across the v0.1 surface.

# --- opaque-pointer types (Z3's `typedef struct _Z3_X * Z3_X;` pattern) ---
#
# Nim convention: identifiers are case- and underscore-insensitive, so
# `Z3_context` (C typedef) collides with `Z3Context` (our idiomatic ref
# type). Prefix raw FFI types with `RawZ3X`; reserve the unprefixed
# `Z3X` for the idiomatic Nim wrapper layer.
#
# The `bycopy importc` idiom: Nim sees these as value-typed opaque
# objects (no pointer auto-wrapping) and emits the importc name
# directly (e.g. `Z3_config`, not `void*`). This is what makes
# softlink's `_Static_assert` accept them as compatible with z3.h's
# typedefs.
type
  RawZ3Config*  {.importc: "Z3_config",  header: "z3.h", bycopy.} = object
  RawZ3Context* {.importc: "Z3_context", header: "z3.h", bycopy.} = object
  RawZ3Sort*    {.importc: "Z3_sort",    header: "z3.h", bycopy.} = object
  RawZ3Ast*     {.importc: "Z3_ast",     header: "z3.h", bycopy.} = object
  RawZ3Symbol*  {.importc: "Z3_symbol",  header: "z3.h", bycopy.} = object
  RawZ3Solver*  {.importc: "Z3_solver",  header: "z3.h", bycopy.} = object
  RawZ3Model*   {.importc: "Z3_model",   header: "z3.h", bycopy.} = object
  RawZ3App*     {.importc: "Z3_app",     header: "z3.h", bycopy.} = object
  RawZ3FuncDecl*{.importc: "Z3_func_decl", header: "z3.h", bycopy.} = object

# Nil checks for the opaque value types — needed because the bycopy
# emission doesn't expose the underlying pointer for the standard
# `isNil` to bind to. Cheap cast through `pointer`.
proc isNil*(x: RawZ3Config | RawZ3Context | RawZ3Sort | RawZ3Ast |
            RawZ3Symbol | RawZ3Solver | RawZ3Model | RawZ3App |
            RawZ3FuncDecl): bool {.inline.} =
  cast[pointer](x) == nil

# --- Z3 enums via importc + size: sizeof(cint) ---
#
# These map to Z3's named enum types at the C level. Without the
# size pragma, Nim emits an incompatible enum width; without importc,
# softlink's `_Static_assert` rejects the binding as a signature
# mismatch (Nim enums are not type-compatible with named C enums
# even at the same width).
type
  Z3LBool* {.importc: "Z3_lbool", header: "z3.h", size: sizeof(cint).} = enum
    Z3_L_FALSE = -1, Z3_L_UNDEF = 0, Z3_L_TRUE = 1

  Z3ErrorCode* {.importc: "Z3_error_code", header: "z3.h",
                 size: sizeof(cint).} = enum
    Z3_OK = 0, Z3_SORT_ERROR = 1, Z3_IOB = 2, Z3_INVALID_ARG = 3,
    Z3_PARSER_ERROR = 4, Z3_NO_PARSER = 5, Z3_INVALID_PATTERN = 6,
    Z3_MEMOUT_FAIL = 7, Z3_FILE_ACCESS_ERROR = 8, Z3_INTERNAL_FATAL = 9,
    Z3_INVALID_USAGE = 10, Z3_DEC_REF_ERROR = 11, Z3_EXCEPTION = 12

# --- softlink dynlib block ---

dynlib "libz3.so(.4|.4.13|.4.12|.4.11|.4.10|)":
  proc Z3_mk_config(): RawZ3Config {.cdecl, header: "z3.h".}
  proc Z3_del_config(cfg: RawZ3Config) {.cdecl, header: "z3.h".}
  proc Z3_mk_context_rc(cfg: RawZ3Config): RawZ3Context
    {.cdecl, header: "z3.h".}
  proc Z3_del_context(ctx: RawZ3Context) {.cdecl, header: "z3.h".}

  proc Z3_inc_ref(ctx: RawZ3Context, a: RawZ3Ast) {.cdecl, header: "z3.h".}
  proc Z3_dec_ref(ctx: RawZ3Context, a: RawZ3Ast) {.cdecl, header: "z3.h".}

  proc Z3_mk_int_sort(ctx: RawZ3Context): RawZ3Sort {.cdecl, header: "z3.h".}
  proc Z3_mk_bool_sort(ctx: RawZ3Context): RawZ3Sort {.cdecl, header: "z3.h".}

  proc Z3_solver_check(ctx: RawZ3Context, s: RawZ3Solver): Z3LBool
    {.cdecl, header: "z3.h".}
  proc Z3_get_error_code(ctx: RawZ3Context): Z3ErrorCode
    {.cdecl, header: "z3.h".}
  proc Z3_ast_to_string(ctx: RawZ3Context, a: RawZ3Ast): cstring
    {.cdecl, header: "z3.h".}
  # ... etc
```

The `header:` pragma per proc enables softlink's `_Static_assert` verification: signatures are checked against `z3.h` at compile time, catches API drift across Z3 versions. **Works under both `nim c` and `nim cpp` backends** (verified after fixing softlink #11 and #12).

### Layer 2 — idiomatic Nim (`z3.nim` + submodules)

Public, user-facing. Types carry sort information; lifecycle is managed via `=destroy`; errors raise `Z3Error`; the API reads like normal Nim.

```nim
# What users see:
import z3

let ctx = newContext()
let x = ctx.mkIntVar("x")       # Z3Ast[IntSort]
let y = ctx.mkIntVar("y")       # Z3Ast[IntSort]
let p = (x + y == ctx.mkInt(10)) and (x > ctx.mkInt(3))   # Z3Ast[BoolSort]

let s = ctx.mkSolver()
s.assert(p)
case s.check():
of zsSat:
  let m = s.model()
  echo "x = ", m[x].toInt          # 4 or 5 or 6 or 7
  echo "y = ", m[y].toInt
of zsUnsat:
  echo "no solution"
of zsUnknown:
  echo "Z3 couldn't decide: ", s.reasonUnknown
```

Three things worth noting:
- `Z3Ast[IntSort]` and `Z3Ast[BoolSort]` are distinct types. The `+` operator is defined for `(Z3Ast[IntSort], Z3Ast[IntSort]) -> Z3Ast[IntSort]`; trying to add a Bool to an Int is a compile error.
- `newContext` returns a `ref Z3Context`. Every `Z3Ast` holds a reference to its parent context, so the context can't be destroyed while ASTs reference it. Lifetimes enforced by the type system.
- `s.check()` returns a `Z3Status` sumtype, not a raw enum, so we can attach reasons to `zsUnknown` etc.

### Layer 3 — high-level macros (future, NOT v0.1)

```nim
# Maybe in v0.3:
let m = solve:
  declare x, y: Int
  assert x + y == 10
  assert x > 3
  assert y > 0
echo m[x], " ", m[y]
```

Out of scope for v0.1. Mentioned here so the architecture leaves room.

---

## 3. The lifetime problem

This is the most important design decision in the wrapper. Z3 objects (`Z3_ast`, `Z3_sort`, `Z3_solver`, `Z3_model`) use **reference counting via `Z3_inc_ref` / `Z3_dec_ref`**. Each object lives within a parent context; destroying the context invalidates all children.

**Wrong**: hope users call dec_ref. They won't. Leaks.
**Wrong**: tie dec_ref to `=destroy` without tracking parent context. Use-after-free on context destruction.

**Right**: each Nim wrapper type holds a *strong reference* to its parent. Nim's GC keeps the parent alive until all children are destroyed; `=destroy` on a child dec_refs cleanly; `=destroy` on the context destroys the Z3 context only when all children are gone.

### Type sketch (**validated**)

The spike confirmed this idiom compiles cleanly under Nim 2's `=destroy` / `=copy` hook rules. Nim 2 requires the hook signature to take the underlying object type (not the `ref` wrapper); the validated pattern uses an `Own` suffix on the underlying type and the bare name as the `ref` alias.

```nim
type
  # Z3Context: ref Z3ContextOwn so =destroy can hook on the underlying object.
  Z3ContextOwn = object
    raw: RawZ3Context
    cfg: RawZ3Config
    errorMode*: ErrorMode      # exception vs swallow vs collect (future)
  Z3Context* = ref Z3ContextOwn

  Z3Sort*[S: static SortTag] = object
    raw: RawZ3Sort
    ctx: Z3Context             # keeps context alive (value-type w/ ref to parent)

  Z3Ast*[S: static SortTag] = object
    raw: RawZ3Ast
    ctx: Z3Context

  Z3SolverOwn = object
    raw: RawZ3Solver
    ctx: Z3Context
  Z3Solver* = ref Z3SolverOwn

  Z3ModelOwn = object
    raw: RawZ3Model
    solver: Z3Solver           # keeps solver alive (transitively the context)
  Z3Model* = ref Z3ModelOwn
```

The `ref object` for `Z3Context`, `Z3Solver`, `Z3Model` (heap-allocated, GC-tracked) plus value-types for `Z3Ast`/`Z3Sort` (which carry a ref to their context) gives us:

- ASTs and Sorts are cheap to pass around (just a pointer + ref).
- The parent context is kept alive as long as any child exists.
- `=destroy` on each type decrements the appropriate refcount in Z3.

### `=destroy` discipline (**validated**)

Three concrete patterns the spike validated:

1. **Hooks operate on the underlying `Own` object type**, not the `ref` alias. Nim 2's signature requirement: `proc =destroy(x: T)` where T is an object type.
2. **`{.raises: [].}` plus internal `try / except CatchableError: discard`** is required. softlink-wrapped procs can raise `SoftlinkError` (the library was unloaded between calls); `=destroy` cannot propagate exceptions.
3. **Defensive nil checks**: parent context may be finalized in unpredictable order; check before calling Z3's `dec_ref`.

Hook signatures are generic for the phantom-typed types:

```nim
proc `=destroy`[S: static SortTag](a: Z3Ast[S]) {.raises: [].} =
  try:
    if not a.raw.isNil and a.ctx != nil and not a.ctx.raw.isNil:
      Z3_dec_ref(a.ctx.raw, a.raw)
  except CatchableError: discard

proc `=destroy`(c: Z3ContextOwn) {.raises: [].} =
  try:
    if not c.raw.isNil: Z3_del_context(c.raw)
    if not c.cfg.isNil: Z3_del_config(c.cfg)
  except CatchableError: discard

proc `=destroy`(s: Z3SolverOwn) {.raises: [].} =
  try:
    if not s.raw.isNil and s.ctx != nil and not s.ctx.raw.isNil:
      Z3_solver_dec_ref(s.ctx.raw, s.raw)
  except CatchableError: discard
```

The `ref Z3Context` should keep the context alive until all ASTs are destroyed, but Nim's GC ordering isn't always parent-first across types — defensive nil checks are cheap insurance against finalizer-order surprises (and the spike's 1000-context stress test passed under them).

### `=copy` discipline (**validated**)

ASTs and Sorts can be copied (value types). Each copy needs to inc_ref the underlying Z3 object so the refcount reflects the number of Nim references:

```nim
proc `=copy`[S: static SortTag](dst: var Z3Ast[S], src: Z3Ast[S]) {.raises: [].} =
  if dst.raw != src.raw:
    try:
      if not dst.raw.isNil and dst.ctx != nil and not dst.ctx.raw.isNil:
        Z3_dec_ref(dst.ctx.raw, dst.raw)
      dst.raw = src.raw
      dst.ctx = src.ctx
      if not dst.raw.isNil and dst.ctx != nil and not dst.ctx.raw.isNil:
        Z3_inc_ref(dst.ctx.raw, dst.raw)
    except CatchableError: discard
```

Standard RAII-with-refcounted-payload pattern with the same `{.raises: [].}` discipline as `=destroy`. The spike's 1000-context stress test exercised this path repeatedly (each `var z = x` triggers `=copy`, each scope exit triggers `=destroy`) without crashes or visible leaks.

### `=sink` (move)

For performance: a move from one Z3Ast to another doesn't need to inc_ref then dec_ref. Implementing `=sink` lets the compiler elide the redundant refcount churn for `let y = mkAdd(a, b)` patterns.

---

## 4. Phantom sort types

The decision: **yes, use phantom types** for sort-level type safety.

### Why

Without phantom types, this compiles and crashes at runtime:
```nim
let x = ctx.mkIntVar("x")
let b = ctx.mkBoolVar("b")
let bad = mkAdd(x, b)   # ill-typed in Z3; runtime error or nonsense
```

With phantom types, this fails at compile time:
```nim
let x = ctx.mkIntVar("x")   # Z3Ast[IntSort]
let b = ctx.mkBoolVar("b")  # Z3Ast[BoolSort]
let bad = x + b             # Error: no '+' for (Z3Ast[IntSort], Z3Ast[BoolSort])
```

For a wrapper aimed at serious use, compile-time sort-safety is a multiplicative win — every bug it catches is a bug a user doesn't have to debug under runtime conditions.

### How

```nim
type
  SortTag* = enum
    stInt, stReal, stBool, stBitVec, stArray, stString, stSeq, stDatatype, stUninterp

  Z3Ast*[S: static SortTag] = object
    raw: Z3_ast
    ctx: Z3Context

  Z3Sort*[S: static SortTag] = object
    raw: Z3_sort
    ctx: Z3Context

# Numeric construction
proc mkInt*(ctx: Z3Context, n: int): Z3Ast[stInt]
proc mkReal*(ctx: Z3Context, n: float): Z3Ast[stReal]
proc mkBool*(ctx: Z3Context, b: bool): Z3Ast[stBool]

# Variables
proc mkVar*[S: static SortTag](ctx: Z3Context, name: string,
                                sort: Z3Sort[S]): Z3Ast[S]
proc mkIntVar*(ctx: Z3Context, name: string): Z3Ast[stInt] =
  ctx.mkVar(name, ctx.mkIntSort)

# Arithmetic (only for numeric sorts)
proc `+`*[S: static SortTag](a, b: Z3Ast[S]): Z3Ast[S]
  ## Compile-time constraint: S in {stInt, stReal, stBitVec}.
  ## Enforced via `when S notin {...}` and `{.error.}`.
```

The `static SortTag` approach uses Nim's static-type-as-value mechanism. `Z3Ast[stInt]` and `Z3Ast[stBool]` are distinct types; the `+` overload checks at instantiation whether the sort is numeric.

### Edge cases

**Some Z3 operations are polymorphic over sort.** `Z3_mk_eq(a, b)` requires `a` and `b` to have the same sort but doesn't care which sort it is. We model this as:
```nim
proc `==`*[S: static SortTag](a, b: Z3Ast[S]): Z3Ast[stBool]
```

**BitVec width**: `Z3_mk_bv_sort(ctx, 32)` makes a 32-bit sort. We'd want `Z3Ast[stBitVec(32)]` distinct from `Z3Ast[stBitVec(64)]`. Static parameters can carry width:
```nim
type Z3Ast*[S: static SortTag, W: static int = 0] = object  # W only meaningful for stBitVec
```

This gets fiddly. Open question for v0.1: do we ship BitVec with width-tracked phantom types from day 1, or width-erased BitVec ASTs (with runtime width checks) initially and tighten later?

**Recommended v0.1**: ship width-tracked phantom types. The cost is generic complexity in the BitVec module; the value is "you cannot add a 32-bit BV to a 64-bit BV at compile time." Worth it.

---

## 5. Error handling

Z3's error model: register a global error handler via `Z3_set_error_handler`; Z3 calls it on errors. The handler can do anything.

### Design

Install a Nim-side error handler that records the last error per context. Wrap each FFI call in a check-and-raise: if the recorded error is non-OK, raise `Z3Error` with the error code and message.

```nim
type
  Z3ErrorCode* = enum
    zecOk, zecSortError, zecIOB, zecInvalidArg, zecParserError,
    zecNoParser, zecInvalidPattern, zecMemoutFail, zecFileAccessError,
    zecInternalFatal, zecInvalidUsage, zecDecRefError, zecException

  Z3Error* = object of CatchableError
    code*: Z3ErrorCode
    z3Message*: string
```

Each high-level wrapper proc is structured:

```nim
proc mkAdd*[S: static SortTag](a, b: Z3Ast[S]): Z3Ast[S] =
  let raw = Z3_mk_add(a.ctx.raw, 2, [a.raw, b.raw])
  checkError(a.ctx)
  result = Z3Ast[S](raw: raw, ctx: a.ctx)
  Z3_inc_ref(a.ctx.raw, raw)
```

`checkError(ctx)` pulls the per-context error code, raises `Z3Error` if non-OK.

### Why exceptions over `Result[T, E]`

- Z3 errors are rare in practice if the wrapper itself is well-tested. The dominant case is "no error," and `Result[T, E]` adds ceremony to every call site for the rare case.
- Z3's own C++ wrapper uses exceptions. Aligning with upstream idiom helps users translate Z3 patterns to Nim.
- Nim's exception model is straightforward; users don't need a new library.

If a consumer wants Result-style handling, they wrap our exceptions in `try-except`.

---

## 6. Threading

**Z3 contexts are NOT thread-safe.** Each thread must have its own context. Z3 documents this clearly.

### Policy

- `Z3Context` is `ref object` — not `{.acyclic.}`, but no other thread-safety annotations.
- We **document** that `Z3Context` must not be shared across threads.
- We do NOT use Nim's `Isolated[T]` enforcement — that's overkill; doc + tests suffice for v0.1.
- For multi-threaded use cases (proptest's symex running on parallel test threads), each thread creates its own context.

### Z3 global state

Some Z3 functions touch global state: `Z3_global_param_set`, `Z3_global_param_reset_all`, etc. We expose them but mark them clearly as global-state-mutating in the docstring.

### softlink threading note

softlink's load/unload procs are NOT thread-safe. We call `loadZ3()` once at module initialization (the first context creation triggers it) and never reload during normal operation. Document this.

---

## 7. Multi-version support

### Compatibility range

**Z3 4.10 (Sep 2022) → 4.13.x (current).**

Pre-4.10 versions are old enough that we don't care; post-4.10 versions are what users will have. We test against 4.10, 4.11, 4.12, 4.13 in CI.

### Optional symbols

Symbols added in later versions are declared `{.optional.}` in the softlink `dynlib` block:

```nim
dynlib "libz3.so(.4|.4.13|.4.12|.4.11|.4.10|)":
  # Available in 4.10+
  proc Z3_mk_int_sort(ctx: Z3_context): Z3_sort {.cdecl, header: "z3.h".}

  # Added in 4.12
  proc Z3_mk_recursive_func(ctx: Z3_context, ...) {.cdecl, optional, header: "z3.h".}
```

Per-symbol availability checks:
```nim
if Z3_mk_recursive_funcAvailable():
  # use it
else:
  # fall back or error
```

### Feature detection API

Expose runtime availability checks for capabilities that span multiple symbols:

```nim
proc hasOptimize*(): bool   ## Z3_optimize_* family
proc hasRecursive*(): bool  ## recursive function defs
proc hasFloatingPoint*(): bool   ## FP theory
```

---

## 8. Module structure

```
nimlibs/z3/
├── z3.nimble
├── README.md
├── LICENSE                          # Apache-2.0 (per nimlibs convention)
├── docs/
│   ├── IMPLEMENTATION_PLAN.md       # this document
│   ├── ARCHITECTURE.md
│   ├── LIFETIME.md                  # the =destroy/=copy/=sink discipline
│   ├── LINKING.md                   # dynamic-via-softlink (default), static (opt-in)
│   └── API_GUIDE.md                 # written tutorial
├── src/
│   ├── z3.nim                       # public re-exports
│   └── z3/
│       ├── ffi.nim                  # softlink dynlib block
│       ├── version.nim              # version detection + feature flags
│       ├── error.nim                # Z3Error, checkError, error handler installation
│       ├── context.nim              # Z3Context lifecycle, =destroy
│       ├── sort.nim                 # SortTag, Z3Sort[S], constructors
│       ├── ast.nim                  # Z3Ast[S], common AST ops
│       ├── numeral.nim              # mkInt, mkReal, mkBV literals
│       ├── boolean.nim              # and, or, not, =>, ite
│       ├── arith.nim                # +, -, *, div, mod, <, <=, etc.
│       ├── bitvec.nim               # BV-specific ops (shifts, bitwise, etc.)
│       ├── array.nim                # Z3 array theory
│       ├── solver.nim               # Solver, assert, check, push, pop
│       ├── model.nim                # Model extraction, value reading
│       └── repr.nim                 # $ for ASTs, sorts, models
├── tests/
│   ├── tffi.nim                     # raw FFI smoke (with softlink loaded)
│   ├── tcontext.nim                 # context lifecycle, no-leak invariant
│   ├── tsort.nim                    # sort construction
│   ├── tnumeral.nim                 # numeral construction + extraction
│   ├── tboolean.nim                 # bool ops + truth tables
│   ├── tarith.nim                   # arithmetic semantics
│   ├── tbitvec.nim                  # BV semantics + width safety
│   ├── tarray.nim                   # array theory
│   ├── tsolver.nim                  # solver basic ops
│   ├── tmodel.nim                   # model extraction round-trips
│   ├── trepr.nim                    # pretty-printing
│   ├── tversion.nim                 # multi-version compat
│   ├── tlifetime.nim                # finalizer / =destroy / =copy / =sink behaviors
│   └── tproperty.nim                # property tests via proptest (dogfooding)
└── examples/
    ├── basic_solve.nim              # find (x, y) s.t. constraints
    ├── bitvec_solve.nim             # BV constraints
    └── quantified.nim               # ∀, ∃ (v0.2 demo)
```

Subdir mirrors the proptest engine/* / derive/* pattern — established convention.

---

## 9. Testing strategy

### Test categories

1. **Smoke** (`tffi.nim`): each FFI symbol is callable. softlink loads. Raw constructors return non-nil. Tests would catch "you forgot to declare Z3_mk_int_sort in the dynlib block."

2. **Lifecycle** (`tlifetime.nim`): create-then-drop a context with N ASTs; assert leak count == 0 via Z3's own `Z3_finalize_memory` or external tooling (valgrind on Linux CI). Verify `=copy` increments refcounts; `=destroy` decrements; `=sink` doesn't churn.

3. **Behavioral** (`tarith.nim`, `tboolean.nim`, etc.): for each operation, construct a query with a known answer (e.g., `mkAdd(2, 3) == 5` is sat with the trivial model); check sat/unsat. Tests the semantics of each builder against Z3's actual behavior.

4. **Type-safety** (`tsort.nim`): tests that *should fail to compile* if phantom types regress. Use `compiles(...)` checks:
   ```nim
   test "cannot add Int and Bool":
     check not compiles(ctx.mkInt(1) + ctx.mkBool(true))
   ```

5. **Differential** (against Python z3): for a corpus of queries, verify nim-z3 and python-z3 return the same sat/unsat. Catches semantic divergence.

6. **Property-based** (`tproperty.nim`, **proptest dogfooding**): generate random Z3 expressions, assert invariants:
   - "If `s.check() == sat`, the returned model satisfies all asserted constraints when evaluated."
   - "`s.check()` is deterministic — two calls return the same result given no state change."
   - "Push then pop returns to the previous solver state."
   - "Commutativity at the SMT level: `a + b` and `b + a` have the same sat/unsat under any context."

   This is the loop we always wanted: proptest tests nimlibs/z3 → nimlibs/z3 powers proptest's symex.

7. **Multi-version matrix** (CI): run the full suite against Z3 4.10, 4.11, 4.12, 4.13.x. Catches version-specific signature drift before users hit it.

### Coverage target

Realistic v0.1 target: **80%+ line coverage on the idiomatic layer**, **smoke-only on the FFI layer** (each symbol called at least once via a public-API path).

### Memory leak checking

CI job runs the test suite under valgrind (Linux) and ASAN (Linux + macOS). Pass criterion: no leaks attributable to nimlibs/z3 (Z3 itself may leak internally; we ignore those).

---

## 10. Performance considerations

Z3's solving time dominates wrapper overhead — typical SMT queries run in microseconds to seconds. The wrapper's per-call cost (function pointer dispatch + Nim-level wrapping + Z3 RC inc/dec) is nanoseconds. Not the bottleneck.

What we DO care about:
- **`=sink` to elide redundant inc_ref/dec_ref** on move semantics. This matters when constructing many ASTs in a loop.
- **Avoid hidden allocations** in hot paths. AST construction shouldn't `seq.add` per call.
- **Lazy serialization** for `$` — only stringify when actually needed (debug output).
- **Bulk solver-state operations** — when supported by Z3, prefer single calls (`Z3_solver_assert` of an N-ary AND) over N calls.

Not a v0.1 concern beyond "don't allocate gratuitously."

---

## 11. Phasing — what ships when

### v0.1 — core capability

- softlink-based FFI for ~150-200 symbols
- `Z3Context` lifecycle + error handler
- Sorts: Int, Real, Bool, BitVec (width-tracked)
- Numerals + variables
- Arithmetic ops (+, -, \*, div, mod, <, ≤, =, ≠)
- Boolean ops (and, or, not, implies, ite)
- BitVec ops (shifts, bitwise, concat, extract)
- Solver: assert, check, push, pop, get-model
- Model: value extraction for Int / Real / Bool / BitVec
- Pretty-printing (`$`) for ASTs, sorts, models
- Tests + examples
- Multi-version CI matrix (Z3 4.10 → 4.13)

**Deliverable target: a user can write the "find x, y s.t. constraints" example in their first 5 minutes.**

### v0.2

- Array theory (mkArray, store, select)
- Quantifiers (forall, exists; pattern triggers)
- Optimization (`Z3_optimize_*` — soft constraints, maximize, minimize)
- Custom datatypes (inductive types via `Z3_mk_datatypes`)
- Tactic combinators
- Goals + applied tactics

### v0.3+

- String theory
- Sequence theory
- Fixedpoint engine
- FloatingPoint theory
- Custom theories via user propagators (advanced)
- High-level macro DSL (`solve: ...`)

---

## 12. Dependencies

### Build / runtime

- **softlink ≥ 0.2.0** (Nim library, this repo's only direct dep)
- **Z3 development headers** (for compile-time `_Static_assert` verification): `apt install libz3-dev` / `brew install z3` / Z3 GitHub releases
- **Z3 shared library at runtime**: same install satisfies both

### Test

- **proptest** (dogfooding) — pinned to a specific commit; we test against the version we know works
- **valgrind / ASAN** (CI environment, not Nim deps)

### Optional `-d:z3Static` future opt-in

- libz3.a + libstdc++ static library — user manages, we document

---

## 13. License

Apache-2.0, per nimlibs convention. Compatible with Z3's MIT license — no friction for users statically or dynamically linking.

---

## 14. Open questions (genuinely open)

These are decisions we'd want resolved before or during v0.1 implementation. Marked here so we don't forget.

1. **BitVec phantom width: ship in v0.1 or defer?**
   Current plan says ship. Cost: width-parameterized generics across all BV ops. Benefit: compile-time width safety. Verdict-leaning: ship; the value is high.

2. **Sort hierarchy as enum or distinct types?**
   Current plan uses `SortTag = enum` with `static SortTag` phantom parameters. Alternative: distinct types (`type IntSort = distinct void`). Enum is simpler to reason about; distinct types compose better with `concept`s. v0.1: enum.

3. **Pretty-printing via Z3's own `Z3_ast_to_string` or custom Nim formatter?**
   Z3's output is canonical SMT-LIB; readable. Custom formatter is more work for marginal gain. v0.1: Z3's.

4. **`Z3Status` shape**:
   ```nim
   type Z3Status* = enum
     zsSat, zsUnsat, zsUnknown
   ```
   or
   ```nim
   type Z3Status* = object
     case kind*: Z3StatusKind
     of zsSat: discard
     of zsUnsat: core*: seq[Z3Ast[stBool]]
     of zsUnknown: reason*: string
   ```
   Second is richer but more allocation. v0.1: probably the variant; the unknown-reason is genuinely useful.

5. **Should `=destroy` on `Z3Context` panic on outstanding ASTs?**
   No. Defensive nil checks handle out-of-order finalization. Panicking would surprise users.

6. **What's the convention for naming wrapped procs?**
   Z3 uses `snake_case`; Nim uses `camelCase`. Convention: `Z3_mk_int_sort` → `mkIntSort`. Symmetric translation. Drop the Z3 prefix on public API (`mkContext`, not `z3MkContext`); the module name is the namespace.

7. **Should we expose Z3's tracing/logging?**
   Yes, via a `setLogFile` proc. Useful for debugging complex queries. Cheap to add.

8. **Threading enforcement: doc-only or type-system?**
   Current plan: doc-only. Type-system enforcement via `Isolated[T]` or similar is heavyweight for v0.1.

9. **Memory leak detection in CI: valgrind, ASAN, or both?**
   Both, on Linux. macOS: ASAN only (valgrind is unreliable on macOS).

---

## 15. Architectural risks

Risks we've identified but accepted:

- **softlink dependency**. softlink is your own library; we trust it. If it changes incompatibly, we pin a version. Risk: bus factor on softlink. Mitigation: softlink is small (739 LOC); we can fork if needed.

- **Z3 API evolution**. Z3 ships breaking changes occasionally. softlink's compile-time signature verification catches them at build; we react when they happen.

- **Phantom types add complexity**. Generic procs across `SortTag` make stack traces uglier and compile errors more verbose. We accept this cost for type safety; document the patterns in API_GUIDE.md.

- **Z3 license is MIT**. Compatible with our Apache-2.0. No legal risk; noted for completeness.

- **Cross-platform softlink**. softlink is tested on Linux primarily. macOS and Windows behavior needs verification in CI. Risk: undetected platform-specific bugs. Mitigation: CI matrix includes both.

---

## 16. Out-of-band decisions to make

These need explicit answers before coding starts:

- **Version pinning**: which exact Z3 versions does CI test against? Proposal: 4.10.0, 4.11.0, 4.12.0, 4.13.4 (latest as of writing).
- **Initial release timeline**: v0.1 target?
- **Repo public vs private during development**: probably private until v0.1; public from v0.1 onwards.
- **README priority sections**: install / 5-minute example / link to API guide / link to lifetime doc.
- **Tagging strategy**: semver; pre-1.0 means commits to main; 1.0+ means RC branches.

---

## 17. Implementation sequence

When we start coding, the work order:

1. **Nimble skeleton + CI**: `z3.nimble`, basic CI config that runs `nimble test` against Z3 4.13 on Linux. Empty tests pass. **DONE** in v0.0.1 commit.

2. **softlink FFI layer**: declare ~30 core symbols (context, config, sort, basic AST, solver, model). Verify softlink loads libz3 and resolves them. Smoke test in `tffi.nim`. **DONE**: ~55 symbols + Z3ErrorHandler callback type, 14 smoke tests covering every category.

3. **`Z3Context` + error handler**: lifecycle, `=destroy`, error capture. Tests verify creation/destruction. **DONE** with two intentional extensions beyond the original spec:

   - **Implicit current-context threadvar**. `newContext()` sets the per-thread current context; `currentContext()` retrieves it; `requireCurrentContext()` raises a clear `Z3Error` for missing-current diagnostics; `setCurrentContext(ctx)` swaps without creating. Idiomatic builders downstream will resolve against current-context when no explicit `ctx: Z3Context` arg is supplied. Same ergonomic pattern Python's z3 library uses; multi-thread composes naturally via threadvar.
   - **`withContext(ctx): body` scoping template**. Temporarily swaps current-context for `body`; restores on normal or exceptional exit. Enables library-internal scoped use without disturbing caller's setting.
   - **Auto-load of libz3 on first `newContext()`**. Users don't need to call `loadZ3()` explicitly; first context creation invokes it idempotently. `LibZ3UnavailableError` (Defect-subclass) raised with a clear remediation message when libz3 is missing or too old.
   - **`Z3Error` carries typed `Z3ErrorCode` enum** (not just a message). `checkErr` template wraps FFI calls; raises with stack trace pointing at the user's code (template-based for inlining).

   Reasoning for divergence: each addition is purely ergonomic with zero impact on the explicit-context API. The plan-strict design still works (`ctx.mkIntVar("x")` is supported via UFCS once builders land); we just don't *require* it.

4. **Sort module**: phantom-typed `Z3Sort[S]`, constructors for Int/Real/Bool. Tests verify sort equality.

5. **AST module + numerals + variables**: `Z3Ast[S]`, `mkInt`, `mkReal`, `mkBool`, `mkIntVar`, etc. Tests verify round-trip via solver.

6. **Boolean ops**: and/or/not/implies/ite. Tests via truth tables.

7. **Arithmetic ops**: +/-/\*//mod, comparison. Tests verify against known queries.

8. **Solver + model**: assert, check, push, pop, get-model, value extraction. **First end-to-end example runnable.**

9. **BitVec module**: width-tracked Z3Ast[stBitVec, W], BV ops. Tests verify against known queries.

10. **Pretty-printing**: `$` for AST, sort, model.

11. **Property tests via proptest**: dogfooding. Confirms wrapper invariants statistically.

12. **Multi-version CI matrix**: Z3 4.10/4.11/4.12/4.13. Surface any version skew.

13. **Examples + README + LICENSE + docs**: ready for public.

14. **v0.1 tag.**

After v0.1: the v0.2 / v0.3 feature waves above.

---

## 18. Deferred from v0.1 (running list, updated as we go)

Items surfaced during implementation that we consciously punted out of v0.1.
**Append-only as new deferrals come up; check off when reabsorbed.** This is
separate from §11's v0.2/v0.3 feature waves (which are categorical: array
theory, quantifiers, etc.) — this section catalogues *narrow, late-binding*
gaps in shipped modules that v0.1 chose not to plug.

Format: each entry says **what** we deferred, **why** (the trade we made
during implementation), and **where it goes** (v0.2 / v0.x / dropped).

### From step 8 (solver + model)

- **Variant-with-reason `Z3Status`** — the `case kind ... of zsUnsat: core: seq[Z3Bool]` shape sketched in §14 Q4. **Why**: a plain `Z3Status` enum reads better at call sites (`case s.check() of zsSat:`) and the reason metadata belongs on the solver (`reasonUnknown`) rather than the decision itself. **Where**: dropped — superseded by the enum + accessor design. (Unsat core extraction itself is still a v0.2 item under "optimization/diagnostics".)
- **`evalReal`/`toReal` composer** — paralleling `evalInt`/`evalBool`. **Why**: Real values aren't always representable as float64 without loss; we exposed `toBigRealStr` instead. **Where**: v0.2 — add `toRealApprox: float64` with a documented precision caveat once we have a clear approximation policy.

### From step 9 (bitvec)

- **`mkBigBitVec(numeral: string, W)`** for widths above 64 bits. **Why**: requires the string-numeral FFI path (`Z3_mk_numeral` with the BV sort) plus a `static: assert W > 64` divergence in the constructor; not exercised by any planned v0.1 example. **Where**: v0.2.
- **`toBigUintStr` / `toBigIntStr` on `Z3BitVec[W]`** for W > 64. **Why**: same. The current `toUint`/`toInt` `static: assert W <= 64` errors give a clear "use the big form" message — but the big form doesn't exist yet. **Where**: v0.2 alongside `mkBigBitVec`.
- **Unified two-param `Z3Ast[S, W: static int = 0]`** sketched in §4. **Why**: chose separate `Z3BitVec[W]` instead — width is a Nat parameter fundamentally different from the finite sort tag, and the sentinel-`W=0` shape would have polluted every existing generic. **Where**: dropped; the separate-type design is now the spec.
- **Width-arithmetic correctness beyond the static asserts** — e.g. `extract(0, -1)` doesn't even type-check because `lo: static int` with `lo < 0` triggers `assert lo >= 0`, but we don't have property-based coverage that every `extract`/`concat`/`zeroExtend`/`signExtend`/`repeat` instantiation matches Z3's actual output width. **Where**: step 11 (property tests via proptest) — the natural place to brute-force this.

### From step 10 (pretty)

- **DOT / GraphViz export of AST DAGs**. **Why**: pretty-printer covers the linear SMT-LIB view; DOT is a separate visualisation surface and only useful when debugging shared-subterm structure. **Where**: v0.2 — likely as `z3/dot` with `Z3_get_ast_id` for hash-consing-aware node identity.
- **Colorised terminal output (`prettyColored`)** with ANSI escapes for keywords/operators/literals. **Why**: orthogonal to indentation; the README/examples in step 13 will tell us whether it materially helps comprehension or just adds noise. **Where**: v0.2 if step 13 surfaces demand; drop otherwise.
- **Multi-byte UTF-8 atom tokenising**. **Why**: Z3's own output is ASCII; our tokeniser walks bytes and would mishandle non-ASCII identifiers only if a user fed `reformat` an external string with unicode atoms. Not exercised by Z3's emitted output. **Where**: v0.2 if a user hits it.
- **SMT-LIB infix mathematical notation** (e.g. render `(+ x 1)` as `x + 1`). **Why**: large divergence from SMT-LIB canonical; would split the output story. **Where**: dropped — SMT-LIB output stays canonical; let users feed `pretty` output through a separate translator if they want infix.
- **`pretty` for `Z3FuncDecl`** — function declarations don't have a typed module yet. **Where**: covered transitively whenever `Z3FuncDecl` lands (likely v0.2 alongside uninterpreted functions / quantifiers).

### From step 11 (property tests via proptest)

- **`Z3_simplify` FFI + idiomatic `simplify(ast)` wrapper**. **Why**: surfaced when a BV-wraparound property tried `toUint` on a `(bvadd #x3c #x01)` AST and got "not a literal numeral" — Z3 doesn't auto-simplify constant folding. We reformulated the test to go through a solver+model instead (which mirrors the realistic user path anyway), but `simplify` would let users normalise ASTs without a check-sat. **Where**: v0.2 — useful for the BV-wraparound style of "concrete value of a built-up expression" check, and for shape-test optimisations where you want to short-circuit obvious cases.
- **Per-iteration Z3 context** in shape-driven property tests. **Why**: a fresh `newContext()` per `forAll` iteration exhausted ~8 GB on depth-3 recipes (context churn outpaces ORC). We share one context per test instead; hash-consing keeps the AST table bounded. The deferral is *robustness under churn*: the wrapper's `=destroy` discipline is correct, but Z3's per-context allocator + Nim's deferred GC interact unfavorably at high iteration counts. **Where**: v0.2 if a real user hits this in their own PBT — investigate whether explicit `GC_fullCollect()` between iterations + a per-context `Z3_finalize_memory` helps, or whether the right answer is to expose `withContext(...)` as a scoping primitive that proptest can call between iterations.
- **Recipe ADTs in the user API surface**. **Why**: `IntRecipe` / `BoolRecipe` / `BvRecipe` are private to the test file; downstream PBT users wanting Z3 shape-strategies have to re-derive them. **Where**: v0.2 as `z3/strategies` (or similar) — a public set of proptest strategies that yields recipes + interpreters. Out of scope for v0.1 because it bundles proptest as a runtime dep rather than test-only.
- **`smtValid` / `smtEquiv` overloads for sorts beyond `Z3Ast[S]` and `Z3BitVec[W]`** (arrays, strings, datatypes). **Where**: v0.2, alongside those sort modules.
- **Property-based width-arithmetic coverage for BV** (from §18 step 9 entry). Step 11 partially addresses this — `extract`/`concat`/`zeroExtend` round-trip properties are now in the suite — but only at W=8. Wider widths and `signExtend`/`repeat` random-tree coverage are still gaps. **Where**: subsumed by step 11's wider-width follow-up in v0.2.

### From step 12 (multi-version CI matrix)

- **macOS / aarch64 runners in the matrix**. **Why**: Z3 ships glibc-2.31 and macOS builds; we only test the glibc rows. PhD-thorough would add `runs-on: macos-latest` (Apple-silicon Z3 release artifact) and an Ubuntu aarch64 row. **Where**: v0.2 — wait until consumers ask for it; the abstraction layer (softlink dynlib pattern) doesn't change shape across platforms, so the matrix expansion is mechanical.
- **valgrind job alongside ASAN**. **Why**: ASAN catches use-after-free / double-free; valgrind's `--leak-check=full` finds bytes-still-reachable that ASAN's leak detector (which we disable due to Z3's intentional static caches) would also flag. We could selectively suppress Z3's known leaks in a `.supp` file. **Where**: v0.2 — same-class signal as ASAN; revisit if ASAN ever misses a real bug.
- **Differential testing against the Z3 CLI binary**. **Why**: §9 / §5 mention it. Now that the matrix puts a real `z3` binary on each row's PATH, we have the infrastructure: emit `smt2Script(solver)`, pipe to `z3 -in`, compare sat/unsat with our result. **Where**: v0.2 — needs a Settings-style runner abstraction so the diff job and the property suite can share a single source of constraints.
- **Differential testing against Python z3** — §9 §5 mentions it. **Where**: post-v0.1 CI job; bigger lift than the CLI variant because requires installing Python z3 wheels per matrix row.
- **`{.optional.}` softlink declarations for symbols added in newer Z3** — the dynlib block still treats every symbol as required. The matrix would surface this immediately if a 4.13+ symbol were used on the 4.10 row. **Where**: still v0.2 — every symbol used today is in 4.10+; revisit when a v0.2 module needs a newer one.
- **`finalizeZ3Memory` hook at process exit**. **Why**: `tversion.nim` calls it manually; PhD-thorough would register it via `addExitProc` so it fires automatically on normal shutdown. But: it would interfere with multi-context test suites that run after `tversion.nim` in the same process. **Where**: dropped for v0.1 — manual call is the right ergonomics; revisit if a real user wants automatic shutdown cleanup.

### Cross-cutting (no longer cross-cutting after step 12)

All previously cross-cutting deferrals have moved into per-step entries.

---

## Closing note

This plan is a **commitment** — we ship to it. Deviations require updating the plan, not just the code. The cost of writing this plan up front (a half-day) is dramatically lower than the cost of discovering halfway through implementation that we got the lifetime story wrong.

If reading this, future-me, and the plan turned out to be wrong somewhere: update the plan with the lesson; keep the lesson explicit so the next library benefits.

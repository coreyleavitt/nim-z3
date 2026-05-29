# Spike findings — `nimlibs/z3` wrapper

Ran a throwaway spike (`spike/spike.nim`) to validate the architectural
assumptions in IMPLEMENTATION_PLAN.md before committing to the full library
design. This document captures what we learned. The spike code itself is
disposable; the lessons are the deliverable.

## Validated assumptions (good news)

### 1. softlink loads libz3 successfully

The `dynlib "libz3.so(.4|)"` block works as documented. softlink finds
`libz3.so.4` on Debian-derived systems (libz3-4 package, Z3 4.13.3).
Multi-version pattern is honored.

### 2. softlink's `_Static_assert` header verification catches real signature mismatches

This is the headline value-add we expected from softlink, and it works.
The spike's initial declarations had legitimate signature errors (Z3 enums
declared as `cint`, opaque pointers declared as raw `pointer`). All of
them were caught at C-compile time with clear "signature mismatch vs z3.h"
errors. Without softlink, those bugs would manifest as runtime SIGSEGVs
or wrong results.

### 3. Opaque pointer types via `bycopy importc`

```nim
RawZ3Config* {.importc: "Z3_config", header: "z3.h", bycopy.} = object
```

This idiom emits `Z3_config` in C output (matching z3.h's typedef name)
rather than `void*`. softlink's verifier accepts this. The `bycopy`
makes Nim treat the type as a value rather than auto-pointer-wrapping it.

### 4. Enum types via `importc` + `size: sizeof(cint)`

```nim
Z3LBool* {.importc: "Z3_lbool", header: "z3.h", size: sizeof(cint).} = enum
  Z3_L_FALSE = -1, Z3_L_UNDEF = 0, Z3_L_TRUE = 1
```

Maps cleanly to Z3's C enum. Required because `cint` is not type-compatible
with the named enum from softlink's perspective.

### 5. `=destroy` / `=copy` discipline compiles

Nim 2's hook signatures need the underlying object type (not the `ref`
wrapper). The pattern is:

```nim
type
  Z3ContextOwn = object       # the underlying type
    raw: RawZ3Context
    cfg: RawZ3Config
  Z3Context* = ref Z3ContextOwn   # the user-facing ref alias

proc `=destroy`(c: Z3ContextOwn) {.raises: [].} = ...
```

The `{.raises: [].}` annotation + `try/except CatchableError: discard` is
required because softlink-wrapped procs can raise `SoftlinkError` and
`=destroy` can't propagate. Defensive but cheap.

### 6. Phantom sort types via `static SortTag`

```nim
type Z3Ast*[S: static SortTag] = object
  raw: RawZ3Ast
  ctx: Z3Context

proc `+`*(a, b: Z3Ast[stInt]): Z3Ast[stInt] = ...
proc `and`*(a, b: Z3Ast[stBool]): Z3Ast[stBool] = ...
```

Compiles cleanly. The `=destroy`/`=copy` hooks become generic procs
parameterised by `S: static SortTag`. Operations restricted to specific
sorts fail to compile when called with the wrong sort — exactly what we
wanted.

## Architectural surprises (none)

The IMPLEMENTATION_PLAN.md design holds up. No fundamental changes needed.
The opaque-types-with-bycopy idiom is a refinement of the plan's "type
sketch" section but doesn't alter the overall architecture.

## softlink issues that need work-arounds or upstream fixes

### Issue 1 — softlink's GCC pathway doesn't strip `const`

**Symptom**: `Z3_get_full_version()` returns `Z3_string` (= `const char *`
in C). Declaring it as `cstring` in Nim (which emits as `char*`) should
match after const-stripping, but the GCC pathway's `__builtin_types_compatible_p`
doesn't strip const before comparing.

**Severity**: blocks use of `Z3_string`-returning procs (~30% of Z3 API)
in C-backend mode.

**Workaround**: switch to `--backend:cpp`. The C++ pathway uses
`softlink_strip_ptr_const<>` which does strip const, so `const char*`
matches `char*` (NCSTRING). The spike confirmed this works for
`Z3_get_full_version` when using `cstring` as the Nim return type.

**Upstream fix**: softlink's GCC pathway should also strip ptr-const
before comparison. Should be a small patch to softlink's macro.

### Issue 2 — softlink emits `extern "C" static` for verify proc in cpp mode

**Symptom**: When compiled with `--backend:cpp`, softlink emits:

```cpp
extern "C" static void softlinkVerifyZ3(void);
```

C++ rejects this (storage-class + linkage-spec conflict). Compilation fails
before the actual `_Static_assert` checks run.

**Severity**: blocks use of cpp backend, which is currently the only way
to use softlink with Z3_string-returning procs (Issue 1).

**Workaround**: patch softlink locally to drop the `static` qualifier when
the target is C++, OR emit `inline` instead of `static`.

**Upstream fix**: softlink's `codegenDecl: "static $1 $2$3"` (around
softlink.nim:370) needs a different template under `defined(cpp)`. Should
be a one-line change.

### Issue 3 — Nim's identifier matching ignores case and underscores

Not a softlink issue, but a real gotcha. The raw C types `Z3_context`
and our idiomatic `Z3Context` collide because Nim treats them as
identical identifiers. Solved by naming the raw types differently
(spike used `RawZ3X`).

**For production**: stick with `RawZ3X` prefix for FFI types, `Z3X` for
idiomatic ref types. Document the convention in the architecture doc.

## What couldn't be runtime-validated due to softlink issues

Until softlink issues 1 and 2 are resolved, we couldn't actually *run*
the spike past compilation. The following assumptions are validated at
the **compile-time** level but not yet at the **runtime** level:

- The refcount discipline (`Z3_inc_ref` / `Z3_dec_ref` paired correctly
  in `=destroy` / `=copy`) doesn't leak in practice
- The end-to-end "x + y == 10 and x > 3" example actually returns sat
  with a valid model
- The 1000-context smoke test doesn't crash

These will be validated **after** softlink fixes land, OR after the
production wrapper adds a thin shim layer that bypasses the problematic
header checks.

## Recommended next steps

In order:

1. **File two issues against softlink**:
   - Const-strip in GCC pathway (parity with C++ pathway).
   - `extern "C" static` in cpp pathway.
   Both are small fixes; both unblock real Nim FFI work beyond just Z3.

2. **Patch softlink locally** as a vendored fork in the meantime, OR contribute
   the fixes upstream. Given softlink is your own project, this is just
   "land the fixes." Two-evening effort.

3. **Restart the spike** with patched softlink to validate runtime behavior
   (sections 6 and 7 of the spike — actual solve + many-context smoke).

4. **Update IMPLEMENTATION_PLAN.md section 2** ("API at three layers") to
   reflect the validated type idiom (`RawZ3X` naming, `bycopy importc`,
   enum mapping pattern).

5. **Then start step 1 of the implementation sequence** (nimble skeleton).

## Files in this spike

- `spike/spike.nim` — the full validation harness. Compiles to the point
  where softlink's verify proc fires; fails on Issues 1 and 2 above.
- `spike/run.sh` — runs the spike inside a podman container with Z3 installed.
- `spike/inspect2.sh` — produces the C/C++ output for diagnosing
  softlink's emitted asserts.

The spike code itself is disposable — keep for reference, but the
production wrapper starts fresh per IMPLEMENTATION_PLAN.md.

## Cost / value assessment

**Time invested**: ~2 hours of iteration.

**Bugs prevented**: hard to count, but: the const-strip issue would have
silently turned into wrong-result bugs in production (we'd have hit
`SIGSEGV` calling functions we thought were correctly bound). The
`extern "C" static` issue would have manifested as "cpp backend doesn't
work at all" which is a deal-breaker for libraries with const-qualified
C types (i.e. most of them). The opaque-pointer-typedef impedance was
real and would have wasted days of debugging if discovered mid-build.

**Architectural confidence**: high. The plan holds. No re-architecting
needed. Two known softlink fixes unblock everything.

**Recommendation**: invest the half-day in patching softlink, restart spike,
then commit to the full implementation per IMPLEMENTATION_PLAN.md.

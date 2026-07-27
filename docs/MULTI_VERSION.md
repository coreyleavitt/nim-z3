# Multi-version Z3 support

nim-z3 supports **Z3 4.13.x → 4.16.x** — one build of nim-z3 loads and runs
against any runtime `libz3` in that range. You do not recompile nim-z3 per Z3
version; a symbol that a later Z3 minor removed or changed degrades gracefully
at load time instead of failing the whole load or, worse, binding a mismatched
ABI.

This is built on [softlink](https://github.com/coreyleavitt/softlink)'s
optional-symbol and version-bound machinery. This document explains what that
means in practice, what the two known drift points are, and how to query the
compatibility of the Z3 you actually loaded.

## Why 4.13 is the floor

nim-z3 declares 674 Z3 FFI symbols. Auditing them against the Z3 header history
shows the surface is stable from **4.13.0** onward: every symbol nim-z3 declares
either exists with a matching signature across 4.13.x–4.16.x, or is one of the
two drift points below (handled explicitly). Below 4.13 the story breaks down —
4.11 and earlier are missing symbols nim-z3 requires (the module will not even
load), and 4.12 has genuinely-drifted signatures on a handful of solver
symbols. Those releases are also 3.5–4 years old, and there is a 14-month gap
between 4.12.0 and 4.13.0 that makes 4.13 a natural boundary. Supporting
4.10–4.12 would be a separate, larger effort; it is deliberately out of scope.

## How graceful degradation works

nim-z3's FFI block declares the volatile symbols `{.optional.}` (and, where a
signature drifted, with a version bound). At `loadZ3()`:

- A required symbol that is missing → the whole load fails
  (`LibZ3UnavailableError`) — nim-z3 never runs half-bound.
- An **optional** symbol that is missing on this runtime → the load succeeds as
  `lrOkPartial`; the symbol is left unbound and reported (see `z3Compat()`).
  Calling an unbound optional symbol raises rather than jumping through a nil
  pointer.
- An optional symbol whose declared **signature is not valid** on this runtime
  (a version-bounded symbol outside its bound) → it is **drift-refused**: left
  unbound exactly as if absent, rather than bound with the wrong ABI. This is
  the safety property — `loadZ3()` succeeding never means a mismatched ABI is
  callable.

## The two drift points (4.15 → 4.16)

| Symbol | What changed at 4.16 | How nim-z3 handles it |
|--------|----------------------|-----------------------|
| `Z3_mk_set_has_size` | **removed** | `{.optional.}` → absent on 4.16; load is `lrOkPartial`; the wrapper (`hasSize`) is unavailable there. |
| `Z3_fpa_get_numeral_sign` | out-param `int*` → `bool*` (**parameter drift**, same name and return type) | `{.optional, until: "4.16.0".}` → on ≥4.16 the historical `int*` signature is **drift-refused**; the symbol is left unbound instead of binding an ABI-incompatible pointer. |

The `fpa` case is the subtle one: because only the parameter changed, a naïve
by-name binding would silently write through a pointer of the wrong width. The
`until: "4.16.0"` bound makes softlink refuse that binding on 4.16, so a caller
gets a clean "unavailable" (or a raised error on direct call) instead of memory
corruption.

## Querying compatibility at runtime — `z3Compat()`

`z3Compat()` (re-exported through `import z3`; you do **not** need a separate
`import softlink`) returns a `CompatReport` describing the Z3 that was actually
loaded:

```nim
import z3

discard newContext()          # triggers loadZ3() + the version probe
let c = z3Compat()

echo "loaded Z3 ", c.runtimeVersion      # e.g. "4.16.0"
echo "attestation: ", c.attestation      # see below

for (symbol, reason, interval) in c.missingReasons:
  echo symbol, ": ", reason              # mrExpected | mrAnomalous | mrDriftRefused
```

`MissingReason` values:

- `mrExpected` — this runtime predates or postdates the symbol as recorded/bounded; its absence is expected.
- `mrDriftRefused` — the symbol resolved by name but was refused because its declared signature is not valid on this runtime (e.g. `Z3_fpa_get_numeral_sign` on 4.16).
- `mrAnomalous` — this runtime's headers should have the symbol, yet it did not resolve (worth investigating).

On a 4.16 runtime, `z3Compat().missingReasons` reports
`Z3_fpa_get_numeral_sign` as `mrDriftRefused`. On 4.13–4.15 that symbol is
usable and absent from the list.

You can also check a single optional symbol directly with the generated
`<symbol>Available()` predicate, e.g. `Z3_fpa_get_numeral_signAvailable()`.

## The three wrapper procs sitting on optional symbols

`getNumeralSign` (`z3/fp`), `hasSize` (`z3/sets`), and `replaceAll`
(`z3/sequence`) each sit directly atop one of the drift-affected symbols
above. Degrading them to a dummy/`none` value on an unavailable symbol would
be unsound — `getNumeralSign`'s `none` already means "not a numeral", and
`hasSize`/`replaceAll` have no honest "unavailable" term to return. Instead,
each checks the corresponding `<Symbol>Available()` predicate before calling
the FFI and raises `Z3FeatureUnavailableError` (a `Z3Error` subclass, see
`z3/error`) if it's false, naming the symbol and the loaded version. Check
`Available()` first if you want to branch instead of catching.

`replaceAll` differs from the other two in one respect: it additionally
requires `-d:z3WithSeqReplaceAll` to be compiled in at all (a deliberate
default-surface choice), so without that flag it isn't in scope regardless of
runtime version. `hasSize` and `getNumeralSign` are always present in the
compiled surface and only raise at runtime when the underlying symbol is
unavailable.

## Whole-load health checks — `z3LoadIsHealthy()` / `z3CompatWarnings()`

Most callers don't want to learn `MissingReason`'s vocabulary just to answer
"is my Z3 healthy?" Two nim-z3-owned facade procs (`z3/ffi`, re-exported
through `import z3`) answer that directly:

- `z3LoadIsHealthy(): bool` — `true` iff every missing symbol is missing
  for a reason that's *expected on this version*: `mrExpected` or
  `mrDriftRefused`. A declared-bound drift refusal (the `fpa` case on 4.16)
  is the wrapper doing exactly what it was built to do, not an anomaly, so it
  does **not** make this `false`. Only `mrAnomalous` does.
- `z3CompatWarnings(): seq[MissingReasonEntry]` — the `mrAnomalous` subset of
  `missingReasons`; empty on a healthy load.

## Attestation and the compat manifest

`CompatReport.attestation` reports how much softlink can vouch for the loaded
version:

- `atNoManifest` — the version probe ran, but no committed compat manifest is
  attached. Version-bounded refusals (like `fpa` above) still work — safety
  does not depend on a manifest.
- `atAttested` — the probed version falls inside a committed manifest's
  harvested corpus, so absences/drifts are cross-checked against recorded facts.

nim-z3 ships a committed `src/z3/z3.compat.json` manifest harvested over the
corpus {4.13.3, 4.13.4, 4.14.1, 4.15.0, 4.16.0}. Every runtime in that range —
including the three the test matrix above exercises — attests `atAttested`;
`tests/tmultiversion.nim` pins this along with the exact classification of
both drift points (`Z3_mk_set_has_size` and `Z3_mk_seq_replace_all` as
`mrExpected`, `Z3_fpa_get_numeral_sign` as `mrDriftRefused` on 4.16).

## Building against a specific Z3

nim-z3 compiles against whatever `z3.h` is on your include path and binds at
runtime against whatever `libz3` is on your loader path — these need not match,
but keeping them in the 4.13–4.16 range avoids surprises. If your distro ships
only a multi-component soname (openSUSE's `libz3.so.4.15` with no `libz3.so` or
`libz3.so.4` symlink), create a symlink or pin the library explicitly.

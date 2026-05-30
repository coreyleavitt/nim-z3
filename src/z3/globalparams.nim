## `z3/globalparams` — process-wide Z3 parameter control.
##
## Z3 maintains a small set of **manager-global** parameters that
## affect every context in the process: tracing knobs (`"verbose"`,
## `"trace"`, `"trace_file_name"`), memory caps (`"memory_max_size"`,
## `"memory_high_watermark"`), and rlimits. They sit on the Z3
## manager singleton, not on a `Z3Context` — hence no `ctx`
## parameter on this module's API.
##
## ## Surface
##
## - `setGlobalParam(name, value)` — set a parameter. Z3 stores
##   everything as a string; numeric coercion is done lazily on
##   read by individual modules.
## - `getGlobalParam(name)` — `some(v)` if the parameter has been
##   set (whether by user code or by an earlier `setGlobalParam`
##   call), `none` if it is at its built-in default.
## - `resetGlobalParams()` — clear every parameter the process has
##   set; restore Z3's built-in defaults.
##
## ## On the absence of `withGlobalParam`
##
## A scoped-override helper would be ergonomic, but Z3 has no way
## to **unset** an individual parameter — only `reset_all`. That
## means a faithful "restore previous value" is not expressible
## when the previous value was `none`. Rather than fake a stronger
## contract than the C API offers, this module exposes exactly the
## three calls Z3 provides; callers can compose them as needed.
##
## ## Thread-safety
##
## The Z3 manager-global parameter store is shared by every context
## in the process. Mutate from a single thread (typically during
## program startup) or guard with your own lock — Z3 does not
## serialise concurrent `set` / `reset` calls.

import std/[options]
import ./ffi, ./context

proc setGlobalParam*(name, value: string) =
  ## Set a manager-global parameter. Z3 silently ignores names it
  ## does not recognise (no error is raised); use a known name from
  ## Z3's `(help-tactic)` / `(get-options)` SMT output.
  ##
  ## Auto-loads `libz3` if needed — callers can use this before
  ## allocating any `Z3Context`, which is the typical pattern when
  ## the parameter affects context construction itself (e.g.
  ## `"verbose"`, `"memory_max_size"`).
  ensureLoaded()
  Z3_global_param_set(name.cstring, value.cstring)

proc getGlobalParam*(name: string): Option[string] =
  ## Return `some(v)` if `name` is a parameter Z3 recognises — `v`
  ## is its current **effective** value (either a user-set override
  ## or Z3's built-in default), serialised as a string in Z3's own
  ## format (`"0"`, `"true"`, `"z3.log"`, …).
  ##
  ## Returns `none` for parameter names Z3 does not recognise. **Z3
  ## does not distinguish "user-set" from "at default"** — to track
  ## whether your code set a particular value, retain it on the
  ## caller side; the underlying C API offers no such signal.
  ##
  ## Note that on `setGlobalParam` for a typed parameter (e.g. the
  ## `unsigned int` `verbose`), Z3 parses the value into its native
  ## type immediately; a malformed numeric string falls back to the
  ## default with a warning written to Z3's stderr.
  ensureLoaded()
  var raw: cstring
  if Z3_global_param_get(name.cstring, cast[pointer](addr raw)):
    if raw.isNil:
      none(string)
    else:
      some($raw)
  else:
    none(string)

proc resetGlobalParams*() =
  ## Restore every Z3 manager-global parameter to its built-in
  ## default. Affects every context in the process.
  ensureLoaded()
  Z3_global_param_reset_all()

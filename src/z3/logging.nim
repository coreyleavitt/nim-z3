## `z3/logging` — process-wide Z3 interaction logging and warning control.
##
## Z3 provides a facility to log every API call to a file ("interaction
## log") — useful for reproducing solver behaviour offline by replaying
## the log through the `z3` CLI's `-log` mode. The logging API is
## **process-global** (no `Z3_context` parameter); it affects all
## contexts simultaneously.
##
## ## Surface
##
## - `openLog(path)` — begin recording API calls to `path`. Returns
##   `true` on success. At most one log is open at a time; a second
##   `openLog` replaces the previous one.
## - `appendLog(msg)` — insert a comment line `msg` into the current
##   log. No-op when no log is open. Useful for human-readable markers
##   ("--- test case 3 ---") between logical sections of a log.
## - `closeLog()` — flush and close the current log. After this call
##   `appendLog` is a no-op until `openLog` is called again.
## - `toggleWarningMessages(enabled)` — enable or suppress Z3's
##   diagnostic warning output to stderr. Affects all contexts in the
##   process. Suppressing is useful in test suites that expect known
##   warnings.
##
## ## Thread-safety
##
## The logging state is shared by every context in the process. Mutate
## from a single thread (e.g. at program startup / test setup) — Z3
## does not serialise concurrent calls to these functions.
##
## ## Note on completeness
##
## Z3's documentation warns that interaction logs "may be potentially
## incomplete or incorrect if error handlers are used." nim-z3 installs
## a custom no-op error handler on every context (so that errors surface
## as Nim exceptions rather than aborting the process). Users relying on
## the log for offline replay should be aware of this interaction.

import ./ffi, ./context

proc openLog*(path: string): bool =
  ## Open `path` as the process-wide Z3 interaction log. Z3 will append
  ## a record of every subsequent C API call to the file until `closeLog`
  ## is called.
  ##
  ## Returns `true` on success, `false` if the file could not be opened
  ## (e.g. permission denied, directory not found).
  ##
  ## At most one log file is open at a time; calling `openLog` when a
  ## log is already open closes the previous file first.
  ensureLoaded()
  Z3_open_log(path.cstring)

proc appendLog*(msg: string) =
  ## Insert the string `msg` as a comment entry in the current interaction
  ## log. No-op if no log is open.
  ##
  ## The string must not contain embedded newlines — Z3 writes exactly
  ## one line per `appendLog` call. Useful for structuring a log into
  ## named sections for easier offline analysis.
  ensureLoaded()
  Z3_append_log(msg.cstring)

proc closeLog*() =
  ## Flush and close the current interaction log. After this call
  ## `appendLog` is a no-op until `openLog` is called again.
  ## Safe to call when no log is open (no-op).
  ensureLoaded()
  Z3_close_log()

proc toggleWarningMessages*(enabled: bool) =
  ## Enable (`true`) or suppress (`false`) Z3's diagnostic warning
  ## output to stderr. Affects all contexts in the process.
  ##
  ## Suppressing is useful in test suites where expected Z3 warnings
  ## (e.g. "WARNING: quantifiers detected") would clutter output. Always
  ## restore to `true` at suite teardown so downstream code sees warnings.
  ensureLoaded()
  Z3_toggle_warning_messages(enabled)

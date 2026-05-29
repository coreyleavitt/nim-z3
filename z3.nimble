# Package
version       = "0.0.1"
author        = "Corey Leavitt"
description   = "Type-safe, memory-safe Nim wrapper for the Z3 SMT solver"
license       = "Apache-2.0"
srcDir        = "src"

# Dependencies
#
# `requires` block kept minimal: just the Nim version. The runtime dep
# on softlink is resolved by milpa (see milpa.kdl); milpa emits nim.cfg
# with the right --path: lines so `nim c` Just Works. nimble is not
# involved in the build, matching the project-wide convention from
# nimkdl / intonaco / fresco / milpa itself.
requires "nim >= 2.0.0"

# Tasks
task test, "Run the test suite":
  # Both backends. cpp is a softlink-#12 regression guard. Paths come
  # from the milpa-emitted nim.cfg at the project root, so no manual
  # --path: flags here.
  for tf in ["tests/tffi.nim", "tests/tcontext.nim",
             "tests/tsort.nim", "tests/tast.nim",
             "tests/tboolean.nim", "tests/tarith.nim",
             "tests/tsolver.nim", "tests/tmodel.nim",
             "tests/tbitvec.nim", "tests/tpretty.nim"]:
    exec "nim c -r --threads:on --hints:off " & tf
    exec "nim cpp -r --threads:on --hints:off " & tf

# Package
version       = "1.0.0"
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
  #
  # Notes:
  # * `tproperty.nim` and `tsimplify.nim` depend on proptest (test-only
  #   dep). CI resolves milpa so the path is on --nimcache.
  # * `tests/tminimal.nim` is intentionally NOT in this list. It
  #   verifies the canonical full-`z3WithoutX`-flag configuration and
  #   needs flag definitions at compile time. Run it via the dedicated
  #   `nimble testMinimal` task.
  # * N11.1 (torphan_audit) wired in all tests that were committed during
  #   N8–N10 slices but never added here. 128 tests total (tminimal excluded).
  for tf in [
      # Core / always-on
      "tests/tffi.nim", "tests/tffi_opaque.nim",
      "tests/tcontext.nim",
      "tests/tsort.nim",
      "tests/tast.nim", "tests/tast_introspect.nim",
      "tests/tast_print_mode.nim",
      "tests/tastmap.nim",
      "tests/tastvector.nim",
      "tests/tboolean.nim",
      "tests/tarith.nim", "tests/tarith_conv.nim",
      "tests/tarith_extractors.nim", "tests/tarith_extras.nim",
      "tests/tarray.nim", "tests/tarray_extra.nim",
      "tests/tbitvec.nim", "tests/tbigbitvec.nim",
      "tests/tbitvec_opt.nim", "tests/tbitvec_overflow.nim",
      "tests/tbitvec_red_rot.nim", "tests/tbitvec_theory_conv.nim",
      "tests/tsolver.nim", "tests/tsolver_cube.nim",
      "tests/tsolver_misc.nim", "tests/tsolver_trail.nim",
      "tests/tmodel.nim", "tests/tmodel_construction.nim",
      "tests/tmodel_enum.nim",
      "tests/tpretty.nim",
      "tests/tproperty.nim",
      "tests/tversion.nim",
      "tests/tsimplify.nim", "tests/tsimplifier.nim",
      "tests/trewrite.nim",
      "tests/ttranslate.nim", "tests/ttranslate_generic.nim",
      "tests/ttranslate_parity.nim",
      "tests/thash.nim",
      "tests/tio.nim",
      "tests/terror.nim", "tests/terrortree.nim",
      "tests/tintrospect.nim",
      "tests/tdecl_introspect.nim", "tests/tdecl_params.nim",
      # Datatypes
      "tests/tdatatypes.nim", "tests/tdatatypes_mutual.nim",
      "tests/tdatatypes_nary.nim",
      "tests/tdatatype_enum.nim",
      "tests/tdatatype_introspect.nim",
      "tests/tdatatype_sortof.nim",
      "tests/tdatatype_tuple.nim",
      "tests/tdatatype_update_field.nim",
      "tests/tdatatype_var_readraw.nim",
      # Quantifiers
      "tests/tquantifier.nim", "tests/tquantifier_intro.nim",
      "tests/tquantifier_nary.nim", "tests/tquantifier_ops.nim",
      # Tactics / probes / goals
      "tests/ttactic.nim", "tests/ttactic_combinators.nim",
      "tests/ttactic_enum.nim",
      "tests/tprobe.nim",
      "tests/tgoal_introspect.nim",
      # Optimize / fixedpoint / proof
      "tests/toptimize.nim", "tests/toptimize_extra.nim",
      "tests/toptimize_extra2.nim", "tests/toptimize_fp.nim",
      "tests/tfixedpoint.nim", "tests/tfixedpoint_callbacks.nim",
      "tests/tfixedpoint_extra.nim",
      "tests/tproof.nim",
      # Float (fp)
      "tests/tfp.nim",
      "tests/tfp_arith_lifts.nim", "tests/tfp_cmp_lifts.nim",
      "tests/tfp_eval.nim", "tests/tfp_from_parts.nim",
      "tests/tfp_numeral_decomp.nim", "tests/tfp_numeral_predicates.nim",
      "tests/tfp_renames.nim", "tests/tfp_sorts.nim",
      "tests/treal_float_lift.nim",
      # Strings / sequences / regex
      "tests/tstring.nim", "tests/tstring_codepoint.nim",
      "tests/tstring_introspect.nim", "tests/tstring_ordering.nim",
      "tests/tstringexport.nim",
      "tests/tsequence.nim",
      "tests/tseq_eval.nim", "tests/tseq_hof.nim",
      "tests/tseq_int_lifts.nim", "tests/tseq_replace.nim",
      "tests/tregex.nim", "tests/tregex_rename.nim",
      # Chars / arrays / sets / order / algebraic / RCF / spacer
      "tests/tchar.nim", "tests/tchar_ordering.nim",
      "tests/tcharbv.nim",
      "tests/tsets.nim",
      "tests/torder.nim",
      "tests/talgebraic.nim", "tests/talgebraic_introspect.nim",
      "tests/trcf.nim",
      "tests/tspacer.nim",
      # Functions / lambdas / uninterpreted
      "tests/tfuncdecl.nim", "tests/tfuncinterp.nim",
      "tests/tlambda.nim",
      "tests/tuninterpretedval.nim",
      "tests/trecfun.nim",
      "tests/tsubst_funs.nim",
      "tests/tonclause.nim",
      # Concurrency / global params / interrupts
      "tests/tconcurrency.nim", "tests/tconcurrency_logging.nim",
      "tests/tglobalparams.nim",
      "tests/tinterrupt.nim",
      "tests/tpseudo_boolean.nim",
      # Propagators
      "tests/tpropagator.nim", "tests/tpropagator_advanced.nim",
      "tests/tpropagator_ffi.nim",
      # Misc / context
      "tests/tscratch_ctx.nim",
      "tests/tsemantics.nim",
      "tests/tparamdescrs.nim",
      "tests/tparity.nim",
      "tests/tstats_consequences.nim",
      "tests/tunsat_core.nim",
      # Audit / meta-tests (N11.1 — these must stay wired in)
      "tests/tdoc_audit.nim",
      "tests/tinline_audit.nim",
      "tests/tnaming_audit.nim",
      "tests/trunnable_audit.nim",
      "tests/torphan_audit.nim"]:
    exec "nim c -r --threads:on --hints:off " & tf
    exec "nim cpp -r --threads:on --hints:off " & tf

task examples, "Compile + run every example on both backends":
  # Each example is itself a runnable test of the public API — if
  # the user's first encounter with the library is broken, nothing
  # else matters. Running them on both backends also catches any
  # accidental c-only / cpp-only regression in the example code.
  for ex in ["examples/basic_solve.nim", "examples/nqueens.nim",
             "examples/bitvec_solve.nim", "examples/pretty_and_smt2.nim",
             "examples/properties.nim", "examples/tactic_pipeline.nim",
             "examples/uninterpreted_axioms.nim",
             "examples/float_verification.nim",
             "examples/string_constraints.nim",
             "examples/optimize_scheduling.nim",
             "examples/array_memory.nim",
             "examples/datatypes_list.nim",
             "examples/smt2_roundtrip.nim"]:
    exec "nim c -r --threads:on --hints:off " & ex
    exec "nim cpp -r --threads:on --hints:off " & ex

task valgrind, "Memory-safety audit — run a subset of tests under valgrind, gate on `definitely lost: 0 bytes`":
  # v0.5 step 5 (goal 4) deliverable. Compiles each test in debug
  # mode and runs it under `valgrind --leak-check=full`. The
  # **gate** is "definitely lost: 0 bytes" — Z3 holds program-
  # lifetime allocations that show as "still reachable" (decl
  # tables, sort caches), Nim's GC arena shows as "possibly lost",
  # and libz3 itself triggers non-leak valgrind errors (invalid
  # reads inside Z3's internal data structures, several thousand
  # of them on a typical run). None of those are wrapper bugs.
  #
  # The task uses `--error-exitcode=0` so valgrind never fails the
  # run on its own, then greps the output for "definitely lost:
  # X bytes" where X != 0. If found, the build fails. This is the
  # plan-stated gate ("reports `definitely lost: 0 bytes`") and
  # the only criterion that maps cleanly to "the wrapper itself
  # has no leaks."
  #
  # Picks a representative subset covering every distinct
  # lifecycle code path (context, value families, ref handles,
  # cross-family generics). Running the full suite would take
  # ~15 minutes; the subset is the 80/20.
  #
  # `valgrind` and `libz3-dev` must be installed. CI is gated on
  # the same #1 blocker as the rest of the matrix; for now this
  # task is a local-dev audit.
  for tf in ["tests/tcontext.nim",
             "tests/tast.nim",
             "tests/tbitvec.nim",
             "tests/tsolver.nim",
             "tests/tmodel.nim",
             "tests/tdatatypes.nim",
             "tests/tfp.nim",
             "tests/tfixedpoint.nim",
             "tests/tprobe.nim",
             "tests/tparity.nim"]:
    let bin = tf[0 ..< tf.len - 4]  # strip .nim
    let logFile = bin & ".valgrind.log"
    exec "nim c --threads:on --hints:off -d:debug --debugger:native " &
         "--opt:none " & tf
    # `--error-exitcode=0`: never fail valgrind on errors. We parse
    # the leak summary ourselves and gate on the one line that
    # matters: definite leaks attributable to the wrapper.
    exec "valgrind --leak-check=full --error-exitcode=0 " &
         "--log-file=" & logFile & " " & bin
    # Grep is exit-0 on match, exit-1 on no match. Our gate:
    # the leak summary MUST contain "definitely lost: 0 bytes".
    exec "grep -F 'definitely lost: 0 bytes' " & logFile
    echo "  OK — `definitely lost: 0 bytes` confirmed for " & tf
  echo "valgrind audit: all subset tests reported `definitely lost: 0 bytes`"

task testMinimal, "Compile + run tests/tminimal.nim with all z3WithoutX flags set — verifies the umbrella's gateable theories are hidden and the always-on core still works":
  # v0.5 step 10 (goal 8) deliverable. Pins the canonical minimal
  # config:
  #   z3WithoutFP / Seq / Strings / Regex / FuncDecl / Datatypes /
  #   Optimize / Tactics
  # all set. Cascades implicitly disable Probe (via Tactics).
  #
  # The test (tests/tminimal.nim) has two suites:
  #   1. Core surface still works (Int/Bool/BV/Solver/Model/SMT2)
  #   2. Scope-hiding invariants (compiles() checks per gated family)
  #
  # Runs on both backends. CI integration is gated on the same
  # private-dep blocker (#1) as the rest of the matrix; locally
  # this task is the canonical 'flags work' verification.
  const flags =
    " -d:z3WithoutFP -d:z3WithoutSeq -d:z3WithoutStrings" &
    " -d:z3WithoutRegex -d:z3WithoutFuncDecl -d:z3WithoutDatatypes" &
    " -d:z3WithoutOptimize -d:z3WithoutTactics"
  exec "nim c -r --threads:on --hints:off" & flags &
       " tests/tminimal.nim"
  exec "nim cpp -r --threads:on --hints:off" & flags &
       " tests/tminimal.nim"
  echo "minimal-build verification: tracer + scope-hiding " &
       "invariants confirmed under the canonical full-flag config"

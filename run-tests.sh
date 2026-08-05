#!/usr/bin/env bash
#
# Test / example / audit runner for nim-z3.
#
# Replaces the former z3.nimble tasks. milpa is the dependency resolver
# (see ../milpa.kdl); it emits ../nim.cfg with the right --path: lines, so
# `nim c` / `nim cpp` Just Work with no manual paths. This is plain shell,
# not NimScript — nimble is not involved in the build at all, matching the
# project-wide convention (milpa / nkdl / intonaco / fresco).
#
# Usage (run from the repo root):
#   tests/run.sh test        [file...]   # the curated suite, both backends (default)
#   tests/run.sh examples    [file...]   # every example, both backends
#   tests/run.sh minimal                 # tminimal.nim under the canonical z3WithoutX flags
#   tests/run.sh valgrind    [file...]   # memory-safety subset, gate: `definitely lost: 0 bytes`
#
# An optional explicit file list overrides the curated list for `test` /
# `examples` / `valgrind` (handy for running one file locally).

set -euo pipefail
cd "$(dirname "$0")"   # repo root, regardless of caller's cwd

# --- curated lists (ported verbatim from the former z3.nimble tasks) --------

# `test`: 129 files. tminimal.nim is intentionally excluded — it needs the
# z3WithoutX flags at compile time; run it via the `minimal` subcommand.
TESTS=(
  # Core / always-on
  tests/tffi.nim tests/tffi_opaque.nim
  tests/tcontext.nim tests/tcontext_registry.nim
  tests/td3_ctx_release.nim
  tests/tsort.nim
  tests/tast.nim tests/tast_introspect.nim
  tests/tast_print_mode.nim
  tests/tastmap.nim
  tests/tastvector.nim
  tests/tboolean.nim
  tests/tarith.nim tests/tarith_conv.nim
  tests/tarith_extractors.nim tests/tarith_extras.nim
  tests/tarray.nim tests/tarray_extra.nim
  tests/tbitvec.nim tests/tbigbitvec.nim
  tests/tbitvec_opt.nim tests/tbitvec_overflow.nim
  tests/tbitvec_red_rot.nim tests/tbitvec_theory_conv.nim
  tests/tsolver.nim tests/tsolver_cube.nim
  tests/tsolver_misc.nim tests/tsolver_trail.nim
  tests/tmodel.nim tests/tmodel_construction.nim
  tests/tmodel_enum.nim
  tests/tpretty.nim
  tests/tproperty.nim
  tests/tversion.nim
  tests/tsimplify.nim tests/tsimplifier.nim
  tests/trewrite.nim
  tests/ttranslate.nim tests/ttranslate_generic.nim
  tests/ttranslate_parity.nim
  tests/thash.nim
  tests/tio.nim
  tests/terror.nim tests/terrortree.nim
  tests/tintrospect.nim
  tests/tdecl_introspect.nim tests/tdecl_params.nim
  # Datatypes
  tests/tdatatypes.nim tests/tdatatypes_mutual.nim
  tests/tdatatypes_nary.nim
  tests/tdatatype_enum.nim
  tests/tdatatype_introspect.nim
  tests/tdatatype_sortof.nim
  tests/tdatatype_tuple.nim
  tests/tdatatype_update_field.nim
  tests/tdatatype_var_readraw.nim
  # Quantifiers
  tests/tquantifier.nim tests/tquantifier_intro.nim
  tests/tquantifier_nary.nim tests/tquantifier_ops.nim
  # Tactics / probes / goals
  tests/ttactic.nim tests/ttactic_combinators.nim
  tests/ttactic_enum.nim
  tests/tprobe.nim
  tests/tgoal_introspect.nim
  # Optimize / fixedpoint / proof
  tests/toptimize.nim tests/toptimize_extra.nim
  tests/toptimize_extra2.nim tests/toptimize_fp.nim
  tests/tfixedpoint.nim tests/tfixedpoint_callbacks.nim
  tests/tfixedpoint_extra.nim tests/tfixedpoint_ctxbox.nim
  tests/tfixedpoint_handlers.nim tests/tfixedpoint_newlemma.nim
  tests/tfixedpoint_typed_callbacks.nim
  tests/tproof.nim
  # Float (fp)
  tests/tfp.nim
  tests/tfp_arith_lifts.nim tests/tfp_cmp_lifts.nim
  tests/tfp_eval.nim tests/tfp_from_parts.nim
  tests/tfp_numeral_decomp.nim tests/tfp_numeral_predicates.nim
  tests/tfp_renames.nim tests/tfp_sorts.nim
  tests/treal_float_lift.nim
  # Strings / sequences / regex
  tests/tstring.nim tests/tstring_codepoint.nim
  tests/tstring_introspect.nim tests/tstring_ordering.nim
  tests/tstringexport.nim
  tests/tsequence.nim
  tests/tseq_eval.nim tests/tseq_hof.nim
  tests/tseq_int_lifts.nim tests/tseq_replace.nim
  tests/tregex.nim tests/tregex_rename.nim tests/tregex_index.nim
  # Chars / arrays / sets / order / algebraic / RCF / spacer
  tests/tchar.nim tests/tchar_ordering.nim
  tests/tcharbv.nim
  tests/tsets.nim
  tests/torder.nim
  tests/talgebraic.nim tests/talgebraic_introspect.nim
  tests/talgebraic_bounds.nim
  tests/trcf.nim
  tests/tspacer.nim
  # Functions / lambdas / uninterpreted
  tests/tfuncdecl.nim tests/tfuncinterp.nim
  tests/tlambda.nim
  tests/tuninterpretedval.nim
  tests/trecfun.nim
  tests/tsubst_funs.nim
  tests/tonclause.nim
  # Concurrency / global params / interrupts
  tests/tconcurrency.nim tests/tconcurrency_logging.nim
  tests/tglobalparams.nim
  tests/tinterrupt.nim
  tests/tpseudo_boolean.nim
  # Propagators
  tests/tpropagator.nim tests/tpropagator_advanced.nim
  tests/tpropagator_ffi.nim tests/tpropagator_exception_wall.nim
  # Misc / context
  tests/tscratch_ctx.nim
  tests/tsemantics.nim
  tests/tparamdescrs.nim
  tests/tparity.nim
  tests/tmultiversion.nim
  tests/tstats_consequences.nim
  tests/tunsat_core.nim
  # Audit / meta-tests (must stay wired in)
  tests/tdoc_audit.nim
  tests/tinline_audit.nim
  tests/tnaming_audit.nim
  tests/trunnable_audit.nim
  tests/torphan_audit.nim
  tests/tmodule_coverage_audit.nim
  tests/tdocs_sweep_audit.nim
  tests/tmigration_audit.nim
  tests/tio_roundtrip.nim
)

EXAMPLES=(
  examples/basic_solve.nim examples/nqueens.nim
  examples/bitvec_solve.nim examples/pretty_and_smt2.nim
  examples/properties.nim examples/tactic_pipeline.nim
  examples/uninterpreted_axioms.nim
  examples/float_verification.nim
  examples/string_constraints.nim
  examples/optimize_scheduling.nim
  examples/array_memory.nim
  examples/datatypes_list.nim
  examples/smt2_roundtrip.nim
)

# valgrind subset: one file per distinct lifecycle code path (the 80/20).
VALGRIND=(
  tests/tcontext.nim tests/tcontext_registry.nim tests/td3_ctx_release.nim
  tests/tast.nim tests/tbitvec.nim tests/tsolver.nim tests/tmodel.nim
  tests/tdatatypes.nim tests/tfp.nim
  tests/tfixedpoint.nim tests/tfixedpoint_ctxbox.nim tests/tfixedpoint_handlers.nim
  tests/tfixedpoint_newlemma.nim tests/tfixedpoint_typed_callbacks.nim
  tests/tprobe.nim tests/tparity.nim
)

# Canonical minimal config — all gateable theories off (cascades disable Probe).
MINIMAL_FLAGS=(
  -d:z3WithoutFP -d:z3WithoutSeq -d:z3WithoutStrings
  -d:z3WithoutRegex -d:z3WithoutFuncDecl -d:z3WithoutDatatypes
  -d:z3WithoutOptimize -d:z3WithoutTactics
)

# --- helpers ----------------------------------------------------------------

# Compile + run one file on BOTH backends. cpp is a softlink-#12 regression guard.
run_both() {
  local f="$1"; shift
  nim c   -r --threads:on --hints:off "$@" "$f"
  nim cpp -r --threads:on --hints:off "$@" "$f"
}

# --- subcommands ------------------------------------------------------------

cmd="${1:-test}"; shift || true

case "$cmd" in
  test)
    files=("$@"); [ ${#files[@]} -eq 0 ] && files=("${TESTS[@]}")
    for f in "${files[@]}"; do run_both "$f"; done
    echo "test: ${#files[@]} file(s) passed on both backends"
    ;;
  examples)
    files=("$@"); [ ${#files[@]} -eq 0 ] && files=("${EXAMPLES[@]}")
    for f in "${files[@]}"; do run_both "$f"; done
    echo "examples: ${#files[@]} example(s) passed on both backends"
    ;;
  minimal)
    run_both tests/tminimal.nim "${MINIMAL_FLAGS[@]}"
    echo "minimal-build verification: scope-hiding invariants confirmed under the canonical full-flag config"
    ;;
  valgrind)
    # Gate: the leak summary MUST contain 'definitely lost: 0 bytes'. Z3's
    # program-lifetime allocations show as still-reachable/possibly-lost and
    # libz3 itself triggers non-leak valgrind errors — none are wrapper bugs.
    files=("$@"); [ ${#files[@]} -eq 0 ] && files=("${VALGRIND[@]}")
    for f in "${files[@]}"; do
      bin="${f%.nim}"; log="${bin}.valgrind.log"
      nim c --threads:on --hints:off -d:debug -d:useMalloc --debugger:native --opt:none "$f"
      valgrind --leak-check=full --error-exitcode=0 --log-file="$log" "$bin"
      grep -F 'definitely lost: 0 bytes' "$log"
      echo "  OK — 'definitely lost: 0 bytes' confirmed for $f"
    done
    echo "valgrind audit: all subset tests reported 'definitely lost: 0 bytes'"
    ;;
  *)
    echo "usage: tests/run.sh {test|examples|minimal|valgrind} [file...]" >&2
    exit 2
    ;;
esac

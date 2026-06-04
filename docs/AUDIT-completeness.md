# nim-z3 completeness audit — consolidated findings

**Date:** 2026-06-03
**Trigger:** proptest Phase 14 wrap-up surfaced multiple "nim-z3 doesn't expose this" walls for the planned Phase 15+ language-fragment expansion (`ref T` aliasing, exceptions, float, generics, closures, full strings, full Nim language).
**Inputs:** 4 parallel `/architect`-style agents (Sonnet), each with a distinct lens:
- Lens 1 — Theory coverage (Z3 C API ↔ nim-z3 wrappers)
- Lens 2 — Ergonomics (idiomatic Nim surface vs FFI-shaped)
- Lens 3 — proptest-needs gap (Phase 15+ blockers)
- Lens 4 — Consistency (cross-theory parity within nim-z3)

**Standing directives applied:**
- `complete-lib-not-consumer.md` — never defer by "no concrete consumer yet"; every gap is in scope.
- `nim-z3-proptest-only-consumer.md` — v1.0 SemVer is a milestone, not a constraint; breaking changes are fine. The 3 v1.x deferred items from the v1.0 audit are IN scope here.
- `audit-cycle-pattern.md` — multi-round, distinct lenses, stop at 0 CRITICAL/HIGH per round.

**Counts:** ~80 distinct findings across the four lenses.

---

## CRITICAL (7)

### C1. `Z3Set[E]` theory entirely missing
- **Source:** Lens 1
- **Z3 surface:** `Z3_mk_set_sort/empty_set/full_set/set_add/set_del/set_union/set_intersect/set_difference/set_complement/set_member/set_subset/set_has_size` (z3_api.h:3291–3378)
- **nim-z3:** zero FFI, zero typed surface
- **Note:** one of the 3 deferred v1.x items.
- **Proposed:** new module `src/z3/sets.nim` with `Z3Set[E] = Z3Array[E, Z3Bool]` alias plus typed combinators.

### C2. `Z3AstMap` type entirely missing
- **Source:** Lens 1
- **Z3 surface:** `Z3_mk_ast_map/ast_map_insert/find/contains/erase/reset/size/keys/to_string` (z3_ast_containers.h)
- **nim-z3:** not wrapped (astvector.nim has no map references)
- **Proposed:** new module `src/z3/astmap.nim`.

### C3. `Z3UninterpretedVal` type missing → blocks `ref T` aliasing
- **Source:** Lens 3
- **Z3 surface:** `Z3_mk_const` on `Z3_mk_uninterpreted_sort` — exists but no typed Nim wrapper.
- **nim-z3:** `mkUninterpretedSort` exists in `sort.nim:107` but there's no `Z3UninterpretedVal` AST family, no `mkUninterpretedVar`, no `sortOf` dispatch for uninterpreted values.
- **Blocks:** proptest `ref T` aliasing (Phase 15+ rectify deferral #136). Requires raw-FFI workaround otherwise.

### C4. `declareDatatypes` arity capped at 3 → blocks exception hierarchies + multi-recursive variants
- **Source:** Lens 2 (MEDIUM as ergonomic gap) + Lens 3 (CRITICAL as blocker) — consensus CRITICAL by impact
- **Z3 surface:** `Z3_mk_datatypes(c, num_datatypes, ...)` — unbounded N-ary (z3_api.h)
- **nim-z3:** `datatypes.nim:379, 457` ship arity 2 and 3 only; comment at `datatypes.nim:461` says "bump if a user needs N ≥ 4."
- **Blocks:** proptest exception-hierarchy encoding; mutually-recursive Nim variant types with 4+ parties.
- **Proposed:** macro-generate overloads through at least arity 8, or expose a `seq[ConstructorSpec]`-based N-ary form.

### C5. Polynomial theory entirely missing
- **Source:** Lens 1
- **Z3 surface:** `z3_polynomial.h` (`Z3_polynomial_subresultants` etc.)
- **nim-z3:** zero coverage. New module `src/z3/polynomial.nim` required.

### C6. RCF (Real Closed Field) theory entirely missing
- **Source:** Lens 1
- **Z3 surface:** `z3_rcf.h` — ~30 entry points including `Z3_rcf_mk_rational/mk_pi/mk_e/add/sub/mul/div/neg/inv/power/lt/le/gt/ge/eq/neq`.
- **nim-z3:** zero coverage. Exact real arithmetic including algebraic numbers, π, e, infinitesimals.
- **Proposed:** new module `src/z3/rcf.nim`.

### C7. Spacer + Algebraic theories entirely missing
- **Source:** Lens 1
- **Z3 surface:** `z3_spacer.h` (Spacer/IC3 CHC extensions: `Z3_fixedpoint_query_from_lvl`, `add_invariant`, `get_ground_sat_answer`, `get_rules_along_trace`, `Z3_model_extrapolate`, `Z3_qe_lite`, `qe_model_project`); `z3_algebraic.h` (~20 entry points for algebraic-number arithmetic).
- **nim-z3:** zero coverage for both.
- **Proposed:** new modules `src/z3/spacer.nim`, `src/z3/algebraic.nim`.

---

## HIGH (25)

### H1. Model enumeration API missing (deferred v1.x item)
- **Lens 1.** `Z3_model_get_num_consts/_const_decl/_num_funcs/_func_decl/_num_sorts/_sort/_sort_universe/_has_interp/_translate` (z3_api.h:5508–5613). One of the 3 v1.x deferred items. Blocks model inspection, function-interpretation enumeration, model translation.

### H2. BV overflow/underflow predicates missing
- **Lens 1.** `Z3_mk_bvadd_no_overflow/_no_underflow/bvsub_no_overflow/_no_underflow/bvsdiv_no_overflow/bvneg_no_overflow/bvmul_no_overflow/_no_underflow` (z3_api.h:3100–3177). Critical for verifying arithmetic safety properties.

### H3. Pseudo-boolean cardinality constraints missing
- **Lens 1.** `Z3_mk_atmost/atleast/pble/pbge/pbeq` (z3_api.h:4694–4736). Required for MaxSAT and optimization workloads.

### H4. Strings: ordering + codepoint + BV-to-string missing
- **Lens 1.** `Z3_mk_str_lt/str_le/string_to_code/string_from_code/ubv_to_str/sbv_to_str` (z3_api.h:3745–3876).

### H5. Strings: `replace_re`, `last_index`, `replace_all`
- **Lens 1 + Lens 2 + Lens 3 consensus.** `Z3_mk_seq_replace_re`, `Z3_mk_seq_last_index`, `Z3_mk_seq_replace_all`. Lens 1 notes these may need Z3 ≥ 4.13.2 — verify against bundled header version.

### H6. Strings: `Z3_get_string_contents` for codepoint extraction
- **Lens 1.** `Z3_get_string_contents` (z3_api.h:3683) — needed for correct multi-byte round-trip.

### H7. Seq: HOF operations missing (`map`, `mapi`, `foldl`, `foldli`)
- **Lens 1.** `Z3_mk_seq_map/_mapi/_foldl/_foldli` (z3_api.h:3814–3832).

### H8. Seq: indices require manual `mkInt(n)` wrapping
- **Lens 2.** `nth`, `at`, `substr`, `indexOf` all need `Z3Int` arguments; no `int`-literal lifts. Numeric families have lifts; sequences are the outlier.

### H9. FPA: shorthand rounding modes + sort aliases + `mk_fpa_fp` + numeral decomposition
- **Lens 1.** `Z3_mk_fpa_rne/rna/rtp/rtn/rtz` (z3_fpa.h:77–213), `Z3_mk_fpa_sort_half/single/double/quadruple` (247–343), `Z3_mk_fpa_fp` (432) — construct FP from sign/exp/sig BVs, `Z3_fpa_is_numeral_nan/inf/zero/normal/subnormal/positive/negative` (1105–1189), `Z3_fpa_get_numeral_sign/significand_*/exponent_*` (1213–1302).

### H10. FPA: missing `==`/`!=`/`<`/`<=`/`>`/`>=`/`+`/`-`/`*`/`/` literal lifts for `float64`/`float32`
- **Lens 2 + Lens 4 consensus.** `Z3Fp` is the only numeric family with no native-literal arithmetic + comparison overloads. ~10 procs to add via existing `liftBin`/`liftCmp` templates.

### H11. FPA: `toFloat64Opt` / `toFloat32Opt` missing
- **Lens 2.** `Z3Int.toIntOpt`/`Z3Bool.toBoolOpt` exist; FP has only raising forms.

### H12. FPA: `toFp` overload ambiguity (lossless bit-reinterpret vs lossy precision conversion)
- **Lens 2.** Rename `toFp(bv: Z3BitVec, _: typedesc[Z3Fp[E,S]])` → `bvToFpBits` (pairs with existing `toIeeeBv`).

### H13. FPA: `evalFloat32`/`evalFloat64` only on concrete aliases, not generic `Z3Fp[E,S]`
- **Lens 4.** Breaks parity with `evalUint[W]`/`evalInt[W]` on `Z3BitVec[W]`.

### H14. Arith: `abs`, `power`, `divides`, `isInt`, `mkRealInt64` missing
- **Lens 1.** `Z3_mk_abs/power/divides/is_int/real_int64` (z3_api.h:2547–3466).

### H15. `Z3Real`: no `float64` literal lift, `toRealApprox` naming asymmetry
- **Lens 2 HIGH + Lens 4 MEDIUM.** All other numeric families accept native literals. Comment justifies omission ("floats aren't exact rationals") but that reasoning doesn't apply to ergonomic lifts that convert via decimal-string representation.

### H16. `Z3_mk_int2real` / `Z3_mk_real2int` / `Z3_mk_is_int` not even in FFI
- **Lens 4.** Standard SMT-LIB 2 operations (`to_real`, `to_int`, `is_int`) absent from the entire wrapper.

### H17. `intToBv` / `bvToInt` not exposed publicly (already in FFI, used internally)
- **Lens 4.** `Z3_mk_bv2int` / `Z3_mk_int2bv` are bound in `ffi.nim` and used by `toBigIntStr` + `optimize.wrapBound`, but no public procs exist. Zero-cost fix.

### H18. BV: `redand`, `redor`, `ext_rotate_left/right`, `bv_numeral` missing
- **Lens 1.** `Z3_mk_bvredand/bvredor/ext_rotate_left/ext_rotate_right/bv_numeral` (z3_api.h:2664–3522).

### H19. Datatypes: `enum_sort`, `tuple_sort`, `rec_func_decl` + `add_rec_def`, `update_field` missing
- **Lens 1.** `Z3_mk_enumeration_sort` (2023), `Z3_mk_tuple_sort` (1994), `Z3_mk_rec_func_decl` + `Z3_add_rec_def` (2329, 2349), `Z3_datatype_update_field` (4661). Enumeration sort is the canonical finite-sum primitive; tuple sort is Z3's product type; recursive function defs allow self-referential definitions; update_field is the functional record update.

### H20. Optimize module: 8+ missing procs
- **Lens 1.** `Z3_optimize_assert_and_track/get_unsat_core/from_file/from_string/get_help/get_statistics/get_assertions/get_objectives/set_initial_value` + multi-objective `get_lower_as_vector/get_upper_as_vector`.

### H21. Fixedpoint: `from_file`/`from_string`/`get_param_descrs` missing
- **Lens 1.** Mirrors solver/optimize gaps.

### H22. Arrays: N-ary arrays + `array_map` + `array_ext` + `as_array` missing
- **Lens 1.** `Z3_mk_array_sort_n`, `Z3_mk_select_n`, `Z3_mk_store_n`, `Z3_get_array_sort_domain_n`, `Z3_mk_map`, `Z3_mk_array_ext`, `Z3_mk_as_array`, `Z3_is_as_array`, `Z3_get_as_array_func_decl`. arrays.nim:42 explicitly punts `array_ext` as "niche, not on the surface" — that's the consumer-driven framing the standing directive rejects.

### H23. Solver: trail/units/cube/set_initial_value/propagator missing
- **Lens 1.** `Z3_solver_get_trail/get_units/get_non_units/get_levels/cube/congruence_root/congruence_next/set_initial_value` + entire user-propagator plugin API (`propagate_init/fixed/final/eq/diseq/created/decide/next_split/declare/register/consequence/register_on_clause/import_model_converter`).

### H24. `Z3Char` missing `>` / `>=` ordering operators
- **Lens 2 + Lens 4 consensus.** Only ordered family missing the symmetric pair. 2-line synthesis fix.

### H25. `translate` only generic over `Z3Term`
- **Lens 2.** `Z3FuncDecl`, `Z3Sort`, `Z3Model` translation missing (Solver has it).

### H26. Module doc-header `z3/` prefix inconsistency
- **Lens 4.** Six older modules (`arith`, `boolean`, `bitvec`, `arrays`, `datatypes`, …) lack the `## \`z3/modulename\` — …` convention used by newer ones.

### H27. `mkDatatypeVar` non-parallel signature
- **Lens 4.** Only `mk*Var` constructor without the `(name: string)` implicit-current-context form. Outlier from the entire `mk*Var` family.

### H28. FP `mkNaN`/`mkInf`/`mkZero` no theory prefix
- **Lens 2 LOW + Lens 4 HIGH consensus HIGH.** `mkZero` collides with any future `mkIntZero`/`mkRealZero`. Rename `mkFpNaN`/`mkFpInf`/`mkFpZero`.

### H29. Cross-theory conversion naming split (`strToInt` vs `toReal`)
- **Lens 4.** `strings.nim` is the only module using `*To*` form; every other cross-theory conversion uses the `to*` receiver-method form. Rename to `Z3String.toInt` / `Z3Int.toStr`.

### H30. Exception `readRaw` escape hatch for dynamic field type dispatch
- **Lens 3.** `read(accessor)` requires statically-known field type. Dynamic dispatch (e.g. from a model-enumerated value) forces raw `Z3_mk_app` + `Z3_get_sort` introspection.

---

## MEDIUM (~30)

Summarized; details in raw agent outputs. Notable items:

- **Solver:** `mkSimpleSolver`, `mkSolverForLogic`, `addSimplifier`, `numScopes`, `toDimacs`, `importModelConverter` (Lens 1).
- **Tactic / Simplifier:** entire `Z3Simplifier` object type missing (added Z3 ~4.12); tactic + probe + simplifier enumeration; `parAndThen`/`parOr`/`when`/`failIf`/`failIfNotDecided` (Lens 1).
- **Goal:** `depth`, `numExprs`, `reset`, `translate` (Lens 1).
- **AstVector:** `translate` overload (Lens 1).
- **Model:** programmatic construction (`mkModel`, `addConstInterp`, `addFuncInterp`, `func_interp_set_else`, `func_interp_add_entry`) (Lens 1).
- **Algebraic numbers:** `is_algebraic_number`, `get_algebraic_number_lower/upper` for inspecting Real model values that aren't rational (Lens 1).
- **Datatype sort introspection:** `num_constructors`, `constructor`, `recognizer`, `accessor` decls for opaque sorts arriving from model enumeration (Lens 1).
- **FuncDecl introspection:** `name`, `arity`, `domain`, `range`, parameter accessors for parametric decls (Lens 1).
- **Quantifiers:** `getQuantifierId`/`SkolemId`; `substituteVars` for de-Bruijn instantiation (Lens 1 + Lens 3); arity > 5 (Lens 2).
- **Introspect:** `isWellSorted`, `isApp`, `isNumeralAst`, `astId`, `sortId`, `indexValue` (de-Bruijn) (Lens 1).
- **Relation sorts:** `get_relation_arity`/`column` (Lens 1).
- **Rewrite:** `substituteFuns` for function-level substitution (Lens 1).
- **Fresh names:** `mkFreshConst`, `mkFreshFuncDecl` for Skolemization (Lens 1).
- **Order theory:** `linear_order`, `partial_order`, `piecewise_linear_order`, `tree_order`, `transitive_closure` (Lens 1).
- **Context:** `enable_concurrent_dec_ref` for multi-threaded GC safety (Lens 1); `newContext` clobbers current-context invisibly (Lens 2).
- **Eval shortcuts:** `evalBigRealStr` (Lens 2); `evalSeq` for non-string sequences + naming clarification (Lens 4).
- **Z3BitVec / Z3Real:** missing `Option`-returning extractors (`toUintOpt`/`toIntOpt`/`toRealApproxOpt`) (Lens 2 + Lens 4).
- **Optimize:** extend constraint set to allow `Z3Fp` objectives (Lens 2).
- **IO:** `parseSmt2String` loses decl handles; `smt2Script` hardcodes `(check-sat)` footer (Lens 2).
- **Inline-pragma discipline:** inconsistent across theories (Lens 4).
- **Test source hygiene:** 4 orphan binaries (`tseq`, `trange`, `tdbg`, `tdbgcat`) without `.nim` sources (Lens 4).
- **Test coverage parity:** `tchar.nim` 46 lines vs other theory tests at 100–330 (Lens 4).

---

## LOW (~15)

- `params_validate` (Lens 1).
- Logging API (`open_log/close_log/append_log/toggle_warning_messages`) (Lens 1).
- `is_string_sort`/`is_seq_sort`/`is_re_sort`/`is_char_sort` (mostly redundant via `SortKind`) (Lens 1).
- `Z3_mk_bit` (Bool → 1-bit BV) (Lens 1).
- `Z3_mk_finite_domain_sort` (research-grade) (Lens 1).
- `roundToIntegral` could have `floor`/`ceil`/`trunc`/`roundEven` convenience aliases (Lens 2).
- `bvult`/`bvule`/... could have shorter `ult`/`ule`/... aliases (Lens 2).
- `smtEquiv` on `Z3Fp` documentation gap (IEEE vs structural) (Lens 2).
- `Z3Renderable` concept verification across `Z3Stats`/`Z3ParamDescrs`/`Z3AstVector` (Lens 2).
- `datatypeRegistry` field exposed instead of through accessor (Lens 2).
- `Z3Sort[S]` no lifecycle hooks if dynamically-created sorts ever refcount independently (Lens 2).
- `Z3Fixedpoint.addFact` (perf, not correctness) (Lens 2).
- `Z3Params` no get surface (Z3 API limitation, not nim-z3) (Lens 2).
- `mkRegexAll` confusable with `mkRegexFull` — rename `mkRegexAllChar` (Lens 4).
- `runnableExamples` only used in `model.nim` (Lens 4).
- Doc-style heterogeneity for `## \`\`\`nim` blocks vs `runnableExamples` (Lens 4).

---

## Cross-lens triangulation (where multiple lenses found the same issue)

| Finding | Lens 1 | Lens 2 | Lens 3 | Lens 4 | Consensus |
|---|---|---|---|---|---|
| `declareDatatypes` arity 3 cap | — | MED | CRITICAL | — | **CRITICAL** |
| Strings `replaceAll` / `lastIndexOf` / `replace_re` | HIGH | MED ×2 | HIGH ×2 | — | **HIGH** |
| FP literal lifts missing | — | HIGH ×4 / MED ×3 | — | MED | **HIGH** (consolidated) |
| `Z3Char` missing `>` / `>=` | — | HIGH | — | HIGH | **HIGH** |
| FP `mkNaN`/`mkInf`/`mkZero` no theory prefix | — | LOW | — | HIGH | **HIGH** |
| `Z3Real` no float lift + `toRealApprox` naming | — | HIGH | — | MED | **HIGH** |

---

## Sizing

- **~80 distinct findings** across 7 CRITICAL / 30 HIGH / 30 MEDIUM / 15 LOW.
- **New modules required:** `sets.nim`, `astmap.nim`, `simplifier.nim`, `polynomial.nim`, `rcf.nim`, `spacer.nim`, `algebraic.nim`, plus likely `propagator.nim` and `order.nim`. ~9 new modules.
- **FFI additions:** large — Lens 1's per-theory gap table covers most. Estimate ~150 new `Z3_*` FFI entries plus ~50 typed-Nim wrappers per major-theory gap.
- **Effort estimate:** comparable to v1.0 audit cycle (multiple weeks of focused work). Subdivide into clusters matching the audit's CRITICAL → HIGH → MEDIUM → LOW priority.

## Suggested cluster decomposition for the RFC

1. **Cluster N1 — Missing whole theories** (the 7 CRITICAL): Sets, AstMap, UninterpretedVal, declareDatatypes-N, Polynomial, RCF, Spacer+Algebraic. Each is a new module or major existing-module extension.
2. **Cluster N2 — Model + introspection** (H1, several MEDIUMs): model enumeration, model construction, datatype introspection, funcdecl introspection, isWellSorted/etc.
3. **Cluster N3 — BV completeness** (H2, H18): overflow predicates, reductions, ext_rotate, bv_numeral, public intToBv/bvToInt (H17), mk_bit (LOW).
4. **Cluster N4 — Arith completeness** (H14, H16): abs/power/divides/isInt/mkRealInt64/int2real/real2int/is_int + algebraic-number bounds (MEDIUM).
5. **Cluster N5 — Strings + Seq completeness** (H4, H5, H6, H7, H8): ordering, codepoint, BV-to-string, get_string_contents, replace_*/last_index, HOF map/foldl, int-literal lifts.
6. **Cluster N6 — FPA completeness** (H9, H10, H11, H12, H13, H28): shorthand RMs, sort aliases, mk_fpa_fp, numeral decomposition, literal lifts, Option-returning extractors, `bvToFpBits` rename, evalFp generic, mkFp{NaN,Inf,Zero} rename.
7. **Cluster N7 — Datatypes + Optimization + Fixedpoint** (H19, H20, H21, H22, H27, H30): enum/tuple/rec_func/update_field, optimize assert_and_track + getUnsatCore + from_string/file + statistics + objectives + set_initial_value, fixedpoint from_*, mkDatatypeVar fix, exception readRaw escape hatch.
8. **Cluster N8 — Solver + Tactic + Simplifier** (H23 + MEDIUMs): trail/units/cube/set_initial_value, propagator plugin (LARGE — could split), mkSimpleSolver/mkSolverForLogic, addSimplifier + whole `Z3Simplifier` family, tactic enumeration + parallel combinators, Goal introspection.
9. **Cluster N9 — Pseudo-boolean + Order + Misc** (H3, several MEDIUMs): atmost/atleast/pb, linear/partial/tree order, transitive closure, substituteFuns, fresh names, AstVector.translate.
10. **Cluster N10 — Consistency + ergonomics pass** (H24, H25, H26, H29, H15 plus MEDIUM/LOW): rename strToInt/intToStr, mkDatatypeVar parallel form, translate generics for FuncDecl/Sort, doc-header prefix, Z3Char `>`/`>=`, Z3Real `toReal` + float lift, missing `Option`-returning extractors, inline-pragma discipline, ergonomic literal-lift completeness.
11. **Cluster N11 — Test hygiene + docs** (LOWs): orphan binaries, `runnableExamples` adoption, doc-style consolidation, theory-test parity for `tchar.nim`, `mkRegexAllChar` rename.

Each cluster is its own multi-cycle batch. Suggested ordering: N1 → N2 → N3-N7 in parallel where possible → N8 (propagator may split) → N9 → N10 → N11. Walker version of nim-z3 should bump at the end of each cluster that breaks API.

---

## Next steps

`/flow` will route this into:
1. **RFC drafting** — translate this finding list into `docs/RFC-completeness.md` in nim-z3 (one cluster per major section, each with cycle definitions).
2. **Round 1 architect review** — 4 parallel agents against the RFC.
3. **Round 2 architect review** — after applying round 1 fixes.
4. **TDD cycles** via `/loop` with the standing rules.

The RFC will need to escalate to user only on genuine forks — and given the standing directives, "consumer demand" is not a fork.

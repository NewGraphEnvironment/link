# Task: Before the next provincial default run: a deterministic crossing pick and the US dams as barriers (#367)

**If done:** the next provincial `default` run (#361) is built at a release whose output is reproducible run to run and whose Columbia groups see the US dams below them. **If never:** that run ships with both known gaps, and the next run that fixes either has to re-model every group again.

## Decided at the gate (operator approved the plan, 2026-10-22)

1. **#244 is a `default` position, not a parity change.** A pipeline knob in `default`'s `config.yaml`, inherited by `default_tuned`; absent means today's behaviour, so the `bcfishpass` config stays faithful to bcfishpass.
2. **The guard sees the placeholders when the knob is on.** The pipeline and the guard share their dam SQL so they cannot disagree, and a group upstream of a placeholder needs that downstream group persisted first like any other dam.
3. **#277's tie-break is "closest modelled crossing, then lowest id".** Append `modelled_xing_dist ASC, modelled_crossing_id ASC NULLS LAST` after `linear_feature_id ASC`, so no pick that is deterministic today changes.

## What exploration found

- **#277.** `R/lnk_pipeline_pscis_build.R` step 4 calls `fresh::frs_candidates_pick()` (`DISTINCT ON (stream_crossing_id) ORDER BY ...`) with `name_score DESC, weighted distance ASC, linear_feature_id ASC`. Candidates come from a LEFT JOIN to every modelled crossing within 100 m on the same `blue_line_key`, so one PSCIS × stream pair can carry two modelled crossings with identical score and distance. bcfishpass's `04_pscis.sql` (`order by stream_crossing_id, name_score desc, weighted_distance`) ties the same way.
- **#244.** The `usa` CTE in `.lnk_pipeline_prep_dams()` writes `NULL::integer AS passability_status_code`, and `.lnk_crossings_union()`'s CASE has no NULL arm. **bcfishpass does the same:** `load_dams.sql` also inserts NULL, and `load_crossings.sql` inner-joins `cabd.dams` on `cabd_id`, so its placeholders never become crossings either. That makes link's `bcfishpass` config faithful today. The downstream guard (`R/lnk_wsg_downstream_check.R:176-178`) documents that the placeholders "never appear".
- All four bundles carry the same `cabd_additions.csv` (csv-synced for `bcfishpass` and `default`).
- The golden dams test (`tests/testthat/test-lnk_pipeline_prepare.R`) pins ADMS at 8; a current `cabd.dams` gives 7 (#345).

## Phase 1 — #277: a deterministic crossing pick
- [x] Move the pick's `order_by` into one internal constant used by `.lnk_pipeline_pscis_build()`, and end it on `modelled_xing_dist ASC, modelled_crossing_id ASC NULLS LAST`
- [x] Measure province-wide that `(stream_crossing_id, linear_feature_id, modelled_crossing_id)` is unique among rows passing the pick filter; if not, extend the key until it is, and record the query in findings
- [x] Test: the existing mock test asserts the full `order_by`; a DB test (`skip_if_no_db()`) builds a synthetic tie, inserts it in two row orders, and asserts one pick
- [x] Audit every `DISTINCT ON` / `ORDER BY` on the crossings path (`lnk_pipeline_pscis_build.R`, `lnk_crossings_union.R`, the dam prep): list each one and whether it ends on a unique key; fix any that can change output, and note the rest in findings

## Phase 2 — #244: the US dam placeholders as barriers in `default`
- [x] Add the pipeline knob to `default/config.yaml` with a comment saying why it differs from bcfishpass; the `usa` CTE writes `passability_status_code = 1` when it is on
- [x] `lnk_wsg_downstream_check()` includes the placeholders under the same knob, and its documentation says so
- [x] Tests: dam-prep SQL for both knob states (off is byte-identical to today); the guard's filter with the knob on
- [x] #345: find which ADMS dam left `cabd.dams`, confirm it is upstream data, and re-pin the golden test on dam IDs with the CABD row count and load date in its comment
- [x] Query which groups hold the five placeholders and which segments would take `DAM`; record it in findings

## Corrections from the plan review (2026-10-22, folded in after Phases 1-2)

The Plan review (`planning/active/review-plan.md`) disproved part of the plan; corrected without a new gate, because each follows the function's stated contract of mirroring bcfp or the plan's own acceptance:
- [x] **The tie came from a missing bcfp step**, not from bcfp tying the same way: bcfp's `02_pscis_streams_150m.sql` keeps one modelled crossing per PSCIS per blue line (nearest instream) before the pick, and link skipped it. Ported as Step 3b with an id tie-break. This moves picks toward bcfp's (ADMS-wide test: 656 PSCIS change modelled crossing, 56 change stream), so bcfishpass parity can move; the parity re-score after the provincial run (#361) measures it. The gate's tie-break terms stay as the last resort.
- [x] Barrier ids numbered in a stated order (`lnk_barriers_unify()`: gradient, falls, user-definite, subsurface), and both KNN snaps end on `linear_feature_id`
- [x] Placeholders numbered in CSV order (bcfp's ids, stated), and a placeholder is a barrier only where its `barrier_ind` is true
- [x] The `config.yaml` comment states the `DAM` change per flavour (resident: next anthropogenic barrier; anadromous: any dam downstream unless remediated)
- [x] The persisted-`fresh.barriers` psc-NULL test removed: `default` also persists to `fresh` by default, and the new prep test covers both knob states
- [x] Decided, not taken: `default_extrabreaks` / `default_rearbreaks` are `extends: ~` experiment bundles and stay off the knob

## Phase 3 — Verify on real groups (revised after review: isolate each change)
- [x] Reproducibility (#277): ADMS and ELKR built twice at branch HEAD (`fresh_367a`, `fresh_367b`); `streams`, `barriers` and habitat identical, matching segments on start and length. Plus the in-process evidence already measured: main's code gave 464 different picks between two builds minutes apart, the branch 0
- [x] Effect of the pick change: ADMS, ELKR and NATR at main (`fresh_367m`, frozen worktree) against branch (`fresh_367a`): segments, accessible / spawning / rearing km per species
- [x] #244 isolated: LARL, KETL and SKGT with the knob on (`fresh_367a`) and off (`fresh_367c`, a scratch bundle extending `default`), both recomputed; expect identical segments, access and habitat, and mapping codes that differ only to `DAM`, per flavour
- [x] Upstream groups (Columbia above the border, Kettle, Skagit) are predicted from the placeholder positions, not rebuilt; the provincial run is their measurement
- [x] Record the results with their environment stamp in `data-raw/logs/provincial_prep_367/`

## Phase 4 — Docs and release
- [x] NEWS, RUNBOOK (dams and the crossings pick), and the `CLAUDE.md` status, including the stale "Full-run digests are not reproducible on main" note
- [x] RUNBOOK (done; #361 owed after merge): with the knob on, the guard fails for groups upstream of a placeholder until KETL, LARL and SKGT are re-persisted at v0.68.0, so the existing `fresh_default` fails `wsg_recompute_one.R`'s error-mode check for them
- [x] Edit the bodies of #277, #244 and #345 to what was found and done
- [x] `devtools::test()` (964 tests, 3,788 expectations, 0 failed), `devtools::check()` (0 errors; 3 warnings and 3 notes, all present on main: non-ASCII counts per file unchanged), `lintr::lint_package()` (no new lints beyond file-style indentation and the stale-install object_usage false positive)
- [x] Bump DESCRIPTION to 0.68.0 as the last commit

## Owed at the end (reported, done after merge)
- [ ] Tag v0.68.0 (`/gh-pr-merge`, on your word)
- [ ] Update #361's "Before the run" checklist (v0.68.0, schema rename, `--refresh-primitives`); close #339
- [ ] Draft, not post, a note to bcfishpass on its `load_crossings.sql` dropping the placeholders, if its `load_dams.sql` comment shows they were meant to count

## Validation

- [x] Tests pass (final: 968 tests, 3,800 expectations, 0 failed)
- [x] `/code-check branch`: four rounds; rounds 2 and 4 found defects inside earlier fixes, so the loop ended on the enumeration in findings.md (every ordering construct, `UPDATE ... FROM` and measure-range join in `R/` and its readers), not on a clean round
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion

Verification: Phase 3 (two same-input builds of ADMS and ELKR diff to 0 segments; placeholder groups' mapping codes differ from `fresh_default` only in `DAM` tokens), plus the unit and DB tests in Phases 1-2.

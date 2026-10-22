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
- [ ] Add the pipeline knob to `default/config.yaml` with a comment saying why it differs from bcfishpass; the `usa` CTE writes `passability_status_code = 1` when it is on
- [ ] `lnk_wsg_downstream_check()` includes the placeholders under the same knob, and its documentation says so
- [ ] Tests: dam-prep SQL for both knob states (off is byte-identical to today); the guard's filter with the knob on
- [ ] #345: find which ADMS dam left `cabd.dams`, confirm it is upstream data, and re-pin the golden test on dam IDs with the CABD row count and load date in its comment
- [ ] Query which groups hold the five placeholders and which segments would take `DAM`; record it in findings

## Phase 3 — Verify on real groups
- [ ] Two full builds of ADMS from the same inputs into two scratch schemas; diff segment by segment, matching start and length: expect 0 differences (#277). Do the same for ELKR, which also had the tie in #362
- [ ] Build the groups holding placeholders (from Phase 2) under `default` into a scratch schema, recompute, and diff mapping codes against `fresh_default` (same 2026-10-17 primitive load): expect changes only to `DAM` tokens on segments with no other anthropogenic barrier downstream
- [ ] Record the results with their environment stamp in `data-raw/logs/provincial_prep_367/`

## Phase 4 — Docs and release
- [ ] NEWS, RUNBOOK (dams and the crossings pick), and the `CLAUDE.md` status
- [ ] Edit the bodies of #277, #244 and #345 to what was found and done
- [ ] `devtools::test()`, `devtools::check()`, `lintr::lint_package()`
- [ ] Bump DESCRIPTION to 0.68.0 as the last commit

## Owed at the end (reported, done after merge)
- [ ] Tag v0.68.0 (`/gh-pr-merge`, on your word)
- [ ] Update #361's "Before the run" checklist (v0.68.0, schema rename, `--refresh-primitives`); close #339
- [ ] Draft, not post, a note to bcfishpass on its `load_crossings.sql` dropping the placeholders, if its `load_dams.sql` comment shows they were meant to count

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification: Phase 3 (two same-input builds of ADMS and ELKR diff to 0 segments; placeholder groups' mapping codes differ from `fresh_default` only in `DAM` tokens), plus the unit and DB tests in Phases 1-2.

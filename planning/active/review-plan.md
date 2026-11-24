# Plan review for #479 (backlog move 11: what blocks access at a barrier)

Blockers raised: 4
Owner forks: 4

Run 2026-11-24, before the baseline, by a read-only Plan agent against `planning/active/task_plan.md`, the five member issues and the code at `c7abea13`. The counts are what the review raised before anything was folded in; the four owner forks are open decisions 1 (option (c) added), 6, 7 and 8 in `task_plan.md`. Each finding below carries the planning session's verdict after a probe.

## Blocker

- **B1. `.lnk_lift_rules(loaded)` could not hold the mixed-floor refusal.** The refusal applies only under `lift_floor` and only to a rule with a threshold above 0 (`R/lnk_observation_records.R:77`, `:99`), and the shipped `bcfishpass` bundle mixes floors without it. Moving it out of `.lnk_observation_species_map()` would also take it off `lnk_vocabulary_resolve()`'s path. **Confirmed, folded:** the reader takes `cfg`, keeps both gates, and the species map calls it; two tests added (Phase 2).
- **B2. No rule for a position whose owner never holds it** (#386's 2 rows and 285 rows; groups the run never models). **Confirmed, folded as open decision 8**, asked only if Phase 1's measurement finds any; the diff script gives them their own category.
- **B3. Where the override and evidence filter sits was unspecified, and filtering by the owner of a rounded position loses lifts at a group boundary.** `natural_barriers` rounds measures and joins FWA with no pick (`R/lnk_pipeline_prepare.R:543-549`). **Confirmed, folded:** the owner is taken once on `gradient_barriers_raw`, and persist keeps an override or evidence row only where the group's own working `barriers` holds a natural row within 1 m (Phase 1).
- **B4. The new verify checks would judge nothing**, being gated on a `link_version` the proof builds do not log until the last commit (`data-raw/study_area_verify.sql:777`, the 0.84.0 gate's form). **Confirmed, folded:** the gate is a psql variable, and each case must judge at least one group (Phase 1).

## Gap

- **G1. `lift_rule` in the evidence key is a key migration**, which `CREATE TABLE IF NOT EXISTS` does not perform (`R/lnk_persist_init.R:613-617`). **Confirmed, folded:** the steps are named, with a test on an old-key table; the consolidate refuses an unmigrated destination (Phase 2).
- **G2. Under decision 3 (a) no bundle declares the lifts table, and the dictionary test needs a declaring bundle** (`tests/testthat/test-dictionaries.R:261-264`). **Confirmed, folded:** the dictionary is tested against the reader's column constant and a fixture (Phase 2).
- **G3. The rule shape could not express slope × length, nor keep the province's result where a measurement is null.** `inst/extdata/thresholds_default.csv` holds `slope_length`. **Confirmed, folded:** a derived column in the PSCIS source and `is_null` / `not_null` operators (Phase 3, D3).
- **G4. Asks neither planned, drafted nor deferred:** #236's optional group-scoped rule; #341's sources beyond PSCIS and its side-by-side export; #83's age cutoff and its `dimensions.csv` location. **Confirmed, folded:** named under "Named and not built here", in Owed, and in the draft issue.
- **G5. `observation_species` readers that bypass the single reader** (`R/lnk_presence_check.R:251-258`, two `data-raw/` scripts). **Confirmed, folded:** the presence check reads the rule frame; the scripts move under decision 3 (b) (Phase 2).
- **G6. "Complete by construction" was claimed while only gradient rows get an owner test.** Falls and user-definite rows are filed by their files' groups. **Confirmed, folded:** falls are measured and the docs are worded to what was measured (Phase 1).
- **G7. The pre-run gate map** needs rows for the two bundle files with the right input, and loses rows under decision 4 (a). **Confirmed, folded** (Phases 3 and 4).

## Ordering

- **O1. The candidate-rule measurement could not run as written:** `lnk_pipeline_run()` drops `observations_province` on exit (`R/lnk_pipeline_run.R:230-233`). **Confirmed, folded:** it is rebuilt, used and dropped (Phase 2).
- **O2. The kept working schemas are whichever build ran last.** **Confirmed, folded:** each proof build has its own working schemas through `schema =` (D9).
- **O3. The proof builds need the recompute pass**, or access differs by build order once copies are gone. **Accepted on the reviewer's reasoning, folded** (D9).
- **O4. The compare's groups were not in the proof set:** #321's parity groups are ADMS and BULK under `bcfishpass` (`data-raw/logs/crossings_upstream_478/stamp.csv`), and `crossings` is not persisted. **Confirmed, folded:** BULK joins the set and the compare names what it reads (Phases 1 and 3).

## Assumption

- **S1. `crossings` has no `stream_crossing_id`** (`R/lnk_crossings_union.R:132-133`). **Confirmed, folded:** the join is on `aggregated_crossings_id` with `crossing_source = 'PSCIS'` (Phase 3). The view holds one row per crossing on this host (19,905 of 19,905).
- **S2. The fallback was silent in the pipeline too.** **Folded:** the helper always writes the column there, so absence means a caller's own table (D4).
- **S3. D3 and D4 disagreed on row order.** **Confirmed, folded:** the marker holds every matching id, sorted (D4).
- **S4. Per-rule floor equality refuses a sound stricter rule.** **Declined for now, named:** equality is today's refusal; relaxing it is a later change (D11).

## Scope

- **C1. The split is one-sided:** the #201 + #83 piece persists every main-line crossing, so it needs its own province-wide rebuild of `barriers`, and a "barrier kinds" column on the lifts table would re-spec `acc` later. **Confirmed. An owner fork:** open decision 1 now states the cost and offers (c), storing the new shape in this PR; the lifts table carries `barrier_kinds` now (D3).
- **C2. Two token choices the plan had decided are the owner's:** whether a rule that moves marks and no access belongs in `acc` (RUNBOOK §6b, "What gets no token"), and whether cut tokens move when controls prune other positions (#478 minted cut rows for a code-only move; the control file is in the cut spec, `R/lnk_vocabulary.R:170-172`). **Confirmed. Two owner forks:** open decisions 6 and 7.
- **C3. The proof set's closure was not sized.** **Folded:** it is computed from the measurement, and out-of-set owners get a diff category (Phase 1).

## Acceptance

- **A1. The diff script's "upstream of one of those" category could explain a defect.** **Folded:** categories are tightened, keyed on position, and it asserts no lift is lost (Phase 1).
- **A2. Holder-equals-owner is not checkable from persisted data** (gradient rows persist no `linear_feature_id`; the verify file reads no FWA table, confirmed by grep). **Folded:** the verify check is one holder per position; ownership is proved in tests and the diff (Phase 1).
- **A3. "FINAL equals AFTER-386" passes with a helper that never runs.** **Folded:** the marker is asserted on FINAL, a non-reproducing rule file is tested at all four sites, and one group runs prepare and persist with a further rule (Phases 2 to 4).
- **A4. "Equal in every persisted table" could not hold literally** (a new evidence column; log tables). **Folded** (Phase 4).
- **A5. The lift check's wording was weaker than the data.** **Folded:** every (lift, rule) present reaches its threshold (Phase 2).
- **A6. The one-group measurement would restore pre-0.93.0 copies from the export.** **Folded:** it loads AFTER-386's rows (Phase 1).

## Not settled by reading

- Whether bcfishpass applies its control table by position: Phase 1 reads its SQL before the docs say so.
- Falls and user-definite rows filed under a non-owner, and the proof set's closure: Phase 1's measurement.
- Whether `barriers`' shape is fixed by the export's per-group parts: read before choosing decision 1 (c).

## Held (checked and found right)

The four status sites and no other barrier-set literal in `R/`; union, per-row overrides, then emit, with nothing rebuilding `crossings` after; streams cut at every crossing; control readers all match by position; the working tables can stay whole-line; the line-rule map, the export's parts, `recompute_readers_check.R`, `lnk_wsg_downstream_check()` and `.lnk_walk_keys()` need no non-owner copy; D8 for the first run; D2's reading of `observation_date_min`; the habitat join's species list; the evidence key as quoted; `config_hash` covers every declared file; the three extending bundles inherit and the two non-extending ones have no tokens; the vocabulary's append-only and one-live-row tests accept the new rows; the weekly sync selects on the provenance `source` string; `lnk_score()`, `lnk_thresholds()` and `lnk_source()` are off the modelling path; `lnk_aggregate()` resolves no vocabulary.

## Files the plan names

R/lnk_pipeline_prepare.R
R/lnk_barriers_unify.R
R/lnk_barriers_emit.R
R/lnk_barriers_views.R
R/lnk_barrier_overrides.R
R/lnk_pipeline_persist.R
R/lnk_persist_init.R
R/lnk_pipeline_classify.R
R/lnk_pipeline_break.R
R/lnk_pipeline_crossings.R
R/lnk_crossings_union.R
R/lnk_pipeline_run.R
R/lnk_observation_records.R
R/lnk_presence_check.R
R/lnk_vocabulary.R
R/lnk_log.R
R/lnk_access.R
R/lnk_aggregate.R
R/lnk_downstream.R
R/lnk_scenario_export.R
R/lnk_wsg_deps.R
R/lnk_thresholds.R
R/lnk_score.R
R/lnk_source.R
R/lnk_pipeline_load.R
R/lnk_db_conn.R
inst/extdata/thresholds_default.csv
inst/extdata/vocabulary.csv
inst/extdata/configs/default/config.yaml
inst/extdata/configs/bcfishpass/config.yaml
inst/extdata/configs/default/parameters_fresh.csv
inst/extdata/configs/bcfishpass/parameters_fresh.csv
inst/extdata/configs/default/overrides/user_barriers_definite_control.csv
inst/extdata/configs/default/overrides/user_barriers_definite.csv
inst/extdata/configs/default/parameters_barrier_rules.csv
inst/extdata/configs/bcfishpass/parameters_barrier_rules.csv
inst/extdata/configs/dictionary_parameters_barrier_rules.csv
inst/extdata/configs/dictionary_parameters_barrier_lifts.csv
data-raw/study_area_verify.sql
data-raw/study_area_verify_negative.sh
data-raw/recompute_deps.R
data-raw/schema_consolidate.R
data-raw/pretest_inputs.csv
data-raw/audit_configs.R
data-raw/regen_provenance.R
data-raw/wsg_run_one.R
data-raw/wsg_recompute_one.R
data-raw/wsg_species_presence_check.R
data-raw/wsg_species_presence_map.R
data-raw/logs/crossings_upstream_478/stamp.csv
tests/testthat/test-lnk_pipeline_prepare.R
tests/testthat/test-lnk_barriers_unify.R
tests/testthat/test-lnk_barriers_emit.R
tests/testthat/test-lnk_pipeline_persist.R
tests/testthat/test-lnk_pipeline_crossings.R
tests/testthat/test-lnk_barrier_overrides.R
tests/testthat/test-lnk_observation_records.R
tests/testthat/test-lnk_vocabulary.R
tests/testthat/test-dictionaries.R
tests/testthat/test-lnk_persist_init.R
tests/testthat/test-pretest.R
tests/testthat/setup.R
RUNBOOK.md
CLAUDE.md
NEWS.md
DESCRIPTION
planning/backlog.md
research/README.md
research/barrier_rules.md
research/bcfishpass_parity.md

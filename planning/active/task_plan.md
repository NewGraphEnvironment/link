# Task: Read discharge from wet in classify and the habitat export, and re-tune BT's MAD range on it (#331)

**If done:** classify, the validator, the scoring harness and the habitat export (#308) all read discharge from wet's published `discharge.fwa_v1_segment_monthly` (`month = 0`, `pick`), and the export's manifest records the wet dataset ID and the md5s of the wet parts the build used, so habitat → discharge provenance is one chain of manifests. BT's MAD range is re-tuned on wet's values the way #302 tuned it on fwapg's, so whether to move any group to `mad` is decided on the source it would run on. **If never:** link keeps reading `whse_basemapping.fwa_stream_networks_discharge`, whose version is only what `provenance.source_artifact` happened to record on the exporting host, and `default_tuned`'s BT 0.078 m³/s stays a threshold fitted to a source we mean to leave.

## Context

Every MAD threshold link has was fitted to fwapg's `whse_basemapping.fwa_stream_networks_discharge`. That covers 2.72 M lines; wet's published `discharge.fwa_v1_segment_monthly` (loaded locally 2026-10-15) gives an annual value to 4.53 M lines (3.15 M PCIC routed, 1.38 M wet water balance). #300 and #305 found that most of `mad`'s loss against `cw` was water with no discharge, not water below the minimum, so the source matters before any group moves to `mad`. The operator asked to redo the BT tuning (#302, #300) on wet's values. #331 carries that, plus the export provenance.

Every group is on `cw` today, so MAD ranges are inert in classification. Switching a bundle's source moves only the export's `*_ratio_mad` columns and any rule-level `mad:` test.

## What the exploration found

- **One reader, several callers.** The table name comes from `.lnk_hv_discharge_tbl()` (`R/lnk_habitat_validate.R:920`). It is used by:
  - `.lnk_discharge_sql()` and `.lnk_discharge_candidates_sql()` (`R/lnk_discharge.R`);
  - prepare (`R/lnk_pipeline_prepare.R:128,701`);
  - the export (`R/lnk_scenario_export.R:219,932`);
  - the validator (`R/lnk_habitat_validate.R:401,475,494,671,1046`);
  - the harness (`data-raw/habitat_variants_build.R:613`, `_score.R:645`).
- **fwapg's table:** `(linear_feature_id, watershed_group_code, mad_mm, mad_m3s)`.
- **wet's table:** `(scenario, forcing, source, linear_feature_id, watershed_group_code, month, runoff_mm, q_m3s, coverage, period, pick)`. Its partial index is `(scenario, linear_feature_id) WHERE month = 0 AND pick`.
- A subquery `(SELECT linear_feature_id, watershed_group_code, q_m3s AS mad_m3s FROM discharge.fwa_v1_segment_monthly WHERE scenario = 'historical' AND month = 0 AND pick)` has fwapg's shape. It can stand wherever the table name is substituted today (`FROM %s`, `JOIN %1$s d`), so the fill SQL is untouched.
- **`discharge_fill` (#305) is the pattern to copy.** It is a bundle knob, `.lnk_discharge_fill(cfg)`. It is recorded per WSG in `<schema>.log.discharge_fill` (`R/lnk_log.R:328,951`). The validator checks it against its `cfg` (`lnk_habitat_validate.R:430-457`). The export reads it from the log (`lnk_scenario_export.R:168`). The harness records it in `built.csv` (`habitat_variants_build.R:419`, `_score.R:310-319`).
- **The harness guard** is at `habitat_variants_build.R:311`. It stops when any cell a variant sets equals the base. `variants_302.csv`'s `set` carries `*_mad_max=9999`, which `default` has carried since #307. #342 is blocked by the same guard.
- **The ladder values are fwapg percentiles.** #302's P10 / P05 / P02 rungs (BT 0.078 / 0.027 / 0.0085) are observation percentiles from `data-raw/query_habitat_thresholds_mad.R`, which hard-codes fwapg's table (lines 111, 286, 390). So "same fixed rule" means re-deriving those rungs on wet, not reusing the numbers.
- **`default`'s width-converted minima** (0.041 / 0.20 / 0.021) come from `data-raw/query_width_mad_equivalent.R`, which also hard-codes fwapg (lines 108, 157).
- **Held-out set:** BT is held out on REVL, ELKR, KOTR, UARL, MURR, UBTN and LHAF, and in sample on PARS and KOTL (`data-raw/habitat_score/wsg_roles_302.csv`).

## Decisions in this plan (approve or change)

1. **The source is a bundle setting, not a switch:** `pipeline: discharge_source: fwapg | wet`, with fwapg when absent. Every run before this change still reproduces, and one scoring build can score both sources on the same segmentation.
2. **The run log records it:** a new `<schema>.log.discharge_source` column. A row written before it existed reads as `fwapg`, as `discharge_fill` reads as FALSE.
3. **Revised 2026-10-15 (operator, after plan review B1/S4): only `default_tuned` sets `discharge_source: wet`,** with BT re-tuned on wet, as the issue says ("land any changed value in `default_tuned` only"). `default` stays on fwapg, and its width-converted minima stay as they are; their wet equivalents are measured and recorded in `research/`. The reason: prepare joins discharge for every group, so any bundle that reads wet needs wet's table on every host that runs it. `bcfishpass` stays on fwapg. GR / RB / KO `default_tuned` MAD values were fitted to fwapg; re-tuning them is a follow-up issue.
5. **wet's 0 m³/s reads as no value** (operator, 2026-10-15): `nullif(q_m3s, 0)`. 29,491 picks are 0 (22,453 `wet_balance`, 7,038 `pcic_routed`). A 0 at a fish location would floor a rung to no minimum at all; as no value, any MAD test fails the line, and an edge 1250 line can be filled.
6. **A source mismatch in the validator is a warning, not an error** (review B2). Which model a build classified on is not logged. `query_habitat_thresholds_mad.R` measures wet at observations on `cw` builds, through the validator, with a method table that puts every group on `mad`.
4. **Unblock the harness by relaxing the guard,** not by editing #302's file. A `set` cell that already equals the base is dropped with a message. The run still stops when the variant's own `column` cell equals the base, or when nothing at all changes. The guard keeps its purpose (no rung that changes nothing), and #302's and #342's files work at HEAD.

## Phase 1: Discharge source as a bundle setting
- [x] `R/lnk_discharge.R`: add `.lnk_discharge_source(cfg)` (`fwapg` | `wet`, validated, default `fwapg`) and `.lnk_discharge_tbl(source)` (the table to check and fingerprint). Add `.lnk_discharge_rel(source)` (the relation to read: the fwapg table name, or the wet subquery with the `historical`, `month = 0`, `pick` predicate matching the partial index). `.lnk_hv_discharge_tbl()` becomes `.lnk_discharge_tbl("fwapg")` or is removed with its callers repointed.
- [x] Thread `source` through `.lnk_discharge_sql()`, `.lnk_discharge_candidates_sql()` and `.lnk_discharge_join()`, as `fill` is threaded.
- [x] Callers:
  - prepare (from `cfg`);
  - the validator (from `cfg`; the existence check names the right table);
  - the export (from the run log row; the artifact lookup at `:932` uses the run's table);
  - the harness build and score (from `cfg` / `built.csv`).
- [x] `R/lnk_log.R`: add the `discharge_source` log column, written with the run. The validator stops on a log/cfg mismatch, as it does for `discharge_fill`. The export reads a missing column or NULL as `fwapg`.
- [x] Tests (`tests/testthat/test-lnk_discharge.R` and siblings):
  - the SQL for both sources;
  - setting validation and the fwapg default;
  - against the DB, one WSG's wet values through `.lnk_discharge_join()` equal a direct read of the wet table (skips if absent);
  - a pre-change log row reads as fwapg in the validator and the export;
  - the `fwapg` path's SQL is byte-identical to today's.
- [x] RUNBOOK §7 (discharge), `lnk_config()`'s roxygen, the export schema's `mad_m3s` notes and the validator / classify docs name the new setting. `lnk_config()` refuses an unknown `discharge_source` at load (review G2).

## Phase 2: Unblock the scoring harness
- [x] `habitat_variants_build.R:311`: drop `set` cells equal to the base, with a message. Stop if the variant's own `column` cell equals the base, or if the variant changes nothing (model included).
- [x] The harness carries `discharge_source` and `discharge_fill` per variant (review G4): optional columns in the variants CSV, resolved against the base bundle and written explicitly into every thin bundle's `config.yaml`, never inherited (review G3d). Recorded in `built.csv`, read back by the score. The base row may set neither. Old variants files stay valid.
- [x] Verify by scripted `--step=bundles` runs (the guard is inline in a `data-raw/` script, so testthat cannot reach it; review G7): `variants_302.csv` regenerates at HEAD and each bundle differs from `default` in exactly its intended cells; a crafted no-op rung still stops; a crafted base row with a source is refused.

## Phase 3: Re-derive the discharge numbers on wet
- [x] `query_habitat_thresholds_mad.R` and `query_width_mad_equivalent.R` take `--discharge-source=fwapg|wet`. They read through `.lnk_discharge_rel()`, never a hard-coded name, and stamp the source and the wet table's load comment. The committed #302 / #307 outputs cannot be reproduced (bcfishobs, fresh and the calibration set have moved since; review B3), so each is re-run on fwapg at HEAD as today's baseline, beside wet on the same day, with drift from the committed values reported separately.
- [x] Run both on both sources into `data-raw/logs/discharge_wet_331/`:
  - BT P10 / P05 / P02 for spawning and rearing on the calibration WSGs;
  - the width-converted minima (BT, GR, KO, RB), recorded only (`default` keeps fwapg's).

  Report wet against fwapg on the lines both value, as well as on each full set (wet values more lines, and adds nine WSGs to the calibration set), and split by wet's `source` (`pcic_routed` / `wet_balance`: two models, forcings and normal periods).
- [x] Measure the fill's reach on wet before paying for fill-on scoring (review S2): edge 1250 lines with no annual pick in the held-out and calibration WSGs.

## Phase 4: Re-score BT on wet's discharge
- [ ] Commit Phases 1–3 first: the harness refuses a dirty tree, and nothing in the repo is edited while a build runs (review O3).
- [ ] Build A, the ladder, `variants_331.csv` (BT only): the `default` base on `cw`; the P10 → P05 → P02 ladders for spawn and rear on wet's values, with `discharge_source: wet`; roles from `wsg_roles_302.csv` (BT rows). Prefix `score331_`.
- [ ] Build B, `cw` against `mad`, `variants_331_model.csv`, on base `default_tuned` as #300 / #305 were (review O2): model-only BT variants on fwapg and on wet, fill as `default_tuned` sets it (on), plus fill off on wet only if the fill's reach measured in Phase 3 is material. Prefix `score331m_`. Build B runs after Phase 5 lands `default_tuned`'s wet values, so it tests the pair that ships (review O1).
- [ ] State the run decisions before launch (config, prefix, closure, species BT), then build detached. Score with #302's fixed rule and #300's size-adjusted comparison.
- [ ] Write a "MAD on wet's discharge (#331)" section in `research/habitat_thresholds.md`:
  - whether BT's 0.078 moves;
  - `mad` vs `cw` on wet against #300 / #305's figures (BT rearing `cw`-only 0.19; −32 % stream rearing);
  - whether the #305 fill still matters on wet.

## Phase 5: Land the values
- [ ] `default_tuned`: BT's re-tuned values (if they move), plus `discharge_source: wet`, documented in its `config.yaml`. `default` unchanged. Regenerate `rules.yaml` to a tempfile and diff it. Check that `cw` classification does not move: prepare once, then re-join `mad_m3s` from each source (`.lnk_discharge_join()`, as the harness's `run_variant()` does; classify alone reads what prepare wrote, so without the re-join both passes read one source — code-check round 3) and re-classify on the same schema, asserting `mad_m3s` differs between the passes (`habitat_thresholds_282/reclassify.R`'s method; two full runs differ by one segment through the PSCIS tie, review A2), compare per `linear_feature_id` (review A3).
- [ ] NEWS: `default_tuned`'s `config_hash` changes, and new `default_tuned` builds export wet's `mad_m3s` / `*_ratio_mad` (review S5).
- [ ] File a follow-up for GR / RB / KO `default_tuned` MAD on wet.

## Phase 6: Provenance and host prep (lands with Phase 5: a host running `default_tuned` needs wet's table, review B1)
- [x] `log_input` fingerprints the wet table, and records its load comment (wet's manifest URL, build time and commit; `wet_db_load()` keeps no per-part record, review G5), only for runs whose config reads wet. The vintage gate does not age-check wet (a static published dataset, review G6) and checks it only for configs that read it.
- [x] The export manifest records, per config that read wet, the load comment logged at classify and the one in the exporting database, and flags a mismatch.
- [x] Dispatcher / cypher prep: on a host that will run a wet-reading config, load wet's annual pick (`wet_db_load(months = 0, pick_only = TRUE)`, about 4.5 M rows) or fail loud. Add `wet` to Suggests / Remotes.
- [x] Per-part md5s of the loaded wet parts: needs a load record from wet; filed as NewGraphEnvironment/wet#88.

## Verification
- `devtools::test()` and `lintr::lint_package()` clean. `devtools::check()` before the release bump.
- On the fwapg path, prepare's `mad_m3s` and the export's ratio columns are byte-identical to main on one WSG (ADMS).
- On the wet path, one WSG's working `mad_m3s` equals a direct `month = 0 AND pick` read, and the fill fires only where wet is NULL.
- The harness regenerates #302's bundles at HEAD, and the guard still refuses a no-op rung (the defect restored → red).
- The Phase 4 score's base reproduces its own digest (the harness's built-in invariant).

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

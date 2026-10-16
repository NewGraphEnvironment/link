# Review of planning/active/task_plan.md (#331) against issue #331, the code at HEAD 55965f10, and the local DB

Note first: the working tree is being edited while I review. Phase 1 is partly implemented in R/lnk_discharge.R, lnk_habitat_validate.R, lnk_log.R, lnk_pipeline_prepare.R, lnk_scenario_export.R, helper-export.R and three test files. I reviewed the plan against HEAD and checked the in-progress diff where it bears on a finding. DB queries were read-only. The only full scans were the 4.5 M-row partial-index reads.

## Blockers

**B1. Phase 5 makes Phase 6's host prep mandatory. It cannot be split out.**
- prepare joins discharge for every group, `cw` included (`R/lnk_pipeline_prepare.R:695-701`). RUNBOOK.md:858-859 says so: "A DB without the discharge table now fails prepare for every group."
- Once `default` / `default_tuned` set `discharge_source: wet`, every host without `discharge.fwa_v1_segment_monthly` fails prepare on all-`cw` runs. That includes every cypher droplet (`data-raw/cypher_prep.sh` loads only snapshot_bcfp primitives) and any export host. The export always computes `*_ratio_mad` from the logged source (`lnk_scenario_export.R:205,219`).
- link does not depend on `wet` at all (DESCRIPTION has no Suggests or Remotes entry for it). A host cannot run `wet_db_load()` without installing it.
- Fix: either Phase 6's host-prep part, and a `wet` Suggests/Remotes entry (or a link-side loader), lands before or with Phase 5, or Phase 5 is held back.
- Consider `wet_db_load(..., months = 0, pick_only = TRUE)` for pipeline hosts. It stores about 4.5 M rows instead of 103 M / 20 GB. The pick_only and months options are in `~/Projects/repo/wet/R/wet_db_load.R:29,47,76`.

**B2. The validator's new log check breaks Phase 3's own instrument.**
- `data-raw/query_habitat_thresholds_mad.R:125-136` runs `lnk_habitat_validate()` on `fresh_default` with cfg `default` and a method table that puts every calibration WSG on `mad`.
- With `discharge_source: wet`, the new check (in-progress `lnk_habitat_validate.R:470-483`, the plan's "validator stops on a log/cfg mismatch") decides "reads" from the overridden cfg (`.lnk_discharge_read`). So it refuses every logged calibration WSG.
- `fresh_default.log` holds rows for KOTL, LARL, SLOC and PINE (all in #302's calibration list) plus DUNC. They were built `cw` on fwapg and log NULL, which reads as `fwapg`. The `--discharge-source=wet` run stops before it measures anything.
- The check is a false positive here: classify never read discharge for those groups.
- Fix options:
  - the script attaches discharge itself instead of going through the validator's check;
  - the check considers only what the build's own config read;
  - an explicit bypass argument on the validator.

**B3. "Re-running `fwapg` reproduces the committed #302 / #307 outputs" (Phase 3) cannot hold.**

| | #302 stamp | #307 stamp | Now |
|---|---|---|---|
| `bcfishobs.observations` rows | 373,050 | — | 375,962 |
| fresh | 0.36.2 | 0.36.2 | 0.39.0 |
| Calibration WSGs (fwapg) | 46 | — | 47 (DUNC added 2026-10-12) |
| `fresh_default` WSGs persisted | — | 55 | 56 |

Stamps: `data-raw/logs/habitat_thresholds_302/stamp.txt`, `habitat_thresholds_307/stamp.txt`.
- Replace the criterion: re-run fwapg at HEAD as today's baseline, compare wet against it on the same day, and report drift from the committed values separately.

## Gaps

**G1. Callers the plan misses:**
- `data-raw/discharge_fill_count.R:71` calls `.lnk_hv_discharge_tbl()`, which the in-progress diff deletes. This script is also the cheap instrument for the issue's "does the #305 fill still apply on wet" (see S2).
- `data-raw/query_habitat_thresholds_fiss.R:125` hard-codes fwapg. It produced #302's FISS evidence (`habitat_thresholds_302/fiss_*`).
- `data-raw/logs/habitat_score_302/power_windows.R:16,36` hard-codes fwapg.
- `data-raw/habitat_publish.R:271` writes `runs.csv` with `discharge_fill` but not `discharge_source`.
- Leftover roxygen after deleting `.lnk_hv_discharge_tbl`: `R/lnk_habitat_validate.R:942-944` ("Mean annual discharge per FWA line…" @noRd) now runs straight into `.lnk_hv_size_col`'s block.
- Docs naming the fwapg table:
  - `lnk_habitat_validate.R:125-126`
  - `R/lnk_discharge.R:7`
  - `lnk_pipeline_classify.R:43-45`
  - `inst/extdata/schemas/habitat_fwa_v1_segment.yaml:86-94` (`mad_m3s` description)
  - `inst/extdata/configs/default_tuned/config.yaml:26-33`
  - `configs/default/README.md:14`
  - RUNBOOK §6d (:704-706), §7 (:855-863) and §8d (vintage gate, :1101+)
  - CLAUDE.md:427-429 (says #302's ladders regenerate only at v0.58.0)

**G2. There is nothing that validates pipeline keys, and no "dictionary" for them.**
- `lnk_config()` merges `pipeline:` shallowly (`R/lnk_config.R:227-231`) and never checks key names. A typo such as `discharge_souce: wet` silently reads fwapg.
- No dictionary CSV covers pipeline keys (`inst/extdata/configs/dictionary_*.csv` are parameter tables). The plan's "`dictionary` / config docs" step has no target. The real targets are the roxygen at `R/lnk_config.R:48-50` (plus the regenerated man page) and the RUNBOOK.
- Recommend validating `discharge_source` in `lnk_config()` at load time, and possibly warning on unknown pipeline keys.

**G3. The harness's per-variant source is under-specified.**
- (a) The strict column check `stopifnot(identical(setdiff(names(variants), c("model","set")), cols_variants))` (`habitat_variants_build.R:~151`) must admit the new optional column.
- (b) The model-only validation (`:~200-215`) rejects any extra field on a model-only row. It has to allow `discharge_source` if Phase 4 wants model-only variants "on both sources".
- (c) `run_variant()` must pass the source to `.lnk_discharge_join()` (HEAD `:613-614`). The base row's source must equal the base bundle's, or the base digest check means nothing.
- (d) **Write the resolved source explicitly into every thin bundle, never inherit it.** The bundles `extends: default` by name. After Phase 5 flips `default` to wet, a Phase-4 bundle that inherited fwapg would re-resolve to wet, the same extends-by-name drift that broke #302.
- (e) The score (`habitat_variants_score.R:304-319`) must override `cfgs[[v]]$pipeline$discharge_source` from `built.csv`, as it does for the fill. A `built.csv` from before #331 (no column) must read as `fwapg`, as `record_built()` back-fills `discharge_fill` with "FALSE" (`build.R:433-435`).
- (f) The "variant changes nothing" stop must count the source too, and refuse a `cw` variant whose only change is the source unless the rules carry a rule-level `mad:`.

**G4. "With and without the #305 fill" needs a per-variant fill too.**
- The fill is a bundle knob: `default` has none, `default_tuned` sets it. #300 and #305 were separate builds on `default_tuned`.
- The plan adds a `discharge_source` column but no fill toggle. One build cannot score fill on/off unless a `discharge_fill` column is added or two builds are run.

**G5. Provenance: the md5s of "the wet parts the build used" are not recorded anywhere link can read.**
- `wet_db_load()` checks each part's md5 against the manifest but persists only a table COMMENT. Locally that is the manifest URL, built time 2026-10-15T02:06:57Z and wet commit acb820f (`wet_db_load.R:133-138`). There is no per-part record.
- `provenance.source_artifact` has no md5 column. Its URL template expands only `{wsg}` (`R/lnk_artifact.R:221-224`), so 43 part URLs need a new template form such as `{part}`.
- The published `manifest.json` sits at a fixed URL that is overwritten on republish, so fetching it at export time can name parts the build never loaded.
- The export today records `source_artifact` "of the exporting database at export time, not … the hosts the builds ran on" (`lnk_scenario_export.R:~985`). The issue's If-done asks for the parts the build used.
- Needs one of:
  - a load record written by wet (cross-repo, wet#7 follow-up);
  - a link wrapper that records the catalog at load time;
  - at minimum, capture the table COMMENT into `log_input` at run start, and have the export flag a mismatch between the logged load and the current one.
- wet is reloaded far more often than fwapg's static table, so drift between classify and export is a real risk (cf. RUNBOOK:705-706, "agrees with the flags while that table is unchanged").

**G6. Adding the wet table to `.lnk_input_primitives()` (Phase 6) changes the vintage gate for every config.**
- `.lnk_vintage_primitives()` takes every primitive whose source is not `fwapg/` (`R/lnk_preflight_vintage.R:179-181`). An absent table makes `ok = FALSE` (`:107,127,154`).
- Effects:
  - a `bcfishpass` (fwapg-only) host fails the gate without wet;
  - a static published dataset ages past `max_age_days` and forces a needless 15-minute, 20 GB reload.
- The gate and the `log_input` fingerprint should depend on the source the config reads, or wet needs its own source class exempt from age checks.

**G7. The guard acceptance cannot be tested as written.**
- The plan asks for "a test or assertion … the defect restored → red". The guard is inline in `data-raw/habitat_variants_build.R` (`write_bundle()`, HEAD `:303-318`), which testthat cannot reach.
- Either factor the guard and cell-diff into a sourced helper or an internal function with a test, or define the acceptance as a scripted `--step=bundles` run on a crafted variants file.

**G8. Performance of the new log check.**
- In the in-progress `.lnk_hv_check_log`, `.lnk_discharge_read(cfg, w)` runs per WSG for every config. Each call reaches `.lnk_rules_read_mad()` → `fresh::frs_params()` and re-reads the method table.
- The fill check short-circuits on the knob; the source check does not.
- Compute the aoi-independent rules part once.

## Ordering

**O1.** Phase 4's model-only "cw-vs-mad at the landed pair" is built on base `default`, whose BT minima (0.041 / 0.021) are fwapg width-conversions that Phase 3 / 5 will change.
- A model-only variant cannot carry `set` (`build.R:~205-210`), so on wet discharge it tests fwapg-derived minima.
- Either land `default`'s recomputed wet minima (Phase 5a) before the Phase 4 build, or let model-only rows carry a `set`.

**O2.** #300 / #305's reference figures (BT rearing `cw`-only 0.19; −32 % stream rearing) were scored on base `default_tuned` (`variants_300.csv`, `variants_305.csv`). `default_tuned`'s BT has `rear_gradient_max` 0.1349 against `default`'s 0.1049, and MAD minima 0.078 / 0.078.
- With base `default` the comparison is not like-for-like.
- That needs a second build with `--base=default_tuned` (its own prefix and `--out`), or the comparison is dropped.

**O3.** The harness refuses a dirty tree for R/, inst/extdata/configs, data-raw/habitat_score and the build script (`build.R:~120-126`). Its header says not to touch the repo while a build runs.
- So Phases 1–2 must be committed before the Phase 4 build.
- Phase 5 / 6 edits during the multi-hour detached build must happen in a separate worktree.

**O4.** Phase 3 (wet) is blocked by B2 until the instrument is fixed. That fix belongs in Phase 1, where the check is introduced.

## Assumptions (checked against the DB)

- **One pick per line:** holds. 4,532,843 picks (`historical`, `month = 0`, `pick`), all distinct `linear_feature_id`. Only `historical` carries picks.
- **`watershed_group_code`:** populated on 100 % of picks, 246 WSGs. Zero mismatches with FWA's group in ADMS, BULK and UBTN.
- **NULL `q_m3s`:** none among picks. wet's "no value" is an absent row; fwapg has 713 k NULL-valued rows out of 2.72 M. The fill's `d.mad_m3s IS NULL` gate still works through the LEFT JOIN.
- **The `cov` gate is now meaningless on wet:** every group is covered.
- **Zeros:** 29,491 picks have `q_m3s = 0` (22,453 `wet_balance`, 7,038 `pcic_routed`), against 559 non-positive in fwapg.
  - They sit on stream edges in the calibration WSGs (`wet_balance` edge 1000: 121 lines in `fresh_default`).
  - P02 of `wet_balance` over ADMS, PARS and KOTL is exactly 0.
  - A P02 rung could floor to 0, which is no minimum at all.
  - Decide whether 0 means no value (and should be NULLed or filled) before Phase 3.
- **Mixed vintages:** a pick mixes two models, forcings and periods: `pcic_routed` PNWNAmet 1951-2012 and `wet_balance` climr 1981-2010.
  - Values differ from fwapg everywhere (mean wet/fwapg ratio 0.83–1.68 by WSG and source; under 0.1 % exactly equal).
  - Report the Phase 3 percentiles split by `source` as well as pooled.
- **The sample changes with the source:**
  - Calibration WSGs are "persisted in `fresh_default` with any discharge" (`query_habitat_thresholds_mad.R:107-114`). Under wet that is 56, not 47: BULK, KISP, KLUM, LKEL, LSKE, MORR, MSKE, USKE and ZYMO join.
  - #302's BT `n_mad_null` (10.7 %, `coverage.csv`) also mostly gains values.
  - `query_width_mad_equivalent.R` has the same issue.
  - To isolate the source effect, report wet on the fwapg-valued common set beside the full wet set.
  - The held-out BT WSGs are not in `fresh_default`, so there is no overlap.
- **The fill on wet:** edge-1250 coverage is nearly complete (UBTN 806 of 806 on wet against 310 on fwapg; ADMS 405 of 406). The fill will touch almost nothing.
- **Performance:** fine. The wet subquery plans as a nested loop over the partial index (BULK join: 0.2 s, 0 heap fetches).
- **Schema detail:** `linear_feature_id` is `integer` in both tables, so the joins are fine.
- **The `scenario` literal is hard-coded:** a later scenario knob would leave a logged `wet` ambiguous. Consider logging `wet:historical`, or adding the scenario to the value now.

## Scope

- **S1.** If Phase 6 is split out, #331 cannot close: its If-done includes manifest md5s and every host carrying the table. B1 also forbids the split.
- **S2.** "Whether the #305 fill still matters on wet" can be answered cheaply with `discharge_fill_count.R` (once source-aware) before paying for scoring builds. Given the coverage above, scoring fill on/off for wet is likely wasted.
- **S3.** `default_extrabreaks` and `default_rearbreaks` are standalone (`extends: ~`). The plan does not say whether they move to wet.
- **S4.** The issue says "land any changed value in `default_tuned` only", yet it also asks to recompute `default`'s width-converted minima. Confirm with the operator whether `default`'s minima and source move in #331.
- **S5.** Flipping `default` changes `config_hash` for `default` and `default_tuned` (config.yaml is hashed along the extends chain, `R/lnk_log.R:84-91`). It also changes the published `mad_m3s` / `*_ratio_mad` for every new `default*` build. Note it in NEWS and the export docs.
- **S6.** Optional: carry wet's `source` (`pcic_routed` / `wet_balance`) into `mad_m3s_source`. That changes the export contract's value domain (`habitat_fwa_v1_segment.yaml:94`), so decide explicitly.

## Acceptance

- **A1.** Phase 3's reproduction criterion is unreachable (B3).
- **A2.** "On NATR and ADMS, `cw` digests must equal main's" is not stable as stated. Two identical full runs differ by one segment through the PSCIS tie (CLAUDE.md:434-439).
  - State the method: prepare once and re-classify on the same schema (`habitat_thresholds_282/reclassify.R`).
  - Re-join discharge from the new source before classify.
- **A3.** "prepare's `mad_m3s` … byte-identical to main on ADMS" has the same problem: compare per `linear_feature_id`, not per segment.
  - "Export ratio columns identical" holds only when both commits export the same persisted schema. Say so.
- **A4.** "The harness regenerates #302's bundles at HEAD" is achievable. The regenerated bundles are not the ones #302 scored, because `default`'s MAD cells changed in #307. Word it as "each bundle differs from `default` in exactly its intended cells".
- **A5.** "The `fwapg` path's SQL is byte-identical to today's" needs a pinned reference string or snapshot in the test. The in-progress `.lnk_discharge_sources()$fwapg$rel` is the bare table name, so it holds.
- **A6.** "The fill fires only where wet is NULL": wet has no NULL values, only absent rows. Reword as "only on edge-1250 lines with no annual pick".

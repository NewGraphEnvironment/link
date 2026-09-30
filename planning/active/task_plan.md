# Task: Research: calibrate CH and BT gradient and channel-width thresholds from observations (#284) — step 5 scoring

**If we do it:** CH and BT habitat in the `default_tuned` bundle rests on measured fish distributions and cited literature, with a recorded verdict per threshold. Steps 1–4 and 6 shipped (PR #287); this PWF is step 5 — score the variants against the #283 validator.

## Context

#284 steps 1–4 and 6 shipped (PR #287): `default_tuned` differs from `default` in one cell, BT `rear_gradient_max` 0.1049 → 0.1349, and every verdict in `research/habitat_thresholds.md` is **unscored**. #283 built the validator (`lnk_habitat_validate()`, `data-raw/habitat_validate.R`) and #290 made DV→BT pooling data (Hazelton split). Under that split the 0.1349 value is only 0.0009 above the line that would give 0.1249, so step 5 must score both.

The agreed step-5 design (issue body, 2026-09-26) is:
- Prepare each WSG once, then re-classify it once per variant, so all variants share segmentation. Full runs are not bit-reproducible: the PSCIS tie in `lnk_pipeline_pscis_build.R:264-279`.
- Seven variants and eight pilot WSGs.
- A decision rule fixed before any run.

Decisions taken at this gate (2026-09-29):
- **Bands are adjacent steps.** Each variant is compared with its nearest tighter neighbour in its ladder.
  - Band = segments that are habitat in the looser variant and not in the tighter one.
  - Incumbent = `default`'s habitat of that flag, outside every band.
  - Walk outward from `default` and stop at the first band that fails.
- **Observation stage = the stage each threshold was calibrated on:** BT rearing → any stage, CH spawning → spawn-staged, CH rearing → rear-staged. The other stages are reported beside it.
- **Export `lnk_habitat_validate_band()`** in the compare family.
- **Model the full 20-WSG drainage closure** into the base schema.

**Rule (fixed now, written to the research doc before any run):**
- A band stays or becomes habitat when its observation density per km is ≥ 0.5× the incumbent's.
- It is read on the held-out WSGs for its species and needs n ≥ 10 observation locations in the band, else keep.
- The literature veto stands.
- In-sample WSGs are reported beside the verdict and never decide it.

## Run decisions (stated here, restated above the launch command)

- **config:** `default`, plus six thin variant bundles that `extends: default` and override only `parameters_habitat_thresholds.csv` and `pipeline.schema`. Not `bcfishpass`.
- **schemas:** `score284_<variant>`, 7 new schemas. `fresh_default` and `fresh` are untouched.
- **focal WSGs:** ELKR, BULL, PARS, KOTL, BULK, MORR, UNTH, LNTH.
- **closure:** `lnk_wsg_resolve(expand = TRUE)` gives 20 WSGs. It adds LARL, LFRA, LPCE, LSKE, HARR, KLUM, UPCE, FRCN, KISP, PCEA, PARA and THOM, 461k source segments.
  - The closure is modelled downstream-first into `score284_default` only.
  - Only the 8 focal WSGs are re-classified per variant.
- **species:** `cfg$species` × presence. The pilots carry BT everywhere and CH in BULK, MORR, UNTH and LNTH.
- **flags:** `dams = TRUE`, `mapping_code = FALSE`, `log = TRUE` on the base run. The post-model access recompute runs on the focal WSGs. No primitives refresh.
- **variants** (`data-raw/habitat_score/variants.csv`): `default`, `default_tuned` (BT rear 0.1349), BT rear 0.1249 and 0.1449, CH spawn 0.0549 and 0.0299, CH rear 0.0649.
- **roles** (`wsg_roles.csv`):
  - BT: held out ELKR and BULL; in sample PARS, KOTL, BULK and MORR.
  - CH: held out UNTH and LNTH; in sample BULK and MORR.
- **Measured cost basis:** m1 0.0391 min per 1000 persisted segments, with persisted ≈ 3.5× source.
  - Base run ≈ 1 h.
  - Six re-classify passes over 206k source segments ≈ 1–1.5 h.
  - Disk: `fresh_default` is 7 GB for 55 WSGs; about 15 GB here, against 981 GB free.

## Phase 1: Inputs as data
- [ ] `data-raw/habitat_score/variants.csv`: `variant, species_code, column, value, flag (spawning|rearing), obs_stage, tighter` (the ladder neighbour; `default` has none). Seven rows. No species is named in code.
- [ ] `data-raw/habitat_score/wsg_roles.csv`: `watershed_group_code, species_code, role (held_out|in_sample)`.
- [ ] `data-raw/fiss_absence_taxa.csv`: `species_code, role (caught|maybe), pattern`. It replaces the hard-coded `caught` / `maybe` regex lists in `data-raw/habitat_validate.R:170-177`.
- [ ] Extract the absence loader and the pooling resolution from `habitat_validate.R` into `data-raw/habitat_validate_inputs.R` (functions, sourced), so the scoring script uses the same code path rather than a copy.
- [ ] Verify with `LNK_KNOWLEDGE_DIR` set: re-run `habitat_validate.R --bundles=default:fresh_default,bcfishpass:fresh`. The CSVs in `data-raw/logs/habitat_validate_283/` must be byte-identical, `stamp.txt` aside. Also confirm that the absence counts would change with a taxa row removed (the guard fires).
- [ ] Write the rule, the band definition and the stage choice into `research/habitat_thresholds.md` §Step 5, **committed before any run**.

## Phase 2: `lnk_habitat_validate_band()` (exported)
- [ ] `R/lnk_habitat_validate_band.R`. Arguments: `conn, aoi, species, flag, schema, schema_ref, observations` (a `lnk_habitat_validate()$observations` frame), `stage`.
- [ ] The function returns, per WSG × species, the band as `schema \ schema_ref` and `schema_ref \ schema`:
  - `band_km` and `n_band` (stage-filtered observation locations on band segments);
  - the incumbent's km and n (`schema_ref`'s flag outside the band);
  - both densities and their ratio.
- [ ] Every join is on `(id_segment, watershed_group_code)`. Before counting, it fails loudly unless both schemas carry an identical segment set per WSG: an id_segment and length digest from `streams`.
- [ ] `tests/testthat/test-lnk_habitat_validate_band.R`, DB-gated like `test-lnk_habitat_validate.R`:
  - band arithmetic on a small constructed pair of schemas;
  - the guard erroring on mismatched segmentation, then restoring the defect and watching it go red;
  - the empty-band case (ratio `NA`, not 0);
  - the stage filter.
- [ ] A roxygen `@examples` block (`\dontrun`, DB), `@family compare`, `devtools::document()`, `pkgdown::check_pkgdown()`.

## Phase 3: Variant build harness
- [ ] `data-raw/habitat_variants_build.R --variants= --roles= [--wsgs=] [--step=base|variants|all]`. It generates one thin bundle per variant into `data-raw/logs/habitat_score_284/bundles/<variant>/` (`config.yaml` + thresholds CSV with checksum), loaded by path through `lnk_config()`.
- [ ] **Base run:** `lnk_pipeline_run()` for `default`, over the closure in `lnk_wsg_resolve()` order.
  - `lnk_wsg_downstream_check()` runs before each WSG in error mode.
  - The working schemas are `working_score_<aoi>`, with `cleanup_working = FALSE` for focal WSGs only.
  - The post-model access recompute (`lnk_access(merge = TRUE)`, as in `wsg_recompute_one.R`) runs on the focal WSGs.
- [ ] **Per variant × focal WSG:**
  - `lnk_pipeline_classify()` and `lnk_pipeline_connect()` on the working schema, then `lnk_persist_init()` and `lnk_pipeline_persist()` into `score284_<variant>`;
  - `streams_access` replaced with the rows from `score284_default`, since access does not depend on the habitat thresholds.
- [ ] **Invariants asserted after each variant:**
  - the `streams` segment digest and the `streams_access` digest are identical to `score284_default` for every focal WSG;
  - re-classifying `default` reproduces the base run's `streams_habitat` digest.
- [ ] Stamp: link and fresh SHAs, `run_uid`, variant bundle hashes, source counts and the bcfishobs row count.
- [ ] Pre-flight on BULL (smallest, 13k source segments) with `default` and `default_tuned`. The invariants must hold and the BT band must be non-empty, framed against `fresh_default` and `fresh` where they exist.

## Phase 4: Full build
- [ ] Restate the run decisions and launch detached (`nohup … & disown`). The repo is not touched while it runs.
- [ ] Verify post-conditions against the DB, not the exit code:
  - 20 WSGs in `score284_default`;
  - the 8 focal WSGs in each variant schema;
  - the invariants from Phase 3;
  - `<schema>.log` rows present for the base run.
- [ ] Commit the run log and stamp to `data-raw/logs/habitat_score_284/` (redacted).

## Phase 5: Score
- [ ] `data-raw/habitat_variants_score.R` sources `habitat_validate_inputs.R` for pooling (from `default`'s tracker) and absences, then runs `lnk_habitat_validate()` on every variant schema at buffers 0 and 100. Output: `summary.csv`, `totals.csv`.
- [ ] Bands per ladder step via `lnk_habitat_validate_band()` → `bands.csv`, which holds held-out and in-sample rows, the absence count in each band, and `n` and `density_ratio`.
- [ ] Apply the rule mechanically → `verdict.csv` (per ladder step: pass, fail or keep with n < 10, then the walked-out value).
- [ ] Question 2: the km of BT rearing newly admitted in each band that has spawning upstream (`fwa_upstream`) against bridge-only. Output: `bridge_band.csv`.
- [ ] Question 3: the CH spawn 0.0299 band (3–4.5 %) as its own row.

## Phase 6: Verdict and landing
- [ ] Revise `research/habitat_thresholds.md` in place:
  - the verdict table, now scored;
  - the Step 5 results;
  - the header status line.
- [ ] Update `habitat_validation.md`'s "Using it for #284 step 5" section.
- [ ] If the rule moves a value, edit `configs/default_tuned/parameters_habitat_thresholds.csv`, its `config.yaml` checksum and README, then check with `lnk_config_verify()` and `audit_configs.R`. If not, the README and config description lose "unscored".
- [ ] Update NEWS.md, the CLAUDE.md status and the #284 issue body (edited, not appended).

## Validation

- [ ] Tests pass (`devtools::test()`), `lintr::lint_package()` clean, and `devtools::check()`, since the new export needs a minor bump.
- [ ] `/code-check` clean on each commit.
- [ ] PWF checkboxes match landed work.
- [ ] `/planning-archive` on completion, then `/gh-pr-push`.

## Verification (end to end)
- Phase 1: the #283 CSVs are byte-identical after the refactor.
- Phase 2: the tests, with the guard shown to fire.
- Phases 3–4: the DB invariants (identical segmentation and access across all 7 schemas, and the default re-classify digest equal to the base run) are the proof that each band difference is purely a threshold effect.
- Phase 5: `bands.csv` n and km reconcile with `summary.csv` totals: the `default_tuned` minus `default` rearing km equals the sum of the BT 0.1249 and 0.1349 band km.

## Out of scope
- Dropping the `score284_*` schemas. They are kept until the verdict lands, and dropping them is a separate, asked step.
- MAD (fresh#114), GSDD (#21) and channel-class segmentation (#52).

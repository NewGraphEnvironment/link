# Task: rearing_km means two things: lnk_rollup_wsg() keeps lake connection lines, the compare rollups do not (#319)

**If done:** `rearing_km` means one thing in every link output: habitat km with lake connection lines reported apart.

## Phase 1: `lnk_rollup_wsg()` default (`R/lnk_rollup_wsg.R`)
- [x] Tests first (`tests/testthat/test-lnk_rollup_wsg.R`): replace "default rearing_km is the flag, connection lines included" with a test that the default `rearing_km` filters `rearing AND NOT connection`, a default `rearing_lake_connection_km` filters `rearing AND connection` (COALESCEd to 0, so the two sum to the flag total even with no connectors), and `accessible_km` / `spawning_km` are unchanged
- [x] Change the default `metrics`; `rearing_km` keeps its existing round/no-COALESCE shape so outputs where nothing changes stay byte-identical
- [x] Roxygen: rewrite the `connection` paragraph and `@param metrics` (default now leaves connectors out and reports them apart; flag total = sum of the two); trim the example that re-derives the split; `devtools::document()`
- [x] Live test (skip_if_no_db, like the existing one): default `rearing_km + rearing_lake_connection_km` equals the flag total on one group

## Phase 2: `lnk_habitat_validate()` (`R/lnk_habitat_validate.R`)
- [x] Capture unchanged (`rearing` / `rearing_any` read the flag). Cost picks up the new default via `lnk_rollup_wsg()` and `.lnk_hv_summary()`'s merge — confirm `rearing_lake_connection_km` lands in `summary` (offline test with a mocked `lnk_rollup_wsg`, or assert in the live test if one exists)
- [x] Fix lines 83-84: `rearing` is not "stream rearing" since #310; say it is the `rearing` flag (stream, lake and reservoir lines), `rearing_km` costs it without connection lines and `rearing_lake_connection_km` carries those
- [x] Add the "where lake fish sit" table (bcfishobs A/B in a lake polygon: share on 1450 vs 1200) to "Reading the numbers" as the reason capture and cost differ for lakes; update `@return` cost list
- [x] `data-raw/habitat_validate.R`: add `rearing_lake_connection_km` to `cols_km` (line 163) so the driver's sums don't silently drop it

## Phase 3: parity scripts apply the same predicate on the bcfp side
- [ ] `data-raw/parity_crosssection.R`: `bcfp_rollup()` reads `fresh.streams_vw_bcfp s` + `link:::.lnk_sql_waterbody_join()` and filters `rearing_<sp> IN (1,2) AND NOT link:::.lnk_sql_lake_connection()` (view carries `edge_type`, `waterbody_key` — checked); update header comment
- [ ] `data-raw/wsg_vignette_data.R`: same on its BT bcfp query; comment
- [ ] Run `parity_crosssection.R` on its default WSGs (FINA PARS PCEA LKEL); record before/after per pair in `data-raw/logs/lake_connection_319/` with an environment stamp. Expect accessible/spawning unchanged, rearing moving alike on both sides
- [ ] Re-run `wsg_vignette_data.R` (its segmentation-parity guard decides whether it can). If the guard refuses, stop on that step and report rather than force; otherwise check the vignette prose still matches the new `pars_accessible.rds` (no hard-coded km to fix, or fix them)

## Phase 4: reproducibility check (#284 re-score)
- [ ] Re-run `data-raw/habitat_variants_score.R` with #284's recorded args (from `data-raw/logs/habitat_score_284/stamp_score.txt`) into a scratch `--out`, against the existing `score284_*` schemas
- [ ] Compare `habitat_change.csv` and `verdict.csv` byte-for-byte with the committed ones; `summary.csv` equal apart from the new column. Expected exact (pre-#310 schemas: connection km 0); if not, record per-WSG/species where 1450 rearing exists and treat it as a finding in findings.md before going further
- [ ] Downstream readers (`habitat_variants_score.R`, `species_pooling_evidence.R`): confirm no change needed given the step above

## Phase 5: docs
- [ ] RUNBOOK §7 lake-connection passage (`RUNBOOK.md:781-784`): default `rearing_km` now leaves connectors out everywhere; `lnk_aggregate()` stays the flag (not in scope, own issue)
- [ ] `research/habitat_validation.md` cost line; `research/habitat_thresholds.md` "Lake connection lines": one meaning, the parity numbers from Phase 3
- [ ] NEWS entry drafted for the release (version bump left to `/gh-pr-merge`)

## Validation
- [ ] Tests pass (`devtools::test()`), `lintr::lint_package()` clean
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion (CLAUDE.md status update there)

## Not in scope
`lnk_aggregate()` (sums the flag, own issue); the rules (1450 stays in the L rule; 1400 stays in km).

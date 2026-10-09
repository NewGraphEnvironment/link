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
- [x] `data-raw/parity_crosssection.R`: `bcfp_rollup()` reads `fresh.streams_vw_bcfp s` + `link:::.lnk_sql_waterbody_join()` and filters `rearing_<sp> IN (1,2) AND NOT link:::.lnk_sql_lake_connection()` (view carries `edge_type`, `waterbody_key` — checked); update header comment
- [x] `data-raw/wsg_vignette_data.R`: same on its BT bcfp query; comment
- [x] Run `parity_crosssection.R` on its default WSGs (FINA PARS PCEA LKEL); record before/after per pair in `data-raw/logs/lake_connection_319/` with an environment stamp. Expect accessible/spawning unchanged, rearing moving alike on both sides
- [x] Regenerated `pars_accessible.rds` only (the accessible-km block of `wsg_vignette_data.R`, evaluated by `data-raw/logs/lake_connection_319/vignette_accessible_only.R`), not the whole script: a full run would also rebuild the gpkg and the mapping-code parity from model state that has moved since July. Vignette prose reads the rds; one sentence added saying rearing km leave connection lines out

## Phase 4: reproducibility check (#284 re-score)
- [x] Re-run `data-raw/habitat_variants_score.R` for #284 — **refused by the script**: since #307 the variant bundles extend a `default` whose thresholds changed (state on main, not #319). Replaced by a direct check: connection km in every score schema, and #284's `habitat_change.csv` recomputed with the new default
- [x] #284 `habitat_change.csv`: 36/36 rows reproduce exactly; `verdict.csv` reads no cost. BT/CH/GR/RB connection km 0 in every score schema. **Finding:** SK/KO are not 0, and #300/#305 carry KO cost rows that a re-score would move (KOTL KO base 568.63 → 259.05 km); no verdict reads them
- [x] Downstream readers (`habitat_variants_score.R`, `species_pooling_evidence.R`): confirm no change needed given the step above

## Phase 5: docs
- [x] RUNBOOK §7 lake-connection passage (`RUNBOOK.md:781-784`): default `rearing_km` now leaves connectors out everywhere; `lnk_aggregate()` stays the flag (not in scope, own issue)
- [x] `research/habitat_validation.md` cost line; `research/habitat_thresholds.md` "Lake connection lines": one meaning, the parity numbers from Phase 3
- [x] NEWS: drafted in the PR body; `/gh-pr-merge` writes NEWS and bumps the version

## Validation
- [x] Tests pass: full `devtools::test()` FAIL 0 / PASS 2594 / WARN 16 (baseline 16) at `de2a793`; the two changed test files re-run green after each code-check round (309 pass). `lintr`: changed R files 0; `test-lnk_rollup_wsg.R` at main's 20 (all pre-existing indentation)
- [x] `/code-check branch`: 3 rounds (0 / 4 / 4 findings; round 3 found one inside round 2's fix), ended by enumeration of 58 closed-set claim lines (`review-enumeration.md`)
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion (CLAUDE.md status update there)

## Not in scope
`lnk_aggregate()` (sums the flag, own issue); the rules (1450 stays in the L rule; 1400 stays in km).

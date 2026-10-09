# Code-check round 3 — #319 (branch 319-rearing-km-means-two-things-lnk-rollup-w @ c9d28c4)

## Mechanism

Every round-1/2 defect is a prose restatement that names a closed set ("every", "only",
"since #310", "stream", "sums to", "everywhere") built from the author's working set, meaning
the species, configs, callers and output files in view while making the change, instead of
being enumerated from the code: callers of `lnk_rollup_wsg()`'s default and of
`lnk_habitat_validate()`, the per-config `rules.yaml` rear rules, the committed outputs those
callers wrote. The round-2 fixes rewrote the instance that was named and kept the same habit.
The validator's `rearing` definition now enumerates configs/species from recall and is wrong
again one axis over. The step-4 reproducibility check enumerated "earlier scores" as the score
schemas (#284/#300/#302/#305) and left out the other committed validator output, #283's
baseline, which is the one where BT moves.

Places the mechanism reaches, checked:

1. `R/lnk_rollup_wsg.R` roxygen ("two sum to the flag total", NA caveat, compare split): correct after round 1.
2. `R/lnk_compare_rollup.R` comment: correct (km_metrics COALESCE and split by polygon).
3. `R/lnk_habitat_validate.R:83-87`, the `rearing` definition (round-2 fix): **wrong**, finding 2.
4. `R/lnk_habitat_validate.R:91-92`, "as every link rollup does": **too wide**, finding 4.
5. `R/lnk_habitat_validate.R:227`, `@return`, "`n_absence_rearing` (stream)": **stale**, finding 3.
6. `research/habitat_validation.md` Capture/Cost bullets: fine. The #283 baseline table and BT narrative in the same file: **finding 1**.
7. `research/habitat_thresholds.md`, "Earlier scores keep their numbers": scope omits #283, **finding 1**.
8. `data-raw/logs/lake_connection_319/README.md`, reproducibility section: omits #283, **finding 1**. Its title "everywhere": **finding 4**.
9. KO numbers in that README (259.06 / 254.67 / −4.39): re-derived at HEAD with `lnk_rollup_wsg()`, they match. #300/#305 being the only KO cost rows: checked against `habitat_score_30{0,2,5}/*.csv` (no SK rows anywhere), correct.
10. Parity tables (README and research): consistent with `parity_crosssection_{before,after}.txt` to rounding. The PCEA 8.2 km is right.
11. `RUNBOOK.md` "every WSG rollup": correct (`lnk_aggregate()` is per crossing and named as the exception).
12. `parity_crosssection.R` / `wsg_vignette_data.R` "both sides" comments and the vignette sentence: correct. The view join does not fan out (accessible and spawning are identical before and after).
13. `tests/testthat/test-lnk_rollup_wsg.R:170-172`, "One meaning of rearing_km in every output": **too wide**, finding 4.
14. `data-raw/habitat_validate.R` / `habitat_variants_score.R` / `species_pooling_evidence.R`: these read by name and recompute on every run, so nothing breaks. `fresh_default` BT carries 0 connection km today.
15. Outside the diff, the same stale phrase: `R/lnk_habitat_validate_band.R:36` ("`rearing` (stream rearing, the flag the rearing thresholds govern)"). Noted only.

Tests: `test-lnk_habitat_validate.R`, `test-lnk_rollup_wsg.R` and `test-lnk_compare_rollup.R` all pass
with `NOT_CRAN=true`. Disclosure: running the validator test file created and then dropped its own
`zz_lnk_validate_probe` schema in local fwapg, which is a write. The schema is gone afterwards.

## Findings

- **[severity: bug — doc contradicts measurement]** `research/habitat_validation.md:101-120`, `research/habitat_thresholds.md` ("Earlier scores keep their numbers for the species they scored", end of "One meaning of `rearing_km`"), `data-raw/logs/lake_connection_319/README.md` ("Reproducibility" section). The #283 validator baseline (`data-raw/logs/habitat_validate_283/`, `fresh` = bcfishpass config, BT `rear: []` admits every edge) **does** carry BT rearing on lake connection lines. Measured at HEAD on the 51 shared WSGs: `fresh` BT flag total 76,872.28 km (identical to the committed `totals_shared.csv` 76,872.29, so the schema has not drifted), of which **2,503.4 km** is connection lines. Under the new default, `rearing_km` = 74,368.9. `fresh_default` BT is unchanged at 75,280.2 (0 connection km). A re-run of the documented baseline command therefore **inverts** the BT bullet in `habitat_validation.md`: "`default` captures slightly more … with 1,592 km *less* rearing. That is the edge-type rule (bcfishpass's BT `rear: []` tests any edge)" becomes default carrying ~911 km *more*, and 2,503 km of the 1,592 km gap was connection lines. The step-4 check enumerated only the score schemas (#284/#300/#302/#305), so `habitat_thresholds.md` and the logs README tell a reader that BT validator costs are stable across #319. That is true of the score schemas and false of the #283 baseline that sits beside them. Add #283 to the enumeration and qualify the baseline table and BT bullet. The "stream rearing" column header in that table repeats round 2's stale definition: it is the flag, and for bcfishpass BT it includes lake lines.

- **[severity: fragile — doc]** `R/lnk_habitat_validate.R:83-87` (and `man/lnk_habitat_validate.Rd`). This is round 2's fix: "lake and reservoir lines where a lake rule admits them (`default` since link#310; `bcfishpass` for BT and SK)". The set was again built by recall and is wrong on both arms:
  - **`default` SK and KO had their L rule before #310.** The branch's own logs README says so ("their L rule always admitted lake lines"), and #310 left SK/KO unchanged.
  - **`bcfishpass` BT has no lake rule.** Its rear rule is `rear: - []`, a catch-all that admits every edge, lake lines included (`inst/extdata/configs/bcfishpass/rules.yaml`).

  A reader of #300/#305 KO or #283 SK-era rows would wrongly conclude that lake lines were not in `rearing` before #310.

- **[severity: fragile — doc]** `R/lnk_habitat_validate.R:227` (`@return`): "`n_absence_rearing` (stream)". The code counts the `rearing` flag (`R/lnk_habitat_validate.R:1234`, `count_by(d$rearing)`), which is the definition round 2 fixed 140 lines above. The same roxygen now gives two different meanings for `rearing`.

- **[severity: fragile — doc]** The "one meaning everywhere" claim from round 2 survives in three places that the round-2 fix did not reach (round 2 narrowed only RUNBOOK and research):
  - `R/lnk_habitat_validate.R:91-92`: "`rearing_lake_connection_km` carries them, as every link rollup does".
  - `data-raw/logs/lake_connection_319/README.md:1`: title "rearing_km leaves lake connection lines out everywhere".
  - `tests/testthat/test-lnk_rollup_wsg.R:170-172`: "One meaning of rearing_km in every output".

  `lnk_aggregate()`'s default `rearing_km` still sums the flag, connection lines included, which is the documented exception.

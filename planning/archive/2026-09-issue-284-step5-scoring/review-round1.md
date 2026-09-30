# Code review, round 1: staged diff for #284 step 5

## Findings

- **[severity: bug]** data-raw/habitat_variants_build.R:389-402. On any multi-species WSG, the pre-copy `same_access` check stops the variants step with a false failure.
  - **Cause.** `lnk_pipeline_persist(..., species = sp)` projects only the variant species' per-species access columns into `<variant>.streams_access`. It writes `has_barriers_bt_dnstr` and `access_bt` (`R/lnk_pipeline_persist.R:159-161`, `.lnk_cols_streams_access_per_sp(species)`). Every other species' `access_<sp>` and `has_barriers_<sp>_dnstr` is left NULL.
  - **Why the digests differ.** `digest_sql$streams_access` hashes `SELECT *` row text. The base schema has those columns populated: `score284_default.streams_access` for LARL has `access_rb` and `access_wct` non-NULL on all 91,083 rows. So the variant digest never equals the base digest in a WSG with more than one active species.
  - **Scope.** Under `default`, all 12 focal WSGs have more than one active species (for example BULL is BT, WCT, RB and GR; LILL is BT, CH, CM, CO, SK, ST and RB). In the normal downstream-first case the recompute changes nothing, so `access_unchanged` is TRUE and the run hits `stop(... "although the recompute changed nothing")` on the first variant WSG. No variant schema can be built as written.
  - **Separate problem: the check cannot test what its comment says.** The comment says it tests that access carries no threshold dependence. But `lnk_pipeline_classify()` and `lnk_pipeline_connect()` never rebuild the working `streams_access`. The comparison is therefore the base run's own pre-recompute access against its persisted copy, and it cannot detect threshold dependence under any outcome.
  - **Fix.** Compare only the id, WSG and variant-species columns, or drop this check. The post-copy digest loop at lines 405-410 already makes access identical to the base by construction.

- **[severity: fragile]** data-raw/habitat_variants_build.R:295-325 and 359/398. `base_recompute.csv` reflects only the most recent `--step=base` invocation, which breaks the check above in both directions.
  - **Re-running base.** A re-run (resume, or adding a WSG) re-merges access that has already been merged. That records `access_unchanged = TRUE` even where the first recompute changed it. The working schema still holds the pre-first-recompute access, so the variant check stops falsely.
  - **Re-running a subset.** `--step=base --wsgs=X` rewrites the CSV with X only. Every other focal WSG then gets `isTRUE(logical(0))`, which is FALSE, and the check is skipped silently: it fails toward pass.
  - **Fix.** If the check is kept, key it to a digest of the working access taken at base-run time, written per WSG the way `base_habitat_digest.csv` already is.

- **[severity: fragile]** data-raw/habitat_variants_score.R:112-121 with data-raw/habitat_variants_build.R:363-364 and 389. A variant schema holds habitat only for its own species, but every variant is validated over all focal WSGs × every roles species.
  - **The trigger.** A roles row is added for a second species in a shared WSG. CH is the stated follow-on, and BABL, BABR, LILL, BULK and MORR all have CH present.
  - **Why nothing stops it.** `.lnk_hv_check_schema` passes: streams and streams_access are present, and `lnk_persist_init` created an empty `streams_habitat_ch`.
  - **The result.** CH rows for the BT variants in `summary.csv` and `totals.csv` report zero spawning and rearing capture and zero km, as real numbers. Latent with today's BT-only `wsg_roles.csv`, but the README says the scripts name no species and the CSVs carry everything species-specific. Validate each variant only for `sp_v` in its own WSGs, or stop when roles carry more species than a variant persisted.

- **[severity: fragile]** data-raw/habitat_variants_score.R:232-234. The absence band marks the wrong WSGs as not assessed.
  - `covered <- unique(absences$watershed_group_code)` is the set of WSGs holding at least one absence row, not the surveyed set. So a surveyed WSG with zero BT absence sites reports `n_absence_band = NA` ("not assessed") instead of 0.
  - `hv_fiss_absences()` already returns the surveyed set as `attr(absences, "covered")`, and that is the set to use.
  - This only affects the `bands.csv` reporting column, not the rule.

Checked and clean:
- `lnk_habitat_validate_band` joins on the full key everywhere; aggregating observations per segment before the join avoids fan-out; NOT/AND precedence is correct; row alignment between the observation and absence band calls is correct; the density-NA semantics hold.
- The rule and walk logic (take and refuse per direction, first step not taken stops the ladder, n < 10 keeps the value) match the research doc.
- The `fwa_upstream` argument order in `bridge_band` is correct (spawning upstream of the band), and `GROUP BY` over the correlated `EXISTS` is valid in Postgres (probed).
- The held-out WSGs are absent from `fresh_default` (the calibration 55).
- `species_code` in the validator's observations is the model species after pooling.
- Classify gates only on the working schema's `streams_breaks`, so variant schemas lacking the closure's barriers do not change the habitat.
- The extends and provenance resolution for the generated bundles looks right.

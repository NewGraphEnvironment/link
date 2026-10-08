# Review — #317 staged diff, round 2

## Clean

No issues found.

### What was checked

- **Round-1 fix is complete.** `lnk_rollup_wsg()`'s default `rearing_km` is still
  `FILTER (WHERE rearing)` (the flag total), pinned by the new
  "default rearing_km is the flag" test. Every no-`metrics` caller compares the flag
  on both sides: `lnk_habitat_validate()` (R/lnk_habitat_validate.R:305, cost vs
  flag-based capture), `data-raw/parity_crosssection.R:79` and
  `data-raw/wsg_vignette_data.R:119` (vs `streams_vw_bcfp.rearing_<sp> IN (1,2)`, which
  also includes connection lines). `data-raw/habitat_validate.R`,
  `habitat_variants_score.R` and `species_pooling_evidence.R` consume the validator's
  `rearing_km`, so they stay on the flag too.
- **No other consumer mixes the two definitions.** Grepped `rearing_km`,
  `rearing_lake_km`, `rearing_stream`, `rearing_wetland`, `habitat_type` across `R/`,
  `data-raw/*.R`, `data-raw/*.sh`, `vignettes/`, `inst/`. The long-format consumers
  (`lnk_parity_annotate`, `wsg_compare.R`, `wsgs_run_host.R`, `regress_dams_isolation.R`,
  `rule_flexibility_render.R`) either compare two outputs of the same code or read only
  `spawning`/`rearing`/ha rows from one run; `compare_rollups.R` is the only cross-run
  consumer and it now guards pre/post-#317. `compare_adms.R` / `exp_gradient_extra_breaks.R`
  build their own SQL and are not compare-family outputs. Vignette data
  (`pars_parity.rds`, `pars_accessible.rds`) does not come from the compare rollups.
- **sprintf positional args, link side** (`R/lnk_compare_wsg.R:250-276`): all six
  arguments used (`%1$s` wb_class, `%2$s` schema twice, `%3$s` wb_join, `%4$s` aoi,
  `%5$s` lake_conn, `%6$s` species), no bare `%s` mixed in, no literal `%` in the
  template or in any interpolated fragment. The new test asserts the rendered
  `FROM working_adms.streams s JOIN working_adms.streams_habitat h` and
  `IN ('CO')`, so an off-by-one positional would fail it.
- **bcfishpass side**: `rear_expr(pred)` / `slice_expr(wb)` produce
  `h.rearing AND NOT COALESCE(...)` etc. — `NOT` binds tighter than `AND`, all
  conjunctions, so precedence is right. `has_rear = FALSE` returns `"0"` for every
  rearing slice including the new one (same as the old `rearing_km` behaviour). The
  `has_table = FALSE` NA frame carries the same seven columns in the same order as the
  query result; `rbind.data.frame` matches by name in any case.
- **NULL safety**: `.lnk_sql_lake_connection()` is wrapped in `COALESCE(..., FALSE)`,
  and `wb_class` is itself `COALESCE`d, so a NULL `edge_type` cannot drop a line from
  both `NOT connection` and `connection` sums. The compare-rollup metrics keep their
  `COALESCE(sum(...), 0)`.
- **compare_rollups.R guard**: every post-#317 RDS carries a `rearing_lake_connection`
  row for every species (assemble emits 9 rows per species unconditionally), so a WSG
  lacking it is genuinely pre-#317; pre-#310 + post-#317 mixes still trip the existing
  pre/post check; post-#310 vs post-#317 directories stop on `sa != sb`.
- **Tests can fail and do run**: ran the three changed files with `NOT_CRAN=true`
  (0 failed, 0 skipped; the live partition test in test-lnk_rollup_wsg.R ran, 3
  passes). The SQL-capture tests match on the full `... AND NOT <lc> THEN ... AS
  rearing_km` text, so dropping the `NOT` or swapping a positional breaks them.

### Notes (not defects)

- `.lnk_compare_wsg_rollup_link()` has no package caller (only the test and
  `data-raw/logs/lake_connection_317/rollup_check.R`); `lnk_compare_wsg()` routes
  through `lnk_compare_rollup()`. Its update is harmless.
- `sk-lake-clustering-divergence` in the taxonomy still lists SK `rearing` with a
  `[8, 100]` link_gt_bcfp band; with SK now at 0.0 % those rows simply fall to
  WITHIN_TOLERANCE. No code breaks.

# Review — #307 phase 2 diff, round 1

## Clean

No issues found.

### What was checked (evidence, not findings)

- **`mad_none` reaches the validator.** `lnk_habitat_validate()` resolves thresholds only via
  `.lnk_habitat_thresholds_csv(cfg)` (`R/lnk_habitat_validate.R:1028`, `R/lnk_discharge.R:251`),
  which returns `cfg$files$parameters_habitat_thresholds$path`. Nothing in the validator reads
  `loaded$parameters_habitat_thresholds` or a provenance/hash of the file; the log check compares
  `config_name` only. So the temp CSV is what the predicates are built from.
- **The read.csv/write.csv round trip is lossless except for the blanked cells.** Probe:
  `fresh::frs_params()` on the original vs the `mad_none = "BT"` temp CSV is `identical()` for
  all 10 other species; BT's `ranges` lose only `mad_m3s` for both stages.
- **The guards can fail.** With default's new values, `.lnk_hv_stage_exprs(default BT, "mad")`
  gives `NULL::boolean` for both `_nomad` columns, so the #299 assertions (`no_mad_threshold`)
  would fail without `mad_none`, and the #307 test would fail if default's BT range reverted to NA.
  The rebased #299 unit test on `bcfishpass` BT was run inline: 11 passes; `params_sp$spawn_mad_min`
  exists (NA) on that bundle, so the new `&&` precondition is not a length-0 trap.
- **Provenance.** `shasum -a 256` of the new CSV = `b397dda1…`, matching `config.yaml`;
  `lnk_config_verify()` reports no byte or shape drift for `default` or `default_tuned`. The
  `source` change away from the fresh URL touches no sync filter (`sync_bcfishpass_csvs.R` selects
  on the bcfishpass URL only).
- **No other reader assumes NA.** No R/ code reads `*_mad_min/max` apart from the validator and
  fresh; no other bundle inherits `default`'s thresholds (`default_extrabreaks`, `default_rearbreaks`,
  `bcfishpass` are `extends: ~` with their own CSVs; `default_tuned` ships its own). No test pins a
  `config_hash` value.
- `tests/testthat/test-lnk_config.R` run in full (NOT_CRAN=true, load_all, read-only): all pass.
- DB-backed tests in `test-lnk_habitat_validate.R` were not run here (suite in flight in the
  repo; concurrent schema creation would race it).

### Note, not a defect in this diff

`data-raw/habitat_variants_build.R:309-312` stops with "variant … equals default" for
`variants_302.csv` rows whose `set` holds `*_mad_max=9999`, now that `default` carries 9999.
The uncommitted `data-raw/habitat_score/README.md` change already records this (regenerates at
v0.58.0 / `8cb4822` only). `CLAUDE.md`'s #300 status line "#302's regenerate byte for byte" is
now stale relative to HEAD of this branch.

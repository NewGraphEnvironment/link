# Review — commit 773672e (Hazelton split + obs_year_max), round 1

## Findings

- **[severity: bug]** data-raw/species_pooling_evidence.R:165-231 (with `keep_dv$S3_pre1995` /
  `S4_hazelton_pre1995` at :193-201) — the reimplementation cannot reproduce the producer for the
  year-limited scenarios, so the new "must match for every scenario" check will likely `stop()`
  for S3 and S4. It is the "two lists agree on a key" mechanism with the order of operations
  reversed:
  - The producer applies the year limit **per record, before** deduplication
    (`t_obs` LEFT JOIN year condition, then `o7` groups by `obs_species x loc`, keeps the lowest
    `observation_key`, and ORs `is_spawn`/`is_rear` across the group;
    query_habitat_thresholds_obs.R:143-150, 256-262).
  - The reimplementation applies the year to S0's **already-deduplicated** rows: `seg0$yr` is the
    year of the one surviving record per location (the lowest key), and its `is_spawn`/`is_rear`
    are the OR over **all** records there, post-1995 ones included.
  - So a location with DV records on both sides of 1995 is (a) kept by the producer via its
    pre-1995 record but dropped by the reimplementation whenever the surviving S0 record is
    post-1995 or undated, which changes `rear_n` and the rear quantiles; and (b) counted as
    spawning by the reimplementation when only a post-1995 record carried the spawn flag, which
    changes `spawn_n` and the spawn quantiles.
  - Measured read-only against docker fwapg (bcfishobs DV, not Releases, match A/B, Fraser /
    Mackenzie / Columbia WSGs persisted in `fresh_default`, loc = blue_line_key x round(m),
    lowest key by `COLLATE "C"` like `dplyr::arrange`): 10 locations straddle 1995; at **5** the
    surviving record is post-1995/undated and there is no BT record at the same location to hold
    it in `BT_any_dv`, and at **2** the spawn flag comes only from a post-1995 record. Exclusions,
    presence, attachment and accessibility filters come after this, so some may drop out, but the
    check has 7 independent chances to fire.
  - Effect: the running regeneration stops at "reimplementation disagrees with the producer for
    S3_pre1995" (loud, not silent), and if a mismatch happened to cancel, `scenarios.csv`'s S3/S4
    rows would still be the reimplementation's numbers, not the producer's. Since every scenario
    now runs through the producer, the S3/S4 metrics can be read from its own `candidates.csv`,
    or the reimplementation restricted to the scenarios with no year limit (S0-S2, BT_only).
  - Not the year boundary: `yr < 1995` vs `extract(year) <= 1994` agree on integers, and the
    future-year-to-NA rule (:72) and SQL both exclude 2080/9990 from a 1994 limit.

## Checked, not findings

- `R/lnk_species_pooling.R`: tie check on `paste(pool, obs_year_max)` treats NA consistently;
  `.lnk_sp_year()` handles readr's all-empty logical column, doubles, quoted strings and blanks;
  self rows never collide with pooled rows (`grid$target != grid$obs`); scope names are validated
  case-insensitively against `wsg_regions.csv`, so a tracker/lookup name mismatch errors.
- A custom tracker **without** `obs_year_max` (a tibble from `lnk_load_overrides()`) makes
  `p$obs_year_max %||% ...` (:288) emit "Unknown or uninitialised column: `obs_year_max`". Result
  is correct (NULL, then no limit); it is only a warning, noted in case anything runs with
  `options(warn = 2)`.
- `R/lnk_habitat_validate.R`: spec `unique()` then `anyDuplicated(obs_species)` correctly refuses
  two limits for one obs species and collapses the self row; the year join sits in the JOIN (an
  undated record fails `NULL <= y`, as intended); the missing-`observation_date` guard runs before
  the query; the validator dedups after the SQL filter, so it has no analogue of the finding above.
  Both test files pass (51 and 120, 0 warnings).
- `data-raw/wsg_regions.R`: `colClasses = "character"` keeps `""` as `""`, so the `xor()` guard is
  sound; list-vs-prefix and list-vs-list overlaps error; unknown and empty list entries error.
- `config.yaml` checksum for `species_pooling.csv` matches the file (sha256 9c42964e...).

# Code-check round 2 — data-raw/query_width_mad_equivalent.R (#307)

## Clean

No issues found.

### What was checked (probes, not reading alone)

- **`channel_width_source = 'MODELLED'` is the right filter.** Values in
  `fresh_default.streams` are `FIELD_MEASURMENT` (sic), `FWA_RIVERS_POLY`,
  `MODELLED` and NULL. All 976,863 NULL-source rows have NULL `channel_width`,
  so the filter drops no segment that has a width. River polygons are excluded,
  as the header says.
- **The SQL reproduces #302's numbers exactly.** Run read-only against docker
  fwapg today: 1.5 m n=36,601 median 0.0214; 2.0 m n=24,509 median 0.0412;
  4.0 m n=5,977 median 0.2010 — identical to
  `data-raw/logs/habitat_thresholds_302/width_mad_equivalent.txt`.
- **`floor_signif2` of those medians** gives 0.021 / 0.041 / 0.2, which are the
  values written into `default`'s `parameters_habitat_thresholds.csv` for
  BT/RB (spawn 0.041, rear 0.021), GR (spawn 0.2, rear 0.021) and KO (spawn 0.041).
- **Discharge join cannot fan out:** `fwa_stream_networks_discharge` has
  2,716,652 rows and 2,716,652 distinct `linear_feature_id`.
- **No circularity.** The script reads only `*_channel_width_min` from the CSV
  #307 edits (those cells are unchanged by the diff) and `rules.yaml` for
  `inherits_size()`; MAD cells feed neither. `cfg$files$parameters_habitat_thresholds$path`
  resolves to `inst/extdata/configs/default/parameters_habitat_thresholds.csv`.
  KO rear resolves lake-only (`waterbody_type: L`), so it is correctly skipped.
- **Copied helpers** `inherits_size()` / `floor_signif2()` are byte-equivalent to
  `data-raw/query_habitat_thresholds_mad.R:321-335`.
- **Stamp:** `.lnk_pkg_git_sha("fresh")` returns a scalar (resolved sha today);
  the dirty pathspec covers `R`, the `default` bundle and the script, and
  excludes `data-raw/logs/`, so writing the run's own outputs does not set it.

### Observations, not findings

- The median is segment-count-weighted (`count(*)` over `fresh_default`
  segments, not length-weighted, not per `linear_feature_id`), and the
  population is the persisted WSGs rather than "BC streams" as header line 2
  phrases it. Both match how #302 ran it; the stamp records the WSG count.

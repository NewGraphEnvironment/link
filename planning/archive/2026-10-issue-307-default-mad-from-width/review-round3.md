# Review round 3 — data-raw/query_width_mad_equivalent.R (#307)

## Clean

No issues found.

## What was checked (probes, not reading alone)

- **Ran the producer** to a scratch `--out` against docker fwapg (read-only).
  Bins reproduce #302's ad-hoc query exactly: n = 36601 / 24509 / 5977 for
  1.5 / 2.0 / 4.0 m (`data-raw/logs/habitat_thresholds_302/width_mad_equivalent.txt`).
  Medians 0.0214 / 0.04115 / 0.20103 floor to 0.021 / 0.041 / 0.2, which are
  exactly the values now in `inst/extdata/configs/default/parameters_habitat_thresholds.csv`
  for BT, GR, KO, RB (spawn and rear), and every `*_mad_max` is 9999 in both.
- **Header claims against the DB:**
  - `fwa_stream_networks_discharge.linear_feature_id` unique: 2,716,652 rows,
    2,716,652 distinct. The join cannot fan out.
  - `channel_width_source` takes MODELLED, FIELD_MEASURMENT, FWA_RIVERS_POLY and
    NULL in `fresh_default.streams`, so `= 'MODELLED'` excludes measured widths and
    river polygons as stated.
  - "segments with none are left out": inner JOIN plus `mad_m3s IS NOT NULL`. Holds.
  - `channel_width` is double precision. The bin edges computed in SQL (w ± 0.1)
    equal the decimal literals 1.4/1.6, 1.9/2.1, 3.9/4.1 in IEEE double, so the
    inclusive `BETWEEN` matches "within +/- 0.1 m".
- **Stage selection:** `inherits_size()` and `floor_signif2()` are byte-identical
  to `data-raw/query_habitat_thresholds_mad.R`. The run drops KO rear (lake-only)
  and keeps the other seven stages, as the header says.
- **Stamp:** the dirty check's pathspec covers `inst/extdata/configs/default`,
  which holds both inputs the script reads (thresholds CSV, rules.yaml), plus
  `R/` and the script itself. HEAD, fresh sha, WSG count and discharge row counts
  were recorded correctly on the run (55 WSGs; 2,716,652 rows, 2,003,189 with
  mad_m3s).

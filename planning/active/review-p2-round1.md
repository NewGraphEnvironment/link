# Review p2, round 1 — `.lnk_sql_lake_connection()` + default `rearing_km` (#317)

Reviewed: staged diff (R/lnk_rollup_wsg.R, tests/testthat/test-lnk_rollup_wsg.R,
man/lnk_rollup_wsg.Rd), plus every caller of `lnk_rollup_wsg()` in R/, data-raw/, tests/.

The SQL itself is sound. Probed on local fwapg:
- `edge_type` is never NULL in `fresh_default.streams` (0 of 1,764,956), so
  `connection` is never NULL. A NULL there would have dropped a lake line from
  every FILTER, `NOT connection` included.
- `connection` is a non-reserved keyword in PostgreSQL. It works as a column
  alias and in `WHERE NOT x.connection`.
- The polygon join is unchanged and is still keyed on the full PK.

The problems are in existing callers that take the **default** `metrics` and
compare `rearing_km` against something that still counts connection lines.

## Findings

- **[bug]** data-raw/parity_crosssection.R:79 (also data-raw/wsg_vignette_data.R:119).
  Both call `lnk_rollup_wsg(..., schema = "fresh")` with the default metrics and
  compare `rearing_km` against bcfp's `rearing_<sp> IN (1,2)` from
  `fresh.streams_vw_bcfp`. bcfp still counts the 1400/1450 lake lines; link's
  default no longer does. In the bcfishpass-config `fresh` schema (measured):
  - **SK MORR** 442.3 → 124.4 km (−72 %)
  - **SK LFRA** 311.1 → 79.8 km (−74 %)
  - **BT FINA** 2,845.6 → 2,452.0 km (−13.8 %)

  `parity_crosssection.R`'s `tol_hab` is 5 %, and FINA is in its default WSG set,
  so the #223 parity proof now reports habitat failures that are an
  accounting change, not a methodology departure. `wsg_vignette_data.R` would
  write a shifted BT rearing diff into the vignette's cached
  `*_accessible.rds` on its next regen. The bcfishpass-mode parity instrument
  should keep counting every `rearing` line. Pass explicit metrics, or keep the
  old expression, at these two call sites.

- **[fragile]** R/lnk_rollup_wsg.R:120 — the default now changes SK/KO
  `rearing_km` in `fresh_default` too, by about 70 % (MORR 442.3 → 124.4,
  LFRA 349.8 → 96.6, ADMS 229.9 → 70.8; connection lines are 69–74 % of SK
  rearing). #310's standing decision was "SK/KO are unchanged", and
  CLAUDE.md says discarding their lake centrelines would remove their habitat.
  If the operator decision for #317 was scoped to the lake-rearing species
  (BT/CH/CO/RB/ST/WCT), this default over-reaches for SK/KO. Confirm the scope
  before it lands.

- **[fragile]** R/lnk_habitat_validate.R:304-305. The validator takes `cost`
  from the default `lnk_rollup_wsg()`. Capture (`n_rearing`, `share_rearing`)
  still reads `h.rearing`, which includes connection lines, while
  `rearing_km` now excludes them. The documented pairing breaks: "`rearing` is
  the flag … that `rearing_km` costs" (lines 83-84). The roxygen at lines 56-58
  already notes that buffered capture near lakes lands on connector lines.
  Downstream, `data-raw/habitat_variants_score.R:455-466` (`habitat_change.csv`)
  and `data-raw/habitat_validate.R:163/276` use this `rearing_km`. So a
  re-score of #284/#302 will no longer reproduce their archived `rearing_km`
  columns, which CLAUDE.md lists as a reproducibility check. Not wrong, if
  intended, but it moves numbers in archived evidence.

No issues found in the tests or the Rd.

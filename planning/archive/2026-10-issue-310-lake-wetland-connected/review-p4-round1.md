# Phase 4 code-check, round 1

## Clean

No bugs, security issues or data-loss risks found in the staged diff.

### What was checked, and how

- **Join fan-out (none).** Probed local fwapg read-only:
  - `fwa_lakes_poly` has 386,025 rows and 386,014 distinct keys. `fwa_wetlands_poly` has 375,178 rows and 333,526 distinct keys. `fwa_manmade_waterbodies_poly` has 1,812 rows, all distinct. No table has a NULL or 0 key.
  - `.lnk_sql_waterbody_join()` takes `SELECT DISTINCT waterbody_key` from each table, so the duplicate keys inside lakes and wetlands cannot multiply lengths.
  - Cross-table key intersections are 0 / 0 / 0.
  - Row count with the join equals row count without it: 15,921 = 15,921 on `fresh_default` ADMS.
- **Partition holds on live data.**
  - `.lnk_compare_wsg_rollup_link` on `zz311_adms` (CH, CO, SK): stream + lake + wetland = `rearing_km` exactly. For example, CO 318.65 + 250.21 + 45.68 = 614.54.
  - `.lnk_compare_rollup_link` on `fresh_default` PINE (11 species): the residual is ≤ 0.01 km, which is rounding.
- **The three paths agree.** All three use the same `.lnk_sql_waterbody_class()`, `.lnk_sql_waterbody_join()` and `.lnk_sql_lake_polys()` helpers. Every column reference in the joined queries is alias-qualified, so the new `wb` subquery introduces no ambiguity.
- **Renamed labels.** Grepped R/, data-raw/*.R, tests/, vignettes/, inst/ and research/*.yml. The only remaining `*_centerline` label uses are:
  - `data-raw/compare_rollups.R`'s keep list, which is intentional for old directories;
  - the frozen `exp_gradient_extra_breaks.R`;
  - committed logs.
- **`lnk_parity_annotate`.** It uses plain `%in%` membership on `habitat_type` and does not validate metric names, so the renamed taxonomy entry matches the new labels.
- **Tests.** The four affected test files pass: rollup_wsg 40, compare_rollup 27, compare_wsg 65, parity_annotate 55, with 0 fail and 0 error. The live partition test ran and passed against `fresh_default`.
  - Disclosure: the repo's `setup.R` `skip_if_no_db()` overrode my stub and issued `CREATE SCHEMA IF NOT EXISTS working`. The schema already existed, so it was a no-op ("already exists, skipping"). No data was written.

### Observations (not findings)

- **The join is slower but gives correct results.** Each species branch of `lnk_rollup_wsg` rebuilds the DISTINCT over about 760k polygon rows. On PINE (113k segments, 11 species), the query takes 3.3 s with the join against 0.4 s without it. That is about 0.26 s per species per WSG, so it adds minutes across a 217-WSG validate sweep. It never causes a failure. Hoisting the derived table into one CTE would build it once if that ever matters.
- **Ref-side reservoir hectares.** `.lnk_compare_wsg_rollup_bcfishpass` now adds reservoir hectares wherever bcfp rearing touches a reservoir line. Link's bucket gains none, which is the accepted tradeoff. The bcfp-config persist (`fresh`) suggests the effect is small: the largest is BT CHWK at 62 ha across 3 reservoirs, and SK, CO, CH and ST have none.
- **`rearing_stream` changed meaning under the same label.** It now includes river-polygon (1250) and other non-lake, non-wetland lines on both sides. So `diff_range` bands calibrated on the old edge-type slice may no longer fit; this affects `hors-class-stream-order-bypass` [4, 12], `setn-anadr-rearing-stale` and `sk-lake-clustering-divergence`. Rows falling outside a band will surface as UNEXPLAINED until the bands are recalibrated in Phase 5. The YAML comment acknowledges this.
- **Not verified:** that the tunnel `bcfishpass` DB carries `whse_basemapping.fwa_manmade_waterbodies_poly`. The tunnel was not reachable from this review. fwapg loads that table as standard.

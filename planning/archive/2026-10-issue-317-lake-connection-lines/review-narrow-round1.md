# Review: narrow `.lnk_sql_lake_connection()` to 1450 (round 1)

## Findings

- **data-raw/logs/lake_connection_317/README.md:3**: the version pin is now false. The header says the measurement ran at "link 0.61.0 at `1161b59` (main plus the PWF baseline)". The re-run (stamp 09:46) used the staged 1450-only predicate. `measure.R` now calls `.lnk_sql_lake_connection()`, which **does not exist at `1161b59`**: `git grep lnk_sql_lake_connection 1161b59 -- R/` finds nothing, because it was added in `c1760d1`. Anyone who checks out the cited SHA and runs `measure.R` gets an error, not these numbers. `stamp.txt` carries no SHA, so nothing else pins the run. Fix: cite the commit that lands the narrowing (or "this branch, after `c3ea9d7`").

- **R/lnk_rollup_wsg.R:244-245** (roxygen of `.lnk_sql_lake_connection()`): "1410 (network connector) is admitted by no rule" is false as a general statement.
  - In the `bcfishpass` bundle, BT's rear rule is `- []`, which has no edge filter (`inst/extdata/configs/bcfishpass/rules.yaml:19-20`).
  - `fresh.streams_habitat_bt` (the bcfishpass-config persist) holds **132 segments, 49.7 km of 1410 rearing**.
  - The statement holds only for `default` (0 rows in `fresh_default`).
  - The predicate is unaffected: province-wide, `fwa_stream_networks_sp` has **no 1410 or 1425 line in a lake or reservoir polygon** (1410 sits in stream 72,846 and wetland 4,624 only).
  - Suggested wording: "1410 (network connector) does not occur in lake polygons."

## Checked and clean

- Predicate, test, roxygen and man agree on 1450 only. No branch-added line outside the excluded PWF files still says 1400 is a connector or is left out of the km. The test files pass: rollup 50, compare 78, 0 fail (`NOT_CRAN=true`).
- **Numbers match the re-run CSVs** in RUNBOOK.md, CLAUDE.md Status (2026-10-08), research/habitat_thresholds.md "Lake connection lines", the logs README, and the archive README:
  - ADMS BT / CH / CO, and NATR BT at +24.4 %;
  - connection ranges 159–164 and 213–275 km;
  - KO 62 %;
  - SK falls of 55–95 % per WSG, recomputed from parity_bcfishpass.csv and ADMS;
  - Adams Lake 148.8 / 62.8 km;
  - lake 1400 at 0.914 / 1.433 km.
- **parity_bcfishpass.csv was not re-run, but the narrowing cannot move it.** Lake-polygon 1400 / 1410 rearing is 0 km on both sides in all 8 parity WSGs (BULK, CHWK, NASR, QUES, THOM, NECR, BBAR, MFRA): 0 rows in `fresh.streams_habitat_{sk,ch,co,st}`, and NA sums in `fresh.streams_vw_bcfp`.
- **measure.R** is compatible with the new predicate. It aliases `s` and `wb` (`.lnk_sql_waterbody_join()`), and `rear_lake_1400_km` is lake-scoped independently of the predicate. **summarise.R** reads only `rear_flag_km`, `rear_km`, `rear_connection_km`, `rear_lake_flag_km` and `rear_lake_km` (plus their `_bcfp` forms), all still present.
- **habitat_thresholds.md "In wetlands [1400] is usually the only line through the polygon (#320)" holds.** 115,097 of the 115,408 wetlands that carry 1400 carry only 1400 (local fwapg, `fwa_stream_networks_sp`).
- **Archive README "within 0.008 km" is still true** (the new max is 0.007).
- **Unverified:** the archive README's "Suite: 2584 pass" may predate the added `expect_false(grepl("1400", p))`, which would make it 2585. The full suite was not re-run here.

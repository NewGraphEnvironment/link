# Code-check round 2: Phase 4 rollups (#310)

## Findings

- **[severity: fragile]** tests/testthat/test-lnk_rollup_wsg.R:784-806: the live invariant test cannot detect a fan-out, which is the main risk of the new join. `total` and the three parts are computed over the same joined rows. If the polygon join duplicates a line (DISTINCT dropped, or a key present in two tables), `total` grows by exactly what the parts grow by, and `parts == total` still holds. Measured on `fresh_default` LSKE BT, read-only, with a mutated join (lakes UNION ALL'd twice, no DISTINCT): total 1,781,402 m = parts 1,781,402 m, against 1,709,465 m without the join. That is +72 km and the test stays green. Of the structural tests, none asserts DISTINCT, so nothing else catches it either. Fix: also assert `r$total` equals rearing length summed with no polygon join. One way is a direct `SELECT sum(s.length_metre) ... JOIN streams_habitat_bt h ... WHERE h.rearing AND s.watershed_group_code = aoi`. Another is `lnk_rollup_wsg()`'s default `rearing_km`, but that cannot see a fan-out either, since it now carries the join too. So use the direct query.

- **[severity: bug]** research/bcfp_divergence_taxonomy.yml:60-67 (`lake-wetland-centerline-zero-bcfp`): the entry is now wrong in both its premise and its effect.
  - **Premise.** It keeps `pattern: link_only`, which `lnk_parity_annotate()` matches only when `ref_value` is NA or 0 (R/lnk_parity_annotate.R:197). Before #310 the bcfp slices were edge types 1500/1525 and 1700, which were about 0, so the pattern held. Under the polygon split the bcfp side is far from zero. Measured on the local bcfp snapshot (`fresh.streams_vw_bcfp`, `rearing_<sp> IN (1,2)`, same polygon join), province-wide:
    - BT rearing: 18,014 km in lake polygons and 14,803 km in wetland polygons, against 124,840 km stream;
    - CO rearing: 6,644 km in wetland polygons.
  - **Effect.** For BT and CO the `rearing_lake` / `rearing_wetland` rows will no longer match this entry. They fall to UNEXPLAINED or WITHIN_TOLERANCE.
  - **The mechanism text is false.** It says "bcfp's linear rearing rarely includes lines inside lake or wetland polygons (SK lake lines aside)". These rows are now a like-for-like comparison, not a link-only asymmetry.
  - **Fix.** Retire or re-scope the entry (for example to species and metrics where bcfp really is 0) and correct the mechanism. Then re-annotate a rollup to confirm no new UNEXPLAINED rows appear.

## Checked and clean

- **bcfp reference SQL (`.lnk_compare_wsg_rollup_bcfishpass`).**
  - The km query has 8 `%s` placeholders and 8 arguments, in the right order.
  - `slice_expr` gives `COALESCE(wb.waterbody, 'stream') = '<wb>'`.
  - The aliases `s` / `h` / `wb` do not collide, and the lake-ha `l` alias wraps the `.lnk_sql_lake_polys()` subquery correctly.
  - Executed read-only against a stand-in: `bcfishpass.streams` and `habitat_linear_co` were swapped for `fresh_default` subqueries with the same column names. It runs and returns all 8 columns.
- **Working path (`.lnk_compare_wsg_rollup_link`).** Ran read-only on `zz311_adms` for CH/CO/BT. The partition sums to `rearing_km` within 0.01 (rounding), and lake ha returns.
- **NULL `waterbody_key`.** 12,219 of 15,921 ADMS lines in `fresh_default.streams` are NULL. They match no polygon and COALESCE to `'stream'`. None of the three polygon tables holds a NULL or 0 key. `zz311_adms.streams` and `fresh_default.streams` both carry `waterbody_key`.
- **Regex tests.**
  - `\n\s*UNION ALL\n` counts only the species separators; the join's UNION ALLs are inline.
  - `AS waterbody,` matches only the class alias: inside the join, `'lake' AS waterbody` is followed by a space.
  - `fwa_waterbodies` is not a substring of `fwa_manmade_waterbodies_poly`.
  - Each of these fails if its target regresses.
- **Mock in test-lnk_compare_rollup.R.** `function(..., metrics)` receives named `conn` / `aoi` / `species` / `schema` / `metrics`, all accepted by the real `lnk_rollup_wsg()`, so no argument mismatch is hidden. The `edge_type` / `centerline` / `waterbody = '<class>'` assertions each fail if the code reverts to edge-type slices.

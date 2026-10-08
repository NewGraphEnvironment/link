# Review — #310 phase 4, round 3 (staged diff)

## Findings

- **[severity: bug]** research/bcfp_divergence_taxonomy.yml:63-66. Entry `lake-wetland-centerline-zero-bcfp`, prose restating data. The new mechanism says "bcfp's linear rearing rarely includes lines inside lake or wetland polygons (SK lake lines aside)", and the entry keeps `pattern: link_only`, which `lnk_parity_annotate()` (R/lnk_parity_annotate.R:197) matches only when `ref_value` is 0 or NA. Under the new polygon split that premise is false. A probe of the bcfishpass-config persist (`fresh`, link's ~99% parity proxy for `bcfishpass.habitat_linear_<sp>`) with the same lakes ∪ manmade / wetlands join gave this rearing km inside polygons:
  - BT: lake **12,099.5 km**, wetland **10,996.7 km**, in 83 WSGs. By edge type these are mostly 1050 inside wetlands, and 1200 and 1450 inside lakes.
  - CO: wetland **3,850.6 km**, in 45 WSGs.
  - ST: wetland **420.7 km**, in 32 WSGs.
  - SK: lake **9,705.7 km**.

  So bcfp's `rearing_lake` / `rearing_wetland` will be non-zero for BT, CO and ST in most WSGs. `link_only` then never fires for those rows: they become `link_gt_bcfp`, `link_lt_bcfp` or tolerance rows, and anything past tolerance reads `UNEXPLAINED`. The old edge-type slices were near zero on the bcfp side; 1700 does not exist on the FWA network, so the wetland slice was 0 on both sides. The entry was written for that shape and was carried over with only its labels changed.

  Fix: re-measure and rewrite the entry. Either drop the `link_only` claim, or scope it to the species and metrics where bcfp really is zero, and correct the mechanism text.

- **[severity: fragile]** data-raw/compare_rollups.R:53-58. The cross-#310 hazard is guarded by a comment only. `merge(..., all = TRUE)` on `habitat_type` still pairs `rearing_stream` from a pre-#310 directory with `rearing_stream` from a post-#310 one. The label is the same but the meaning differs (edge type against polygon), so the script reports a "methodology delta" that is really the definition change. The `*_centerline` rows and the new `rearing_lake` / `rearing_wetland` rows go unmatched. They become NA on one side and are dropped silently by `aggregate(formula, ...)`'s default `na.action = na.omit`, so the province-wide totals give no sign that anything is wrong.

  Fix: a hard stop when one directory carries `*_centerline` labels and the other carries `rearing_lake` / `rearing_wetland`. The comment already states the rule; nothing enforces it.

## Checked and consistent (the two-places mechanism)

- **Three rollup paths.** `lnk_compare_rollup` → `lnk_rollup_wsg`, `.lnk_compare_wsg_rollup_link` and `.lnk_compare_wsg_rollup_bcfishpass` all take the class from `.lnk_sql_waterbody_class()` / `.lnk_sql_waterbody_join()`, and lake ha from `.lnk_sql_lake_polys()`. No path restates the rule.
- **Builder against fresh.** `.lnk_sql_waterbody_join()` uses the same tables as fresh v0.39.0's `.frs_waterbody_tables()`: L = lakes + manmade, W = wetlands. The claim that `lake_rearing` reads `fwa_lakes_poly` only matches `frs_habitat_predicates.R` at v0.39.0. The local fresh checkout is v0.40.0, so this was checked with `git show v0.39.0:`.
- **"Cannot fan out" claim** (DB probe, local fwapg):
  - waterbody_key overlap is 0 for lakes∩manmade, lakes∩wetlands and manmade∩wetlands, and 0 for lakes∩rivers;
  - no NULL keys in any of the tables.

  So the partition `stream + lake + wetland = rearing` holds by construction.
- **Lake ha DISTINCT.** 9 lake keys have more than one polygon, each with a different `area_ha`. DISTINCT (species, key, area_ha) sums the pieces, which is unchanged behaviour.
- **`waterbody_key` columns.** The column is present on `<schema>.streams` in every persist and working schema probed, and in `lnk_persist_init` cols.
- **Doc text against SQL.**
  - The roxygen in `lnk_rollup_wsg`, `lnk_compare_wsg` (8 habitat types and their labels) and `.lnk_compare_wsg_assemble_rollup` matches `habitat_types` / `units` / `col_suffix`.
  - The taxonomy schema comment's metric list matches `habitat_types`. It omits `accessible`, but that omission predates this diff.
  - The man/*.Rd files are regenerated.
- **Test literals against SQL.** They match the helpers. The `\n\s*UNION ALL\n` count separates species branches from the inline waterbody-join UNION ALLs, which `paste()` joins with a space.
- **Not verifiable from here.** The tunnel DB (`conn_ref`) is assumed to carry `whse_basemapping.fwa_manmade_waterbodies_poly`. Probes were limited to localhost.

---

## Triage of rounds 2 and 3 (parent session; they ran in parallel on the same diff)

- **Taxonomy `lake-wetland-centerline-zero-bcfp`** (both rounds): retired with a comment that gives the measured reason. bcfp's rearing inside polygons is large, so `link_only` no longer fits.
- **Live invariant test could not catch a fan-out** (round 2): it now also asserts the total against a direct sum with no polygon join, and picks a WSG with BT rearing inside a wetland.
  - Mutation check: a wetland join with no DISTINCT (~41k duplicate keys) fails it, as well as the structural tests. On a WSG with no polygon rearing the old version passed under that mutation.
- **`compare_rollups.R` silent mixing** (round 3): it now stops when one directory carries the `*_centerline` labels and the other does not.
- **Accepted (observation):** the DISTINCT join costs ~3 s per 11-species WSG (PINE 0.4 → 3.1 s). An EXISTS variant measured 2.5 s with identical results, so no change.

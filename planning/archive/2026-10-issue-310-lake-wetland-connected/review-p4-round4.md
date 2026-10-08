# Review — #310 phase 4, round 4 (fixes after rounds 2 and 3)

## Findings

- **[severity: fragile]** data-raw/compare_rollups.R:56-61. The guard checks only whether each directory contains *any* `*_centerline` row. A directory holding both pre-#310 and post-#310 files reads as pre-#310, so comparing it with a pure pre-#310 baseline passes with no stop. `rearing_stream` then pairs edge-type values with polygon values for every post-#310 WSG, which is the mixing the guard exists to prevent.

  This kind of directory is what the shipped resume path produces. `data-raw/wsgs_run_host.R:266-274` skips a WSG as "fully cached" when PG has rows and a non-stub `<WSG>.rds` exists. Any other WSG is re-run, and its new post-#310 RDS lands in the same `out_dir` beside the cached pre-#310 ones.

  Fix: also stop when a single directory carries both label sets. For example, `any(grepl("_centerline$", x$habitat_type)) && any(x$habitat_type %in% c("rearing_lake", "rearing_wetland"))` → stop, naming the directory.

  Minor, in the same lines: with an empty directory, `read_dir()` returns NULL, so `pre310(NULL)` is `FALSE`. Paired with a pre-#310 directory, the script then stops with the "pre-#310 vs post-#310" message instead of "no rows". It stopped before this change too (`NULL[logical(0), ]` errors at line 65), so nothing new is wrong except the message.

## Checked and clean

1. **Live test "stream + lake + wetland rearing km equal rearing km (live)"**
   - It ran rather than skipping: 2 expectations passed with `NOT_CRAN=true`, and the whole file is green. The pick resolves to LSKE on the local persist.
   - **integer64.** `count(*)` arrives as integer64, and `has$n == 3L` dispatches correctly through bit64, which RPostgres imports. `length_metre` is `double precision`, so `r$total` and `direct$m` are both double, and `as.numeric()` is harmless.
   - **NULL sums.** None are possible. The pick guarantees at least one `h.rearing` row in the aoi, so `direct$m` and `r$total` are non-NULL. `parts` uses `na.rm = TRUE`, so a class with no rows (NA) does not poison it.
   - **Fan-out detection.** The direct side omits both the polygon join and the access LEFT JOIN, so a duplicate in either shows as a mismatch. The streams ⋈ habitat join is shared by both sides, so a fan-out there would agree with itself. That join is outside this fix's scope.
   - **Lake-side fan-out.** The pick targets wetlands only. 9 keys in `fwa_lakes_poly` ∪ `fwa_manmade_waterbodies_poly` have more than one polygon, so a lake-side DISTINCT removal could fan out. But `fresh_default` has 0 BT rearing segments on any of those 9 keys in any WSG (probed), so it cannot affect output today and the test cannot be fooled by real data.
   - `h.rearing` is boolean, so the `WHERE ... AND h.rearing` filters are valid.

2. **Taxonomy retirement**
   - No code, test or driver references `lake-wetland-centerline-zero-bcfp`; the grep covered R/, tests/, data-raw/*.R|*.sh, research/ and inst/.
   - The only remaining mentions are prose. They are historical run records (`provincial_parity_2026_05_11.md`, `_05_12.md`) and the comment itself.
   - The YAML loads: `yaml::read_yaml()` gives 10 entries with unique ids.
   - `test-lnk_parity_annotate.R` passes in full against the shipped file. Its shipped-file test asserts `lake-wetland-polygon-asymmetry`, which is untouched.
   - `wsgs_run_host.R` and `wsgs_dispatch.sh` read the file only by path.

3. **compare_rollups.R guard**
   - It runs before any use of the frames: after the row-count `cat` and before the `keep` filter and the merge.
   - It cannot stop falsely on two clean directories of the same vintage. `.lnk_compare_wsg_assemble_rollup()` emits every habitat_type for every species, so a pre-#310 directory always carries `*_centerline` rows and a post-#310 one never does. No other emitted label ends in `_centerline`.
   - Mapping_code-mode RDS files are lists, which `read_dir` skips. That predates this change.
   - The mixed-directory gap is the finding above.

---

## Triage (parent session)

- **Fixed (a defect inside round 3's fix):** `compare_rollups.R` classifies each directory as empty, pre-#310, post-#310 or mixed, and proceeds only on pre/pre or post/post. The error names the directory.
  - **Enumeration that ends the loop:** all 16 state pairs were run through the guard's own code (`slices()` extracted from the script, synthetic frames). The 2 matching pairs proceed and the other 14 stop.
- **Accepted:** the live test picks a WSG by wetland rearing, so a lake-side fan-out would not show. 9 lake / reservoir keys carry more than one polygon, and none carries BT rearing in `fresh_default`. The structural tests pin DISTINCT on all three branches of the join.

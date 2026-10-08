# Review p234 round 3 (#317): code re-check + doc number/claim verification

## Findings

- **[severity: fragile]** RUNBOOK.md:761-783. The new "Lake connection lines" top-level bullet went in at the wrong place: in the middle of the #310 bullet's list. It sits between "**Rollups split `rearing` km by the polygon each line sits in**" and that item's own sub-bullet. As a result:
  - "The polygon is matched by `waterbody_key` against those polygon tables, not `fwa_waterbodies` ..." (the 4-space sub-bullet at :777-778) now renders nested under "SK / KO lake rearing is mostly 1450". That attributes the polygon-matching rule to the SK/KO drop.
  - "**`lnk_habitat_validate()` reads a bucket cleared by the connection test as `post_predicate`**" (:779) and its sub-bullet "`lake_rearing` / `wetland_rearing` are hectares ..." (:782) are #310's spawning-connection mechanics. They now sit under the #317 "Lake connection lines" bullet, so "the connection test" reads as the lake-connection-line predicate. The RUNBOOK is read as the spec, and this changes which mechanism a reader thinks those two lines describe.
  - Fix: move the #317 block to after line :783, the end of the #310 bullet, before "**`default` and `default_tuned` carry MAD ranges**".

- **[severity: fragile, doc number]** The SK/KO drop figure is stated as general but was measured on two rows only, ADMS SK (−69.2 %) and NATR KO (−61.7 %).
  - Where the figure appears:
    - CLAUDE.md, #317 status: "SK / KO rearing km fall about 60–70 % on both sides".
    - research/habitat_thresholds.md, new section: "SK / KO rearing km fall by about 60–70 % ... That happens on both sides".
    - RUNBOOK.md:775-776: "drop by about 70 % on both sides".
  - The PR's own `parity_bcfishpass.csv` gives the SK drop, connection / (rearing + connection), on the six bcfishpass-config WSGs: BULK 58.6 %, CHWK 76.8 %, NASR 78.7 %, NECR 55.1 %, THOM 83.2 %, QUES 95.2 %. So the evidence range is about 55–95 %, not 60–70 %.
  - KO has no bcfishpass reference, so "on both sides" holds for SK only.
  - RUNBOOK's "about 70 %" also disagrees with the other two docs' "60–70 %".
  - Suggest: "about 60–70 % on ADMS / NATR, and 55–95 % for SK on the bcfishpass-config WSGs (QUES 95 %)", with "both sides" scoped to SK.

## Verified correct (no action)

**Numbers against `summary.csv`, `measure.csv` and `reference.csv`:**
- ADMS BT +16.4 → +2.0, CH +91.1 → +38.9, CO +75.0 → +28.7, SK 0.0 → 0.0.
- NATR BT +29.8 → +24.3.
- Every old → new rearing value and every connection km in the habitat_thresholds table.
- SK −69 % if the rule were applied to link alone.
- ADMS SK 159.1 of 229.9 km.
- bcfishpass BT connection lines: 65.9 km on ADMS and 88.1 km on NATR. bcfishpass SK holds the same 159.1 km.
- "1400 at most 1.4 km": 1.433 km on NATR RB, 0.914 km on NATR BT, 0 elsewhere.

**Adams Lake:**
- 62.8 km of 1200 and 148.8 km of 1450 (`adams_lake.csv`).
- Re-queried on `zz311_adms.streams` over all lines, not only rearing ones: the same 62.8 / 148.8. So "holds" is correct as a whole-lake statement.

**Parity on the bcfishpass config (`parity_bcfishpass.csv`):**
- "SK 0.0 % on BULK, CHWK, NASR, NECR, QUES, THOM" holds.
- "Connection km equal ... within 0.3 %" holds; QUES is −0.3 %, the rest 0.
- "Pinned CH / CO / ST bands (BBAR, THOM, MFRA) do not move" holds: connection km is 0 on both sides for those rows, so `rearing` is unchanged.

**Function claims:**
- `lnk_aggregate()` defaults to `rearing_km = "rearing"`.
- `lnk_habitat_validate()` cost calls `lnk_rollup_wsg()` with no `metrics` (R/lnk_habitat_validate.R:305).
- `data-raw/parity_crosssection.R:79` and `data-raw/wsg_vignette_data.R:119` call `lnk_rollup_wsg()` with no `metrics`.
- So all of them get the flag total. Strictly, the last three go through `lnk_rollup_wsg()`'s default rather than "summing `streams_habitat.rearing` directly", but the effect claimed is right.

**Dictionary CSV:**
- `inst/extdata/configs/dictionary_dimensions.csv` parses with `read.csv`.
- Its columns are identical to HEAD, with 34 rows and the same `column` keys.

**Provenance checksums:**
- `.lnk_config_hash()` (R/lnk_log.R:52) hashes `config.yaml`, rules, dimensions, the declared `files:` and `provenance:` entries.
- No `config.yaml` declares `README.md` or `dictionary_dimensions.csv`, so neither edit moves a config hash.

**Code:**
- `.lnk_sql_lake_connection()` is NULL-safe, wrapped in `COALESCE(..., FALSE)`, and lake-only. Stream and wetland lines can never be connection lines, so stream + lake (no connection) + wetland partitions `rearing_km` (no connection). `rollup_check.csv` confirms this within 0.01.
- In `.lnk_compare_wsg_rollup_link`, every `sprintf` spec is positional: `%1$s` through `%6$s`, with the argument order matching.
- On the ref side:
  - `rear_expr(pred)` returns `"0"` when `has_rear` is FALSE, the connection column included.
  - The lake slice appends `AND NOT <conn>`.
  - `bcfishpass.streams` carries `edge_type` / `waterbody_key`: the parity run produced non-zero ref connection km.
- `compare_rollups.R`:
  - The pre / post-#317 detection is keyed by WSG.
  - A pre-#310 directory returns before the #317 test.
  - A mixed directory stops.
- No other R/ or data-raw consumer hardcodes the 8-type habitat list. `exp_gradient_extra_breaks.R` is pre-#310 and unaffected.
- Tests pin the predicate text and the SQL on both sides.

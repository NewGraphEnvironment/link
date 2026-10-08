# Review p56, round 3 (#310 docs claims against their sources)

## Findings

- **[severity: bug, minor]** RUNBOOK.md:776-777 — "Since #310 `default`'s buckets keep only polygons connected to same-species spawning." This sits in the bullet about BT, GR, **KO** and RB, and it is false for KO (and SK): their `rear_*_connected_distance_max` cells are blank (`configs/default/dimensions.csv`), the builder refuses them (circular), and `rules.yaml`'s KO / SK L rule carries no `requires_connected`. Their `lake_rearing` bucket still keeps every accessible lake over 200 ha with no spawning test (the snapshots confirm it: KO NATR and SK ADMS are row-identical A vs B). Suggest "keep only polygons connected to same-species spawning, except SK and KO". The CLAUDE.md status headline ("`default`'s buckets keep only polygons with same-species spawning within 10 km") has the same overreach, though its third sub-bullet then says SK / KO are unchanged.

## Verified (no issue)

Every other quantitative or categorical claim in the CLAUDE.md status block, the RUNBOOK #310 bullets, the research "Measured" paragraph and the `lake_connected_310/README.md` checks out against its source:

- **CSV numbers:** all README table cells (rearing A/B/Δ, lake/stream Δ, vs-bcfp %, bucket ha and counts, divergence counts) match `summary.csv` / `measure.csv`. The ranges hold: 237–525 km; ADMS +237 to +255; NATR +408 to +525; NATR BT wetland −2.1 %; at most 14 lake polygons. `rollup_check.csv` has parts − total ≤ 0.01.
- **DB probes on `zz310_snap.*`:**
  - SK (ADMS, 39,422 rows) and KO (NATR, 47,300 rows) are identical A vs B by EXCEPT both ways. Spawning differs on 0 rows in both WSGs.
  - Adams Lake (wbk 329014384) is 13,229.3 ha. Every species rears 62.8 km of 1200 and 148.8 km of 1450 there in B; in A only SK reared there (211.6 km). 211.6 / 62.8 = 3.4 ("roughly three times").
  - No reservoir (`fwa_manmade_waterbodies_poly`) line rears in either WSG, so the lake divergence counts contain no reservoir.
  - Wetland "ha, no km": NATR BT 808 = 515 (1050/1150) + 12 (1000/1100 only) + 281 residual. ADMS BT 14 of 28 and CH 9 of 19 are residual, and so are all of RB's (273, 13). The residual lines are 1200 / 1400, plus 2 segments of 1410 per species, so the "(1200 / 1400)" label is materially right. No residual polygon holds 2000 / 2300 lines.
  - GR's 160 "km, no ha" wetlands: their rearing lines are all 1000 (369 segments) / 1100 (6) mainlines.
- **Bundle:** 10 km cells for BT/CH/CO/GR(L only)/RB/ST/WCT. CT/DV carry the cells but have no row in the bundle thresholds CSV and no entry in `rules.yaml`. CO has blank floors and its `rules.yaml` rules carry no ha_min. RB `cluster_rearing = FALSE`. `default_tuned` inherits rules via `extends: default`.
- **Run A (`865bd04`, on origin/main):** CO floored at 2 ha (L) / 0.5 ha (W); the L rule is on 1000/1100 with no connection. This matches "52 lakes under 2 ha / 6 wetlands under 0.5 ha".
- **Builder:** the retired columns stop the build. Stamping goes on the first L / W rule only. The lake edge set is as stated. W is emitted before L in the additive branch. The SK/KO circular and area_only refusals are present.
- **fresh v0.39.0 = `e247ca1`** (matches `runs.csv`):
  - `frs_habitat_predicates.R:205-211`: the bucket reads `fwa_lakes_poly` only.
  - `.frs_waterbody_tables("L")` adds manmade, and the rule compiler uses it (`utils.R:286`).
  - `.frs_validate_rear_connected()` refuses the keys on later L / W rules, and `.frs_validate_rule` refuses a rear `requires_connected` without `waterbody_type`, so "refuses the keys on any other rule" holds.
  - `.frs_run_connectivity()` anchors on the first rear L or W rule.
  - `.frs_bucket_connected()`'s three connection cases match the RUNBOOK / research wording.
- **Rollup:** `.lnk_sql_waterbody_join()` classes lines by lakes ∪ manmade / wetlands `waterbody_key`, not edge type. `*_centerline` is gone from `R/`.

---

## Triage (parent session)

Fixed: "except SK's and KO's" is now in the RUNBOOK sentence and the CLAUDE.md headline. The reviewer checked every quantitative and categorical claim in the docs against its source (CSVs, snapshots, builder, rules.yaml, fresh v0.39.0), and this was the only false one, so the loop ends on that enumeration. Round 2 was clean.

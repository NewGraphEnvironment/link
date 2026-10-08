# Review p56, round 1 (#310 measurement logs + docs)

## Findings

- **[severity: bug]** data-raw/logs/lake_connected_310/README.md:67 — "The wetland 'ha, no km' counts are mostly a different gap: lines inside wetlands that are construction lines (1200 / 1400). No rear rule admits those." This is false for the clustered species, and for the largest count in the table. I probed the B snapshots (same polygon rule as measure.R, wetland = `fwa_wetlands_poly`, `wetland_rearing AND NOT any rearing`) and split each polygon by whether it holds any line a W rule admits (1000/1100/1050/1150):
  - NATR BT: 808 polygons. 515 hold 1050/1150 wetland-flow lines (`thresholds: false`, admitted by the floored carve-out rule), 12 more hold only 1000/1100, and **only 281 (35 %) are construction-only**.
  - ADMS BT: 14 of 28 construction-only. ADMS CH: 9 of 19. ADMS CO: 19 of 26.
  - RB (NATR 273, ADMS 13): all construction-only. That fits: RB has no rearing cluster pass, so an admitted line always rears.

  For BT and CH, then, most "ha, no km" wetlands have admissible lines that do not rear. That is the `cluster_rearing` divergence (the polygon connects within 10 km, its lines are cluster-dropped), the same mechanism the README gives for lakes one bullet earlier. It is not the construction-line gap. Why it matters: the README sends the operator, and the drafted wetland-construction-line follow-up, to a rule gap. For BT on NATR that gap explains about a third of the count. Pooled over all six rows it is about 52 % (609 of 1,167), so "mostly" holds only by pooling RB in. Reword to give the split per species, or at least to name clustering as the main cause for BT and CH.

- **[severity: bug]** data-raw/logs/lake_connected_310/README.md:57-58 — "CO gains … 5 wetlands under 0.5 ha … Some of its wetlands drop out for lack of connected spawning". On ADMS, CO A → B gains **6** wetlands, all under 0.5 ha (largest 0.486 ha), and loses **1** (3.24 ha). So 5 is the net change (106 → 111), and "some" is one. The 52 lakes check out exactly: 52 gained, all under 2 ha (largest 1.92), none lost.

- **[severity: bug, minor]** data-raw/logs/lake_connected_310/README.md:9 — "NATR has all the lake species except CO (BT, GR, KO, RB)". NATR has none of CH, SK, ST or WCT, which also rear in lakes under `default`. What NATR does have is all four of BT / GR / KO / RB (CLAUDE.md's "Only NATR and PARS hold all four species"). Two related lines, not really wrong given the next clause:
  - CLAUDE.md "Rearing rises 237–525 km per lake species": SK and KO are lake species and rise 0. The next clause says they are row-identical.
  - research's "+237 to +255 km per species on ADMS": SK is +0.

## Verified (no issue)

- **No fan-out in measure.R.**
  - No `waterbody_key` is shared between the lakes, manmade and wetlands tables (all three intersections are 0), so the `wb` UNION ALL cannot duplicate a line.
  - `id_segment` is unique in `zz311_adms.streams` (39,422) and `zz311_natr.streams` (47,300).
  - The snapshots are unique on `(id_segment, species_code)`.
  - spawning / rearing / lake_rearing / wetland_rearing have no NULLs in any snapshot, so `NOT bucket` / `NOT any_rear` cannot drop rows.
  - integer64 counts are converted.
- **A and B are measured by one rule.** It is pure SQL on the snapshots against the same `streams`, with no link code in the path.
- **Every number in the README tables and in the research / CLAUDE.md bullets matches measure.csv / summary.csv**: rearing A/B/Δ, lake and stream Δ, vs-bcfp %, bucket ha and counts, divergence counts, NATR BT wetland −2.1 %. rollup_check.csv matches measure.csv to rounding.
- **Adams Lake** (wbk 329014384, 13,229.3 ha): 211.6 km rearing for BT/CH/CO/RB (and SK, already in A); 62.8 km 1200 + 148.8 km 1450. NATR BT lake km: 275.0 (1450) + 227.6 (1200) + 5.1 (1475) + 0.9 (1400).
- **SK (ADMS) and KO (NATR) are row-identical A vs B**, by EXCEPT both ways.
- **Lake divergence polygons**: none are reservoirs. All are accessible, all have L-rule-admissible lines, and all are at or above the lake floor where one exists. That is consistent with the README's cluster explanation.
- **`fwa_waterbodies` gap**: 23,507 km province-wide, which matches "~23,000 km".
- **fresh v0.39.0 claims**:
  - `frs_habitat_predicates.R:205-211`: the bucket uses `fwa_lakes_poly` only.
  - `.frs_waterbody_tables("L")` adds manmade.
  - `.frs_validate_rear_connected()` exists and refuses the keys on later rules.
  - `.frs_run_connectivity()` anchors on the first rear L or W rule (200 ha fallback).
  - The bucket connection semantics (on it / downstream within distance / upstream traced down mainstem lines) match `.frs_bucket_connected()` docs.
- **Builder claims**: the retired-column stop, stamping on the first L/W only, the lake edge set, W emitted before L, and the SK/KO circular and area_only refusals.
- **Bundle claims**: the 10 km cells for BT/CH/CO/GR(L)/RB/ST/WCT (CT/DV inert), CO's NA floors, and RB `cluster_rearing = FALSE`.
- **Validator roxygen**: the `post_predicate` wording is consistent with the rear predicate `rearing OR lake_rearing OR wetland_rearing`.
- **No infra identity**: localhost:5432 and docker default credentials only.

---

## Triage (parent session)

All three fixed in the README. The breakdown was spot-checked before it was written down: NATR BT has 808 such polygons, and 515 of them hold 1050/1150 lines; the CO gain is 6 wetlands. CLAUDE.md and the research text now exclude SK / KO from the rise.

# Plan review (#310) — Plan agent, 2026-10-07, read against HEAD 51752c1 + fresh v0.39.0

Written by the parent session from the agent's reply (Plan agents have no Write tool).

## Blockers
- **B1 (verified):** fresh's lake bucket reads `fwa_lakes_poly` only (`R/frs_habitat_predicates.R:205-211` at v0.39.0); `.frs_waterbody_tables("L")` (lakes + manmade) is used by the rule compiler (`rearing`) and the SK/KO spawning pass only. Decision 5 needs a fresh change. → link-side ha join keeps lakes ∪ manmade (adds 0 until fresh changes); fresh issue drafted; comment in `.lnk_sql_lake_polys()` corrected.
- **B2 (verified):** CT and DV have no row in the thresholds CSV, so `lnk_rules_build()` skips them; their distance cells are inert. → bundle test asserts them absent; research + NEWS say so.

## Questions answered
- L rule reaches `rearing` (`accessible AND (edge IN … AND waterbody_key IN lakes ∪ manmade)`). `thresholds: false` is redundant on L/W rules (`utils.R:252`), kept for explicitness.
- No misread of rear `requires_connected` by the spawning-connectivity pass (it scans spawn rules only).
- Missed consumers: long-format labels + roxygen (done in Phase 4 draft), `research/bcfp_divergence_taxonomy.yml` (schema comment + `lake-wetland-centerline-zero-bcfp`), `data-raw/compare_rollups.R` keep-list, `data-raw/exp_gradient_extra_breaks.R` (frozen experiment, left), research prose.
- Provenance: rules.yaml checksum; dimensions.csv checksum + shape_checksum + synced; generator_sha two-step; commit atomically (test-lnk_config.R:396-406).

## Gaps
- G1: RB (and CT, DV) have `cluster_rearing = FALSE`, so RB lake centreline km count in every accessible lake ≥ 10 ha regardless of spawning; cluster upstream check has no distance. Divergence runs both ways. → documented; count both directions in Phase 5.
- G2: lake lines can join inlet/outlet rearing clusters, so stream rearing may rise too. → report `rearing_stream_km` change separately.
- G3: build_rules.R / regen_provenance.R rewrite bcfishpass rules.yaml (date line). → build default + top-level, copy to variants; leave bcfishpass.
- G4: `rearing_stream_km` keeps its name, changes meaning. → NEWS breaking note; taxonomy entries keyed on rearing_stream noted.
- G5: lnk_rollup_wsg defaults unchanged (already so). → plan text updated.
- G6: categories-mode lake edges wider than explicit. → fixed (explicit codes both modes), also code-check round 1.
- G7: edge set from 4 WSGs only. → province-wide query.
- G8: top-level dims not a mirror. → edited by column name (done).
- G9: dictionary rows stale. → rear_lake / retired rows updated.
- G10: distance on a species with no L/W rule silently skipped. → stop.

## Assumptions
- A1: `fwa_waterbodies` built from lines with non-NULL localcode, non-999 wscode; keys carried only by other lines fall into "stream". `fwa_waterbodies` on the bcfp DB unverified (tunnel down).
- A2: per-metric rounding → invariant tolerance needed (live test sums unrounded).

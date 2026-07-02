# Progress — Per-WSG habitat/access km roll-up (accessible_km) (#221)

## Session 2026-07-01

- Plan-mode exploration of `lnk_compare_rollup.R`, `lnk_compare_wsg.R`,
  `lnk_pipeline_access.R`, `lnk_persist_init.R`, bcfp `wsg_linear_summary.sql`.
- Spawned Plan agent to pressure-test the draft — surfaced the unverified-columns
  blocker; resolved live against local fwapg.
- Verified `fresh.streams_vw_bcfp` columns; corrected the accessible predicate to
  `= ''` (text, not `text[]`); ran the coho proof: MORR 0.09%, BULK 0.27%.
- Phases approved by user.
- Created branch `221-per-wsg-habitat-access-km-rollup` off main.
- Scaffolded PWF baseline with approved phases.
- **Phase 1 done.** Wrote `data-raw/accessible_km_proof_co.R`; ran across all 20
  locally-persisted WSGs: 19/20 within ±5% (most < 1%), SETN +109.75% correctly
  flagged as documented bcfp-side stale-subsurfaceflow divergence (link correct).
  Predicate corrected to `= ''` (snapshot stores barrier arrays as text).
- **Phase 1 committed** (`510ec08`) after 3-round code-check (on.exit wrapped in
  `main()` so cleanup fires; null_ref guard; coho-present `lnk` universe).
- **Phase 2 (1/4) done.** Shipped `R/lnk_rollup_wsg.R` — reusable predicate-driven
  per-(WSG, species) roll-up mirroring `frs_aggregate`'s `metrics`/`where` shape.
  Per species it joins streams+access+habitat on full PK and aliases the species-
  varying columns to generic `access`/`spawning`/`rearing` so `metrics` SQL stays
  species-agnostic. Default emits accessible_km/spawning_km/rearing_km. 27 unit
  tests (arg validation + offline SQL build via `DBI::ANSI()`), code-check clean.
  Live: MORR coho accessible_km 3330.25 (= Phase-1 proof). Key: accessible_km
  sources `streams_access.access_<sp> IN (1,2)`, not `streams_habitat.accessible`.
- Discovered `streams_habitat_<sp>.accessible` bool diverges from the access model
  (MORR coho 3424 vs 3330 km) — do NOT sum it for accessible_km.
- **Phase 2 (1/4) doc tweak committed** (`f8ce11c`): `@seealso [lnk_aggregate()]`
  + a flat-per-WSG-GROUP-BY vs per-crossing-upstream-network note, so the
  rollup/aggregate split is intentional. Regenerated compare-family Rd
  back-references (missed in the prior commit).
- **Phase 2 (2/4) done.** Folded `.lnk_compare_rollup_link`'s `km` block into
  `lnk_rollup_wsg`: it now passes a 5-metric `metrics` vector (COALESCE→0 to
  keep the old CASE-WHEN measured-zero, not NULL/NA), renames
  `species`→`species_code`, drops `wsg`, preserving the
  `list(km, lake_ha, wetland_ha)` contract. `lnk_rollup_wsg` streams_access
  join `JOIN`→`LEFT JOIN` (access is optional metadata; absent → accessible_km
  0, habitat length never dropped). Verified byte-identical vs the old
  CASE-WHEN SQL on MORR BT+CO across all 5 metrics (BT 951.33/1824.66/1272.03/
  0/0, CO 915.97/1228.72/927.70/0/0); `lnk_rollup_wsg` accessible_km still
  3330.25. `lnk_pipeline_access` runs unconditionally so persist
  `streams_access` always exists — fold is safe even for mapping_code=FALSE.
  Dead working-schema `.lnk_compare_wsg_rollup_link` left untouched.
- **Phase 2 (2/4) committed** (`4be5b87`) after 3-round code-check clean.
- **Phase 2 (3/4) done.** accessible_km now emits as the 8th
  habitat_type. Added `accessible_km` to `.lnk_compare_rollup_link`'s
  `km_metrics` (`round(COALESCE(sum(length_metre) FILTER (WHERE access IN
  (1,2)),0)/1000,2)`) — sources link's per-species access model via
  lnk_rollup_wsg's LEFT-joined `access` alias, NOT the divergent
  streams_habitat.accessible bool. Appended `accessible` (unit km) to
  habitat_types/units/col_suffix/link_sources in
  `.lnk_compare_wsg_assemble_rollup`. Its `ref_value`/`diff_pct` stay NA
  (the bcfp habitat ref has no accessible column) until Phase 2 (4/4)
  wires the tunnel-free `fresh.streams_vw_bcfp` ref. Row-count assertions
  bumped 7→8 / 14→16 in test-lnk_compare_wsg.R + 7→8 in
  test-lnk_compare_rollup.R, each with a new accessible-row check
  (link populated, ref NA). Live MORR coho accessible_km 3330.25
  (= Phase-1 proof). 108 tests green; lint clean (only pre-existing
  helper-name/indent notes); docs regenerated.
- **Phase 2 (4/4) done.** Tunnel-free `accessible_km` reference wired.
  New `.lnk_compare_wsg_accessible_ref(conn, aoi, species)` sums
  `fresh.streams_vw_bcfp.length_metre WHERE <barrier_group> = ''` on the
  LOCAL conn (snapshot authoritative; tunnel dead on M1). Only the
  Phase-1-proven salmon group is wired (CH/CM/CO/PK/SK →
  `barriers_ch_cm_co_pk_sk_dnstr`); BT/ST/WCT/CT-DV-RB short-circuit to
  NA (each needs its own proof — Phase 3). Threaded local `conn` through
  `.lnk_compare_wsg_rollup_reference` (habitat ref stays tunnel-based on
  `conn_ref`; the two reference sources are intentionally decoupled) and
  `lnk_compare_rollup`'s call site. Live: MORR CO ref 3327.38 vs link
  3330.25 → diff_pct 0.1% (matches Phase-1); BT ref NA. SK ref = CO ref
  (bcfp models the salmon group with one shared column — per-species vs
  per-group coarsening surfaces in the diff, documented for Phase 3).
  4 new helper tests (mock `DBI::dbGetQuery`); m_ref mock gained `conn`.
  65+20 tests green in the two touched files; lint no new indent notes
  (one object_length note on the >30-char helper name, matching the
  established `.lnk_compare_wsg_*` family); docs regenerated. The one
  full-suite FAIL (`public.wsg_outlet` missing) is pre-existing +
  environmental, unrelated.
- Next: Phase 3 — extend `accessible_km` ref to BT
  (`barriers_bt_dnstr`), ST (`barriers_st_dnstr`), WCT/CT-DV-RB; wire
  into `lnk_parity_annotate()` + `research/bcfp_divergence_taxonomy.yml`.
  Each species-group needs its own Phase-1-style proof before wiring.

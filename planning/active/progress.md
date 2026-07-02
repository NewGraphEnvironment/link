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
- Next: Phase 2 (3/4) — emit accessible_km as 8th habitat_type in
  `.lnk_compare_wsg_assemble_rollup` + update row-count assertions
  (7→8, 14→16) in `test-lnk_compare_wsg.R`.

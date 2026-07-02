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
- Next: Phase 2 (2/4) — fold `.lnk_compare_rollup_link` habitat km sums into the
  `lnk_rollup_wsg` path; then emit accessible_km as 8th habitat_type + update tests.

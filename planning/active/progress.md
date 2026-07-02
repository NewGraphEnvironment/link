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
- Next: Phase 2 — abstract the roll-up into `lnk_rollup_wsg`.

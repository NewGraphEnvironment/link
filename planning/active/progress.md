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
- Next: Phase 1 — write `data-raw/accessible_km_proof_co.R`.

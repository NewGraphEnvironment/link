# Progress — lnk_compare_wsg + provincial parity annotated CSV (#162)

## Session 2026-05-12

- Plan-mode exploration — phases approved by user.
- Created branch `162-lnk-compare-wsg-annotated-csv` off main.
- Scaffolded PWF baseline from #162 with approved phases.
- Driving motivation: zero rows ≥2% divergence end up "unexplained" — every divergence either maps to a known class (A/B/C/D/measurement asymmetry/intentional) or is flagged for investigation. Single CSV ties together rollup + mapping_code lenses + taxonomy.
- Next: start Phase 1 — `R/lnk_compare_wsg.R` rollup-only path.

## Session 2026-05-12 (Phase 1)

- Wrote `R/lnk_compare_wsg.R` (~440 lines). Exported function `lnk_compare_wsg(conn, aoi, cfg, loaded, reference, with_mapping_code, conn_ref, species, schema, dams, cleanup_working)`.
- Library-vs-script separation: lib takes pre-resolved `conn` + `conn_ref` + `cfg` + `loaded`. Data-raw wrappers (Phase 3) handle env vars, conn creation, baseline stamping, RDS persistence.
- Internal helpers: `.lnk_compare_wsg_rollup_link()`, `.lnk_compare_wsg_rollup_reference()`, `.lnk_compare_wsg_rollup_bcfishpass()` (dispatched), `.lnk_compare_wsg_assemble_rollup()`.
- Reference dispatch ready for additional references (default-bundle, federal data) — currently only `"bcfishpass"` wired.
- `with_mapping_code = TRUE` errors with explicit Phase 2 message — guard against premature use.
- Tests: 29 PASS / 0 FAIL. Cover arg validation, reference dispatch, pipeline phase order, rollup tibble shape, diff_pct edge cases (NA ref, zero ref).
- Full suite: 1047 PASS / 0 FAIL.
- Surfaced morning's link#160/#161: SIGPIPE in snapshot_bcfp.sh Parquet check (NOT conda env activation — rtj#129 was wrong diagnosis). Plan Phase 7 updated to reflect v0.35.1 baseline.

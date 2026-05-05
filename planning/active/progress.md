# Progress — Auto-stamp bcfp baseline in run_provincial_parity.R (#121)

## Session 2026-05-04

- Plan-mode exploration of `run_provincial_parity.R`, `compare_bcfishpass_wsg.R`, `bcfp_baselines.csv`, `R/` exports, and per-host tunnel patterns. Phases approved by user.
- Created branch `121-auto-stamp-bcfp-baseline-in-run-provinci` off main (v0.29.0).
- Scaffolded PWF baseline (task_plan.md, findings.md, progress.md) with approved phases.
- Issue #121 body trimmed of the (now-discarded) "revert build-time wiring" item — no commit ever carried that wiring.
- Phase 1 complete: `host` column added to `bcfp_baselines.csv`, 3 existing rows backfilled to `m4`, all 4 lines now 8 fields.
- Next: Phase 2 (stamp helper + invocation in `run_provincial_parity.R`).

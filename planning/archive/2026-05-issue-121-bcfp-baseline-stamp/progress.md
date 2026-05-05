# Progress — Auto-stamp bcfp baseline in run_provincial_parity.R (#121)

## Session 2026-05-04

- Plan-mode exploration of `run_provincial_parity.R`, `compare_bcfishpass_wsg.R`, `bcfp_baselines.csv`, `R/` exports, and per-host tunnel patterns. Phases approved by user.
- Created branch `121-auto-stamp-bcfp-baseline-in-run-provinci` off main (v0.29.0).
- Scaffolded PWF baseline (task_plan.md, findings.md, progress.md) with approved phases.
- Issue #121 body trimmed of the (now-discarded) "revert build-time wiring" item — no commit ever carried that wiring.
- Phase 1 complete: `host` column added to `bcfp_baselines.csv`, 3 existing rows backfilled to `m4`, all 4 lines now 8 fields.
- Phase 2 complete: inline `stamp_bcfp_baseline()` helper added to `run_provincial_parity.R` between the per-WSG-timings setup and the WSG loop. Connection pattern reused from `compare_bcfishpass_wsg.R:44–54`. `LNK_HOST_ALIAS` env var override falls back to `Sys.info()[["nodename"]]`. Single invocation site after helper definition.
- Phase 3 complete: smoke + idempotency + tunnel-down all pass. `model_run_id=120, model_version=v0.7.14-113-ga7373af`. Row written cleanly, second run within minute correctly skipped, `--no-environ` (no `PG_PASS_SHARE`) WARN-and-continued without writing.
- Verification logs: `20260505_0545_link121_verification.txt`, `20260505_0546_link121_verification_tunneldown.txt`.
- Phase 4 partial: `NEWS.md` 0.29.1 entry written; `DESCRIPTION` bumped 0.29.0 → 0.29.1.
- Next: push branch, open PR (Closes #121), then `/planning-archive` on merge.

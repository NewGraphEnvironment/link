# ops-hardening 2026-05-13 → 2026-05-14

## Outcome

Operational hardening from the post-compact provincial dispatch session. Three new top-level scripts (`province_run.sh`, `province_clean.sh`, `province_progress.sh`) landed alongside hot patches to `trifecta_provincial.sh` (M1 reverse-forward tunnel, M4 idempotent inline-tunnel, LPT host_speeds-weighted fallback, HOST_SPEEDS recalibration to time-multiplier semantics). 12 distinct gotchas captured in `findings.md` (M1 ssh key passphrase, `pkill -f Rscript` missing the R subprocess, RDS-cache-skip, stale cypher snapshots, cross-host TZ-glob hell, M4 PG over-tuning, etc.). Final deliverable: 217-WSG BC stream network model in M4 `fresh` schema; 91 UNEXPLAINED rows at |diff_pct|>=2% remain as investigation queue.

Closed by: PR #171, released as v0.36.1 (tag 91f2544).

Follow-up issues: link#167 (tunnel autossh), link#168 (decouple compare), link#169 (simplify lnk_persist_init), link#170 (S3 consolidate), rtj#145 (clean cypher snapshot), fresh#199 reopened (M4 PG over-tuning), link#172 (rename + autonomous wrapper — next).

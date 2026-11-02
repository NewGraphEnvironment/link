# hosts_ready_439 — fresh pin and primitives on the minimal run's hosts (#439)

**2026-11-02.** The two persistent hosts of #441's run, m4 (dispatcher) and m1 (worker), on fresh 0.52.0 with
primitives loaded the same day.

| | m4 | m1 |
|---|---|---|
| fresh | 0.52.0, `RemoteSha 245c8d8d` = `v0.52.0^{commit}`; reinstalled from the tag by pak (#441's Phase 0) | 0.52.0, `245c8d8d`; `remotes::install_github()` with no token, because m1's GitHub token is refused (HTTP 401) and pak reads it from the git credential store |
| primitives | `snapshot_bcfp.sh --with-bcfp-views --force`, 2026-11-02 09:40 to 09:44 UTC (`snapshot_m4.log`) | the same, 09:42 to 09:44 UTC, under `bash -lc` from a worktree at `34c4c598` (`snapshot_m1.log`) |
| ledger row | `snapshot-20261102`, `v0.7.15-51-g3bd2824` | the same (copied into `../bcfp_baselines.csv` from the m1 worktree) |

- **Both hosts loaded the same object versions** (`load_stamps.csv`: `bcfishobs.observations` and
  `fresh.modelled_stream_crossings` carry the same `version_id` on both; PSCIS and CABD are API loads with no version).
- **S3's `log.json` names the same build as both ledger rows** (`s3_log.json`: `v0.7.15-51-g3bd2824`, completed
  2026-10-28T04:44:44Z). Cloud hosts snapshot whatever S3 holds at prep, so compare `log.json` again just before the
  launch; `verify_extra.sql` check 5 fails on a mismatch.
- **m4's pre-flight vintage line passes** (`preflight_m4.log`: oldest primitive 0.0 d, judged by load stamp). The same
  run's other refusals were expected or are not this issue's: the branch was not yet pushed, the pre-run gate has no
  record yet (#441's next phase), and `~/Projects/repo/bcfishobs` holds uncommitted files that are not this work's
  (a modified `planning/active/task_plan.md`, an untracked `duplicates.csv`), which fail the launch until the operator
  clears them.

**Still owed for the run:** the cloud hosts install fresh and snapshot at prep (`--auto-install` and `preflight_hosts`);
m1's `--auto-install` uses pak and fails until its GitHub token is rotated.

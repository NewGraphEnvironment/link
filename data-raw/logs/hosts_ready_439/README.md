# hosts_ready_439 — fresh pin and primitives on the minimal run's hosts (#439)

**2026-11-02.** The two persistent hosts of #441's run, m4 (dispatcher) and m1 (worker), on fresh 0.52.0 with
primitives loaded the same day.

| | m4 | m1 |
|---|---|---|
| fresh | 0.52.0, `RemoteSha 245c8d8d` = `v0.52.0^{commit}`; reinstalled from the tag by pak (#441's Phase 0) | 0.52.0, `245c8d8d` (`m1_fresh_installed.txt`); pak's install failed with HTTP 401 on m1's GitHub credentials, with the token variables cleared too; `m1_fresh_install.R`, `remotes::install_github(auth_token = NULL)`, installed it. Why that call passed is not established. |
| primitives | `snapshot_bcfp.sh --with-bcfp-views --force` from about 09:40 UTC; the four primitive loads 09:42 to 09:44 (`load_stamps.csv`), then the FWA probe, the bcfishpass views and the ledger stamp (`snapshot_m4.log`) | the same from 09:42 UTC, under `bash -lc` from a worktree at `34c4c598` (`snapshot_m1.log`) |
| ledger row | `snapshot-20261102`, `v0.7.15-51-g3bd2824`, stamped 03:01 Vancouver time (10:01 UTC) at the end of the run | the same, stamped 02:52 (09:52 UTC); copied into `../bcfp_baselines.csv` from the m1 worktree |

- **Both hosts loaded the same object versions** (`load_stamps.csv`: `bcfishobs.observations` and
  `fresh.modelled_stream_crossings` carry the same `version_id` on both; PSCIS and CABD are API loads with no version).
- **S3's `log.json` names the same build as both ledger rows** (`s3_log.json`: `v0.7.15-51-g3bd2824`, completed
  2026-10-28T04:44:44Z). Cloud hosts snapshot whatever S3 holds at prep, so compare `log.json` again just before the
  launch. That comparison is the only check before anything is written: `verify_extra.sql` check 5 runs after the
  consolidate and compares only the observations and crossings object versions and row counts across hosts, and the
  driver exports the dispatcher's ledger version to every host, so a new build that changed only the views would pass.
- **m4's pre-flight vintage line passes** (`preflight_m4.log`: oldest primitive 0.0 d, judged by load stamp). The same
  run's other refusals were expected or are not this issue's: the branch was not yet pushed, the pre-run gate has no
  record yet (#441's next phase), and `~/Projects/repo/bcfishobs` holds uncommitted files that are not this work's
  (a modified `planning/active/task_plan.md`, an untracked `duplicates.csv`), which fail the launch until the operator
  clears them.

**Still owed for the run:** the cloud hosts install fresh and snapshot at prep (`--auto-install` and `preflight_hosts`);
m1's `--auto-install` uses pak and fails until its GitHub token is rotated.

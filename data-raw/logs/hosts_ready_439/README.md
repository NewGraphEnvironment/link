# hosts_ready_439 — fresh pin and primitives on the minimal run's hosts (#439)

**2026-11-02.** The two persistent hosts of #441's run, m4 (dispatcher) and m1 (worker), on fresh 0.52.0 with
primitives loaded the same day.

| | m4 | m1 |
|---|---|---|
| fresh | 0.52.0, `RemoteSha 245c8d8d` = `v0.52.0^{commit}`; reinstalled from the tag by pak (#441's Phase 0) | 0.52.0, `245c8d8d` (`m1_fresh_installed.txt`). pak's install failed with HTTP 401 on m1's GitHub credentials, with the token variables cleared too: pak reads the token from the git credential store. `m1_fresh_install.R`, `remotes::install_github(auth_token = NULL)`, installed it: with the token NULL, remotes 2.5.0 sends no `Authorization` header, so the public repo is fetched anonymously. Both outputs are in `m1_fresh_session.txt`, copied from the terminal. |
| primitives | `snapshot_bcfp.sh --with-bcfp-views --force`, first timestamp 09:42:02 UTC (`snapshot_m4.log`); the four primitive loads end 09:43:11 (`load_stamps.csv`); then the FWA probe, the bcfishpass views (`ogr2ogr` prints nothing on success; the ledger note records them) and the ledger stamp | the same, first timestamp 09:42:19 UTC, under `bash -lc` from a worktree at `34c4c598` (`snapshot_m1.log`) |
| ledger row | `snapshot-20261102`, `v0.7.15-51-g3bd2824`, stamped 03:01 Vancouver time (10:01 UTC) at the end of the run | the same, stamped 02:52 (09:52 UTC); copied into `../bcfp_baselines.csv` from the m1 worktree |

- **Both hosts loaded the same object versions** (`load_stamps.csv`: `bcfishobs.observations` and
  `fresh.modelled_stream_crossings` carry the same `version_id` on both; PSCIS and CABD are API loads with no version).
- **S3's `log.json` names the same build as both ledger rows** (`s3_log.json`: `v0.7.15-51-g3bd2824`, completed
  2026-10-28T04:44:44Z). The ledger rows were stamped from it, so this shows only that it has not changed since.
- **What to check just before launch.** Cloud hosts run `snapshot_bcfp.sh` at prep: PSCIS and CABD from live APIs,
  observations and crossings from the bchamp object store (`snapshot_bcfp.sh`, `BCHAMP`), not from `log.json`. So
  HEAD the two bchamp objects and compare their `x-amz-version-id` with `load_stamps.csv` (1790057230537 and
  1793134826715). Nothing checks PSCIS or CABD before the writes. After the run, `verify_extra.sql` check 5 compares the
  observations and crossings versions and every `log_input` table's row count across hosts, PSCIS and CABD included.
- **m4's pre-flight vintage line passes** (`preflight_m4.log`: oldest primitive 0.0 d, judged by load stamp). The same
  run's other refusals were expected or are not this issue's: the branch was not yet pushed, the pre-run gate has no
  record yet (#441's next phase), and `~/Projects/repo/bcfishobs` holds uncommitted files that are not this work's
  (a modified `planning/active/task_plan.md`, an untracked `duplicates.csv`), which fail the launch until the operator
  clears them.

**Still owed for the run:** the cloud hosts install fresh and snapshot at prep (`--auto-install` and `preflight_hosts`);
m1's `--auto-install` uses pak and fails until its GitHub token is rotated.

# Code-check, PR 4 (#439 hosts ready), round 3: an enumeration of the claims

## Checklist read

- code-check.md, `## Mechanisms`: the prose of all fourteen H3s, with table rows skipped: "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", "Verification that reads its own output", "A guard's scope, escape hatches, and remedies", "A fix lands in one of two callers that share a harness", "Restore the bug and prove the guard fires", "A shared working tree, and what generators leave in it", "A wrapper's exit is not the work", "Zero-length, empty, and unset are three different things", "The probe is broken before the world is", "Written data outlives the fix", "Serialization loses meaning silently", "One fact derived twice".
- Other files were read by their index lines only. The diff holds no R, shell or spatial code: it is a README, logs, a CSV ledger and a four-line R record.

## Every claim, with its verdict

The claims come from README.md (at 524a04fd) and the header lines of m1_fresh_session.txt.

| # | Claim | Checked against | Verdict |
|---|---|---|---|
| 1 | 2026-11-02; m4 is the dispatcher and m1 the worker of #441's run; both are persistent hosts | `preflight_m4.log` (`workers: worker1 … persistent`); rounds 1 and 2 | holds |
| 2 | m4 runs fresh 0.52.0, `RemoteSha 245c8d8d` = `v0.52.0^{commit}`, reinstalled from the tag by pak | round 1 (the installed DESCRIPTION, `RemotePkgRef`, the tag); `preflight_m4.log` line 23 (`fresh_sha 245c8d8db60b`) | holds |
| 3 | m1 runs fresh 0.52.0, `245c8d8d` | `m1_fresh_installed.txt` | holds |
| 4 | pak failed with HTTP 401 on m1's credentials, including with the token variables cleared | `m1_fresh_session.txt` lines 2–7 (a hand copy) | holds as a record |
| 5 | "pak reads the token from the git credential store" | pak 0.11.1's `remote()` passes only `PKG_*`, `PATH` and a few other variables to its persistent callr worker. callr's `make_environ()` appends `~/.Renviron` to the worker's `R_ENVIRON_USER`. So `Sys.unsetenv()` in the parent clears nothing the worker reads | **not established** (finding 1) |
| 6 | `m1_fresh_install.R` (`remotes::install_github(auth_token = NULL)`) installed fresh | `m1_fresh_session.txt` line 10 is the format of the script's `cat()`: `INSTALLED 0.52.0 245c8d8d… v0.52.0` | holds |
| 7 | "with the token NULL, remotes 2.5.0 sends no `Authorization` header" | `remotes:::download()` adds the header only when `auth_token` is not NULL; read from remotes 2.5.0 on m4. No file shows m1's remotes version | holds as code; the version is m4's (finding 1, minor) |
| 8 | Both outputs are in `m1_fresh_session.txt`, copied from the terminal | the file | holds |
| 9 | The session header: pak was run twice, once with `Sys.unsetenv` first, and both printed the 401; then the script ran; the `.txt` is a later separate read | the file's own lines; formats are consistent | holds as a hand copy |
| 10 | m4 ran `snapshot_bcfp.sh --with-bcfp-views --force`, with first timestamp 09:42:02 UTC | log line 1 (`--force`); the ledger note (`--with-bcfp-views`); line 41 prints `02:42:02` in local time, which is UTC-7 (tzdata MST) | holds |
| 11 | m4's four primitive loads end at 09:43:11 | `load_stamps.csv`; `provenance.source_artifact` on m4 matches row for row | holds |
| 12 | Then the FWA probe, the views (the ledger note records them) and the stamp | log lines 146–147; `set -euo pipefail` (line 61), so reaching the stamp implies the views loaded | holds |
| 13 | m1 did the same, with first timestamp 09:42:19 UTC (`snapshot_m1.log`) | log (`02:42:19` local) | holds |
| 14 | m1 ran "under `bash -lc` from a worktree at `34c4c598`" (`snapshot_m1.log`) | the log shows neither the shell nor a SHA. It names only `link 0.78.0 (source tree)`. The commit exists, and it is 0.78.0 | the cited file does not support it (finding 3) |
| 15 | Ledger rows `snapshot-20261102`, `v0.7.15-51-g3bd2824`, stamped 03:01 and 02:52 Vancouver time (10:01 and 09:52 UTC) at the end of the run | `bcfp_baselines.csv`. `lnk_baseline_append()` stamps `Sys.time()` in America/Vancouver, which is UTC-7 on that date | holds |
| 16 | The m1 row was copied in from the m1 worktree | the row is present, with `host` m1 | holds |
| 17 | Both hosts loaded the same object versions; PSCIS and CABD are API loads with no version | `load_stamps.csv`; DB `version_id` is NULL for those two | holds |
| 18 | S3's `log.json` names `v0.7.15-51-g3bd2824`, completed 2026-10-28T04:44:44Z, and the rows were stamped from it | `aws s3 cp s3://fresh-bc/bcfishpass/log.json -` is identical to `s3_log.json`; the stamp calls `lnk_bucket_log()`, which reads the same object | holds |
| 19 | Cloud hosts run `snapshot_bcfp.sh` at prep: PSCIS and CABD from live APIs, observations and crossings from bchamp, not from `log.json` | `cypher_prep.sh:259`; `snapshot_bcfp.sh` (`BCHAMP`, bcdata WFS, the CABD API) | holds |
| 20 | HEAD the two bchamp objects and compare their `x-amz-version-id` with 1790057230537 and 1793134826715 | `curl -sI` today returns 1790057230537 and 1793134826715 | holds |
| 21 | Nothing checks PSCIS or CABD before the writes | `preflight_hosts` checks software parity and load-stamp vintage only, which is age, not identity | holds (read as identity) |
| 22 | Check 5 of `verify_extra.sql` compares the observations and crossings versions after the run | `verify_extra.sql:69-80` | holds |
| 23 | Check 5 compares "every `log_input` table's row count across hosts, PSCIS and CABD included" | both row-count blocks filter `table_name NOT LIKE 'whse_basemapping.%'` (`verify_extra.sql:91, 102`), which drops the 8 FWA tables of `.lnk_input_primitives()` | **fails** (finding 2) |
| 24 | m4's pre-flight vintage passes, oldest 0.0 d, judged by load stamp | `preflight_m4.log` line 32 | holds |
| 25 | Other refusals: branch not pushed, no gate record, bcfishobs dirty (`planning/active/task_plan.md` modified, `duplicates.csv` untracked), which fail the launch | log lines 19, 21, 24 and 38; `git ls-remote origin 439-hosts-primitives` is still empty; `git -C ~/Projects/repo/bcfishobs status --short` shows the two paths | holds |
| 26 | Still owed: cloud hosts install fresh and snapshot at prep (`--auto-install`, `preflight_hosts`) | `study_area_run.sh:1486`, the `--auto-install` branch, `cypher_prep.sh` | holds |
| 27 | m1's `--auto-install` uses pak and fails until its GitHub token is rotated | `worker_prep.sh:161` `pak::pkg_install`; which token pak sends is claim 5 | uses pak: holds. Which token to rotate: finding 1 |

Public-repo scan: nothing non-public is new. The `postgres:postgres@localhost` string is the documented local docker default and is already in committed logs, and no token, address or private repo appears.

## Findings

- **[severity: fragile]** data-raw/logs/hosts_ready_439/README.md:8 (and :28): "with the token variables cleared too: pak reads the token from the git credential store". The evidence does not support this, because clearing the variables in the parent session does not reach pak.
  - pak resolves in a persistent callr worker. In pak 0.11.1 on m4, `pak:::remote()` passes the worker only `PKG_*`, `PATH` and a few other variables, never `GITHUB_PAT` or `GITHUB_TOKEN`.
  - The worker is a callr `r_session`. callr's `make_environ()` appends `~/.Renviron` to the child's `R_ENVIRON_USER`, so a `GITHUB_PAT` in m1's `~/.Renviron` is read again in the worker.
  - If the second `pak::pkg_install` ran in the same R session as the first, as the session header suggests, it also reused a worker started before the `Sys.unsetenv()`.
  - So the 401 does not tell the credential store from an env-var token. The inference matters to the owed line ("fails until its GitHub token is rotated"): an operator who rotates the gitcreds entry may leave the refused token in `~/.Renviron`.
  - Fix: say which token is bad only once it is measured (for example, `Sys.getenv("GITHUB_PAT")` inside `pak:::remote(function() Sys.getenv("GITHUB_PAT"))` on m1, or `gitcreds::gitcreds_get()`), or drop the "because" and write "a refused GitHub token".
  - A lesser point in the same cell: "remotes 2.5.0" is the version installed on m4, where the code was read. No file shows m1's remotes version.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (a justification never measured; a causal claim)
- **[severity: fragile]** data-raw/logs/hosts_ready_439/README.md:20: "every `log_input` table's row count across hosts, PSCIS and CABD included". Both of check 5's row-count blocks filter `i.table_name NOT LIKE 'whse_basemapping.%'` (`data-raw/logs/provincial_246/verify_extra.sql:91` and `:102`). The comment above them gives the reason: FWA estimates drift with autovacuum, so they are reported, not asserted.
  - Those blocks therefore leave out 8 of the 12 tables `.lnk_input_primitives()` fingerprints (`R/lnk_log.R:234-243`): every FWA input.
  - Round 2 proposed "the row counts of all four snapshot tables", and the fix widened that into a universal quantifier that the SQL contradicts. This is a defect inside the previous round's fix.
  - Fix: "every snapshot-loaded table's row count (all `log_input` tables outside `whse_basemapping`), PSCIS and CABD included".
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (a quantified claim to execute; a compression that changes its population)
- **[severity: fragile]** data-raw/logs/hosts_ready_439/README.md:9 (m1 cell): "under `bash -lc` from a worktree at `34c4c598` (`snapshot_m1.log`)". The cited log shows neither the shell nor the SHA. It prints only `artifact_record: link 0.78.0 (source tree)`.
  - Commit `34c4c598` exists and is at 0.78.0, so the two are consistent, but that fits any 0.78.0 commit.
  - Every other cell in the row ties its claim to what its file shows, and rounds 1 and 2 removed the same pattern elsewhere: a claim cited to a file whose content came from somewhere else.
  - Fix: either say that the shell and SHA are recorded from the command as run (as `m1_fresh_session.txt` does for its install), or limit the citation to the timestamp.
  - **Rule:** code-check.md "Verification that reads its own output" (a citation whose content came from another source); round 1/2's stand-in pattern

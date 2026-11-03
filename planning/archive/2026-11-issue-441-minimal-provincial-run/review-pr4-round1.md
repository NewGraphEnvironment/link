# Code-check, PR 4 (#439 hosts ready), round 1

## Checklist read

- code-check.md, `## Mechanisms`: the prose of all fourteen H3s (tables skipped): "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", "Verification that reads its own output", "A guard's scope, escape hatches, and remedies", "A fix lands in one of two callers that share a harness", "Restore the bug and prove the guard fires", "A shared working tree, and what generators leave in it", "A wrapper's exit is not the work", "Zero-length, empty, and unset are three different things", "The probe is broken before the world is", "Written data outlives the fix", "Serialization loses meaning silently", "One fact derived twice".
- Others by index line: nothing in the diff is R, shell, or spatial code (a CSV ledger, a README, logs). Considered from the index: code-check-r.md "Postgres row order..." (n/a), code-check.md Security "Secrets in Committed Files" / "Credentials" (applied to the logs).

## Claims in hosts_ready_439/README.md, with verdicts

| # | Claim | Checked against | Verdict |
|---|---|---|---|
| 1 | m4 and m1 are #441's persistent hosts, m4 dispatcher, m1 worker | `preflight_m4.log` (`workers: worker1`), `gh issue view 441` | holds |
| 2 | m4 fresh 0.52.0, RemoteSha 245c8d8d = `v0.52.0^{commit}` | installed DESCRIPTION on m4 (`RemoteSha 245c8d8db60b…`, `RemotePkgRef …@v0.52.0`); `git rev-parse v0.52.0^{commit}` in fresh = same | holds |
| 3 | m4 reinstalled from the tag by pak | `RemotePkgRef` field (pak writes it), Packaged 2026-11-02 00:43 UTC | holds |
| 4 | m1 fresh 0.52.0 at 245c8d8d | no committed file shows m1's fresh (`snapshot_m1.log` names link 0.78.0 only; `preflight_m4.log`'s fresh_sha is the dispatcher's) | unevidenced (finding 2) |
| 5 | m1 used `remotes::install_github()` "with no token, because … pak reads it from the git credential store" | `remotes:::github_pat()` 2.5.0 falls back to `gitcreds_get()` too | reason misleading (finding 2) |
| 6 | m4 snapshot `--with-bcfp-views --force`, 09:40 to 09:44 UTC | log line 1 (`--force`), ledger notes (`--with-bcfp-views`); loads 09:42:15–09:43:11, probe 09:43:29 (DB), crossings_vw_bcfp autoanalyze 09:48:50, ledger stamp 03:01 local = 10:01 UTC | flags hold; span wrong (finding 1) |
| 7 | m1 the same, 09:42 to 09:44 UTC, `bash -lc`, worktree 34c4c598 | log (bcdata from 02:42:19 local), commit exists (version 0.78.0, fresh@v0.52.0 pin); ledger stamp 02:52 local = 09:52 UTC | commit holds; span wrong (finding 1) |
| 8 | ledger rows `snapshot-20261102`, `v0.7.15-51-g3bd2824`, m1 copied from the m1 worktree | `bcfp_baselines.csv` last two rows | holds |
| 9 | Both hosts loaded the same object versions; obs and crossings share `version_id` | `load_stamps.csv`; m4 rows = `provenance.source_artifact` on m4 exactly; m1 rows = `snapshot_m1.log` printout (etag, n_rows also equal) | holds |
| 10 | PSCIS and CABD are API loads with no version | DB `kind = api`, `version_id` NULL | holds |
| 11 | S3 `log.json` names the same build as both rows, completed 2026-10-28T04:44:44Z | `aws s3 cp s3://fresh-bc/bcfishpass/log.json -` byte-identical to `s3_log.json` | holds |
| 12 | Cloud hosts snapshot whatever S3 holds at prep | `study_area_run.sh` prep / `preflight_hosts` | holds |
| 13 | `verify_extra.sql` check 5 fails on a mismatch | `data-raw/logs/provincial_246/verify_extra.sql` check 5 | partly; post-run and objects only (finding 3) |
| 14 | m4 pre-flight vintage passes, oldest 0.0 d, judged by load stamp | `preflight_m4.log` lines 30–31 (`load stamp: 4`) | holds |
| 15 | Other refusals: branch not pushed, no gate record, bcfishobs dirty with modified `planning/active/task_plan.md` and untracked `duplicates.csv` | the three `✗` lines are exactly these; `git -C ~/Projects/repo/bcfishobs status --short` today shows the same two paths | holds |
| 16 | Owed: cloud hosts install fresh and snapshot at prep (`--auto-install`, `preflight_hosts`) | `study_area_run.sh:1486` `preflight_hosts`, `--auto-install` branch | holds |
| 17 | m1's `--auto-install` uses pak | `worker_prep.sh:161` `pak::pkg_install` | holds |

Ledger rows: 8 fields each (33 rows, all 8 fields), header unchanged, LF, trailing newline; `lnk_baseline_read()` reads the file; `.lnk_bcfp_log_ledger()` returns `v0.7.15-51-g3bd2824` for both `LNK_HOST_ALIAS=m4` and `m1`; `lnk_baseline_current(host = "m1")` is TRUE at that version. `run_started_pdt`: Vancouver is UTC-7 on 2026-11-02 (tzdata prints MST), the same offset as PDT, so lexical ordering stays chronological.

Public-repo scan: no tokens, keys or addresses; `preflight_m4.log` says it redacted host addresses. The `postgresql://postgres:postgres@localhost:5432/fwapg` string in the snapshot logs is the documented local docker default and already sits in 23 committed logs on `origin/main`, so it is not a new disclosure.

## Findings

- **[severity: fragile]** data-raw/logs/hosts_ready_439/README.md:10 — The "primitives" row gives the snapshot spans as 09:40 to 09:44 UTC (m4) and 09:42 to 09:44 UTC (m1). Those are the four primitive loads only. `snapshot_bcfp.sh` keeps going after them: the FWA probe (m4: `recorded_at` 09:43:29 in `provenance.source_artifact`), then step 5's `--with-bcfp-views` ogr2ogr of `crossings_vw` and `streams_vw` (m4's `fresh.crossings_vw_bcfp` autoanalyzed at 09:48:50), and then the ledger stamp. The ledger rows this PR adds record that stamp: 03:01 (m4) and 02:52 (m1) Vancouver time, which is 10:01 and 09:52 UTC. A reader who compares the README with `bcfp_baselines.csv` finds a `run_started_pdt` 8 to 17 minutes after the run's stated end. The command also loaded the bcfp parity views (the reference `fresh.streams_vw_bcfp`), and they fall outside the stated window. Either give the command's span (to 10:01 / 09:52 UTC) or label the window as the primitive loads, and say that the ledger time is written at the stamp, not at the start. That stamp-time behaviour comes from `lnk_baseline_append()` and is pre-existing, so it is out of scope here; the column's name makes the disagreement read as an error.
  - **Rule:** code-check.md "One fact derived twice"

- **[severity: fragile]** data-raw/logs/hosts_ready_439/README.md:8 — Nothing in the record shows m1's fresh. `snapshot_m1.log` names link 0.78.0 only, and the `fresh_sha 245c8d8db60b` in `preflight_m4.log` belongs to the dispatcher. So "0.52.0, `245c8d8d`" for m1 is stated without evidence, while every other cell has a file behind it. The reason given for the route is also misleading. "`remotes::install_github()` with no token, because … pak reads it from the git credential store" implies that remotes does not read it. `remotes:::github_pat()` (2.5.0, on m4) falls back to `gitcreds_get()` when `GITHUB_PAT` and `GITHUB_TOKEN` are unset. A plain `remotes::install_github("NewGraphEnvironment/fresh@v0.52.0")` would therefore send the same refused token. It worked only if the token was suppressed explicitly (for example `auth_token = NULL`, or an empty `GITHUB_PAT`). Record the exact call, and add m1's `packageDescription("fresh")` `RemoteSha` line (or `worker_prep.sh`'s `=== link … ; fresh …` line) as a file.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **[severity: fragile]** data-raw/logs/hosts_ready_439/README.md:17-19 — "Cloud hosts snapshot whatever S3 holds at prep … `verify_extra.sql` check 5 fails on a mismatch" offers check 5 as the backstop for a newer S3 build. Check 5 (`data-raw/logs/provincial_246/verify_extra.sql:69-80`) compares `log_input.artifact_version_id` for `bcfishobs.observations` and `fresh.modelled_stream_crossings`, plus `row_count`, across the run's hosts. It runs after consolidate, so after the spend and the writes. It never reads `log.json` or `bcfp_model_version`, and it does not cover `fresh.streams_vw_bcfp` / `crossings_vw_bcfp`. Meanwhile `study_area_run.sh:1220-1229` exports the dispatcher's ledger version to every host, so a cloud host that loaded a newer build still logs `v0.7.15-51-g3bd2824`. A build that changed only the views, or `log.json`, passes check 5 silently. One that republished the crossings object is caught, but only after the run. The pre-launch `log.json` comparison the same sentence asks for is therefore the only pre-write guard, and the README should say so rather than present check 5 as one.
  - **Rule:** code-check.md "A guard that fails toward pass" (a check that exists only in the post-write verifier refuses after the write it should have prevented)

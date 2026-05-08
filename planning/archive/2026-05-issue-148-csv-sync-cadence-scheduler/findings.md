# Findings — csv-sync cadence shift + weekly snapshot scheduler templates (#148)

## Issue context

## Problem

Two-part Wednesday-morning sync gap. After `NewGraphEnvironment/db_newgraph#6` shifts the upstream CSV dump to Wed 3 AM PDT, link side needs to follow:

1. **csv-sync cadence shift.** `.github/workflows/sync-bcfishpass-csvs.yml` is `0 13 * * WED` (Wed 6 AM PDT / 13:00 UTC). Should be `0 11 * * WED` (Wed 4 AM PDT / 11:00 UTC) — 1 hour after the upstream dump.
2. **No scheduler for `data-raw/snapshot_bcfp.sh`.** The script is portable and stamps `bcfp_baselines.csv` per run, but installation is ad-hoc — every host (M4, M1, cypher) currently relies on the user running it manually. For weekly tunnel-parity work to survive without babysitting, we need install-able scheduler entries.

## Codebase notes (from plan-mode exploration 2026-05-08)

- `.github/workflows/sync-bcfishpass-csvs.yml` — invokes `Rscript data-raw/sync_bcfishpass_csvs.R`. PR-merge handling: `gh pr merge "$PR_URL" --merge --delete-branch` (no `--auto` due to no branch protection). Shape drift halts with exit 2 + labels PR `schema-drift`. Outputs `/tmp/sync_drift_kind` + `/tmp/sync_summary.md`.
- `data-raw/snapshot_bcfp.sh` — derives `DATABASE_URL` from `PG*` env vars if not set directly. Already accepts `--with-bcfp-views` flag. No SHA-skip guard currently. Stamps ledger via `Rscript -e "..."` block at end calling `link::lnk_baseline_append(link::lnk_bucket_log(), run_label = ..., notes = ...)`.
- `R/lnk_bucket_log.R` — exports `lnk_bucket_log()` returning a list `{model_version, date_completed, head_sha}`. `head_sha` is the full 40-char SHA; `model_version` is `git describe`-style (e.g. `v0.7.14-125-g6e9cf1c`).
- `R/lnk_baseline_read.R` — exports `lnk_baseline_read(path = "data-raw/logs/bcfp_baselines.csv")` returning a tibble. Schema (`cols_baseline`): `run_started_pdt, host, run_label, link_schema, bcfp_model_run_id, bcfp_model_version, bcfp_date_completed, notes` (all character).
- `R/lnk_baseline_append.R` — exports `lnk_baseline_append(log, run_label, link_schema = "n/a", notes = "", path = "...")`. Returns the path invisibly.
- `data-raw/logs/bcfp_baselines.csv` — exists, has rows including `2026-05-07 16:10,runnervmeorf1,csv-sync-20260507,n/a,,v0.7.14-125-g6e9cf1c,2026-05-06T04:15:41Z,auto-append by csv-sync; head_sha=6e9cf1c`. The `bcfp_model_version` column is the comparable identifier across rows.
- `data-raw/scheduler/` — does NOT exist yet; new directory per this issue.

## Proposed changes (from issue body)

### Part 1 — csv-sync cron shift

- One-line: `cron: '0 13 * * WED'` → `cron: '0 11 * * WED'`.
- README note explaining the chain (upstream dump 10:00 UTC → csv-sync 11:00 UTC → host snapshot 12:00 UTC).

### Part 2 — `data-raw/scheduler/` templates

- `com.newgraph.snapshot-bcfp.plist` (macOS launchd, M4 + M1)
- `snapshot-bcfp.cron` (Linux crontab line, cypher)
- `README.md` (which host installs which + commands)

Both fire Wed 5:00 AM PDT (12:00 UTC) local time. macOS launchd's `StartCalendarInterval` operates in local time; cron uses UTC by default on cypher's existing setup so the crontab is `0 12 * * WED`.

Both invoke `bash data-raw/snapshot_bcfp.sh` with the host-specific `DATABASE_URL` from a per-host env file (`~/.config/snapshot-bcfp.env`). README documents the env file format.

Output goes to a per-host log directory (`~/.local/state/snapshot-bcfp/$(date +%Y-%m-%d).log`).

`bcfp_baselines.csv` ledger stamping continues to work via the existing `lnk_bucket_log()` + `lnk_baseline_append()` path inside the script.

### Part 3 — script hardening

- Exit 0 with a warning if `lnk_bucket_log()` returns a SHA matching the most-recent `bcfp_baselines.csv` row (skip redundant snapshot). **Per-host scoping decision (this PR):** the most-recent row should be filtered by host hostname so M4 stamping doesn't prevent M1 from snapshotting its own fwapg.
- Optional `--with-bcfp-views` flag continues to load Simon's `crossings_vw` / `streams_vw` from `s3://newgraph/` for parity comparison.

## Acceptance

- csv-sync workflow shifted; tested by a `workflow_dispatch` against the existing s3 bucket.
- launchd plist template + crontab line both work end-to-end on M4 (smoke-tested by running once manually).
- README documents per-host install + uninstall commands.
- `bcfp_baselines.csv` ledger gets one new row per scheduled fire on each host (verified after one Wednesday cycle).

## Cross-references

- Upstream dependency: `NewGraphEnvironment/db_newgraph#7` (cadence shift to Wed 3 AM PDT) — merged 0bec7be 2026-05-08.
- Fork-pattern context: `NewGraphEnvironment/db_newgraph#8` (newgraph as default branch) — closed 2026-05-08.

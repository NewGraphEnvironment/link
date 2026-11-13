# Task: Backlog move 6: What a run stamps and checks before launch, and how primitives load (#474)

**If we do it:** each stamp describes something the run read, one rule picks the bcfishpass reference build, the pre-run gate finds its own history, hosts install the fresh `DESCRIPTION` pins, and primitive loads fall back and record what they loaded. **If we never do:** every launch needs a clean bcfishobs clone for a number nothing reads, and a stale primitive can pass the vintage gate.

## Decided at the gate (operator, 2026-11-12)

- **#451:** retire `bcfishobs_sha`.
  - New rows write NULL. The column stays, so no persist schema changes shape.
  - The observations' identity is `log_input.artifact_version_id`.
- **#266/#446:** add `bcfp_date_completed` to `log` and `log_recompute` as the bcfp build's run identity, beside `bcfp_model_version`.
- **#450:** per-group build minutes go in a committed CSV, `data-raw/logs/build_minutes.csv`.
- **#269:** keep the `Remotes:` tag pins. `update_hosts.sh` installs the tag that `DESCRIPTION` names.
- **Defaults I took** (each can be overruled at review):
  - #458: `log` keeps history by design (#354), and RUNBOOK says readers key on `run_uid`.
  - #450: a group with no minutes row anywhere gets a fixed 60 min bound.
  - #270: the wrapper is tested on a captured trace; its first real run is at the next FWA reload (owed).
  - The batch 9 proof reload runs on m1 (this host).

## Found in exploration (shapes the phases)

- **flooded no longer reads `bcfishpass.log`** (flooded#87 replaced it with `fresh_default.log` fields). So #266 becomes: fix link's one rule and document it in RUNBOOK. There is no second reader to reconcile.
- **The snapshot skip guard repeats #446's defect.** `lnk_baseline_current()` (`R/lnk_baseline_current.R`) takes the newest ledger row of any kind (m1's `csv-sync-20261031` row qualifies). It also keys on `nodename`, while the writer uses `.lnk_host()` (`LNK_HOST_ALIAS`), so on an aliased host it never matches.
- **The ledger rows can already be told apart.** The run label starts `snapshot-` or `csv-sync-`, and notes contain `--with-bcfp-views` when the views were loaded (`R/lnk_baseline_append.R`, `data-raw/sync_bcfishpass_csvs.R:317`). No new ledger column is needed.
- **A cross-host artifact check already exists, unwired:** check 5 of `data-raw/logs/provincial_246/verify_extra.sql` (observations and crossings version ids agree across hosts; row counts agree). It becomes the source for #451's verify check and #276's pre-spend check.
- **The gate already has the pieces #450 needs:**
  - `pretest_config_chain()` (`data-raw/pretest.R:78`) walks `extends:`.
  - `pretest_history_source()` decides where history comes from.
  - `PRETEST_SPECIAL` and `pretest_inputs()` decide which inputs are hit.
  - `speeds_state_read()`, `host_class()` and `weights_normalize()` (`data-raw/study_area_packing.R`) scale minutes by host.
  - Today a config with no history is refused outright (`pretest_pick.R:85-89`).
- **PSCIS assessment is 19,905 features,** above the BC WFS's 10,000 cap on an unpaged `GetFeature` (which still answers HTTP 200). So #459's WFS fallback must page, and #484's row check must compare with `numberMatched`, not just test for more than 0.
- **`.lnk_artifact_head()`** (`R/lnk_artifact.R:116`) already HEADs an object and never errors. #273 and #270 reuse it.
- **No test exists for `snapshot_bcfp.sh`.** The stub-on-PATH pattern is `tests/testthat/test-worker_prep.R` and `helper-study_area_hosts.R`.

## Plan review folded in (2026-11-12, `review-plan.md`)

Corrections taken, each reflected in the phases below:
- **#266:** `bcfp_date_completed` goes on `log` only. `log_recompute` carries no bcfp pin at all (G2), so the gate's "log and log_recompute" was written on a wrong assumption. Reported in the PR.
- **#450:**
  - With no history there is no diff: the inputs are every query in `data-raw/pretest/`, `since_sha = until_sha`, and a new `range_source` column (`own | ancestor | every_input`) on `log_pretest` (B2).
  - The launch check accepts an `every_input` record explicitly (B3).
  - `pretest_run.sh` reads the resolved source from the pick (B4).
  - Minutes are divided by the gate host's factor, and eligibility stays `modelable`. The fixed bound is 60 min of minutes (so 180 min after ×3), and `--minutes-exclude` stays (G9).
  - A short ancestor history still refuses, as the issue says; RUNBOOK says why (A5).
- **#459/#484:**
  - The WFS fallback matches bc2pg's table shape (`geom`, MultiPoint, `EPSG:3005`, paging sorted on the primary key), and `source_artifact.notes` names the path taken (B5).
  - The row check refuses zero and re-queries `numberMatched` once on a mismatch.
  - The fallback triggers when bc2pg's attempts are spent (A4).
- **#276:**
  - The compare fetches each host's rows over `remote_run` as plain SQL, covers the four snapshot tables only, and cannot be downgraded by a note (G5).
  - `preflight_local()` refuses before the spin when cloud hosts are in the run and the dispatcher has not loaded in this dispatch (G6).
  - The guard requires a views row under `--with-bcfp-views` (G4).
  - `snapshot_bcfp.sh` loads link from the source tree, like `artifact_record.R` (O2).
  - verify (SQL over `log_input`) and the pre-flight (R over `source_artifact`) stay two implementations of one rule, with tests of both against the same states (O1).
- **#273:** the etag rule covers the object tables in the vintage set (observations and crossings), from loader rows only. FWA joins once #270's loader rows exist; that is said in the message and in RUNBOOK (G3).
- **#270:** the wrapper maps each traced URL to its dictionary table, drops the rest (kept in the log), records through `lnk_artifact_record(recorded_by = "loader")`, and flags a URL whose `Last-Modified` is later than the load's start (B1, A3). #270 stays open until a real run.
- **#269:** fresh is installed at its pin. link keeps its current source (main's head), since nothing pins it. On the pak path the env pins are removed from `~/.Renviron`. wet's pin is read for the record only (G7, S1). `--dry-run` prints the resolved tag, sha and per-host command (AC5).
- **Proof:**
  - Phase 10 forces each fallback on m1 and compares `n_rows`, columns and geometry with the primary path (AC1).
  - The Phase 7 comparator runs on real m1 and m4 rows (AC3).
  - `pretest_run.sh --pick-only` runs for `default_minimal` with no flags, and for a parentless bundle on an empty schema (AC4).
  - The live etag test also skips when offline (AC6).
- **Already true:** `parity_0.78.0/README.md` names `-50-g620dbe4` (G11). A1, A2 and A7 confirm the plan.

## Phase 1 (#451): retire the bcfishobs checkout stamp
- [x] Remove the dirty-checkout gate and the `BCFISHOBS_GIT_SHA` export.
  - Driver pre-flight: `data-raw/study_area_run.sh:1102-1130`, plus the stamp ssh at `:1427`.
  - `data-raw/study_area_remote.sh`: `REMOTE_LEG_VARS` and the leg export.
  - `data-raw/worker_prep.sh`: its refused-pin list.
- [x] `.lnk_bcfishobs_sha()` and `lnk_stamp()`'s `bcfishobs_sha` slot return NA. DDL unchanged.
- [x] Doc fixes:
  - `lnk_stamp()`: the field is retired, and the identity is `log_input.artifact_*`.
  - `man/`.
  - RUNBOOK §6b, and the §8d pre-flight lines.
- [x] `data-raw/study_area_verify.sql`:
  - Drop `bcfishobs_sha` from the NULL and agreement checks.
  - Add check 5's logic over `log_input` for the run: the observations and crossings version ids are non-NULL and agree across hosts, and the snapshot tables' row counts agree.
  - Update `data-raw/study_area_verify_negative.sh` to match (null or diverge an artifact version, expect FAIL).
- [x] Tests: `test-lnk_log.R`, `test-lnk_stamp.R`, `test-study_area_remote.R`, `test-worker_prep.R`.

## Phase 2 (#446, #266): one rule for the bcfp reference build, with a run identity
- [x] Ledger tier: `.lnk_bcfp_log_ledger()` (`R/lnk_log.R:1281`) reads only rows that loaded the views. That means the run label matches `^snapshot-` and the notes contain `--with-bcfp-views`. It returns `bcfp_date_completed` too.
- [x] db tier: `WHERE model_type = 'LINEAR' ORDER BY date_completed DESC, model_run_id DESC LIMIT 1`, returning `date_completed`. Probe bcfishpass.log's columns on the tunnel before committing the SQL; if `model_type` is absent there, record that and keep the sort only.
- [x] Env tier: an optional `LNK_BCFP_DATE_COMPLETED`.
- [x] New column `bcfp_date_completed` (timestamptz) on `log` only (G2), added through the existing `ADD COLUMN IF NOT EXISTS` path and written in `.lnk_log_run_start()`.
- [x] The driver's pin read (`study_area_run.sh:1209-1242`) uses the same function and exports both values. `LNK_BCFP_DATE_COMPLETED` crosses ssh (`REMOTE_LEG_VARS`, the leg export, a whole-value regex) (G1). Also fix the contradictory "a cypher has no row of its own" comments.
- [x] Tests:
  - a csv-sync row newer than a snapshot row;
  - a snapshot row without views newer than one with views;
  - the date is carried into `log`.
- [x] RUNBOOK §6c, "The bcfp reference pin": state the rule, say `model_version` is a code identity, and say `log.json` carries no `model_type` (G10). `data-raw/logs/parity_0.78.0/README.md` names the right version for #440's run (`v0.7.15-50-g620dbe4`); the 17 rows stay as written.

## Phase 3 (#458): say how `log` keeps history
- [x] RUNBOOK §6b's `log` row and the §6c reader guidance:
  - `log` and `log_recompute` both accumulate across runs (consolidate keeps history, #354). Measured: nothing clears `log_recompute`; `fresh_default`'s asymmetry is #454's hand-seeded `log`, not a clearing rule (the issue's premise corrected).
  - Readers take a build as the `log` rows of one `run_uid` (`lnk_log_read(run_uid =)`), never every row.
  - Bring §6b's column list up to date (`run_uid`, `bcfp_pin_source`, `bcfp_date_completed`, the tokens).

## Phase 4 (#450): the gate finds its history with no flags or copies
- [x] `data-raw/logs/build_minutes.csv`:
  - Columns: `wsg, config, run_uid, host, host_class, link_sha, fresh_sha, date_start, minutes`.
  - Its columns documented in `build_minutes_append.R`'s header and RUNBOOK §8d (`data-raw/logs/` has no dictionary family; the gate's reader validates the columns).
  - Seeded from the 2026-11-03 `default` run and the 2026-11-02 `default_minimal` run. Their minutes are read from m1's or m4's `log` by a committed query, not retyped.
  - `data-raw/build_minutes_append.R --schema= --run-uid=` appends a run.
  - `study_area_run.sh`'s summary prints the append command, as it does for the calibrator.
- [x] **Range, when the bundle has no run of its own:**
  - With an ancestor: the nearest ancestor with history on this database, found through `pretest_config_chain()` with no flags. The flags stay as overrides, and the record names the source.
  - With no ancestor, or none with history here: every query input counts as changed, giving two picks per input over the groups the config models. The range starts at the bundle's first commit (record `since` = none, reason "no history: every input").
- [x] **Minutes:**
  - A group's own local `log` row wins when it is newer. Otherwise use the CSV row for the same config or its nearest ancestor, scaled by `speeds_state_read()` and `weights_normalize()`. Otherwise use the fixed 60 min bound.
  - Picks no longer require a group to have local history: `pretest_pick()`'s `v$wsg %in% history$wsg` reads the minutes table.
- [x] `pretest_check.R` at launch resolves the history source by the same rule. A short history under a parent is still refused, as now.
- [x] `pretest_verdict.R` records the source used (ancestor, csv, or every-input).
- [x] Tests in `test-pretest.R`:
  - a bundle with no runs whose parent has history gates without flags;
  - a parentless bundle picks on every input;
  - a group missing from the CSV gets 60 min;
  - a short borrowed history is still refused;
  - a local row newer than the CSV wins.
- [x] RUNBOOK §8d, "The pre-run gate": update.

## Phase 5 (#269): `update_hosts.sh` installs what `DESCRIPTION` pins
- [x] Read fresh's ref from `DESCRIPTION`'s `Remotes:` (and wet's, which is pinned too). Resolve the tag to a commit for the record, and refuse a package with no pin rather than fall back to main.
- [x] Install with pak (`NewGraphEnvironment/fresh@<tag>`), which sets `RemoteSha` so the pin check has something to compare with. Keep the tarball path only for hosts where pak fails (pak#658), behind a flag, and then write the env pin with the tag's sha.
- [x] Detect the local host (`hostname -s` or `LNK_HOST_ALIAS`) instead of assuming m4. Do not ssh to yourself.
- [x] Test with stubs (`curl`, `ssh`, `Rscript` on PATH), in the style of `test-worker_prep.R`:
  - reads the tag;
  - refuses with no pin;
  - local host detected;
  - parses under `/bin/bash` 3.2.
- [x] RUNBOOK §8d's host-prep lines.

## Phase 6 (#484, #459): `snapshot_bcfp.sh` loads that survive a flicker and an old GDAL
- [ ] `data-raw/snapshot_bcfp_lib.sh`, sourced by the script:
  - `bc2pg_retry <tbl>`: drop, `bcdata bc2pg` inside an `if`, count rows, and compare with the WFS `numberMatched` where it can be read.
    - A non-zero exit or zero rows fails the attempt.
    - `SNAPSHOT_BCFP_BC2PG_ATTEMPTS` (3) and `_BACKOFF` (30 s × attempt).
    - Ends in `FATAL: bc2pg <tbl>: <n> attempts, last: <status>`, and logs which attempt succeeded.
  - WFS fallback for PSCIS, when bcdata cannot reach the catalogue: curl `GetFeature` paged with `startIndex`/`count`, JSON, then `ogr2ogr`. The same row check (against `numberMatched`) covers both paths.
  - Every `--config KEY=VALUE` becomes `--config KEY VALUE` (CABD, modelled crossings, observations, bcfp views).
  - Parquet fallback when `ogr2ogr --formats` lacks Parquet: download the version-pinned object to a tempfile, then read it with pyarrow's `ParquetFile.read` (the duplicate `observation_key` column) from an isolated `uv` environment, never a shared Python, and load it into the existing explicit `CREATE TABLE`. The script refuses with a clear message where neither path is available.
  - Bash 3.2 safe: no `mapfile`, no `${,,}`, no empty arrays under `set -u`.
- [ ] Tests (stub `bcdata`, `psql`, `curl`, `ogr2ogr` on PATH), shown red against the current loop first:
  - fails once, then succeeds;
  - exits 0 with 0 rows, then loads;
  - every attempt fails;
  - every attempt gives 0 rows;
  - first attempt succeeds (one call, no sleep);
  - WFS paging assembles more than 10,000 rows;
  - the `--config` form;
  - the Parquet fallback is chosen when the driver is absent.
- [ ] The PR notes that steps 2-5 (CABD and the object fetches) get no retry.

## Phase 7 (#276): one freshness decision, judged before spend
- [ ] `lnk_baseline_current()`:
  - reads only `snapshot-` rows;
  - keys on `.lnk_host()`;
  - compares `bcfp_date_completed` as well as `model_version`, so a same-version newer build is a miss.
- [ ] `preflight_hosts()`, after prep and before any write:
  - compares each remote host's `provenance.source_artifact` loader rows with the dispatcher's (version id for objects; `content_md5`, then `n_rows`, for the API kinds);
  - fails loud on a difference, naming the table and the hosts;
  - takes check 5's logic as the source of truth, now in `R/` (`lnk_preflight_inputs()`, or beside `lnk_preflight_vintage()`) so verify and pre-flight share it.
- [ ] Tests:
  - a host current by version but behind by date does not skip;
  - a csv-sync row does not skip a snapshot;
  - an aliased host matches;
  - two hosts with different observation versions fail pre-flight;
  - identical hosts pass.

## Phase 8 (#273): the vintage gate asks whether the source changed
- [ ] `lnk_preflight_vintage()`:
  - For an object-kind primitive with a recorded `etag`, HEAD now through `.lnk_artifact_head()`. A different etag is stale whatever the age; the same etag is current whatever the age.
  - A failed HEAD is unknown and falls back to age, never "unchanged".
  - API kinds (CABD, PSCIS) stay on the age rule.
  - `judged_by` gains `etag`, and the message names the predicate per table.
- [ ] Tests with injected HEAD results (each known answer), plus one live test against the real bchamp bucket: a recorded etag equal to the live one reads current, and a deliberately wrong etag reads stale. That live test skips on CI.
- [ ] RUNBOOK §8d's vintage lines.

## Phase 9 (#270): fwapg loads record what they fetched
- [ ] `data-raw/fwapg_load_capture.sh <fwapg checkout>`:
  - runs `load.sh` with stderr teed to a dated log;
  - extracts the distinct object-store URLs, in order;
  - HEADs each one and writes `loader` rows through `lnk_artifact_record()` (via `artifact_record.R`), with the fwapg checkout's commit in `notes` (`fwapg_commit=<sha>`).
  - A loader row replaces the probe row by the existing upsert rule.
- [ ] Unit test on a captured or synthetic `set -x` trace (URL extraction, the per-group template, dedupe), with `load.sh` stubbed.
- [ ] RUNBOOK §6b: the FWA loader rows.

## Phase 10: proof, release
- [ ] One primitives reload on m1: `snapshot_bcfp.sh --with-bcfp-views --force` through the new library. Its log shows the four PSCIS views loaded, their counts, and the attempt each took. Then:
  - `artifact_record` read back;
  - `host_vintage.R` passes, judged by etag for the object tables;
  - the new ledger row is read by both the pin and the guard.
- [ ] `study_area_run.sh --preflight-only` on m1 for `default`: the bcfishobs gate is gone, and the pin prints version plus date. The gate's refusal (code changed) is expected, and is reported, not overridden.
- [ ] `devtools::test()`, `devtools::check()`, and `lintr` per file and linter against `origin/main`.
- [ ] NEWS, version 0.81.0, CLAUDE.md status block.

## Owed at the end (reported, done after merge)

- [ ] Re-snapshot every host's primitives before the next provincial run (already owed from #465).
- [ ] The pre-run gate runs again: `R/`, `data-raw/pretest_*` and `study_area_run.sh` changed.
- [ ] #270's wrapper on the next real FWA reload.
- [ ] Rotate the worker host's GitHub token (#269's residue from #439).
- [ ] Append the next provincial run to `build_minutes.csv`.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved:
- Shell and gate changes: stub-on-PATH tests that go red against the current code.
- Pin and guard: ledger fixtures with sync rows and with views-less rows.
- The vintage etag rule: a live test against the real bucket.
- End to end: one primitives reload on m1, plus a `--preflight-only` launch.


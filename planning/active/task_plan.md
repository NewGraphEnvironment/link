# Task: Auto-stamp bcfp baseline in run_provincial_parity.R (#121)

`data-raw/logs/bcfp_baselines.csv` records the bcfp comparison baseline (`model_run_id` + SHA) each link comparison was computed against. The CSV's existing rows are compare-flavoured: `(link_schema, bcfp_model_run_id)` pairs. Currently hand-maintained — the goal is auto-stamping.

Stamping must happen where comparisons actually occur. The trifecta orchestrator (`data-raw/trifecta_provincial.sh`) dispatches builds; it does not compare. Comparison happens one layer down inside `run_provincial_parity.R` (per-WSG via `compare_bcfishpass_wsg()`).

## Phase 1: CSV schema migration

- [x] Add `host` column to `data-raw/logs/bcfp_baselines.csv` between `run_started_pdt` and `run_label`. New header order: `run_started_pdt, host, run_label, link_schema, bcfp_model_run_id, bcfp_model_version, bcfp_date_completed, notes`.
- [x] Backfill the 3 existing rows with `host=m4` (they were single-host M4 runs).
- [x] Commit as a standalone change so the schema migration is reviewable in isolation.

## Phase 2: Stamp helper + invocation in `run_provincial_parity.R`

- [x] Add an inline helper `stamp_bcfp_baseline(config_name, link_schema)` near the top of the script (after args parsed and after the per-WSG-timings CSV setup, before the per-WSG-loop). Single function, same file — no R/ helper, no test file (orchestration scope).
- [x] Helper logic:
  - Open DB conn to `localhost:63333` / `bcfishpass` using `Sys.getenv("PG_USER_SHARE", "newgraph")` and `Sys.getenv("PG_PASS_SHARE")`. Pattern matches `compare_bcfishpass_wsg.R:50–53`.
  - `tryCatch` the entire body — connection failure logs `[bcfp-baseline] WARN: ...` to stderr and returns invisibly. Stamp failure must not block the build.
  - Query: `SELECT model_run_id, model_version, to_char(date_completed, 'YYYY-MM-DD HH24:MI') AS date_completed FROM bcfishpass.log ORDER BY model_run_id DESC LIMIT 1`.
  - Compose row fields:
    - `run_started_pdt` = `format(Sys.time(), "%Y-%m-%d %H:%M")`
    - `host` = `Sys.getenv("LNK_HOST_ALIAS", Sys.info()[["nodename"]])` — env-var override gives clean shorthand (`m4`/`m1`/`cypher`); nodename fallback when unset
    - `run_label` = `if (config_name == "bcfishpass") "provincial_parity" else paste0("provincial_", config_name)`
    - `link_schema` = `cfg$pipeline$schema` (already reflects `--schema=` override applied at lines 42–45)
    - `notes` = `"auto-stamped at run_provincial_parity.R start"`
  - Idempotency: read existing CSV; if any row matches `(host, link_schema, bcfp_model_run_id, run_started_pdt)`, skip append and log a `[bcfp-baseline] skip: already stamped` line.
  - Append row via `write.table(..., append = TRUE, sep = ",", row.names = FALSE, col.names = FALSE, quote = FALSE)` — matches the per-WSG-timings convention at line 103.
  - `cat("[bcfp-baseline] stamped: model_run_id=<N> host=<H> -> <csv-path>\n")`.
- [x] Call the helper between the setup banner and the per-WSG `for (w in wsgs)` loop. Single invocation per run.

## Phase 3: Verification (single-host)

- [x] M4-local smoke: stamp helper produced `model_run_id=120, model_version=v0.7.14-113-ga7373af, date_completed=2026-04-28 23:17, host=MacBook-Pro-2.local` (no `LNK_HOST_ALIAS` env var set during test, so nodename fallback was exercised). Row appended cleanly.
- [x] Idempotency check: second run within the same minute logged `[bcfp-baseline] skip: already stamped (host=MacBook-Pro-2.local link_schema=fresh_default model_run_id=120)`; CSV row count unchanged.
- [x] Tunnel-down sanity: ran with `Rscript --no-environ` (truly unset `PG_PASS_SHARE`), got `[bcfp-baseline] WARN: PG_PASS_SHARE not set, skipping stamp`; CSV unchanged. Build path would proceed unaffected.
- [x] Stamped verification logs under `data-raw/logs/20260505_0545_link121_verification.txt` and `data-raw/logs/20260505_0546_link121_verification_tunneldown.txt`.
- Trifecta verification (3 hosts, one row each) deferred to the next provincial run when M1 docker CLI is updated and cypher is back on tailscale.

## Phase 4: Release

- [x] `NEWS.md` 0.29.1 entry covering the auto-stamp + `host`-column migration.
- [x] `DESCRIPTION` 0.29.0 → 0.29.1 (patch bump — orchestration-tooling change, no public R API touched).
- [ ] PR body: "Closes #121". SRED ref goes in PR body only (not in issue body).
- [ ] `/planning-archive` on PR merge.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

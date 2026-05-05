# Task: Auto-stamp bcfp baseline in run_provincial_parity.R (#121)

`data-raw/logs/bcfp_baselines.csv` records the bcfp comparison baseline (`model_run_id` + SHA) each link comparison was computed against. The CSV's existing rows are compare-flavoured: `(link_schema, bcfp_model_run_id)` pairs. Currently hand-maintained — the goal is auto-stamping.

Stamping must happen where comparisons actually occur. The trifecta orchestrator (`data-raw/trifecta_provincial.sh`) dispatches builds; it does not compare. Comparison happens one layer down inside `run_provincial_parity.R` (per-WSG via `compare_bcfishpass_wsg()`).

## Phase 1: CSV schema migration

- [x] Add `host` column to `data-raw/logs/bcfp_baselines.csv` between `run_started_pdt` and `run_label`. New header order: `run_started_pdt, host, run_label, link_schema, bcfp_model_run_id, bcfp_model_version, bcfp_date_completed, notes`.
- [x] Backfill the 3 existing rows with `host=m4` (they were single-host M4 runs).
- [x] Commit as a standalone change so the schema migration is reviewable in isolation.

## Phase 2: Stamp helper + invocation in `run_provincial_parity.R`

- [ ] Add an inline helper `stamp_bcfp_baseline(cfg, schema_arg)` near the top of the script (after args parsed at lines 36–77, before the per-WSG-loop banner at lines 79–83). Single function, same file — no R/ helper, no test file (orchestration scope).
- [ ] Helper logic:
  - Open DB conn to `localhost:63333` / `bcfishpass` using `Sys.getenv("PG_USER_SHARE", "newgraph")` and `Sys.getenv("PG_PASS_SHARE")`. Pattern matches `compare_bcfishpass_wsg.R:50–53`.
  - `tryCatch` the entire body — connection failure logs `[bcfp-baseline] WARN: ...` to stderr and returns invisibly. Stamp failure must not block the build.
  - Query: `SELECT model_run_id, model_version, date_completed FROM bcfishpass.log ORDER BY model_run_id DESC LIMIT 1`.
  - Compose row fields:
    - `run_started_pdt` = `format(Sys.time(), "%Y-%m-%d %H:%M")`
    - `host` = `Sys.info()[["nodename"]]` (matches the per-WSG-timings CSV's `host_id` pattern at line 92)
    - `run_label` = `if (CONFIG == "bcfishpass") "provincial_parity" else paste0("provincial_", CONFIG)`
    - `link_schema` = the `--schema` value (default `fresh` when bcfishpass bundle, otherwise required)
    - `notes` = `"auto-stamped at run_provincial_parity.R start"`
  - Idempotency: read existing CSV; if any row matches `(host, link_schema, bcfp_model_run_id, run_started_pdt)`, skip append and log a `[bcfp-baseline] skip: already stamped` line.
  - Append row to CSV. Use `data.table::fwrite(..., append = TRUE)` or base `write.table(..., append = TRUE, sep = ",", row.names = FALSE, col.names = FALSE)` — match whichever the existing script already uses for the per-WSG-timings file (line 95) for consistency.
  - `cat("[bcfp-baseline] stamped: model_run_id=<N> host=<H> -> <csv-path>\n")`.
- [ ] Call the helper between the setup banner (line 105) and the per-WSG `for (w in wsgs)` loop (line 107). Single invocation per run.
- [ ] `/code-check` on staged diff.

## Phase 3: Verification (single-host)

- [ ] M4-local smoke: `Rscript run_provincial_parity.R --wsgs=ADMS --config=default --schema=fresh_default`. Confirm one row appended with `host=m4`, `bcfp_model_run_id=120`, `bcfp_model_version=v0.7.14-113-ga7373af` (or whichever build is current at run time).
- [ ] Idempotency check: re-run the same command within the same minute, confirm `[bcfp-baseline] skip: already stamped` and CSV row count unchanged.
- [ ] Tunnel-down sanity: temporarily kill the M4 tunnel, run the same smoke, confirm `[bcfp-baseline] WARN: ...` and that the WSG loop still proceeds (build doesn't block on stamp failure).
- [ ] Stamped verification log under `data-raw/logs/<TS>_link121_verification.txt`.

## Phase 4: Release

- [ ] `NEWS.md` 0.29.1 entry: "Auto-stamp bcfp comparison baseline in `run_provincial_parity.R`; add `host` column to `bcfp_baselines.csv`".
- [ ] `DESCRIPTION` 0.29.0 → 0.29.1 (patch bump — orchestration-tooling change, no public R API touched).
- [ ] PR body: "Closes #121". No SRED tag in issue body; SRED ref goes in PR body only.
- [ ] `/planning-archive` on PR merge.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

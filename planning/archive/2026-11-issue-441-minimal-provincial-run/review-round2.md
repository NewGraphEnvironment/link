## Checklist read

- code-check.md: every H3 under `## Mechanisms` (14), prose without table rows; the 23 other headings by index line only.
- code-check-r.md: "`on.exit()` at a script's top level never fires"; "`$` on a list partial-matches, so a longer sibling key answers for a missing one"; "A database driver's value is not a base R type — and it fails twice"; "`tryCatch()` nests its handlers, so a `stop()` in one is caught by a later one"; "An `information_schema` lookup by the literal table name misses what Postgres resolves"; "Rscript reads a script as it runs, so never edit a script while a run of it is in flight"; about 109 not read.
- code-check-shell.md: "Over Tailscale SSH to a Mac, `ssh` exits 0 whatever the remote command returned"; "A second `trap … EXIT` replaces the first"; "Heredoc precedence in pipelines"; "`if ! cmd; then rc=$?` captures the negation, not the command"; "A failed `git fetch` leaves the comparison you make next reading stale refs"; about 65 not read.
- code-check-spatial.md: no heading names anything this diff uses; 0 read, 94 not read.

## Findings

No bug. Round 1's two fixes hold. Three fragile items, each loud or cosmetic; none lets a wrong run through.

- **[severity: fragile]** data-raw/pretest.R:416-426 and data-raw/pretest_check.R:52-59 — the "cover every group" rule has no working route when the modelled set grows past both histories, and the printed remedy does not fix it.
  `modelable` is read from the presence table at HEAD. Adding a cell to `default` for a group that has none (CHUK, HAYR, KCHL, SAHT and SHEK are not modelable today) makes it 242 while neither the bundle's own builds nor the parent's log holds that group. Reproduced in a temporary worktree with SHEK BT set, on a `default_minimal` schema with its own complete 241 builds and a 241-group history:
  - no flags: `REFUSED: ... does not cover the groups default_minimal models; borrow from a config it extends`
  - with flags: `REFUSED: fresh_default_history.log holds 241 of the 242 groups ... (missing SHEK) ...; load the full history (data-raw/pretest_history_load.sh)`
  - launch check on the record: `does not cover the groups ..., and its gate borrowed no history`, exit 2
  So one added cell discards 241 complete own builds. The named remedy reloads a log that also lacks SHEK, and the first refusal sends the operator to the flags that then refuse. The ways out are to model that group under the parent and reload, or `--pretest-note`; no message or RUNBOOK line says so. The plan for the next run does not re-model `default` first (CLAUDE.md, 2026-11-01 status), and #402's literature PR may add cells. `default`, with no parent, is not affected. It stops loud, so the cost is an operator stuck at launch.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **[severity: fragile]** data-raw/pretest_pick.R:165 and data-raw/pretest_pick.R:201 — two lines still carry the assumption round 1's fix removed, that a borrowing bundle has no rows of its own.
  Line 165 writes `borrowed: it has no builds of its own` into `pretest.md` (the committed evidence). Reproduced false with two own builds in the schema. Line 201 tests `identical(minutes_schema, schema)` where the query's source is now `hist_src`: with `--minutes-schema=<own schema>` while borrowing, the bound silently uses the parent's minutes from `built`, and line 168's header says `last minutes in <own schema>.log`. Reproduced: the header named the own schema, and by the code the values are the parent's; my fixture's rows were copies, so the values could not differ there. Querying instead would not help, because `pretest_history_sql()` filters to `hist_src$config` and finds none there. Only the operator's explicit flag reaches line 201, and the default (`SHAPE_SCHEMA`) is right.
  - **Rule:** none

- **[severity: fragile]** data-raw/pretest_check.R:54 and data-raw/pretest_check.R:59, with data-raw/study_area_run.sh:1203 — two judgements leave on the exit status reserved for a check that could not run.
  A short history and "borrowed no history" are decisions, raised with `stop()`, so they exit 2 (the file's header: "2 when the check itself could not run"), and the driver then prints `(the check itself could not run)` under the reason. That line steers an operator to look for a broken database or checkout. The launch is refused either way, and nothing else branches on 1 against 2. Returning `list(ok = FALSE, why = ...)` keeps the channel honest.
  - **Rule:** none

## Checked and sound

Run in a temporary worktree at `4457654e`, schema `zzrev_rec` (dropped; worktree removed).

- `rbind` in the launch check, on a real pass record against the 241-group copy. `<schema>.log` absent (`own` NULL): exit 0. Log with 2 own rows: exit 0. Log empty (0-row frame): exit 0. A dirty own row: exit 1, "holds a build from a dirty tree". `hist` is used only as `link_sha` and `link_dirty` after the `rbind`, and `hist$wsg` is read before it. Pick's `rbind` with its typed empty frame and with 2 rows: ran through to picks.
- Own builds complete while the newest record borrowed: the check reads own builds, exit 0, and the record's range still holds them; with a `since_sha` after them, exit 1. `--history-*` on a complete own: refused, no flags: picks. Partial own, no flags: refused with `--history-config=default`.
- `default_tuned` (241 groups, schema `fresh_default_tuned`): no own log and no flags is refused with the remedy; borrowing picks. A partial `fresh_default_tuned`, which gated on its own builds before, now needs the flags and a full `default` history. That follows the stated rule; no driver or test depends on it. The new `load_all()` in the check resolves `bcfishpass` (217), `default`, `default_tuned` and `default_minimal` with nothing written to stdout.
- No caller on the old signature (`pretest_history_source`, `pretest_record_history`): grep of `data-raw/`, `R/` and `tests/`. `test-pretest.R` with `NOT_CRAN=true`: 128 expectations, 0 failed, 0 errors, 2 skipped.
- Own schema for a group's minutes or provenance while borrowing: none. Minutes come from the history (`--minutes-schema` aside, above); the verdict reads only `<scratch>.log`; the scratch shape comes from `SHAPE_SCHEMA`, and `--subset` changes only the verdict.
- History-only scratch: `.lnk_log_create_tables()` aligns columns, so an older host's `log` meets current code. Read, not run; no pick has yet been modelled on one.
- `pretest_record_history()` and `pretest_record_check()` pick the newest record by one rule (pass or fail, `run_at` descending), so they cannot read different rows.
- Not reported as a defect: the default `--since` comes from `built` alone, so an own build older than the parent's newest run refuses until `--since=` is passed. It stops before modelling and the message names both SHAs. A history group the child does not model could be picked and would fail the gate, loudly; latent while `default_minimal` and `default_tuned` share `default`'s presence table.
- Branch's new logs: no addresses (`phase0_connections.txt` says it left them out).

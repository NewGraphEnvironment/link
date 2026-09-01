# Task: Provenance gaps that must close before the 217-WSG run (#262)

Before the 217-WSG provincial run (#256 scope, #246 machinery), `fresh.log` has gaps
that **cannot be retrofitted** — a run that lands without them is not labelled, and no
later query recovers what was not recorded.

Four gaps, audited 2026-09-01 against the 34-WSG field run `20260831_232553`, by
querying the table rather than reading the schema:

1. No run-level identifier — `run_id` is per WSG (37 rows, 37 distinct), `run_label`
   NULL on every row.
2. The recompute writes no provenance at all, and its output is what ships.
3. The comparison reference is not pinned in the DB.
4. `link_dirty` is `t` on every dispatcher row and is false (#257).

## Corrections to the issue body — measured, and they change the work

Two of the four gaps are **wired and unfed**, and one names the wrong source.

**`run_label` is fully plumbed.** `lnk_pipeline_run()` already takes
`run_label = Sys.getenv("LNK_RUN_LABEL", NA_character_)` (`R/lnk_pipeline_run.R:115`),
threads it to `.lnk_log_run_start()` (`:147`), which INSERTs it (`R/lnk_log.R:584`).
It is NULL because **nothing ever sets `LNK_RUN_LABEL`**.

**`bcfp_model_version` is not unfilled by missing code.** `.lnk_bcfp_log_current()`
(`R/lnk_log.R:664`) is called at run open (`:570`) and inserted (`:604`). It returns
NULL because local docker fwapg holds **zero** `bcfishpass` tables (measured), and the
run is deliberately tunnel-free. The reference is the local snapshot
`fresh.streams_vw_bcfp`, whose build id is already recorded in
`data-raw/logs/bcfp_baselines.csv` (m1 latest: `v0.7.15-47-ga702229`). Querying the
tunnel at compare time would pin the build the tunnel is at *now*, not the one the
numbers were computed against — a wrong pin, not a missing one.

Gaps 2 and 4 are confirmed as stated.

## Decisions (user-approved, 2026-09-01)

| Decision | Choice |
|---|---|
| Recompute provenance | Own table `<schema>.log_recompute` |
| Dirty predicate | `git status --porcelain -- . ':(exclude)data-raw/logs'` — keep untracked |
| bcfp pin source | Tier 2 on `.lnk_bcfp_log_current()`: DB first, then the local ledger |
| Cross-host id name | `run_uid` |

## Phase 1: `run_uid` + `run_label` end to end

- [ ] `cols_log` gains `run_uid text` (`R/lnk_log.R:160`); `.lnk_log_align_columns()`
      back-fills live schemas via `ADD COLUMN IF NOT EXISTS`
- [ ] Index `log_run_uid` on `log (run_uid)` in `.lnk_log_create_tables()`
- [ ] `.lnk_log_run_start()` gains `run_uid`; `lnk_pipeline_run()` gains
      `run_uid = Sys.getenv("LNK_RUN_UID", NA_character_)`, mirroring `run_label`
- [ ] `lnk_log_read()` gains a `run_uid` filter; with it set, return the **full** set
      regardless of `latest` (`DISTINCT ON` would silently drop re-runs)
- [ ] `study_area_run.sh`: `--run-label=` flag; mint `RUN_UID` once before fan-out;
      echo both in the banner
- [ ] Export `LNK_RUN_UID` / `LNK_RUN_LABEL` on **both legs** — the local loop and
      inside the ssh command string (the `LNK_GUARD_DOWNSTREAM` trap)
- [ ] Tests: run_uid threaded to the INSERT; `lnk_log_read(run_uid=)` returns all rows

## Phase 2: `<schema>.log_recompute`

- [ ] `cols_log_recompute` in `R/lnk_log.R`, carrying `watershed_group_code` so
      `schema_consolidate.R` auto-discovers it
- [ ] Add to `.lnk_log_create_tables()`'s `specs` so `lnk_persist_init()` creates it
- [ ] `.lnk_log_recompute_start()` / `_finish()` / `_fail()` — open loud, rest soft
- [ ] Start path **must not run DDL** — the pool runs at `-j4`+ and
      `CREATE TABLE IF NOT EXISTS` takes AccessExclusiveLock (the #250 convoy). Verify
      presence and `stop()` naming `lnk_persist_init()` as remediation
- [ ] `wsg_recompute_one.R` opens before step 1, finishes after the post-condition
      guard, `on.exit` fail-mark
- [ ] `lnk_log_read()` gains `phase = c("model", "recompute")` selecting the table
- [ ] Tests: recompute row written; absent-table path errors with the remediation

## Phase 3: pin the bcfp reference from the snapshot actually used

- [ ] `.lnk_bcfp_log_current()` tier 2 — latest ledger row for **this host**, reusing
      `lnk_baseline_read()` and `lnk_baseline_current()`'s host/recency rule
- [ ] Path: `LNK_BCFP_BASELINE`, then `data-raw/logs/bcfp_baselines.csv` from cwd
      (both hosts run from the repo root); return NULL on a miss, never error
- [ ] `bcfp_model_run_id` stays NULL on this path and that is correct — `log.json`
      carries none. Do not invent one; state the asymmetry
- [ ] Tests: DB tier wins when present; ledger tier fills version and leaves id NULL;
      missing ledger returns NULL

## Phase 4: #257 — `link_dirty` that means something

- [ ] `.lnk_pkg_git_dirty()` pathspec `c("--", ".", ":(exclude)data-raw/logs")` —
      long form only (`:!` aborts, and an aborted `git status` reads as clean)
- [ ] Keep assign → test exit status → test value; `NA` on failure stays
- [ ] `preflight_local()`'s dirty gate takes the same predicate
- [ ] Tests against a **real temp checkout**, all four known answers: logs-only →
      clean, modified tracked → dirty, new untracked `R/` file → dirty, git fails → `NA`

## Phase 5: verify SQL, parameterized and negative-tested

- [ ] `study_area_verify.sql` keys on `:run_uid`, not a 6-hour window plus a hardcoded
      34-WSG `VALUES` list; derive the expected set from the run's own rows
- [ ] New check: every run WSG has **both** a `log` and a `log_recompute` row, reported
      side by side
- [ ] **Negative-test it** — delete one `log_recompute` row in a transaction, confirm
      red, `ROLLBACK`
- [ ] Keep the host-aware `fresh_sha` verdict (NULL on m1 is correct)

## Phase 6: docs + release

- [ ] `RUNBOOK.md` — run-identity model, `log_recompute`, tunnel-free bcfp pin
- [ ] `CLAUDE.md` status block
- [ ] `NEWS.md` + version bump as the **final** commit

## Validation

- [ ] `devtools::test()`, `devtools::document()`, `lintr::lint_package()` clean
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

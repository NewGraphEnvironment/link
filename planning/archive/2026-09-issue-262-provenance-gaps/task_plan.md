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
| Dirty predicate | exclude `data-raw/logs`, keep untracked. Landed as `-- ':(top,exclude)data-raw/logs'` (repo-root anchored, cwd-independent) |
| bcfp pin source | Tier 2 on `.lnk_bcfp_log_current()`: DB first, then the local ledger |
| Cross-host id name | `run_uid` |

## Phase 1: `run_uid` + `run_label` end to end

- [x] `cols_log` gains `run_uid text` (`R/lnk_log.R:160`); `.lnk_log_align_columns()`
      back-fills live schemas via `ADD COLUMN IF NOT EXISTS`
- [x] Index `log_run_uid` on `log (run_uid)` in `.lnk_log_create_tables()`
- [x] `.lnk_log_run_start()` gains `run_uid`; `lnk_pipeline_run()` gains
      `run_uid = Sys.getenv("LNK_RUN_UID", NA_character_)`, mirroring `run_label`
- [x] `lnk_log_read()` gains a `run_uid` filter; with it set, return the **full** set
      regardless of `latest` (`DISTINCT ON` would silently drop re-runs)
- [x] `study_area_run.sh`: `--run-label=` flag; mint `RUN_UID` once before fan-out;
      echo both in the banner
- [x] Export `LNK_RUN_UID` / `LNK_RUN_LABEL` on **both legs** — the local loop and
      inside the ssh command string (the `LNK_GUARD_DOWNSTREAM` trap)
- [x] Tests: run_uid threaded to the INSERT; `lnk_log_read(run_uid=)` returns all rows

## Phase 2: `<schema>.log_recompute`

- [x] `cols_log_recompute` in `R/lnk_log.R`, carrying `watershed_group_code` so
      `schema_consolidate.R` auto-discovers it
- [x] Add to `.lnk_log_create_tables()`'s `specs` so `lnk_persist_init()` creates it
- [x] `.lnk_log_recompute_start()` / `_finish()` / `_fail()` — open loud, rest soft
- [x] Start path **must not run DDL** — schema DDL belongs at init, not in N
      concurrent jobs. Verify presence and `stop()` naming `lnk_persist_init()`.
      (The #250 lock-convoy analogy was softened in the code comment: that convoy
      was long-held AccessShareLocks on views, which is not this shape, and stating
      the stronger version as fact would teach "never DDL under any pool")
- [x] Driver ensures the log tables **once**, single-threaded, beside
      `barriers_views_build.R` — otherwise a run where every dispatcher WSG
      species-skips never creates the table and hard-stops all N recomputes at the
      end of a paid run
- [x] `LNK_LOG=0` opt-out, set by `recompute_sweep.sh` / `recompute_parity.sh`, so
      benchmark passes cannot satisfy the model-vs-recompute check
- [x] `wsg_recompute_one.R` opens before step 1, finishes after the post-condition
      guard. **Not** an `on.exit` fail-mark as planned: `on.exit()` at an Rscript's
      top level never fires (measured, on both `stop()` and `quit()`), so the work
      runs inside a function and the failure path is explicit
- [x] `lnk_log_read()` gains `phase = c("model", "recompute")` selecting the table
- [x] Tests: recompute row written; absent-table path errors with the remediation

## Phase 3: pin the bcfp reference from the snapshot actually used

- [x] `.lnk_bcfp_log_current()` tier 2 — latest ledger row for **this host** (via
      `.lnk_host()`, not `Sys.info()[["nodename"]]`, which is what
      `lnk_baseline_current()` uses and would filter on the wrong string wherever
      `LNK_HOST_ALIAS` is set — i.e. every host in this fleet)
- [x] Tier 0 `LNK_BCFP_MODEL_VERSION`, resolved once in `preflight_local()` and
      exported on both legs. The ledger is per host and a cypher has no row of its
      own, so without this the majority of a 217-WSG run lands unpinned
- [x] `bcfp_pin_source` column records which tier answered
- [x] Path: `LNK_BCFP_BASELINE`, then `data-raw/logs/bcfp_baselines.csv` from cwd
      (both hosts run from the repo root); return NULL on a miss, never error
- [x] `bcfp_model_run_id` stays NULL on this path and that is correct — `log.json`
      carries none. Do not invent one; state the asymmetry
- [x] Tests: DB tier wins when present; ledger tier fills version and leaves id NULL;
      missing ledger returns NULL

## Phase 4: #257 — `link_dirty` that means something

- [x] `.lnk_pkg_git_dirty()` pathspec — long form only (`:!` aborts, and an aborted
      `git status` reads as clean), anchored with `:(top,...)` so it is
      cwd-independent, and **`shQuote()`d**: `system2()` pastes args on raw, so the
      parens were parsed by the shell and the predicate returned `NA` for every
      input. Caught on the first probe
- [x] `.lnk_git_dirty_at(d)` extracted so the tests can reach a real checkout
- [x] Keep assign → test exit status → test value; `NA` on failure stays
- [x] `preflight_local()`'s dirty gate takes the same predicate
- [x] Tests against a **real temp checkout**, all four known answers: logs-only →
      clean, modified tracked → dirty, new untracked `R/` file → dirty, git fails → `NA`

## Phase 5: verify SQL, parameterized and negative-tested

- [x] `study_area_verify.sql` keys on `-v run_uid=`, not a 6-hour window plus a
      hardcoded 34-WSG `VALUES` list. Per-WSG detail derives from the run's rows;
      the **count** comes from outside via `-v expected_n=`, because deriving the
      expected set entirely from the log is circular — a WSG that never logged
      vanishes from "expected", which is the failure being checked for
- [x] Assertions `RAISE`, so the exit status means something. Parameters reach the
      block via `set_config` — psql does not interpolate `:'var'` inside a
      dollar-quoted string
- [x] Reports attempted vs completed separately (the old window filter excluded
      NULL `date_end`, so its single count silently meant "completed")
- [x] New check: every run WSG has **both** a `log` and a `log_recompute` row, reported
      side by side
- [x] **Negative-test it** — `data-raw/study_area_verify_negative.sh`, against a
      scratch copy rather than a transaction (each `psql -f` is its own session, so
      a transaction could not span the runs). Three cases, healthy first: a script
      that always exits non-zero "detects" everything
- [x] Keep the host-aware `fresh_sha` verdict (NULL on m1 is correct)

## Phase 6: docs + release

- [x] `RUNBOOK.md` — run-identity model, `log_recompute`, tunnel-free bcfp pin
- [x] `CLAUDE.md` status block
- [x] `NEWS.md` + version bump as the **final** commit

## Validation

- [x] `devtools::test()`, `devtools::document()`, `lintr::lint_package()` clean
- [x] `/code-check` — 4 rounds; rounds 1-3 each found real defects in the previous round's fixes; round 4 converged by enumeration
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion

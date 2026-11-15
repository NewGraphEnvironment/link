# Task: Record what a stalled statement is waiting on while it stalls (frs_near_river_walk, four dates) (#487)

Fresh's near-river walk (`CREATE TEMP TABLE pg_temp.frs_near_river_walk AS ...`) sometimes runs for an hour or more where it normally takes a minute or two (OKAN/KTSU 2026-10-23, KHTZ/MAHD 2026-10-25, TAHS 2026-11-13, SANJ 2026-11-14), always on the host whose database takes other heavy work, never on a worker, and each time the backend was cancelled at the statement bound before anyone read `pg_stat_activity`. Record, while the stall is happening, what the stalled backend is doing.

## Context

`frs_near_river_walk` has stalled on the dispatcher on four dates (OKAN/KTSU, KHTZ/MAHD,
TAHS, SANJ) and each time the backend was cancelled at the statement bound before anyone read
`pg_stat_activity`, so the cause (a lock, an I/O or worker wait, or a statement that is simply
working) is unknown. This change makes the next stall leave a time series of what the stalled
backend, its parallel workers and its blockers were doing, so the fix can be filed where it
belongs. Fixing the stall and changing the default bound are out of scope.

What the code gives us (explored on `e5acee31`):
- `data-raw/wsg_run_one.R` connects once (`conn`), prints `statement_timeout=<bound>`, runs
  the `LNK_TEST_STALL_WSG` hook (`SELECT pg_sleep(3600)`), and on a cancel prints
  `[wsg_run_one] <WSG> TIMEOUT after <bound>: <statement>` from `name_timeout()`.
- The local leg's output goes to `$LOG_DIR/${TS}_run_local.log`; each remote leg's arrives over
  ssh in `$LOG_DIR/${TS}_run_<host>.log` (`study_area_remote.sh`, `REMOTE_LEG_VARS`).
- `study_area_finish.sh::run_timeouts()` reads those logs (byte-wise, unanchored) and the
  INCOMPLETE block prints `statement bound hit:` with one line per group.
- No `callr`/`processx` in DESCRIPTION; `system2(wait = FALSE)` inherits stdout.
- Local fwapg is PostgreSQL 17.5, so `pg_stat_activity.leader_pid` and `pg_blocking_pids()` exist.
- `data-raw/pretest_inputs.csv` refuses an unmapped changed file; `wsg_run_one.R` is `any`.

## Decided at the gate

Plan approved by the user 2026-11-14 as presented (mechanism choices proposed by Claude, not objected to).

1. **One sampler process per group**, `data-raw/wsg_stall_sample.R`, started by
   `wsg_run_one.R` with `system2(wait = FALSE)` after it connects, given the group's backend
   pid (`pg_backend_pid()`), its own R pid and the group code. It holds its own connection
   (`SET statement_timeout = '10s'`), checks its parent's pid every few seconds and exits when
   the parent or the backend is gone, so it ends with its group and lingers seconds, not a
   minute. Every error is caught, printed as one tagged line, and the sampler exits 0: it
   cannot fail the group (it is another process).
2. **Rows go to the group's stdout as tagged lines** (`[wsg_stall] <WSG>\t<fields>`, a header
   line first), so they land in the host log on every host kind, cloud hosts included, which are
   burned after their leg. The driver splits them into `$LOG_DIR/<TS>_stall_<WSG>.tsv` at the
   end of the run (`<TS>` from the run_uid, so `--recompute-only` rewrites the same files).
   The header is written by R only, so the shell never restates the columns.
3. **Long rows:** one row per backend per check (`role` = `leader` | `worker` | `blocker`),
   keyed by `sampled_utc`, rather than one wide row holding lists. Columns: `sampled_utc`,
   `wsg`, `role`, `pid`, `leader_pid`, `blocks_pid`, `state`, `wait_event_type`, `wait_event`,
   `query_start`, `query` (first 200 chars, whitespace squished; blockers only, plus the
   leader), `load1`, `load5`, `load15` (`/proc/loadavg`, else `sysctl -n vm.loadavg`),
   `n_active` (active backends on the database).
4. **Threshold and cadence:** a check every 60 s (`LNK_STALL_EVERY_S`, for tests); rows only
   while the leader has been `active` on one statement longer than N min, N = 10 by default,
   set by `study_area_run.sh --stall-sample-after=<min>` (1–1440) and passed on both legs as
   `LNK_STALL_AFTER_MIN` (the both-legs rule). A bad env value at group level prints a line and
   runs the group without a sampler.
5. **Naming the file:** `wsg_run_one.R` prints `[wsg_run_one] <WSG> stall samples: <TS>_stall_<WSG>.tsv`
   on the line after `TIMEOUT after`, rather than appending to it, so `run_timeouts()`'s parser
   and the format test stay unchanged. The INCOMPLETE block prints the file under each
   `statement bound hit` line when the driver wrote it, and the summary lists every
   `_stall_` file the run left (a group can stall past N and still finish).
6. The plan (EXPLAIN) stays out, per the issue: it needs code inside fresh's session.

## Phase 1: Tests first, shown red
- [x] `tests/testthat/test-lnk_stall.R`, no DB: the line formatter squishes and truncates a
      query to 200 chars, strips tabs/newlines, writes the header once; load average parses
      both forms.
- [x] Live (`skip_if_no_db()`): a background Rscript session (tagged `application_name`) runs
      `pg_sleep(30)`; past a 2 s threshold the snapshot has a `leader` row with
      `wait_event = 'PgSleep'`; under the threshold it has none.
- [x] Live lock case: a test session `LOCK TABLE <scratch> IN ACCESS EXCLUSIVE MODE` in an open
      transaction; the stalled session's `SELECT count(*)` on it waits; the snapshot's
      `blocker` row names the locker's pid and its `LOCK TABLE` query, and the leader's
      `wait_event_type` is `Lock`.
- [x] The watch loop exits within seconds of its parent pid going away, and a broken connection
      gives one error line and a normal return, never a condition.
- [x] `test-study_area_finish.R`: `run_stalls` splits fake local and remote host logs into one
      file per group with the header once; the INCOMPLETE block prints the file beside the
      group's statement; the summary lists the files; `wsg_run_one.R` prints the
      `stall samples:` line inside `name_timeout()` after the TIMEOUT line (structural test).
- [x] Run them; record the red output in `progress.md`.

## Phase 2: The sampler
- [x] `R/lnk_stall.R`: `.lnk_stall_snapshot(conn, pid, after_s)` (one query over
      `pg_stat_activity` with `leader_pid` and `unnest(pg_blocking_pids())` for the leader and
      its workers), `.lnk_stall_lines()`, `.lnk_loadavg()`, `.lnk_stall_watch(conn, pid,
      parent_pid, wsg, after_s, every_s)`; roxygen `@noRd`, matching `R/utils.R`'s style.
- [x] `data-raw/wsg_stall_sample.R`: the same `LNK_LOAD` switch as `wsg_run_one.R`, connect,
      call the watch inside `tryCatch`, always exit 0.
- [x] `data-raw/pretest_inputs.csv`: `R/lnk_stall.R` and `data-raw/wsg_stall_sample.R` as `any`.
- [x] Phase 1's sampler tests green.

## Phase 3: `wsg_run_one.R`
- [ ] Read and validate `LNK_STALL_AFTER_MIN` / `LNK_STALL_EVERY_S`; start the sampler after
      the bound check, inside `tryCatch` (a launch failure prints a line and the group runs on).
- [ ] `name_timeout()` prints the `stall samples:` line; header comment documents both vars.

## Phase 4: The driver
- [ ] `study_area_run.sh --stall-sample-after=<min>` (default 10, 1–1440), usage text, banner
      line, exported on the local leg; `study_area_remote.sh` adds `LNK_STALL_AFTER_MIN` to
      `REMOTE_LEG_VARS` and the ssh string. Tests beside the existing `LNK_TEST_STALL_WSG` ones.
- [ ] `study_area_finish.sh`: `run_stalls()` (byte-wise, never fatal under `set -e`, same log
      glob as `run_timeouts()`), called from `run_finish`; INCOMPLETE and summary lines.
- [ ] Phase 1's driver tests green.

## Phase 5: Live evidence
- [ ] One dispatcher-only run on a scratch schema with `LNK_TEST_STALL_WSG=<small group>`,
      `--statement-timeout=2 --stall-sample-after=1`, `LNK_STALL_EVERY_S=15`: the stalled
      group's `_stall_` file holds `PgSleep` rows, the TIMEOUT and `stall samples:` lines and the
      INCOMPLETE block name it, the other group finishes; then a re-model without the hook.
- [ ] `data-raw/logs/stall_sample_487/README.md` with the run log, the file and the summary
      (redacted by the driver's rule).

## Phase 6: Docs and release
- [ ] RUNBOOK §8d: a subsection "A stalled statement leaves samples" beside "A runaway
      statement fails its group"; correct that section's stale "it is not passed over ssh"
      (`study_area_remote.sh` passes `LNK_TEST_STALL_WSG` as a group code).
- [ ] CLAUDE.md status block; NEWS.md; issue #487's body gets a `## Plan` / `## Decisions`
      section; DESCRIPTION 0.83.0 as the last commit.

## Owed at the end (reported, done after merge)
- [ ] The next real stall leaves a `_stall_` file; its reading goes into #487's body and the fix
      is filed where it lives (#487 acceptance 2; the issue stays open).
- [ ] The pre-run gate runs again before the next provincial run (`R/`, `wsg_run_one.R`,
      `pretest_inputs.csv` changed).

## Validation
- [ ] Tests pass (`devtools::test()`), lint clean against main per file, `devtools::check()`
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification: Phase 1's tests red before Phase 2 and green after; each new guard (parent-exit,
error-never-raises, file named only when written) restored to its bug once to watch it fail;
Phase 5's live run shows the whole chain from a real `wsg_run_one.R` under the driver.


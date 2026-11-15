# Plan review — #487 (Plan agent, read-only, against 4585ae0d; received 2026-11-15 ~00:15 UTC)

Written here by the parent session from the agent's reply (Plan agents cannot write).
Disposition of each finding is in `findings.md`, "Plan review disposition".

## Blocker
1. The watch test's "parent" (`sh -c 'sleep 4 & echo $!'` under `system2(stdout = TRUE)`) is dead
   before the watch starts: the backgrounded sleep holds the capture pipe. Redirect the sleep.
2. An orphaned sampler can hold a remote leg open: it inherits the ssh channel's stdout, and sshd
   keeps the session until every holder exits. `system2(wait = FALSE)` gives no pid, so the
   parent cannot kill it. Add a connect timeout, poll in `poll_s` steps, wrap the error print in
   `try`, and either a killable launch or explicit acceptance of the risk.

## Gap
3. `data-raw/pretest.R` `PRETEST_LINK_PATHS` lists only four data-raw scripts: a map row for
   `wsg_stall_sample.R` is dead until the path is added there (then `test-pretest.R:296-312`
   requires the row). Either edit voids gate records.
4. `test-study_area_remote.R:264-268` pins the `WORKER_PREP_LEG_VARS` string; `:395-406` checks
   the list against the exports; `run_remote` runs under `set -u` with globals lacking a stall
   value, so use `${STALL_AFTER_MIN:-10}`; update `study_area_remote.sh:28-30`'s header.
5. `test-lnk_pipeline_prepare.R:1167-1169` expects the line above the local leg's Rscript line to
   hold `LNK_HABITAT_GATE=0`: put the new env var elsewhere.
6. `--recompute-only` should refuse `--stall-sample-after` (`study_area_run.sh:363-372`).
7. A threshold at or above the bound never samples, yet the `stall samples:` line would name a
   file: refuse or warn in the driver; print the line only when `bound_ms > N*60000`.
8. `<TS>` is unknown outside the driver (`pretest_run.sh` sets no run uid; a hand re-model):
   define the behaviour.
9. Phase 5 will be refused by the pre-run gate (`R/` and `wsg_run_one.R` changed): needs
   `--pretest-note=` (an override row) or a gate pass.
10. The parent-gone / backend-gone / closed-connection tests connect to localhost directly but
    only call `skip_if_no_db()`: add `skip_if_not_local_db()`.

## Assumption
11. Blocker query text could fake `[wsg_run_one] <WSG> done` or `__LNK_LEG_END__`, which
    `host_log_reported` and `remote_leg_status` grep unanchored: neutralise `[wsg_` and `__LNK_`
    in the sampler's text fields.
12. `pskill(pid, 0)` works on macOS and Linux; FALSE on EPERM, TRUE for a zombie (callers reap).
13. `pg_blocking_pids(leader)` already covers its workers' blockers; per-worker calls duplicate
    (DISTINCT). Heavyweight locks only: LWLock, buffer pin, I/O waits show in `wait_event` with no
    blocker row; say so in the RUNBOOK.
14. Autocommit is required: `pg_stat_activity` is snapshotted once per transaction.
15. Do not set the sampler's own `application_name`: the gate excludes and terminates its group by
    `PGAPPNAME=pretest_<wsg>`, which the sampler inherits.
16. Per-group `load_all()` in the sampler costs seconds of CPU on the dispatcher.

## Ordering
17. The sampler starts before the guard (right: the guard runs under `name_timeout`), so the
    `LNK_TEST_STALL_WSG` refusal fires with a sampler running; the parent check ends it.
18. `run_stalls` must run before `run_finish_report` exits; a driver dead before `run_finish`
    splits nothing until a `--recompute-only`. Say so in the RUNBOOK.

## Acceptance
19. The remote path ships unexercised: add one `--workers=` run with the hook on a worker group
    and check the leg ends promptly.
20. The lock case is unit-only; meets the issue's wording.
21. The TIMEOUT line itself naming the file is moved to the next line: record in `## Decisions`.

## Scope
22. Nothing dropped. Long rows are link's call. `n_active` counts the sampler: exclude
    `pg_backend_pid()`.

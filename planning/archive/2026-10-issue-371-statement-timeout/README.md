## Outcome

`data-raw/study_area_run.sh` now bounds each modelling statement, with
`--statement-timeout=<minutes>` defaulting to 30. The bound is set as
`PGOPTIONS='-c statement_timeout=<N>min'` on both modelling legs, and
`LNK_STATEMENT_TIMEOUT_MIN` goes with it. `wsg_run_one.R` refuses a connection
whose bound differs, so a leg that lost the export fails its first group instead
of running unbound. A runaway statement now fails its own group and nothing else:
- `wsg_run_one.R` names the cancelled statement on a `TIMEOUT` line. The handler is
  `.lnk_timeout_statement()`; it reads `.lnk_db_execute()`'s `Statement:` when a
  transaction re-threw the error.
- The INCOMPLETE summary lists the group under `statement bound hit:`, with its
  statement and a bounded re-model command that carries the run's own bound.
- The recompute keeps `wsg_recompute_one.R`'s 10-minute in-session `SET`.
- RUNBOOK §8d has the mechanics, under "A runaway statement fails its group".

What we learned:
- **fresh's bare `dbExecute` puts no SQL in the error,** so naming the statement
  needs a calling handler, while the DBI frames still hold it as `statement`.
- **`dbWithTransaction()` re-throws and drops those frames.** The plan review found
  this, and it was reproduced.
- **Shell text must be checked as what its consumer parses.** Every code-check round
  found an instance of this: a log is not clean bytes (macOS `sed` aborts in a UTF-8
  locale), echoed lines are not one command, and a regex-extracted bound is not a
  whole value (a bare `30` is 30 ms).

## Measurement

- **The default:** in run `20261023_074321-24d85e8c`, the longest group that
  finished took 16.3 min in total (SETN), then LNAR 13.8 and BULK 13.7. KTSU's
  65.4 min was the stall. No statement outlasts its group, so 30 min is at least
  1.8× headroom. The plan review measured cyphers at up to 2.9× the dispatcher's
  time on the same group, so RUNBOOK says to raise the bound when a top group is
  placed on a cypher by hand. This number has not been measured per statement.
- **Postgres reports 60 min as `1h`,** so the per-group check compares milliseconds
  from `pg_settings`, not the `SHOW` text.
- **`PGOPTIONS` reaches RPostgres.** With it set, a probe reported `3s`; without it,
  `0`.
- **Acceptance criterion 1, end to end, dispatcher only:**
  - The run stalled one group with `LNK_TEST_STALL_WSG` under a 2-min bound. That
    group was cancelled at the bound and named with its statement, and the run
    exited 1.
  - The printed re-model then exited 0, and `--recompute-only` recomputed both
    groups and compared them, exiting 0.
  - **The first attempt (MUSK + LEUT) was a wrong turn.** Its `--recompute-only`
    exited 1 for reasons of the test's scope, not #371: LEUT stopped at the #227
    guard because of a dam outside the two-group schema, and MUSK is RB-only, which
    bcfishpass cannot compare. NBNK + EUCH were then chosen because they pass the
    guard on an empty schema.
- **Tests:** the full suite ran 979 tests with 0 failures. Every new guard was
  mutation-checked by restoring the defect, and each went red.

## Evidence

`data-raw/logs/statement_timeout_371/`: its README indexes run 1, run 2 and the
bound-check probes.

## Owed

- A full provincial run at the default bound completes with no group timing out (acceptance criterion 2; it needs the next `default` run). Checked as: no `statement bound hit` in the report, no `TIMEOUT` line in any `<TS>_run_*.log`, and every host's `statement_timeout=` lines read `30min` (review AC3).

Closed by: PR for branch `371-study-area-run-sh-bound-each-modelling-s`

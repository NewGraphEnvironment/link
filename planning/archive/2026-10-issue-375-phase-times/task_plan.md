# Task: study_area_run.sh: record each phase's start and end per host, so run speed is measured, not reconstructed (#375)

## Problem

A provincial run's time is split across phases: modelling per host, consolidate, the barrier-view build, the recompute and the compare. The driver records none of those boundaries. Every speed number so far was rebuilt by hand from log tables, console logs and `date_end` columns (`research/study_area_run.md`), so there is nothing comparable to read off run after run when a change is meant to make runs faster.

## Context

Every speed number for a provincial run so far was rebuilt by hand from log tables,
console logs and `date_end` columns. #377 (the speed tracker) wants one row per run
read off a file, so each speed change is measured the same way. #375 is that file:
`<TS>_phases.tsv`, written by the driver as each phase ends.

What exploration found that shapes the design:

- The console log carries **no timestamps**: `=== run buckets (DS-first) ===` etc. are
  bare. So "times agree with the console log" needs the driver to print each phase's
  times as it closes it, and the check against *independent* evidence is the DB
  (`<schema>.log.date_start/date_end`, `log_recompute`) and file mtimes.
- Cypher legs are `wait`ed **serially** after the local leg (`study_area_run.sh:1461-1468`,
  `host_wait`), so the wait's return time is not a leg's end. Each leg's row must be
  written from inside its own backgrounded subshell, when its loop ends.
- `run_finish_report` **`exit 1`s** on an incomplete run (`study_area_finish.sh:651-772`),
  so the phase table must print before that branch, not at the end.
- The explicit `burn_cyphers` (`:1625`) and per-host accounting (`:1497-1517`) sit on the
  critical path between modelling and the tail, and the issue's six phases leave them out.
- `date` here is GNU, BSD on other Macs (`code-check-shell.md`), so the lib never parses
  dates with `date`: one `date -u '+%Y-%m-%dT%H:%M:%SZ %s'` call gives ISO and epoch together,
  and the report parses ISO with perl (`Time::Local`), which the driver already uses.

## Decided at the gate (operator approved the plan, 2026-10-23)

1. **Phases**, in run order. The issue's six, plus four that sit on the critical path:
   `prep` (run-wide: driver start → dispatch; and one per cypher: spin start → its prep
   done), `refresh` (`--refresh-primitives`), `model` (one per host), `account`,
   `consolidate`, `burn`, `coverage`, `views` (the log-table step and
   `barriers_views_build.R`), `recompute` (the pool), `compare`.
2. **A phase that does not run gets a `skipped` row with blank times**, so every run's
   file has the same shape and the critical path ignores it (`refresh` without the flag,
   `consolidate` / `burn` with no cyphers, the tail when no group has rows).
3. **Columns are the issue's plus `minutes`** (end − start, one decimal), computed at
   write time from the epochs, so a tracker row is read off without arithmetic:
   `run_uid phase host start_utc end_utc minutes groups status`.
4. **`--recompute-only` writes its own `<its TS>_phases.tsv`** with the finished run's
   `run_uid` in every row (as the issue says), and its summary prints its own rows only:
   a critical path spanning a hand re-model hours later would mislead. Its rows are a
   `prep` (its own preamble; plan review S1) and the tail.
5. **A phase in flight when the driver exits writes a `failed` row from the EXIT trap**
   (`on_exit`), so a run that dies leaves the phase it died in, not just those it finished.
   `model` status is the leg's exit status; failed groups stay named where they are today.
   A phase a subshell already wrote is not closed again (review B2), and the trap prints
   the table once for a run that exits before its summary (review G4). The file's shape
   is guaranteed only for runs that reach the report (review S3).

## Phase 1: the lib and its tests

- [x] `data-raw/study_area_phases.sh`: `phase_begin <phase> [host]`, `phase_end <phase>
      [host] <groups> <status>`, `phase_skip <phase> [host]`, `phase_row` (one `printf >>`
      line, under PIPE_BUF, so parallel legs can append), `phases_report` (prints the table
      and the critical path: first start to last end, in minutes), the open-phase record
      `on_exit` reads. Header written once by `phases_init`. Globals documented like
      `study_area_finish.sh`'s header.
- [x] `tests/testthat/test-study_area_phases.R`, same harness as `test-study_area_hosts.R`
      (bash ≥ 4, skip when the lib is absent): header once; one row per end; blank times on
      skip; `minutes` right; two parallel writers leave whole rows; report's critical path
      over a fixture; skipped rows ignored; an open phase closed `failed`.
- [x] Restore-the-bug check: a mutant (e.g. critical path from first *end*) turns a test red.

## Phase 2: wire the driver

- [x] Source the lib beside the other two; `phases_init "$LOG_DIR/${TS}_phases.tsv"` after
      run identity (`:445`); `on_exit` closes an open phase `failed`.
- [x] Run-wide `prep` begins at driver start, ends at dispatch; `refresh` around
      `snapshot_bcfp.sh`; per-cypher `prep` rows from inside each prep subshell
      (`:1324-1361`), status from its exit.
- [x] `model`: the local loop subshell and each ssh leg write their own row when the loop
      ends (`:1418-1457`), groups = bucket size.
- [x] `account`, `consolidate`, `burn` (explicit call only, not the trap's) around their
      blocks; `consolidate` / `burn` skipped when `N_CY=0` (`account` runs for the
      dispatcher too). The burn row reads what the burn left, not its return (review B1).
- [x] Plan review folded in (`review-plan.md`): B1, B2, G1–G5, O1–O3, A3, S1, X2. A1/A2
      go to the RUNBOOK in Phase 4; X1/X3 shape Phase 3.
- [x] `study_area_finish.sh`: `coverage`, `views`, `recompute`, `compare` in `run_finish` /
      `run_finish_recompute` / `run_finish_compare`, statuses from the existing fail flags;
      `phases_report` called at the top of `run_finish_report`, before its `exit 1`.
- [x] `--recompute-only` path: `phases_init` with its own TS; tail rows under the
      finished run's uid.
- [x] Each `phase_end` prints `  [phase] <name> <host> <status> <start>→<end> (<min> min)`.
- [x] Existing tests (`test-study_area_finish.R`, `test-study_area_hosts.R`) pass; `bash -n`.

## Phase 3: dispatcher-only acceptance run

- [x] From a worktree (never this repo mid-run), into scratch `fresh_375`:
      `bash data-raw/study_area_run.sh --buckets-exact --focal=NBNK,EUCH --config=default
      --schema=fresh_375`, console teed to a file. NBNK and EUCH pass the downstream guard
      on an empty schema and carry reference species (#371's run 2).
- [x] Check: one row per phase; `model` end within a minute of `max(log.date_end)` for the
      run_uid; `recompute` brackets `log_recompute`'s rows; console `[phase]` lines match
      the TSV; skipped rows for `refresh`, `consolidate`, `burn`.
- [x] A `--recompute-only --run-uid=<that uid>` pass writes its own file with the tail rows.
- [x] A killed run (SIGTERM during `model`) leaves a `failed` row for it.
- [x] Evidence to `data-raw/logs/phases_375/` with a README; drop `fresh_375`.

## Phase 4: docs

- [x] RUNBOOK §8d: what `<TS>_phases.tsv` holds and how to read a tracker row off it.
- [x] Driver header: `<TS>_phases.tsv` in the file list.
- [x] CLAUDE.md status; #377's #375 line filled with what this run measured. NEWS is written
      by `/gh-pr-merge` at release, as for 0.68.2.

## Owed at the end (reported, done after merge)

- [ ] Acceptance criterion 2: the next provincial run's `phases.tsv` committed with its
      evidence and its #377 runs row filled from it. #375 stays open for it, as #371 did.

## Validation

- [x] Tests pass
- [x] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification is Phase 3: rows against the DB's own timestamps, the console against the
TSV, the trap's `failed` row on a kill, and a mutant per test file proving the tests fire.


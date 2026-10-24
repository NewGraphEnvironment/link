# Findings — study_area_run.sh: record each phase's start and end per host (#375)

## Issue context

## Problem

A provincial run's time is split across phases: modelling per host, consolidate, the barrier-view build, the recompute and the compare. The driver records none of those boundaries. Every speed number so far was rebuilt by hand from log tables, console logs and `date_end` columns (`research/study_area_run.md`), so there is nothing comparable to read off run after run when a change is meant to make runs faster.

## Proposal

`study_area_run.sh` writes `<TS>_phases.tsv`, one row per phase per host:

| column | e.g. |
|---|---|
| `run_uid` | `20261023_074321-24d85e8c` |
| `phase` | `prep`, `model`, `consolidate`, `views`, `recompute`, `compare` |
| `host` | `dispatcher`, `job1`, … (blank for run-wide phases) |
| `start_utc`, `end_utc` | ISO 8601 |
| `groups` | number of groups the phase covered |
| `status` | `ok`, `failed`, `skipped` |

Each row is written as its phase ends, so a run that dies still leaves the phases it finished. `--recompute-only` writes its own rows under the run_uid it finishes. The final summary prints the table, along with the run's critical path (the first start to the last end).

## Acceptance

- A dispatcher-only test run writes one row per phase, with times that agree with the console log.
- The next provincial run's `phases.tsv` is committed with its evidence, and its row in the speed-up tracker (#377) is filled from it.



## Errors Encountered

| Error | Resolution |
|-------|------------|

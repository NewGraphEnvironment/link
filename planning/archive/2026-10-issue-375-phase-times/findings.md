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
| `${#PHASE_OPEN[@]}` on a never-filled assoc array is "unbound variable" under `set -u` (bash 5.3); `for k in "${!PHASE_OPEN[@]}"` is fine | Tests count by loop; the lib only loops |

## Plan review (2026-10-24 UTC): what was verified, what was done

Review text: `review-plan.md`.

- **B1 confirmed** by reading `burn_cyphers` (`study_area_hosts.sh:413-466`): `local rc=$?` then `return $rc`, so the explicit call returns 0 whatever it burned. The driver now derives the burn row from `CY_BURNED` / `CY_HOLD` / `KEEP_CYPHERS`.
- **B2 confirmed** by tracing the serial waits; reproduced in a test (a leg that wrote `ok` while still open in the parent). `phases_close_open` now skips a key whose row (phase, host, start) exists.
- **G1** was already done when the review landed (harness sources the phases lib). **G2, G3** done in the same pass. **G4**: `on_exit` prints the table once (`PHASES_REPORTED`).
- **G5**: chose to document, not count WARN lines: the account row is the measured answer to "did the hosts finish", and counting log text is what #347 moved away from.
- **O1**: `phases_close_open || true` in the trap. The bash < 4.4 empty-array point is moot (driver refuses bash < 4; Homebrew bash is 5.3), but `${#PHASE_OPEN[@]}` on a never-assigned map *is* unbound in 5.3, so the map is declared `=()`.
- **O2**: `date` failure now costs only the row's times (test with a `date` function returning 1).
- **A3**: comment corrected (one write() to an O_APPEND local file), `LC_ALL=C` on the awk.
- **S1**: `--recompute-only` writes a `prep` row for its preamble.
- **X2**: structural test pins both model wrappers and the prep wrapper (`|| mrc=$?`, `exit "$mrc" ) &`), the parent's forget/print after each wait, and the trap's order.

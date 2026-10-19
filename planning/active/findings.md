# Findings — study_area_run.sh: a run that stops before its tail leaves no record of which groups it was running (#358)

## Issue context

## Problem

#348 lets a run that loses groups still recompute and compare the rest. It also adds `--recompute-only --run-uid=<uid>` to finish a run once the missing groups have been re-modelled. Two gaps remain.

- **The expected set has no record of its own.** Without `--wsgs=`, `--recompute-only` expects the groups that have a `<schema>.log` row for the run_uid on the dispatcher. Some groups have no such row:
  - a group that failed on a cloud host, since consolidate copies log rows only for groups that finished;
  - a group that failed before `.lnk_log_run_start()`, for example in `lnk_load_overrides()`, at the downstream guard's `quit(1)`, or on a connect failure (`wsg_run_one.R`).

  The driver knows the full set once the buckets resolve, but it writes that set nowhere.
- **A consolidate failure still exits before coverage.** If one source is refused (`dest_log_newer`, which a single group can trigger), the driver exits after consolidate, before the coverage step and the recompute. That is the same failure class as #348. Since #348 the banner prints the `--recompute-only` recovery, but the groups that were consolidated are not recomputed in that run.

## Proposal

- Write `<TS>_run_wsgs.tsv` (group, host, SKIP) as soon as the buckets resolve. `--recompute-only` reads it by default (`<run_uid minus its suffix>_run_wsgs.tsv`, since a run_uid's prefix is its `TS`) and falls back to the log.
- After a consolidate refusal, carry on to coverage with the sources that consolidated, keep the refused host, and exit non-zero as the kept-host path already does.

## Acceptance

- `--recompute-only` with no `--wsgs=` names a group that failed on a cloud host.
- A run with one refused source recomputes the other hosts' groups and exits non-zero naming the refused host.

## Plan-mode exploration


#348 made one failed group cost only itself, and added `--recompute-only --run-uid=<uid>`
to finish a run later. Two gaps are left (issue #358):

1. **No record of the run's groups.** Without `--wsgs=`, `--recompute-only` expects the
   groups with a dispatcher `<schema>.log` row for the run_uid
   (`run_expected_from_log`, `data-raw/study_area_finish.sh:138`). A group that failed on a
   cypher (consolidate copies finished groups only), or that failed before
   `.lnk_log_run_start()`, has no such row, so it is never named. The buckets resolve at
   `study_area_run.sh:1196-1209` and are written nowhere.
2. **A consolidate failure exits before coverage.** `study_area_run.sh:1475-1482` exits on
   any non-ok source. `schema_consolidate()` already loops past a failed source (`next`
   at every refusal, `schema_consolidate.R:300-600`), so the other hosts' groups *are* on
   the dispatcher, but they are never recomputed or compared in that run.

What exploration settled:
- `TS` is `%Y%m%d_%H%M%S` and `RUN_UID="${TS}-<8 hex>"` (`:297`, `:387`), so `${RUN_UID%-*}`
  is the TS and names the file.
- A failed source's `CY_BUCKET_DONE` is in `RUN_SIGNALS` (`run_expected_from_hosts`,
  `study_area_finish.sh:54`). After a mid-copy failure (`source_copy`/`dest_copy`/
  `copy_empty`) the log tables may have copied while `streams` did not, so coverage could
  class a half-copied group `recompute`. The failed source's groups must therefore be
  **forced out** of the recompute, not left to coverage.
- `host_release` reads the host's database (`host_split`), and consolidate deletes source
  rows only after a full success, so a refused or failed source keeps its finished groups
  there and is already kept (`CY_UNCONS`), listed in `kept_hosts.tsv`, and `KEPT_CAUSE_N`
  already makes `run_finish_report` exit 1. Only its comment ("call only after consolidate
  returned success") and its reason text need changing.

Decisions taken (mechanism, stated rather than asked):
- **Carry on after any per-source failure that has a recorded outcome**, refusal or
  mid-copy; that source's groups are excluded from the recompute and classed
  `not_consolidated`. If R died without writing an outcome for every source, keep today's
  exit (nothing says which hosts landed).
- **`--recompute-only` takes the file ∪ the log** when the file exists (nothing in either
  is dropped), and falls back to the log alone, with today's message, for runs before #358.
- **`run_wsgs.tsv` columns:** `wsg host skip run_uid`. Written with `skip` = `unknown` when
  the buckets resolve, rewritten with `yes`/`no` after per-host accounting. The reader
  excludes `yes` only. A group in two buckets has two rows; the reader takes unique groups.

## Errors Encountered

| Error | Resolution |
|-------|------------|

## Correction to the plan (Phase 3)

The plan said `host_release` keeps a host whose consolidate failed. It keeps it only while finished
groups are left on it, as before; `CY_CONS_FAIL` changes the reason to `consolidate failed at stage
<X>; finished groups left on the host`. A failed source with nothing left (e.g. `copy_empty`) has
nothing to lose, and #347's rule is that the measured state decides a burn. The run still exits
non-zero through the `not_consolidated` class. Tested both ways in `test-study_area_hosts.R`.

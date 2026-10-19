# Task: study_area_run.sh: a run that stops before its tail leaves no record of which groups it was running (#358)


#348 lets a run that loses groups still recompute and compare the rest. It also adds `--recompute-only --run-uid=<uid>` to finish a run once the missing groups have been re-modelled. Two gaps remain.

- **The expected set has no record of its own.** Without `--wsgs=`, `--recompute-only` expects the groups that have a `<schema>.log` row for the run_uid on the dispatcher. Some groups have no such row:
  - a group that failed on a cloud host, since consolidate copies log rows only for groups that finished;
  - a group that failed before `.lnk_log_run_start()`, for example in `lnk_load_overrides()`, at the downstream guard's `quit(1)`, or on a connect failure (`wsg_run_one.R`).

  The driver knows the full set once the buckets resolve, but it writes that set nowhere.
- **A consolidate failure still exits before coverage.** If one source is refused (`dest_log_newer`, which a single group can trigger), the driver exits after consolidate, before the coverage step and the recompute. That is the same failure class as #348. Since #348 the banner prints the `--recompute-only` recovery, but the groups that were consolidated are not recomputed in that run.

## Phase 1: Record the run's groups (`<TS>_run_wsgs.tsv`)
- [x] Tests first in `tests/testthat/test-study_area_finish.R`: `run_wsgs_write` writes one
      row per bucket member and host (dispatcher + each cypher, overlap kept), `skip`
      `unknown` before accounting and `yes` for an `ACC_SKIP` group after;
      `run_expected_from_file` returns the unique groups less `skip = yes`, refuses (rc 1) a
      file whose `run_uid` column is not `RUN_UID`, and returns rc 2 for an absent file.
- [x] `run_wsgs_write <path>` and `run_expected_from_file <path>` in
      `data-raw/study_area_finish.sh` (header's globals lists updated).
- [x] Driver: call `run_wsgs_write` right after the overlap check (`study_area_run.sh:1223`),
      before any spin, and again after per-host accounting (`:1427`) to fill `skip`.

## Phase 2: `--recompute-only` reads the file
- [x] Tests first: a fixture `T0_run_wsgs.tsv` naming GGGG on host `job1` with no log row →
      the expected set includes GGGG, and `run_finish` names it under "no rows" (acceptance 1);
      no file → log only, with the "pass --wsgs=" note; `--wsgs=` still wins over both.
- [x] Move the expected-set resolution out of the driver block (`:663-682`) into
      `run_expected_recompute_only` in `study_area_finish.sh` (sets `RO_EXPECT`, prints the
      source of each part: file, log, or `--wsgs=`), so it is testable; the driver calls it.
- [x] Driver header (`:82-90`) and the block's comment say the file is read first.

## Phase 3: Carry on after a consolidate failure
- [x] Tests first: `consolidate_outcomes <tsv>` with one refused source (`dest_log_newer`)
      and one ok source → `CONS_FAILED` names the refused workspace, its bucket is in
      `CONS_EXCLUDED`, the ok host's signals survive; a TSV missing a source → rc 1.
      `run_finish` with an excluded set recomputes and compares only the other host's
      groups, writes `not_consolidated` rows to `coverage.tsv`, and exits 1 (acceptance 2,
      lib level). In `test-study_area_hosts.R`: `host_release` on a host whose consolidate
      failed keeps it with reason `consolidate refused (dest_log_newer)` and its groups.
- [x] The R snippet at `study_area_run.sh:1466-1473` writes `${TS}_consolidate.tsv`
      (`host ok stage groups`) from `res$sources` before `quit()`.
- [x] `consolidate_outcomes` (finish lib): maps `cypher@<ip>` back to the workspace via
      `CY_IP`, sets `CY_CONS_FAIL[ws]=<stage>`, `CONS_EXCLUDED`, and drops a failed host's
      `CY_BUCKET_DONE` so it never reaches `RUN_SIGNALS`.
- [x] `run_finish`/`run_coverage` take the excluded set as a third argument: removed from
      every other class, added to `COV_MISSING` as `COV_UNCONS`, printed and written as
      `not_consolidated`. The report's existing kept-host branch then defers those groups to
      `kept_hosts.tsv`.
- [x] Driver: on `crc != 0`, if `consolidate_outcomes` accounts for every source, print each
      failed host, stage and groups, set `RUN_INCOMPLETE=1`, and carry on to release, burn and
      `run_finish`; otherwise keep today's exit and banner.
- [x] `host_release` (`study_area_hosts.sh:332`): comment no longer says "only after
      success"; a host with `CY_CONS_FAIL` set is kept with that reason (after `host_split`,
      so `CY_UNCONS` still fills the groups column).

## Phase 4: Docs
- [x] RUNBOOK §8d "A missing group costs only itself": the run_wsgs file, what
      `--recompute-only` reads, and the consolidate-failure path. Driver header lines 53-57.
- [x] Mutation check: restore each defect (no file write; signals kept for a failed host;
      the old `exit 1`) against the new tests and record which test goes red in `findings.md`.

## Validation

- [x] Tests pass
- [x] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

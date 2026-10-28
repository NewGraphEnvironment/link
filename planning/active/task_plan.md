# Task: Variants harness: run a variant's groups in parallel (from #404) (#406)

## Problem

`data-raw/habitat_variants_build.R`'s `run_variant()` loops over a variant's groups one at a time (`for (w in wsgs_v)`). #404 measured one variant's pass over #331's nine groups on m4 (fresh 0.44.0, link `45b12b2e`): 5.6 min serial, 0.3 to 1.0 min per group. Inside a pass classify holds 36.5 %, connect 30.9 %, persist 30.3 % and the two verification digests 0.4 %, so no single step is the target; the lever is width over groups. The `default` pass a variants run makes first (all species, steps 1, 2, 3 and 7) is 6.8 min over the same nine, half classify and half connect.

The bound from the serial numbers (`analyze.R`, longest-first greedy): four jobs over groups take a variant's pass from 5.6 to 1.6 min (longest group PARS 1.0) and the `default` pass from 6.8 to 1.8. Record: `data-raw/logs/variant_cost_404/` (README, `variant_timing.csv`, `steps_vs_segments.png`).


## What exploration settled

- **Each group's pass is independent.** Classify, connect and the discharge join write only
  `working_<prefix><wsg>`, including `streams_breaks` (`R/lnk_pipeline_classify.R:260`).
  `lnk_pipeline_persist()` and `copy_access()` DELETE and INSERT only that group's rows of the
  variant's schema. The gate's overlay is a session temp table (`R/lnk_habitat_gate.R:225`). DDL
  (`lnk_persist_init()`) runs once per variant, before the groups.
- **Concurrent `ANALYZE` on the same table serializes** (`ShareUpdateExclusiveLock` conflicts with
  itself). It is correct, only slower. It is 1.6 % of the pass, so it is left alone.
- **Variants stay sequential.** The `default` pass's digest check licenses the others.
- **#404's base survives on m4** (`score404_default`, nine `working_score404_*`, fresh 0.44.0 as the
  pin). The measurement reuses it with `--step=variants`, and no base rebuild is needed.
  `max_connections` is 40, and 16 cores.
- **`built.csv`'s columns are read by `habitat_variants_score.R`**, so its shape does not change.

## Decided at the gate

- **Mechanism: a PSOCK cluster inside the one build process** (`parallel::makeCluster`, base R).
  Each worker runs `load_all()`, opens its own connection and receives `loaded` once. Not forks:
  a DBI connection does not survive a fork, and forked workers crash under macOS BLAS
  (`code-check-r.md`). Not one Rscript per group: one process means one permission prompt and
  one place that writes the CSVs (`agent-operations.md` §2, "Fan out inside one process").
- **Only the master writes files.** Workers return each group's step seconds, digest and status.
  The master writes `built.csv` and `variant_timing.csv` in group order once a variant's groups
  return. Parallel writers would interleave.
- **A failed group stops the run after the others return.** The master records every group whose
  checks passed, then stops and names each failure. In the serial path the run still stops at the
  first failure, as today.
- **Measured at widths 1, 2, 4 and 8** to show where the database stops paying, against #374's
  ceiling of about four jobs.

## Phase 1: `--jobs` in the build script

- [x] Parse and validate `--jobs` (digits only, 1 to 16, default 1), and document it in the header
      usage block.
- [x] Move the body of `run_variant()`'s group loop into `variant_pass(v, w, cfg)`. It returns the
      step seconds, discharge-join seconds, load, working digest and an error message. It writes
      no file. The master's loop calls it, then `record_built()` and `record_timing()`.
- [x] With `--jobs` above 1, start the cluster once before the variants loop and close it in a
      `tryCatch(finally =)`. `on.exit()` at a script's top level never fires. Set each worker's
      working directory, `load_all()`, connection, and the exported helpers and `loaded`.
      Export `cfgs[[v]]` per variant. Dispatch with `parallel::clusterApplyLB()` in descending
      segment count (longest first). Workers write progress lines to the log (`outfile = ""`),
      prefixed with the group.
- [x] `variant_timing.csv` gains a `jobs` column, backfilled to 1 on older rows as
      `record_built()` backfills its columns. Each variant also gets one `pass_wall` row (group
      blank, `in_total` FALSE): first dispatch to last return, the number the speed-up is read
      from.
- [x] Keep the serial path behaviourally unchanged. At `--jobs=1` no cluster starts, and each
      group is recorded as it finishes.
- [x] Update the header comment, and RUNBOOK if it describes the loop (grep for
      `habitat_variants_build`).

## Phase 2: measure on #331's nine groups (m4)

- [x] Run from a `git worktree` at the branch commit, so this checkout can take commits during the
      run. New `--out=data-raw/logs/variants_parallel_406/`, with #404's
      `base_habitat_digest.csv` and `closure.txt` copied in and the copy stated in the README.
      `--prefix=score404_`, `--variants=…variants_331.csv`, `--roles=…wsg_roles_331.csv`,
      `--only=bt_rear_wet_p10`.
- [x] Write the run decision into the README before the first build: host, load, fresh pin, widths,
      the order of the runs.
- [x] `digest.R`: md5 per group of every persisted table of `score404_bt_rear_wet_p10`
      (`streams`, `streams_access`, `streams_habitat_bt`) and of each working schema's
      `streams_habitat`, written to `digests_<jobs>.csv`.
- [x] Builds at `--jobs` 1, 2, 4 and 8 in turn, each followed by `digest.R`. Record the load and
      the other backends at each launch (`launch_state.txt`, as #404 did).
- [x] `compare.R`: every digest identical across the four widths, and the `default` pass's digest
      check passed in every worker (or the build would have stopped). Prove the comparison can
      fail by pointing it once at `score404_default`'s BT habitat against the variant's, which
      must differ.
- [x] `analyze.R`: `pass_wall` per variant per width against #404's serial 5.6 / 6.8 min and its
      greedy bound of 1.6 / 1.8. Per-step seconds per width show what contends: classify and
      connect against persist and `ANALYZE`.

## Phase 3: record and release

- [x] README `## Measurement` and `## Evidence` sections. The verdict states the default width to
      recommend and the database ceiling, beside #374's.
- [ ] Fill #406's line on #377 ("Measured: …"), and edit #406's body if the measurement changes
      what it says.
- [x] Add a CLAUDE.md Status entry. NEWS entry and patch version bump as the final commit.

Approved by the operator 2026-10-28 ("go all phases to pr").

## Owed at the end (reported, done after merge)

- (none planned)

## Validation

- [x] Tests pass (`devtools::test()`; no package R code changes, so this is the regression check)
- [x] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification is the digest identity across widths 1, 2, 4 and 8 (Phase 2), the comparison's proven
failure on a known-different pair, and `analyze.R`'s assertion that each pass's steps still sum to its
"done in" line. A mutation check on the error path: one worker made to fail (a bad group in a
scratch run) stops the build, names the group, and leaves `built.csv` holding only the groups that
passed.


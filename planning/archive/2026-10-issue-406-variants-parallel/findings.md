# Findings — Variants harness: run a variant's groups in parallel (#406)

## Issue context

**If we do it:** a tuning ladder's variant passes run about 3.5× faster, about 53 min saved on #331's 12-rung ladder, with no output change. **If we never do:** every variant pays 5.6 min over nine groups serially, about two thirds of a tuning build's wall clock after the base.

## Problem

`data-raw/habitat_variants_build.R`'s `run_variant()` loops over a variant's groups one at a time (`for (w in wsgs_v)`). #404 measured one variant's pass over #331's nine groups on m4 (fresh 0.44.0, link `45b12b2e`): 5.6 min serial, 0.3 to 1.0 min per group. Inside a pass classify holds 36.5 %, connect 30.9 %, persist 30.3 % and the two verification digests 0.4 %, so no single step is the target; the lever is width over groups. The `default` pass a variants run makes first (all species, steps 1, 2, 3 and 7) is 6.8 min over the same nine, half classify and half connect.

The bound from the serial numbers (`analyze.R`, longest-first greedy): four jobs over groups take a variant's pass from 5.6 to 1.6 min (longest group PARS 1.0) and the `default` pass from 6.8 to 1.8. Record: `data-raw/logs/variant_cost_404/` (README, `variant_timing.csv`, `steps_vs_segments.png`).

## Proposed solution

- Run a variant's groups in parallel in `run_variant()`, width `--jobs` (default 1, so the serial path is unchanged), each job on its own connection against its own `working_<prefix><wsg>` schema. The per-group steps touch only that group's working schema and the group's rows of the variant's persist schema; `lnk_persist_init()` stays once per variant before the jobs.
- `variant_timing.csv`, `built.csv` and the digest files are written per group from one process: collect each job's rows and write once, or lock the writes (parallel writers interleave; `code-check-shell.md`).
- Keep the `default` pass on the same width.

## Acceptance

- [ ] Every variant × group digest (`built.csv`, the habitat digests) identical between a serial and a parallel build of the same base.
- [ ] Measured on #331's nine groups and `bt_rear_wet_p10` at `--jobs=4`, beside #404's serial numbers, in `data-raw/logs/`; the line on #377's iteration-speed list filled in.
- [ ] The database's own ceiling noted: #374 found the database saturates past about four jobs on a full-width recompute.

## Not in scope

Making classify, connect or persist themselves faster; parallelism inside a group.

## Errors Encountered

| Error | Resolution |
|-------|------------|

## Plan review (Plan agent, 2026-10-28)

Ten findings, saved here in brief. The database side is safe to run concurrently: fresh's
classify and connect name every scratch table from their `table`/`to` argument (the group's
working schema) or put it in `pg_temp`; persist deletes by group, and the persist tables' keys
include `watershed_group_code`, with no foreign keys or triggers.

- Blocker 1, widths overwrite each other's timing in one `--out`: each width gets its own
  `--out` (`j<N>/`).
- Blocker 2, #404's `analyze.R` matches `built_at` to log lines: the new `analyze.R` parses
  the "done in" lines directly, and worker lines keep that format. `built_at` now carries
  the group's finish time from the worker.
- Helpers on workers: the export list is explicit (`variant_helpers`), the master's `conn`
  is never exported, and each worker opens its own after the exports.
- A killed build records none of the variant's groups: stated in the header.
- Comparator proof: `compare.R` also perturbs one digest and requires a failure.

## `could not truncate file … Input/output error` is the mount, not the change

The smoke run logged two of these Postgres warnings. The container log holds ten since
2026-10-21 (21, 27 and 28 Oct, during serial runs too). The data directory is a Docker Desktop
grpcfuse bind mount, 91 % used with 351 GB free. Postgres warns and completes the drop.

## Smoke and mutation (scratch `--out`, `--wsgs=REVL,UBTN`, base `score404_*`)

- `--jobs=2`: both passes completed, and the REVL digests equal #404's (`default`
  `778f7c72`, `bt_rear_wet_p10` `15073c87`). `built.csv` and `variant_timing.csv` were
  written in group order, with a `pass_wall` row per variant.
- UBTN's base digest corrupted, `--jobs=2`: exit 1, the build names UBTN, `built.csv` holds
  `default` REVL only, the variant pass never ran, and no worker was left running.
- The same at `--jobs=1`: exit 1 at UBTN, with REVL recorded, as before the change.

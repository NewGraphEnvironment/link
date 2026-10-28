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

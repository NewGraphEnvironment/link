# Findings — #372

## Issue context


## Problem

Each provincial run is the first time some newly landed code meets every group. On 2026-10-23 the near-river walk (link 0.67.0 / fresh 0.42.0, #364) had been built and scored on ADMS, BULK, CHWK, CLWR and SQAM; the run was its first contact with OKAN and KTSU, and the dispatcher lost about five hours to those two groups while three cloud hosts idled. Whether or not the walk itself was the cause (see the #361 record), the pattern is general: a rule's cost and its correctness are driven by an input the test groups did not carry (here, lake connector length and lake-centreline density), so a happy-path group set cannot find it before the ten-hour run does.

Operator, 2026-10-23: "Provincial runs should prob be pretended with scoped tests to be sorted we have a working system before running for 10hrs to find out."

## Proposal

A pre-run gate, run on the dispatcher before `study_area_run.sh` spends anything, that models a small set of groups chosen by the inputs that drive the code changed since the last run, and refuses the launch when any of them fails or takes more than k× its last-run minutes.

- **Picking the groups is the method, not a fixed list.** For each rule or pipeline step changed since the last run's link SHA (`git log <last_run_sha>..HEAD -- R/`), name the input that drives its cost or its branches, and take the 2 or 3 groups at the extreme of that input from the database (e.g. longest connector run per group for the near-river walk; most PSCIS crossings per group for the pick; most dams for the placeholder rule). Record the pick and its query in `data-raw/logs/provincial_<issue>/pretest.md`.
- **The time bound is per group against its own history**: the group's newest `log` minutes in the persist schema, times a factor (3× is a start; KTSU was 50×).
- **Where it runs**: m1, into a scratch schema (`fresh_pretest_<issue>`), with the run's config and flags, under a statement timeout (#371), so a stall is a failure within minutes, not a wait.
- **What it is not**: a parity or correctness test. The variants harness and `habitat_validate.R` keep that job. This gate asks only "does every changed path run to completion at a sane cost on the groups most likely to break it".

## Acceptance

- `data-raw/pretest_run.sh --since=<sha> --config=default` (name open) prints the changed files, the inputs chosen, the groups picked, models them into the scratch schema, and exits non-zero on a failure or a time bound breach.
- Re-run against link 0.68.0 with `--since=<0.66.6 sha>`: it must pick OKAN or QUES (longest connectors) for the near-river walk, and the result on them is recorded.
- `study_area_run.sh` header and RUNBOOK §8d say the gate precedes a provincial run.

## Related

#361, #364 (the walk), #367 (the pick), #371.


## What exploration found (it shaped the phases)

- **The walk's cost input is computable, and it ranks QUES first.** fresh's `frs_near_river()`
  (`fresh/R/frs_near_river.R:142-152`) sizes its prefilter as `conn_max`. That is the longest
  1400/1450 connector run per waterbody on main flow, plus the longest on a side line. The same
  query run per group on `whse_basemapping.fwa_stream_networks_sp` (2 s) gives QUES 63.3 km,
  TAKL 32.3 and CHIR 25.0. OKAN is not in the top 12, so the acceptance criterion's "OKAN or QUES"
  is met by QUES. OKAN's 4 h did not reproduce (#361), so nothing should be expected to pick it.
- **Most of the cost-relevant change sits in fresh, not `R/`.** From 0.66.6 to 0.68.0 the walk
  arrived with the fresh pin (v0.39.0 to v0.42.0). So the changed set is link's
  `R/` and `inst/extdata/configs/<config>/`, plus the files changed in fresh between the two
  `Remotes:` pins, read from the fresh checkout beside link.
- **History is per group.** The minutes come from the packer's query
  (`study_area_buckets.R:333-339`): the newest finished `log` row per group, with the `host` that
  ran it. `fresh_default.log` holds one run_uid, `20261023_074321-24d85e8c`, at link `1d00c04c`.
  That row is the default `--since`.
- **`wsg_run_one.R` already provides** the schema override (`LNK_SCHEMA`), the statement bound
  (`PGOPTIONS` / `LNK_STATEMENT_TIMEOUT_MIN`), `TIMEOUT` naming, the downstream guard mode and the
  stall hook (`LNK_TEST_STALL_WSG`). The gate reuses all of these and adds no modelling code.
- **Test pattern:** `data-raw/` helper libraries are `sys.source()`d by `tests/testthat/test-study_area_*.R`
  and skip under R CMD check (`test-study_area_packing.R:10-21`).


## Errors Encountered

| Error | Resolution |
|-------|------------|

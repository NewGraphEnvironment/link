## Outcome

`data-raw/habitat_variants_build.R --jobs=N` (1 to 16, default 1) runs a threshold variant's
groups on a PSOCK cluster, one connection per worker, longest groups first, while variants
stay sequential and only the build process writes `built.csv` and `variant_timing.csv`. Each
group's pass became `variant_pass()`, which returns its timings, digest and any error and writes
no file. Four rounds of code review shaped the failure handling. A repeated `--wsgs` group
would have gone to two workers. NA meant both "no check" and "the base digest is NA". A killed
worker's Postgres backend keeps writing its group, and so does every sibling when one worker
dies. `clusterApplyLB()` returns `NULL` for no tasks. Round 3 named the mechanism, that the
build took its own end for the end of a group's work. It enumerated what a pass holds and
what sentinels it decides on, 21 rows, and round 4 walked every row, which ended the loop.

## Measurement

On #331's nine groups on m4, from #404's surviving base, at widths 1, 2, 4 and 8 (21:57 to
22:29 UTC, host load 7 to 17 from another process): 45 of 45 digests were identical across
the widths. `--jobs=4` took `bt_rear_wet_p10`'s pass from 6.23 to 2.10 min and the `default`
pass from 8.06 to 3.02, against this run's longest-first bound of 1.73 and 2.12. On #331's
12-rung ladder that saves about 55 of 83 min, where #404 estimated 53. Eight jobs add only 10
to 13 % over four: classify and connect contend in the database (30 to 41 % more summed
minutes at four jobs, 48 to 89 % at eight), and persist does not. That matches #374's ceiling
of about four jobs on the recompute. So `--jobs=4` is the width for a ladder, and the default
stays 1. Postgres's `could not truncate file … Input/output error` turned up during a smoke run
and was traced to the Docker Desktop bind mount (ten such warnings since 2026-10-21), not to
this change.

## Evidence

`data-raw/logs/variants_parallel_406/` (its README): `j*/`, `digests_j*.csv`, `compare.csv`,
`wall.csv`, `steps.csv`, `launch_state.txt`.

Closed by: release commit a13af341 on branch `406-variants-harness-run-a-variant-s-groups` (PR to follow)

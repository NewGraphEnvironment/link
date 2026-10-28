# variants_parallel_406 — a variant's groups in parallel (#406)

## Run decision (written before any build)

- **What is measured.** `habitat_variants_build.R --step=variants` at `--jobs` 1, 2, 4 and 8:
  the `default` pass and `bt_rear_wet_p10`'s pass over #331's nine groups, with each pass's
  wall minutes (`pass_wall`) and per-step seconds. The question is how much width buys and
  where the database stops paying, against #404's greedy bound (1.6 and 1.8 min at four jobs)
  and #374's ceiling of about four jobs on a full-width recompute.
- **The base is #404's, reused.** `score404_default` and `working_score404_<wsg>` (built
  2026-10-28 at `45b12b2e`, fresh 0.44.0) still sit on m4. A variants step reads them and
  rebuilds nothing of the base. Each width builds into its own `--out` (`j<N>/`), into which
  #404's `base_habitat_digest.csv` and `closure.txt` are copied, so no width overwrites
  another's timing rows. Every width writes the same schema, `score404_bt_rear_wet_p10`.
- **Order.** Widths 1, 2, 4 then 8, one after another. After each, `digest.R` writes
  `digests_j<N>.csv`: the variant schema's `streams`, `streams_access` and
  `streams_habitat_bt`, each working schema's `streams_habitat`, and the base's
  `streams_habitat_bt` as a control. `compare.R` then requires every digest identical across
  the widths. It must fail on a perturbed digest and see the base against the variant as
  different, or it stops.
- **Host and software.** m4 (Apple M4 Max, 16 cores, 128 GB), local docker fwapg
  (`fresh-db`, `max_connections` 40). fresh 0.44.0 (the pin). link from a `git worktree` at
  the branch commit the stamp names, so this checkout can take commits while it runs.
- **Load from elsewhere.** At planning (14:56 PDT) the host's load average was 5.4 / 5.4 / 4.9
  with no other client on the database. Each timing row carries the 1-minute load at its
  pass's start, and `launch_state.txt` holds the load and other database clients at each
  width's launch.
- **Schemas stay**, as every `score*` schema has.

## Files

| file | what it is |
|---|---|
| `run.sh` | the four builds and their digests, in order, with each launch's state |
| `j<N>/` | the build at `--jobs=N`: `build.log`, `built.csv`, `variant_timing.csv`, `stamp_build.txt`, `bundles/`, and the copied base files |
| `digest.R` → `digests_j<N>.csv` | md5 per schema, table and group after each build |
| `compare.R` → `compare.csv` | every digest across the four widths, with its two self-checks |
| `analyze.R` → `wall.csv`, `steps.csv` | wall minutes per pass and width; summed step minutes per width |
| `launch_state.txt` | load and other database clients at each launch and at the end |

## What happened during the builds

`run.sh` ran the four widths one after another from the worktree at `0d70696b` (every
`stamp_build.txt`), from 21:57:21 to 22:29:51 UTC, with no other client on the database at
any boundary (`launch_state.txt`). Later commits on the branch (code-check rounds 1 to 4)
de-duplicate `--wsgs`, refuse an NA base digest, log the workers' R and backend pids, word the
orphan remedy and route a variant with no groups to the serial branch. None of these changes
what these four builds did. The final code was smoke-tested afterwards at `--jobs=4` on REVL,
UBTN, UARL and LHAF. It gave the same working digests as the `--jobs=4` build here and left
every persisted digest unchanged. A variant with no groups also ran through at `--jobs=2`.

| build | launched (UTC) | the script's own "done in" | host load (1 min) at launch |
|---|---|---|---|
| `--jobs=1` | 21:57:21 | 14.3 min | 10.5 |
| `--jobs=2` | 22:11:45 | 8.0 min | 8.9 |
| `--jobs=4` | 22:19:52 | 5.2 min | 9.5 |
| `--jobs=8` | 22:25:08 | 4.6 min | 17.4 |

The host carried load from elsewhere throughout: 5.4 at planning with nothing of ours
running, and 7 to 17 at the passes' starts, the highest during the `--jobs=8` build, whose
own eight workers and backends are part of it. Three Postgres warnings,
`could not truncate file … Input/output error`, appear in the `j1` and `j2` logs. The
container's log holds ten since 2026-10-21, during serial runs too. They come from the data
directory's Docker Desktop bind mount, and Postgres completes the drop.

## Measurement

**Every digest is identical across the four widths:** 45 of 45 (`compare.csv`). Those are
the variant schema's persisted `streams`, `streams_access` and `streams_habitat_bt`, plus
each working schema's `streams_habitat`, for nine groups. The comparison can fail: it
rejects a perturbed digest, and it reads the base's BT habitat against the variant's as
different in all nine groups.

**Four jobs take a variant's pass from 6.2 to 2.1 min and the `default` pass from 8.1 to
3.0** (`wall.csv`; first dispatch to last return, discharge join included):

| pass | width | wall (min) | speed-up | summed step minutes | load at start |
|---|---|---|---|---|---|
| `bt_rear_wet_p10` | 1 | 6.23 | 1.00 | 5.75 | 7.3 |
| | 2 | 3.36 | 1.85 | 5.93 | 7.9 |
| | 4 | 2.10 | 2.97 | 7.05 | 9.7 |
| | 8 | 1.82 | 3.42 | 8.62 | 12.0 |
| `default` | 1 | 8.06 | 1.00 | 7.65 | 10.5 |
| | 2 | 4.60 | 1.75 | 8.23 | 8.9 |
| | 4 | 3.02 | 2.67 | 10.28 | 9.2 |
| | 8 | 2.72 | 2.96 | 13.95 | 17.4 |

The serial pass is #404's again once the join is counted: 6.2 min for the variant against
5.6 + 0.6 there, and 8.1 for `default` against 6.8 + 0.8.

**Past four jobs the database stops paying.** This run's own longest-first bound, from its
serial per-group minutes, is 1.73 min for the variant at four jobs and 2.12 for `default`;
four jobs reach 2.10 and 3.02. The gap is contention in classify and connect: their summed
minutes grow 30 to 41 % at four jobs and 48 to 89 % at eight, against one (`steps.csv`). Persist does
not grow (1.35 min serial, 0.87 at four jobs). Eight jobs buy 13 % on the variant and 10 %
on `default` over four, for 22 % and 36 % more summed step minutes. That is #374's finding on the
recompute (the database saturates past about four jobs), here on the variant pass.

**On #331's ladder** (12 rungs and the `default` pass), four jobs save
12 × (6.23 − 2.10) + (8.06 − 3.02) = 54.6 min of 82.8 serial, leaving 28.2. #404 estimated 53.

**Verdict.** `--jobs=4` is the width to use for a tuning ladder on m4. The default stays 1,
so a build that does not ask for width runs as it did. Eight jobs are not worth their load
on a shared host.

## Evidence

`data-raw/logs/variants_parallel_406/`: this directory. The builds are in `j1/`, `j2/`, `j4/`
and `j8/` (`build.log`, `built.csv`, `variant_timing.csv`, `stamp_build.txt`, `bundles/`),
and their boundaries in `launch_state.txt`. The digests are `digests_j*.csv` →
`compare.csv`, and the timings `analyze.R` → `wall.csv`, `steps.csv`. The planning archive
is `planning/archive/2026-10-issue-406-*/`.

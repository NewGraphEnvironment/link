# Phase times per host (link#375)

Dispatcher-only runs of `data-raw/study_area_run.sh --buckets-exact --focal=NBNK,EUCH
--config=default --schema=fresh_375`, made on 2026-10-24 UTC from a worktree at
`e118c0b5`, on the local docker fwapg. The scratch schema `fresh_375` was dropped
afterwards. Another session was running a query on the database the whole time.

| run | file | result |
|---|---|---|
| full run `20261024_033035-1ecf477d` | `driver_run.out`, `20261024_033035_phases.tsv` | one row per phase: `prep`, `model dispatcher`, `account`, `coverage`, `views`, `recompute`, `compare` `ok`; `refresh`, `consolidate`, `burn` `skipped` with blank times. Critical path 2.2 min, longest model leg 1.6 min. Exit 0 |
| `--recompute-only --run-uid=20261024_033035-1ecf477d` | `driver_recompute_only.out`, `20261024_033312_phases.tsv` | its own file, under the finished run's uid: `prep` (its preamble), `coverage`, `views`, `recompute`, `compare`, all `ok`. Exit 0 |
| killed run `20261024_033333-71471db8` (SIGTERM to the driver 22 s into `model`) | `driver_kill.out`, `20261024_033333_phases.tsv` | the EXIT trap wrote `model dispatcher failed` at 03:34:02 and printed the table; exit 143. The leg, which the kill does not stop, finished both groups and wrote its own `ok` row at 03:35:05 with the same start |

## The rows against the database's own times

From `fresh_375.log` and `fresh_375.log_recompute` for the full run:

| row | phases.tsv | database |
|---|---|---|
| `model dispatcher` | 03:30:43 → 03:32:21 | NBNK 03:30:45.7 → 03:31:33.4, EUCH 03:31:35.3 → 03:32:22.0 (`log.date_start` / `date_end`) |
| `recompute` | 03:32:24 → 03:32:36 | 03:32:26.4 → 03:32:36.0 (`log_recompute`) |

Each row brackets what the database recorded, to the second. The console's
`[phase]` lines are printed from the same rows, so they match the file by
construction; the database is the independent check. File mtimes cannot serve:
the EXIT trap's address redaction rewrites every log at exit (all three read 03:32:45).

Not exercised here: the cypher legs, their prep rows, `consolidate` and `burn`
with hosts. A structural test pins their wrappers
(`tests/testthat/test-study_area_phases.R`, "each model and prep leg re-raises its
own exit status"); the next provincial run is their first real exercise, and its
`phases.tsv` fills #377's runs row.

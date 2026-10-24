# A bounded modelling statement (link#371)

These are dispatcher-only runs of `data-raw/study_area_run.sh --buckets-exact` into a
scratch schema, `fresh_371`, dropped afterwards. They were made on 2026-10-24 UTC, on
the local docker fwapg, with `--config=default`. A second session was loading the
database at the time, so the bound was 2 min, not 1.
`LNK_TEST_STALL_WSG` stalls one group on `SELECT pg_sleep(3600)` until the bound
cancels it.

## `run2_nbnk_euch/`: acceptance criterion 1, on the branch's final code

| step | run_uid / command | result |
|---|---|---|
| run | `20261024_012623-309b2f46`, `--focal=NBNK,EUCH --statement-timeout=2`, `LNK_TEST_STALL_WSG=EUCH` | banner shows `statement:` and `TEST HOOK:`; both groups print `statement_timeout=2min`; EUCH prints `TIMEOUT after 2min: SELECT pg_sleep(3600) -- LNK_TEST_STALL_WSG` and the driver's `[WARN] … failed (continuing)`; NBNK is done in 0.7 min, recomputed and compared; INCOMPLETE names EUCH under `no rows` and `statement bound hit`, with the statement; the printed re-model carries `PGOPTIONS`; exit 1 |
| re-model | the printed command, run without `LNK_TEST_STALL_WSG` | EUCH done in 0.8 min, rc 0 |
| finish | `--recompute-only --run-uid=20261024_012623-309b2f46` | recompute 2/2, compare CSV written, `study_area_run done`, exit 0 |

Files: `driver_run.out`, `remodel_EUCH.out` and `driver_recompute_only.out` are the
console output. `20261024_012623_*` is the run and `20261024_013025_*` is the
`--recompute-only` pass.

## `run1_musk_leut/`: the first attempt, on the code before the review fold-in

- Run `20261024_011513-4e796a4c` (MUSK, plus LEUT stalled) showed the same
  stall, naming and INCOMPLETE behaviour.
- Its `--recompute-only` then exited 1, for two reasons outside #371:
  - LEUT's recompute stopped at the #227 downstream guard, because a blocking dam
    lies downstream of it in a group not in the two-group scratch schema;
  - the compare had nothing to compare, because MUSK is RB-only under `default` and
    the bcfishpass reference has no RB.
- Run 2 uses groups that pass the guard on an empty schema and carry species the
  reference has.

## Bound check probes (on `wsg_run_one.R`, not a run)

These were run with `LNK_LOAD=loadall LNK_SCHEMA=fresh_371 LNK_GUARD_DOWNSTREAM=warn`
on MUSK:

```
PGOPTIONS=3min, LNK_STATEMENT_TIMEOUT_MIN=5  -> statement_timeout=3min; Error: ... is 3min: PGOPTIONS did not reach it
no PGOPTIONS,   LNK_STATEMENT_TIMEOUT_MIN=30 -> statement_timeout=0;    Error: ... is 0: PGOPTIONS did not reach it
PGOPTIONS=1min, LNK_STATEMENT_TIMEOUT_MIN=1, LNK_TEST_STALL_WSG=MUSK
                                             -> statement_timeout=1min; TIMEOUT after 1min: SELECT pg_sleep(3600) ...  (01:24:48 -> 01:25:49 UTC)
PGOPTIONS=60min (psql)                       -> SHOW reads 1h; pg_settings reads 3600000 (why the check compares ms)
```

Earlier, before `LNK_STATEMENT_TIMEOUT_MIN` existed, ADMS gave `statement_timeout=3s`
with `PGOPTIONS='-c statement_timeout=3s'` and `0` without it. That was the control
showing that `PGOPTIONS` reaches RPostgres's connection.

## Setting the default

The longest group of `20261023_074321-24d85e8c` that finished took 16.3 min (SETN),
then LNAR at 13.8 and BULK at 13.7 (`fresh_default.log`, `date_end - date_start`).
KTSU's 65.4 min is the stall itself. No statement outlasts its group, so the default
of 30 min is at least 1.8x the longest statement. Cyphers ran up to 2.9x the
dispatcher's time, measured by the plan review, so raise the bound when a top group
is placed on a cypher by hand.

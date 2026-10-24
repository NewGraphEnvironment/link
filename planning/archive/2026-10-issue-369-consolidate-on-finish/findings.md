# Findings — study_area_run.sh: consolidate each cloud host when its own leg finishes, then burn it (#369)

## Issue context

## Problem

`study_area_run.sh` waits for every leg (the dispatcher's and each cloud host's) before it consolidates anything, then consolidates every host in one call, then burns them (`data-raw/study_area_run.sh`, the `wait $LOCAL_PID` / `host_wait` block before "completeness accounting"). So a cloud host that finished early sits idle, paid, holding the only copy of its groups, until the slowest leg ends and the whole consolidate completes.

Measured on the two provincial `default` runs:

| run | cloud legs done | longest leg | idle cloud time | consolidate |
|---|---|---|---|---|
| `20261017_004619-3f4c713b` | job1 171, job2 207, job3 277 min | job3 (277) | job1 106 min, job2 70 min, plus the 46 min consolidate for all three | 46 min, serial, after every leg |
| `20261023_074321-24d85e8c` | all three by 12:27 UTC (57 / 68 / 42 groups, no failures) | the dispatcher, stalled 4 h in one group (#361) | about 6.5 h × 3 hosts, about $5 at $0.25/h | pending at filing |

Each host was holding 3.4 to 4.1 GB of persisted tables (8.2 to 10.1 GB with indexes) for that whole time, with the #347 hold rules as the only thing between a driver fault and losing them.

## Proposal: consolidate each cloud host when its own leg finishes, then burn it

Per cloud host, as soon as its `host_wait` returns: run the completeness accounting for that host, consolidate that one source into the persist schema, apply the #347 release check (no finished group's `streams` rows left on the host), and burn it. The dispatcher's leg keeps modelling meanwhile; its own groups need no consolidate. The last consolidate, the recompute and the verify run as they do now.

What this buys, from the numbers above:

- **Idle cloud time goes to about zero** on every run, whichever leg is the long pole. On 2026-10-17 that is about 3 host-hours; on 2026-10-23, about 20.
- **Wall clock drops by most of the consolidate.** The 46 min of 2026-10-17 overlaps the longest leg instead of following it; only the last host's copy stays on the critical path.
- **Exposure shrinks.** A host holds the sole copy of its groups for minutes after it finishes, not hours. The #347 incident (18 finished groups nearly burned) and the #358 refused-source path both get a smaller window.

Nothing new is needed on the hosts: consolidate already streams `COPY` over ssh per source (#180, #185), and the persist tables replace per group (`DELETE … WHERE watershed_group_code` then `INSERT`), so copying job1's groups into `<schema>` while the dispatcher is writing its own groups to the same tables is the same per-group replace the design already relies on.

## What has to change, and the decisions in it

- **`study_area_run.sh`:** the single post-all-legs consolidate becomes a per-host step triggered by that host's `host_wait`, with the dispatcher's `wait $LOCAL_PID` moved after them. The completeness accounting, `<TS>_consolidate_state.tsv` (`in_flight` before the copy, #358), `CONSOLIDATING`, and `kept_hosts.tsv` are already per source and keep working; the `CONSOLIDATING` flag becomes per host so the EXIT trap can still tell which host has a write in flight.
- **The pre-consolidate backup.** `schema_consolidate(backup = TRUE)` dumps the destination before the copy; today that is one dump per run (the one #354 restored log rows from). Per-host consolidate would take one per host unless the backup is taken once, at the first consolidate. Proposed: once, before the first host's copy; the dispatcher's groups written after that are in its own log and are rebuilt by the recompute anyway.
- **Load on the dispatcher's database while it models.** Each copy is a few GB of `COPY` in plus index maintenance on tables the dispatcher is writing to. Measure the modelling minutes of the groups that overlap a copy against the same groups' minutes on 2026-10-23; if it costs more than it saves, the copy can be rate-limited or held until the dispatcher's current group finishes.
- **`--keep-cyphers`** keeps its meaning: consolidate on finish, do not burn.
- **A host that fails its consolidate is kept, as now**, and the run goes on. The difference is that the failure surfaces hours earlier, while the operator is still watching.

## Why not stage through S3 (#170)

#170 proposed routing dumps through S3 so a host could burn the moment its upload completed. Costed at today's prices it does not pay: about 4 GB of compressed dumps per run is about $0.40 in egress, against $0.75 per idle hour for three hosts, so it breaks even at about 30 minutes of idle, and with consolidate-on-finish the idle is minutes, not hours. It also adds a dump, an upload, a verified download and a restore to a path that today is one streamed `COPY`, and a second "data is safe" test before burn. The one case it still covers is a dispatcher that cannot accept the copy when a host finishes (database down, disk full); that has not happened, and the #347 hold already keeps the host in that case. #170's premises (a separate consolidate host, serialized `scp` of dump files, a slow tailnet hop) no longer describe the driver.

## Acceptance

- Per-host consolidate and burn on a real multi-host run: each cloud host is burned within minutes of its leg finishing; `<TS>_consolidate_state.tsv` shows one `ok` row per host with timestamps inside the dispatcher's modelling window; `kept_hosts.tsv` empty.
- `study_area_verify.sql` and `verify_extra.sql` pass at the run's `expected_n` with one `config_hash` and every group's newest `log` row from the run, so overlapping copies lost nothing.
- The modelling minutes of dispatcher groups that overlapped a copy are reported against the same groups' 2026-10-23 minutes.
- RUNBOOK §8d ("Which host may be burned") and the header of `study_area_run.sh` say that a host is consolidated and burned when its own leg finishes, and why the backup is taken once.
- A kept host still appears in `kept_hosts.tsv` with the burn command when its consolidate fails (negative test: refuse one source's consolidate and check the row).

## Related

- #347 (which host may be burned), #358 (a refused source costs only its groups), #170 (S3 transit, the option costed above), #361 (the run that measured the idle hours).


## Errors Encountered

| Error | Resolution |
|-------|------------|

## Phase 1 measurements (2026-10-24)

### Lock experiment (local docker fwapg, PostgreSQL 17.5, scratch schema; lock_timeout 3 s)

| holder's lock | probe | result |
|---|---|---|
| ROW EXCLUSIVE (a `COPY` in flight) | `CREATE INDEX IF NOT EXISTS`, index present | **blocked** |
| ROW EXCLUSIVE | `ALTER TABLE … ADD COLUMN IF NOT EXISTS`, column present | **blocked** |
| ROW EXCLUSIVE | `DELETE` + `INSERT` of one group (persist's replace) | passes |
| ACCESS SHARE (`pg_dump`) | `CREATE INDEX IF NOT EXISTS`, index present | passes |
| ACCESS SHARE | `ALTER TABLE … ADD COLUMN IF NOT EXISTS`, column present | **blocked** |
| ACCESS SHARE | `DELETE` + `INSERT` | passes |

Both no-ops lock their table before they find the work done. `lnk_persist_init()` runs once per group on the dispatcher and issued 8 index statements on the persist tables plus, through `.lnk_log_create_tables()`, an `ALTER` per log column and 6 log indexes. So a dispatcher group starting while a consolidate copied into `streams` waited for that table's `COPY` to commit, and the wait counts toward the 30 min statement bound. A `pg_dump` taken while the dispatcher models would stall each group's log `ALTER` for the whole dump. Script: scratchpad `lock369.sh` (not committed; the test below is the durable form).

**Fix:** existing index names come from `pg_indexes` and existing columns from `information_schema.columns`, read once per call; neither locks a user table. An index or column already there is not issued. An unreadable or empty catalog names nothing, so everything is issued with `IF NOT EXISTS`, as before. Tested live (`test-lnk_persist_init.R`, "an up-to-date persist schema waits on no other session's write"): a second session holds ROW EXCLUSIVE on every persist and log table, and a second `lnk_persist_init()` completes under `lock_timeout = 2s`. With the catalog reads mocked away, the same call fails with `lock timeout`.

### The backup's cost

`pg_dump -Fc --schema=fresh_default` (241 groups, 14 GB of tables): **457 s (7.6 min), 4.6 GB**, on m1 with nothing else running. That is what taking the backup before the dispatcher leg adds to the dispatcher leg. The 2026-10-23 run's dump at consolidate time took about 1.6 min for 1.06 GB (`/tmp/fresh_default_pre_consolidate_202610231023.dump`), when the dispatcher's groups alone were in it.

### How long a copy holds a table (2026-10-23 consolidate log)

The per-source copy ran 12.7 min (job1, 57 groups), 13.9 min (job2, 68) and 12.9 min (job3, 42) for 20 tables each, then 0.5 min for the source cleanup; the log has no per-table times. The largest table is `streams` at 2.9 M rows for job1. So any one table's `COPY` held its lock for minutes, under the 30 min bound but long enough to stall a dispatcher group repeatedly; the fix above removes the wait rather than relying on the margin.

## Run A — per-host consolidate and burn on real droplets (2026-10-24)

run_uid `20261024_072631-73621c49`, branch `369-run` at `8d0a1822`, config `default`, scratch schema `fresh_smoke369`, `--buckets-exact`: dispatcher 12 groups, job1 NBNK, job2 MBNK, KEEC, KAKC, PITR, VICT. Evidence: `data-raw/logs/consolidate_on_finish_369/run_A/`.

| host | model end (UTC) | consolidate | burn end | before dispatcher model end |
|---|---|---|---|---|
| job1 | 07:37:46 | 07:37:48–07:38:16 (0.5 min) | 07:38:45 | 12.8 min |
| job2 | 07:43:32 | 07:43:34–07:44:26 (0.9 min) | 07:44:59 | 6.5 min |
| dispatcher | 07:51:30 | — | — | — |

- Each host was burned within about 1 min of its leg ending; `consolidate_state.tsv` rows are `ok` at 07:38:15 and 07:44:25, inside the dispatcher's model window (07:35:45–07:51:30); no `kept_hosts.tsv`; doctl shows no job droplet; recompute 18/18; consolidate tail 0.0 min; critical path 26.1 min.
- **Overlap cost:** the four dispatcher groups that modelled during a copy ran 1.02–1.37× their 2026-10-23 minutes (median 1.11), the eight that did not 0.68–1.73× (median 1.19): no slowdown visible at this size (1- and 5-group copies). `run_A_overlap_minutes.tsv`. The provincial-scale measurement is owed.
- **Two defects found, both fixed after Run A:**
  - `study_area_verify.sql` failed: the 12 dispatcher rows had `link_sha` NULL. The dispatcher ran from a git worktree, and `.lnk_read_git_head()` looked for the branch ref beside the worktree's private HEAD instead of in the common dir (or `packed-refs`). Pre-existing, and it hits every worktree run CLAUDE.md recommends.
  - The dispatcher, now accounted after the copies, read the six copied-in cypher groups in its own log as "finished outside its bucket". Harmless to the result (they were finished), misleading in the report.

## Run B — a refused host is kept and listed (2026-10-24)

run_uid `20261024_075836-321a58e2`, branch `369-run` at `a414d72b`, scratch schema `fresh_smoke369b` with a future-dated MILL log row seeded (`seed369b`). Dispatcher LNRS; job1 MILL, LPET. Evidence: `data-raw/logs/consolidate_on_finish_369/run_B/`.

- job1's consolidate refused at `dest_log_newer` before deleting anything; the host was kept; `kept_hosts.tsv` names LPET, MILL (`groups_measured` yes) with the burn command; state `failed:dest_log_newer`; coverage named both `not_consolidated`; LNRS was still recomputed; the run ended INCOMPLETE.
- The listed burn command was then run by hand (`run_B_manual_burn.log`); doctl shows no job droplet.
- The dispatcher row now carries `link_sha a414d72b`, `link_dirty f`, from the worktree: the stamp fix holds.
- The compare failed for a reason outside #369: LNRS models only RB, which the bcfishpass reference does not carry, so a run whose only compared group is LNRS has nothing to compare.
- Host addresses: the driver's `${TS}_*` files held only `0.0.0.0` after its own redaction; the launcher's stdout and the manual-burn log are outside that glob and were redacted when copied.

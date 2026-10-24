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

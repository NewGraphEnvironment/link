## Outcome

`study_area_run.sh` now accounts, consolidates, releases and burns each cloud host as soon as its own leg ends (`data-raw/study_area_legs.sh`: `legs_wait` over `wait -n -p`), while the other legs keep modelling. Previously every host waited for the slowest leg and one consolidate of all of them. The dispatcher's persist is initialised and backed up once, before any leg writes (the operator's choice at the gate), with the dump in the background through spin and prep. The plan review found four blockers before any code was written:

- the backup failed on a schema that did not exist yet;
- a host consolidated into an uninitialised schema copied only the log tables, reported success and deleted its source log rows;
- a bucket overlap in closure mode would race the dispatcher's own writes, so overlapping hosts now wait for the dispatcher leg;
- bash 5.3's `wait -n -p` returns an already-returned job again.

A lock experiment showed that the dispatcher's per-group no-op DDL (`CREATE INDEX IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`) blocks behind a consolidate `COPY`, so `lnk_persist_init()` and the log-table setup now read the catalog first. Three small live runs on real droplets confirmed the behaviour and found two more defects:

- a dispatcher run from a git worktree logged `link_sha` NULL (`.lnk_read_git_head()` read the branch ref beside the worktree's HEAD; this predates #369);
- the dispatcher, accounted after the copies, claimed the cyphers' groups.

Code-check ran three rounds. Round 3 named the shared mechanism (each step read shared state at a moment the old fixed sequence made safe) and found one more defect inside a fix, a relative `gitdir:` pointer. The loop ended by enumeration.

## Measurement

- **No-op DDL blocks** (PostgreSQL 17.5, lock_timeout 3 s): `CREATE INDEX IF NOT EXISTS` and `ALTER TABLE … ADD COLUMN IF NOT EXISTS` both block behind ROW EXCLUSIVE (a `COPY`); the `ALTER` also blocks behind ACCESS SHARE (`pg_dump`). Per-group `DELETE` + `INSERT` passes both. After the fix, a live test holds ROW EXCLUSIVE on every persist and log table and a second `lnk_persist_init()` completes under `lock_timeout = 2s`.
- **Backup cost:** `pg_dump -Fc` of `fresh_default` (241 groups, 14 GB of tables) takes 7.6 min and writes 4.6 GB. It runs during spin and prep (9 to 10 min in Runs A and C), so it is off the critical path.
- **Per-host consolidate and burn**, Runs A and C: each cypher was consolidated in 0.5 min (one group) or 0.9 min (five) and burned about 0.5 min later. Both cyphers were gone 6.5 to 34.5 min before the dispatcher leg ended. The consolidate tail was 0.0 min in both runs.
- **Overlap cost:** dispatcher groups modelling during a copy ran at a median 1.11× their 2026-10-23 minutes; the rest ran at 1.19×. No slowdown is visible at this size; the provincial-scale number is owed.
- **A wrong turn worth keeping:** Run C's dispatcher leg took 37.7 min against Run A's 15.8. One group, EUCH, took 21.9 min against 1.09, beside another session's four-worker query on the same database, after both copies had finished. That is not a cost of #369; it is the shape of the 2026-10-23 OKAN stall.
- Full suite at the end: 4030 passed, 0 failed, 0 skipped.

## Evidence

`data-raw/logs/consolidate_on_finish_369/` (its README indexes Runs A, B and C). Plan review and code-check rounds: `review-plan.md`, `review-round[1-3].md` in this directory.

## Owed

- On the next provincial `default` run: idle cloud minutes per host, consolidate rows inside the modelling window, and the dispatcher groups that overlapped a copy against their 2026-10-23 minutes. Fill #377's runs row.

Closed by: PR for branch `369-study-area-run-sh-consolidate-each-cloud`

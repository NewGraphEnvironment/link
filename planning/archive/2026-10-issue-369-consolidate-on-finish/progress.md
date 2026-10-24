# Progress — study_area_run.sh: consolidate each cloud host when its own leg finishes, then burn it (#369)

## Session 2026-10-23 / 24

- Plan-mode exploration — phases approved by user (2026-10-23); gate: backup before the dispatcher leg; live check on little groups
- Created branch `369-study-area-run-sh-consolidate-each-cloud` off main
- Scaffolded PWF baseline from issue #369 with approved phases
- Operator, 2026-10-24: run all phases, launch the cyphers without waiting, poll so a hung run is caught
- Next: start Phase 1
- Phase 1: lock experiment shows both no-op DDLs (index, log column) block behind a COPY's lock, and the ALTER behind pg_dump's; fixed in `lnk_persist_init()` / `.lnk_log_create_tables()` with catalog reads, tested live. pg_dump of fresh_default: 7.6 min.
- Plan review folded in (planning/active/review-plan.md): 4 blockers (absent schema at backup, log-only copy, closure overlap race, wait -n re-return) plus gaps, dispositions recorded
- Phase 2: bucket-scoped copy check, refuse a destination missing link's persist tables, per-table copy seconds, verify=FALSE, schema_consolidate_backup() that fails loud
- Phase 3: new `data-raw/study_area_legs.sh` (`legs_wait`, `host_finish_leg`, `host_consolidate`); CONSOLIDATING per host; `burn_cyphers ended`; per-host outcomes and state (`state_utc`, old header still read); stub-world helpers moved to `helper-study_area_hosts.R`; `hosts_bash()` needs 5.1. 56 legs tests; five mutants each caught (no deferral, unscoped burn, release after no outcome, CONSOLIDATING unset, pending list not shrinking — that one now fails by a 60 s timeout instead of hanging)
- Phase 4: driver wired. The dispatcher persist is initialised (tested on a scratch schema: 3 s, 23 tables), the backup runs in the background through spin and prep, and dispatch waits on its rc file; `legs_wait` replaces the wait, consolidate and burn blocks; dispatcher accounting after; bash ≥ 5.1 floor; prep waits on its own pids (no bare `wait`); phases: `backup` row, consolidate tail in the report
- Code-check round 1 (2 findings, both fixed): an unset `who` after `wait -n -p` returns 127 killed the driver under set -u; a deferred host was reported kept mid-run. Both pinned by tests that fail on the old lib
- Run A (run_uid 20261024_072631-73621c49, exit 0): job1 burned 07:38:45 and job2 07:44:59 UTC, 12.8 and 6.5 min before the dispatcher leg ended (07:51:30); state rows ok inside the dispatcher window; no kept hosts; recompute 18/18; consolidate tail 0.0 min. Found two defects: the dispatcher's log rows had link_sha NULL (`.lnk_read_git_head()` read a worktree's branch ref beside its HEAD, not in the common dir; pre-existing, fixed with packed-refs too), and the dispatcher's accounting claimed the copied-in cypher groups (fixed)
- Code-check round 2: one fragile point (a leftover habitat table for a species outside the config would refuse a host): the refusal is now limited to the core persist tables
- Code-check round 3: named the mechanism (each step read shared state at a moment the old fixed sequence made safe) and enumerated its 16 reach points, all handled but one: a relative `gitdir:` pointer in `.lnk_read_git_head()` (inside the round-of-Run-A fix 4), now resolved against the `.git` file's dir. The reader's input set (plain/absolute/relative pointer × detached/loose own/loose common/packed own/packed common/none) is now pinned case by case: enumeration ends the loop

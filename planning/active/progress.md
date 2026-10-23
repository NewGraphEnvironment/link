# Progress — Provincial run: can a drainage component be split across hosts now that the recompute settles access? (#361)

## Session 2026-10-22

- Plan-mode exploration — phases approved by user; gate decisions recorded in task_plan.md
- Created branch `361-provincial-run-can-a-drainage-component` off main
- Scaffolded PWF baseline from issue #361 with approved phases
- Next: start Phase 1

## Session 2026-10-23

- Phase 1: `study_area_buckets.R --minutes-schema=` weights by measured minutes; `--host-speeds`
  default equal. Split for the run: `data-raw/logs/provincial_361/buckets_default.md`, hosts at
  218 / 219 / 217 / 219 min (2026-10-17 packing measured 165 / 205 / 272 / 231). Segment weights
  at equal speeds reproduce the 2026-10-17 focal lists exactly; the 2026-10-17 split was not
  generated at 0.45x.
- Next: Phase 2 pre-flight, rename `fresh_default`, launch.
- Pre-flight (`--preflight-only`, bash 5) clean at 04:43 UTC. Two gate decisions revised with the
  operator: `--refresh-primitives` (cypher_prep loads current primitives; keeping the 10-17 load
  would split the hosts' inputs), and wait for another session's jobs (`knowledge`
  `0320-tune-run.R` / `0330-compare.R`) that read `fresh_default` live before renaming or launching.
- Phase 3 harness written and smoke-tested: `provincial_361/split_test.sh` (parses; BSD `tail -r`
  replaced, GNU tail is first on PATH here) and `split_compare.R` (ADMS vs itself: 16/16 identical,
  control differs; `fresh_default` vs `fresh_parity362`: differing branch lists columns).
  `launch.sh` holds the run command (4 focal lines, 246 groups).

## Session 2026-10-23 (launch)

- Gate revision recorded: `--refresh-primitives` (not `--vintage-max-days=10`), wait for the other
  session's two R jobs (`0320-tune-run.R`, `0330-compare.R`) before the rename.
- Pre-flight passed 04:43 UTC; both jobs exited 07:40 UTC; `fresh_default` renamed to
  `fresh_default_20261017` 07:41 UTC (no holders in `pg_stat_activity`; 174 G free).
- Next: launch `data-raw/logs/provincial_361/launch.sh` detached; monitor from the databases.

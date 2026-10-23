# Provincial run #361 — launch notes (kept out of the repo while the run is in flight)

- Other session's jobs (PIDs 39789, 46864) exited 2026-10-23 07:40:48 UTC (waiter bxwteb05z).
- `pg_stat_activity`: no backend held `fresh_default`; disk 174 G free (590 G volume, 70 % used).
- 07:41:45 UTC `ALTER SCHEMA fresh_default RENAME TO fresh_default_20261017` (241 groups).
- Commit 650040c4: gate revisions + pre-launch boxes; pushed.
- Attempt 1 (07:42:33 UTC): driver refused, "bash 3.2.57 is too old" — `launch.sh` did `exec bash`,
  which resolved to /bin/bash under nohup. No spend (version check is the driver's first line;
  `data-raw/logs/study_area_run/` has no file from attempt 1). Log kept as
  `data-raw/logs/provincial_361/run_attempt1_bash32.log`.
- Fix 1d00c04c: `exec "$BASH" data-raw/study_area_run.sh`; pushed; origin confirmed by ls-remote.
- Attempt 2 (07:43:21 UTC): run_uid `20261023_074321-24d85e8c`, link SHA 1d00c04c, driver PID 76810
  (ancestor subshell 76779 reparented to 1). `--refresh-primitives` → `snapshot_bcfp.sh --with-bcfp-views --force` first.
- Slip, no consequence: in the relaunch command the trailing `&` bound to the whole `&&` chain, so the
  commit/push ran in the background subshell. Verified afterwards.
- Untracked files under `data-raw/logs/` do not set `link_dirty` (`.lnk_git_dirty_pathspec` excludes
  `data-raw/logs` at top).
- Waiters: buz9ddug4 (first finished log row of this run_uid on m1 → check link_sha/link_dirty/fresh_sha),
  b97kim0nh (driver exit).

## To do after the run (repo untouched until then)
- progress.md entry for the launch; tick the Launch box with the run_uid and the attempt-1 note.
- Verify: `study_area_verify.sql` + `provincial_246/verify_extra.sql` at expected_n=241, run_uid above.
- Copy `run.log`, `run_verify*.log` into `data-raw/logs/provincial_361/`.

## 08:05 UTC check (waiter buz9ddug4)
- snapshot done; cyphers spun and prepped (first prep at the fresh 0.42.0 pin: OK on all 3); host parity OK
  across 4 hosts; primitives within 7 d on each cypher. m1 modelling began 08:02:43 UTC (HOLB first, 1.9 min).
- First rows: link_sha 1d00c04c, link_dirty f, fresh_sha e9793047, config_hash sha256:379e1651…, host m1.
- BEFORE COMMITTING `data-raw/logs/provincial_361/run.log` (and run_attempt1): redact addresses by hand, the
  driver's trap covers only `study_area_run/<TS>_*`:
    perl -i -pe 's/(?<![\d.])(?!0\.0\.0\.0)(?!127\.0\.0\.1)(?!0\.0\.0\.9)(\d{1,3}\.){3}\d{1,3}(?![\d.])/<host>/g' data-raw/logs/provincial_361/run*.log
  then grep -cE '[0-9]{1,3}(\.[0-9]{1,3}){3}' must be 0 (2026-10-17's committed run.log reads `<host>`).
- `bcfp_baselines.csv` (tracked) gained a snapshot row: commit it with the run records.

## 13:30 UTC intervention (operator-approved: "go on 1 and 2")
- m1 stalled: KTSU 65 min (1.3 on 2026-10-17), OKAN > 4 h in fresh 0.42.0's `frs_near_river_walk` statement
  (planner estimates 44 rows for the origin x main-stem join, nests per-row subqueries; same plan shape on
  a cypher for ATLL, so group shape, not host). Long lake connectors set the prefilter radius: OKAN 8.8 km,
  TAKL 31, QUES 64, CHIR 25; LFRA 6 km ran in 6.6 min. ATLL (13 km) ran 3.5 min on a cypher: radius is
  necessary, not sufficient. EXPLAIN ANALYZE on working_ktsu (kept on m1) after the run.
- Cloud legs all done by ~12:27 UTC (57/68/42, no failures); cyphers up and idle, unburned (burn waits on m1).
- knowledge chain2 (started 07:48 UTC, 6 R workers at 100 %, fresh_default_20261017) is NOT the cause and does
  not call fresh's walk (its own R walk, R/link_walks.R).
- 13:30:17 UTC `ALTER ROLE postgres SET statement_timeout = '30min'` (new sessions; RESET after the run:
  `ALTER ROLE postgres RESET statement_timeout`). Then `pg_cancel_backend(970488)` on OKAN's leader.
- OKAN is a failed group of this run: re-model it (and any timed-out group) after a fresh fix, under
  run_uid 20261023_074321-24d85e8c, then `--recompute-only --run-uid=...`.
- fresh issue to draft: the near-river walk's plan on lake groups (OKAN reproduction).

## Close-out (driver exited 20:04 UTC = 1:04 PM PDT; INCOMPLETE by design, OKAN)
- Stages (UTC): launch 07:43:21; snapshot/spin/prep to 08:02; modelling 08:02 -> cyphers done 12:12 / 12:27 / 12:22,
  m1 done 17:23 (DRIR); consolidate 17:24 -> 18:06 (42 min, 167 groups ok, backup dump taken 17:23);
  burn clean (0 tofu resources x3); coverage 240/241; recompute -j8 18:06 -> 19:57 (110 min, 240 groups,
  longest LFRA 22.7, FRCN 17.9, SETN 16.5 min); compare 674 rows / 216 of 240 (24 groups GR/RB-only,
  no shared mapping_code column with bcfishpass: pre-existing); exit 20:04.
- Per host (log, this run): job1 57 groups 247 min of modelling in 249 wall; job2 68 / 260 / 264; job3 42 / 257 / 259;
  m1 73 done, 306 min of modelling in 560 wall (KTSU 65.4 and the OKAN 4 h stall). Phase 1 estimate was ~218 each.
- Provenance: 241 log rows this run_uid (74 m1 incl. OKAN's failed row), one link_sha 1d00c04c, link_dirty f,
  fresh_sha e9793047, config_hash sha256:379e1651; log_recompute 240 rows, same sha. kept_hosts.tsv absent.
- `ALTER ROLE postgres RESET statement_timeout` done 20:05 UTC (rolconfig now NULL).
- run.log redacted by hand (3 addresses -> <host>, 0 left); the 0.0.0.0/0 in up/burn logs is the firewall rule, kept as on 10-17.
- study_area_verify.sql at 241: fails only "1 WSG modelled but not recomputed: OKAN" (exit 3); verify_extra PASS 241.
- OKAN: no BC group drains through it (lnk_wsg_resolve: closure = OKAN; no group's closure includes OKAN),
  so `--recompute-only --run-uid=... --wsgs=OKAN` is the finish (driver header: --wsgs= scopes coverage+recompute).
- Re-model launched 20:15:04 UTC, PGOPTIONS statement_timeout=30min, log data-raw/logs/provincial_361/okan_remodel.log.

## OKAN / KTSU stall: what the evidence says (2026-10-23 20:10-20:14 UTC)
- The near-river walk (fresh .frs_near_river_walk_sql, cw 15 m / 1000 m) re-run on the SAME working tables the run left:
  HOLB 2.7 s (229,774 origin x main-stem pairs), KTSU 3.0 s (220,649 pairs), OKAN 58.9 s (3,228,956 pairs; 6,597 origins kept).
  Same plan shape as the EXPLAIN taken during the run (planner estimates 44 rows; nested loop over main-stem rows with a
  BitmapAnd of geom GiST + wscode GiST/blk; per-row EXISTS on blk_drm index; polygon subplan 2,181 loops). FWA_Downstream is
  LANGUAGE sql IMMUTABLE and inlines, so the ltree index is used.
- During the run: KTSU 08:07-09:13 UTC (65.4 min; 1.3 on 10-17), OKAN 09:19 -> cancelled 13:30 (2.8 min on 10-17), both with
  3 parallel workers attached at cancel. Every m1 group after 13:30 ran at the 10-17 pace (54 groups), while the knowledge
  session's jobs kept running (its scratch logs written until 20:07 UTC). PG log: autovacuum "skipping vacuum of streams ---
  lock not available" at 10:26 and 10:52 UTC; nothing else in 09:00-13:40 besides my probes' timeouts.
- So: NOT reproducible on the table + SQL in isolation (1300x and >250x faster now). Coincides with the first 5.5 h after
  `--refresh-primitives` reloaded the primitives (07:43-08:02) and with the other session's heaviest phase; mechanism not
  identified. The "plan shape on lake groups" premise for a fresh issue is disproved: do not file it. The actionable item is
  the driver-side statement timeout (a runaway statement fails as a named group), plus the pre-run scoped gate.

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

## Session 2026-10-23 (the run)

- Launched 07:43:21 UTC detached (`launch.sh`); attempt 1 at 07:42:33 was refused by bash 3.2 (`exec bash`
  resolved to `/bin/bash` under nohup; no spend; `run_attempt1_bash32.log`), fixed in `1d00c04c`. run_uid
  `20261023_074321-24d85e8c`, label `provincial-241-default-361`, `--refresh-primitives`, `--recompute-jobs=8`,
  cyphers `job1,job2,job3`. First rows: link_sha `1d00c04c`, link_dirty f, fresh_sha `e9793047`,
  config_hash `sha256:379e1651…`.
- Cloud legs done 12:12 / 12:27 / 12:22 UTC (57 / 68 / 42 groups, 247 / 260 / 257 min of modelling; no failures).
  m1: KTSU 65.4 min (1.3 on 2026-10-17) and OKAN stalled from 09:19 UTC inside fresh's near-river walk statement.
  Operator-approved 13:30 UTC: `ALTER ROLE postgres SET statement_timeout = '30min'` then `pg_cancel_backend` on
  OKAN's leader; OKAN failed as a named group and the dispatcher ran the remaining 54 groups at the 2026-10-17
  pace (done 17:23 UTC). Role timeout reset 20:05 UTC.
- Consolidate 17:24–18:06 UTC (167 groups `ok`); burn clean; coverage 240/241; recompute `-j8` 18:06–19:57 (110 min);
  compare 674 rows over 216 of 240 (24 GR/RB-only groups share no mapping-code column with bcfishpass, as before);
  driver exit 20:04 UTC, non-zero by design (#348).
- The stall does not reproduce: the same walk on the same working tables takes 59 s (OKAN) and 3 s (KTSU) with the
  same plan shape (findings). Both slow groups ran in the first 5.5 h after the primitives reload, while another
  session loaded the database; every later group ran at pace. Mechanism not identified; the fresh issue premise
  ("plan shape on lake groups") is withdrawn. Two follow-ups drafted for the operator's review, not filed: a
  per-statement timeout in the driver, and a scoped pre-run gate picking groups by the input that drives each
  changed rule (scratch `issue_drafts_pretest_timeout.md`).
- OKAN re-modelled under the run's uid 20:15–20:22 UTC (7.6 min; `okan_remodel.log`, `PGOPTIONS` statement
  timeout 30 min); no BC group drains through OKAN (`lnk_wsg_resolve`: closure = OKAN, nothing's closure holds
  it), so the finish was `--recompute-only --run-uid=… --wsgs=OKAN`, 20:23–20:25 (`okan_recompute.log`).
- `study_area_verify.sql` read OKAN's failed row (date_end NULL by design, `.lnk_log_run_fail()`) as "started and
  never finished" and could not pass the #348 path. Patched: an open row a later finished row of the same group
  and run_uid supersedes is a NOTICE, one nothing supersedes still raises; 1c prints the flag. Negative test gains
  6f (superseded → PASS) and 6g (not superseded → FAIL); all 17 cases pass on this run (`verify_negative.log`).
  Both verifiers pass at `expected_n=241` (`run_verify.log`, `run_verify_extra.log`).
- Filed #369 (consolidate each cloud host when its leg finishes, then burn it); closed #170 as superseded (operator).
- Next: Phase 3 split test. `split_test.sh` requires HEAD's short SHA to equal the reference's `link_sha`
  (`1d00c04c`): run it from a checkout of that commit, or relax the check to the reference SHA being an ancestor.

## Session 2026-10-23 (split test)

- Split test ran 20:33–21:32 UTC from a worktree at `1d00c04c` (`~/Projects/repo/link-wt361`; the
  harness demands HEAD = the reference's link SHA and a clean tree, and the branch had moved on).
  Two lanes, 13 groups each, worst order; the guard warned on 18 of 26 at open (`split_guard_warnings.tsv`),
  the recompute's error-mode guard passed on all 26. Digests: 387 of 442 identical, 55 differing
  (`split_test_summary.txt`).
- Every difference traced (`split_verdict.md`): cross-host arithmetic at ≤ 4e-9 m (`length_metre`
  on 104,047 segments, 1,265 geometries, 62 barrier positions; the reference Peace was built on a
  cloud host, the split on m1), and NATR's `streams_access` / habitat / mapping code on 2 segments
  (0.1 km) of Fraser-coded line whose downstream barriers are in TAKL, outside the 26-group scope.
  MILL and LPCE rebuilt on m1 alone (`fresh_361c`) are identical to the split build in every
  model-time table; the habitat rows that differ are exactly the gate's. Nothing is attributable to
  the order. Verdict: Phase 4a.
- Scratch schemas `fresh_361a`, `fresh_361b`, `fresh_361c` kept until the PR; the worktree too.
- Phase 4a landed: `--atom=group` (both makespans in the report; 4 hosts 270 = 270, 5 hosts 216 < 231),
  `study_area_wsgs.R --exact`, `study_area_run.sh --buckets-exact` (+ `bucket_mode` column in `run_wsgs.tsv`,
  reader accepts both headers), RUNBOOK §8d and the research record. Driver tests 296/296.
- Parity run `20261023_203809` had 16 of 17 rows `link_dirty` (edits to the main repo during the run, my
  slip); schema dropped, re-run `20261023_215312-16fb3aae` launched 21:53 UTC from the worktree at `1d00c04c`.
- Records: `data-raw/logs/provincial_361/README.md`, `data-raw/logs/README.md` campaign rows, NEWS 0.68.1 entry.
  `habitat_validate.R` accepts `fresh_default` under `default` (ADMS; run without `--out`, which rewrote the
  #283 directory: restored from HEAD, lesson in findings).

### Resume (written 2026-10-23 22:05 UTC for a session that may not be this one)

Branch `361-provincial-run-can-a-drainage-component`, pushed through `120cc9fd`. Phases 1–4a and most of 6 are
done and committed; what is left, in order:

1. **Parity re-score (Phase 5).** A run is in flight FROM THE WORKTREE `~/Projects/repo/link-wt361` (checkout of
   `1d00c04c`; run_uid `20261023_215312-16fb3aae`, label `parity-4-bcfishpass-361`, schema `fresh_parity361`,
   launched 21:53 UTC; wrapper log `data-raw/logs/parity_0.68.0/run.log` in THIS repo). Check it from its
   artifacts, never from a waiter: `grep -E '=== study_area_run (done|INCOMPLETE)' data-raw/logs/parity_0.68.0/run.log`;
   its driver files are under the worktree's `data-raw/logs/study_area_run/20261023_215312_*` (copy them here).
   Then, from this repo (DB is local docker fwapg, `docker exec -i <db> psql -U postgres -d fwapg`):
   - verify: `study_area_verify.sql -v schema=fresh_parity361 -v run_uid=20261023_215312-16fb3aae -v expected_n=17`
     → `data-raw/logs/parity_0.68.0/run_verify.log`;
   - score: `LNK_LOAD=loadall LNK_SCHEMA=fresh_parity361 LNK_CONFIG=bcfishpass LNK_PARITY_OUT=data-raw/logs/parity_0.68.0/parity_annotated.csv Rscript data-raw/parity_crosssection.R ADMS BULK BABL ELKR`
     → log to `parity_crosssection.log`; compare with `expected.txt` (48/50; CO ADMS −0.22 km, CO BULK −1.45 km rearing);
   - moves: `LNK_COMPARE_NEW=20261023_215312_compare.csv Rscript data-raw/logs/parity_0.68.0/moves.R > data-raw/logs/parity_0.68.0/moves.log`
     (old schema `fresh_parity362`, new `fresh_parity361`; the file first needs the new compare CSV copied into
     `data-raw/logs/study_area_run/`);
   - write `data-raw/logs/parity_0.68.0/README.md` on the pattern of `parity_0.66.6/README.md`; revise
     `research/bcfishpass_parity.md` (table, what moved, the run line); drop scratch `fresh_parity246`, keep `fresh_parity362`.
   - Do NOT edit this repo while a run models from it (the first parity attempt stamped 16 rows `link_dirty`;
     `run_dirty_tree.log`). Runs from the worktree are safe to edit around.
2. **Issue bodies**: apply `planning/active/drafts/issue_361_body.md` (`gh issue edit 361 --body-file`), ticking the
   parity line once scored; tick #364's open line "The next provincial `default` run re-models every group"; add a
   one-line "Done: run 20261023_074321 at 0.68.0" to #367. Then tick the Phase 6 box.
3. **Validation**: `devtools::test()` + `lintr::lint_package()` (a run was started 21:59 UTC; if no result is
   recorded in progress.md, run again); `/code-check branch` (three-round floor; reviewers in a copy of the tree);
   fixes as follow-up commits; `DESCRIPTION` to 0.68.1 as the last commit (NEWS already says 0.68.1).
4. `/planning-archive`, then `/gh-pr-push`. PR body ends with the Claude Code line and the session URL (see git log).
5. Clean-up to name in the final report, not to do: drop `fresh_361a/b/c` and the worktree
   (`git worktree remove ~/Projects/repo/link-wt361`) after merge; `fresh_default_20261017` is the operator's call;
   `job4` workspace in the infra repo if a 5-host run is wanted.

For the operator's review (not filed): `planning/active/drafts/followup_issues_timeout_pretest.md` (two issues).
Withdrawn: the fresh near-river-walk issue (premise disproved; see findings). Already filed/closed: #369, #170.

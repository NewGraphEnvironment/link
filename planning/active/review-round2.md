# Code-check round 2 — #358 (branch vs main, planning/ excluded)

Reviewer: subagent, 2026-10-18. Read: branch.diff, round1_fix.diff, review-round1.md;
study_area_run.sh (296-460, 560-680, 1380-1538), study_area_finish.sh and
study_area_hosts.sh in full, schema_consolidate.R (stages, delete, copy loop);
checklist shell and mechanism sections, R and spatial by heading. Nothing in the repo
was edited except this file. The probe ran on copies of the two libs in a mktemp dir,
with `.hosts_query` stubbed.

## Findings

- **[fragile — inside round 1's fix]** data-raw/study_area_finish.sh:313-321
  (`run_expected_recompute_only`). The round-1 fix keeps not_consolidated groups out of a
  bare `--recompute-only`, but only `if [ -z "$wsgs" ] && [ -f "$cov" ]`. A missing
  `<TS>_coverage.tsv` reads as "nothing excluded". That is the "missing record reads as
  nothing missing" shape. The file is written only inside `run_finish`, after
  `run_coverage` succeeds (finish.sh:357-364). A run from after #358 (one with a
  `run_wsgs.tsv`) can leave a partial bucket on the dispatcher and still write no
  coverage file, in three ways:
  1. The consolidate R process dies or is killed mid-copy. Then there is no consolidate
     TSV, the else branch runs (run.sh:1496-1505), and the driver exits before coverage.
  2. The run carries on past a failed source, and `run_coverage` then hits
     `FATAL: could not verify WSG coverage` (finish.sh:352-354).
  3. The driver is killed between the carry-on and `run_finish`, which spans
     host_release and `burn_cyphers` (cypher_down waits on tofu).

  The partial state is real. `schema_consolidate`'s copy loop does not stop on a failed
  table (schema_consolidate.R:501-573, "do NOT break on the first per-table failure"). A
  `dest_copy` failure on one `streams_habitat_*` table therefore still copies `log` and
  `streams`, so the group has rows and a closed newest log row for the uid. Coverage
  classes it `recompute`, and `lnk_access(merge=TRUE)` then runs over the missing
  habitat table. The only thing in the way is the `kept_hosts.tsv` WARN ("settle
  first"), which does not stop the run, and the report shows nothing wrong.

  Probe: with a run_wsgs.tsv listing `AAAA dispatcher` and `BBBB a`, a stub giving both
  groups a log row, and no coverage.tsv, `run_expected_recompute_only ''` returns 0 with
  `EXP=AAAA,BBBB EXCL=[]`.

  Secondary: the record is not written atomically. It is
  `{ … } > "${TS}_coverage.tsv"`, with the `not_consolidated` rows written **last**. The
  reader checks no header and no completeness, so a truncated file (killed mid-write,
  ENOSPC) loses exactly those rows.

  Suggest: record `CONS_EXCLUDED` durably at the carry-on point, before host_release and
  burn. For example, write `<TS>_not_consolidated.tsv` via temp file + `mv`, or rewrite
  run_wsgs.tsv with a column for it. Then have a bare `--recompute-only` refuse
  (require `--wsgs=`) when run_wsgs.tsv exists (rc=0) and lists cypher groups but the
  run left no coverage.tsv, because that run never reached its tail.

- **[fragile, minor — inside round 1's fix]** data-raw/study_area_finish.sh:317.
  `RO_EXCLUDED=$(.hosts_inter "$RO_EXCLUDED" "$RO_EXPECT")` drops any not_consolidated
  group that is not otherwise expected. The full-run fix deliberately went the other way:
  `run_finish` puts the excluded set into `RUN_WSGS` "even when the host finished one
  outside its bucket" (finish.sh:325-333). Such a group is in no bucket, so it is not in
  run_wsgs.tsv. With no dispatcher log row for the uid (the `dest_log_newer` case, where
  nothing was copied), it is also not in `logged`.

  Probe: a coverage.tsv naming `ZZZZ not_consolidated` gives `EXCL=[BBBB]`, and ZZZZ is
  named nowhere. When it is the only not_consolidated group, a bare `--recompute-only`
  passes `excluded=""`, so `COV_MISSING` is empty and the run exits 0. The full run for
  the same uid exited 1 naming ZZZZ, and its finished work is still on the kept host
  (KEPT_CAUSE_N is 0 in this mode, so the kept host does not force a non-zero exit
  either). Suggest: union rather than intersect (`RO_EXPECT ∪ RO_EXCLUDED` flows into
  `run_finish` anyway through its third argument), or drop the `.hosts_inter`.

## Checked and found sound (no finding)

- **Round-1 fix 1:** `RUN_SKIP = skip − finished`, where finished includes the
  failed hosts' `CY_BUCKET_DONE`, while `RUN_SIGNALS` leaves them out. A group SKIPped on
  one host and finished on a failed host stays expected. Then `CONS_EXCLUDED ⊆ finished`
  and `RUN_WSGS ⊇ CONS_EXCLUDED`, so `COV_UNCONS` is non-empty whenever `CONS_FAILED`
  is. `[ -z "${CONS_FAILED:-}" ] || RUN_INCOMPLETE=1` also forces a non-zero exit on its
  own. The "accounting did not cover its bucket" message is not reachable with
  `CONS_FAILED` set, because `COV_MISSING` is non-empty.
- **Separate TS:** `--recompute-only` mints its own `TS` (run.sh:303). Its own
  coverage.tsv therefore never overwrites the original run's
  `${RUN_UID%-*}_coverage.tsv`, which every later bare run reads. A `--wsgs=` subset
  run cannot erase the record.
- **Coverage read fails closed:** an unreadable coverage.tsv gives FATAL
  (pipefail + `||`). Its header and any malformed row are ignored by the `^[A-Z]{4}$`
  guard.
- **Errexit:** `consolidate_outcomes` inside `elif` runs with errexit off. If it
  returns 1 after setting some `CY_CONS_FAIL`, the else branch still exits 1 with every
  host held. In the else branch, `run_expected_from_hosts` prints a complete
  `RUN_EXPECT`, because failed hosts still count as finished.
- **Outcome TSV parse:** `IFS=$'\t' read` collapses an empty field. Only `stage` NA
  (never produced by `schema_consolidate`) followed by a groups value could misparse,
  and that only changes the printed stage.
- **host_release:** a failed source keeps its finished groups (the source delete is
  step 5, after every table copied and the row check passed), so it is kept with the
  consolidate-failed reason. A source-delete failure after a full copy releases a host
  whose rows are on the dispatcher; its bucket is excluded (conservative), and the
  run exits non-zero.
- **Driver wiring:** the structural test pins `run_finish "$RO_EXPECT" "" "$RO_EXCLUDED"`
  and the `CONS_FAILED` line. Both match the driver text.

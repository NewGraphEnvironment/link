# Code-check round 3: #358 (branch vs main, planning/ excluded)

Reviewer: subagent, 2026-10-18. Read: round2_fix.diff, branch.diff (all hunks),
review-round2.md; study_area_run.sh 630-690, 1200-1230, 1395-1560;
study_area_finish.sh (run_expected_from_hosts, run_wsgs_write, run_expected_from_file,
consolidate_outcomes, consolidate_state_write, run_unconsolidated_from_state,
run_coverage, run_expected_recompute_only, run_finish, run_finish_report);
study_area_hosts.sh (host_finished, host_split, host_account,
host_consolidate_bucket, host_release, hosts_kept_report, set helpers);
schema_consolidate.R 240-300, 420-700 (stage order: refusals before the DELETE,
then source_copy / dest_copy / copy_empty after it; a source-delete failure is a
WARN and still `ok = TRUE`); checklist "One fact derived twice". Nothing in the
repo was edited except this file. The probe ran on copies of the two libs in a
mktemp dir.

## Mechanism

Confirmed, and narrowed: **one fact ("which groups may not be safely on the
dispatcher") is derived separately at each consumer, from a record whose
population or write time differs from the consumer's.** Rounds 1 and 2 were
each a consumer whose operand covered a smaller population (RUN_SIGNALS without
the failed host; RO_EXPECT without the out-of-bucket group) or was written later
than the event it described (coverage.tsv written after the risky step). The
tell is the group a failed host finished **outside its bucket**: it is in
CY_BUCKET_DONE / CY_UNCONS but in no CY_BUCKET, so any operand built from
CY_BUCKET (or from run_wsgs.tsv, which is CY_BUCKET) silently lacks it.

Round 2's fixes close both instances it found: the state record is now written
before the copy and fails closed (in_flight), and RO_EXCLUDED is unioned into
RO_EXPECT. One consumer still derives "on a kept host" from CY_BUCKET: the
full-run report (finding 1).

## Enumeration

| set combination | same population / time? | consequence |
|---|---|---|
| `RUN_SKIP = skip − finished` (finish.sh run_expected_from_hosts) | yes: both from accounting; `finished` now includes every CY_BUCKET_DONE, failed hosts too | sound (R1 fix) |
| `RUN_SIGNALS` = disp finished ∪ done ∪ CY_BUCKET_DONE of non-failed sources | same time (after outcomes) | sound; failed sources add nothing and are excluded anyway |
| `RUN_EXPECT = all − RUN_SKIP`, all = ∪ CY_BUCKET | `all` lacks out-of-bucket finished groups | covered: run_finish unions CONS_EXCLUDED into RUN_WSGS |
| `RUN_WSGS = expect ∪ excluded` (run_finish) | yes | sound |
| `excluded ∩ expected` (run_coverage) | expected = RUN_WSGS ⊇ excluded at the only caller | inert today (no-op). Same shape as R2b; fragile only if a second caller appears |
| COV_* = classes − excluded; COV_MISSING ∪= COV_UNCONS | same DB read, same call | sound |
| `CONS_EXCLUDED` = CY_BUCKET_DONE of failed sources; SRC_R buckets; consolidate_outcomes' source set; consolidate_state rows | all four iterate CY_WS_ARR with non-empty CY_BUCKET_DONE, read once after accounting | same population; sound |
| consolidate_state.tsv in_flight → ok / failed:<stage> | written before the copy, rewritten only after outcomes; mv atomic; rewrite failure leaves in_flight | fails closed; sound (R2a fix) |
| consolidate_state.tsv absent → RO_EXCLUDED empty | absent only if consolidate was never started by this run (n_src=0, killed before the write, FATAL on the write, N_CY=0) | accepted tradeoff; sound |
| run_wsgs.tsv (CY_BUCKET rows, skip) ∪ logged ∪ RO_EXCLUDED = RO_EXPECT | file lacks out-of-bucket groups; logged has them if consolidated; RO_EXCLUDED has them if not | sound (R2b fix). A host never handed to consolidate (unknown accounting) has no out-of-bucket groups in any record, as in the full run |
| run_wsgs.tsv skip (kept if any row not `yes`) vs RUN_SKIP (skip − finished) | different rule: a group SKIPped on one host and failed (not skipped, not finished) on another is RUN_SKIP in the full run, expected in --recompute-only | --recompute-only is stricter: fails toward fail. Not flagged |
| `--wsgs=` → RO_EXCLUDED skipped entirely | by design | accepted tradeoff |
| `held` = ∪ CY_BUCKET of held hosts ∪ KEPT_TSV_GROUPS, vs COV_MISSING (run_finish_report) | full run: CY_BUCKET only; COV_UNCONS can hold an out-of-bucket group finished on a kept host. --recompute-only: KEPT_TSV_GROUPS = kept_hosts.tsv `groups` (CY_UNCONS), which has it | **finding 1** |
| KEPT_TSV_GROUPS (kept_hosts.tsv) vs RO_EXCLUDED (consolidate_state.tsv) | different populations: kept_hosts.tsv also names hosts the driver never consolidated from (unknown accounting, session rc ≠ 0), which the operator settles by hand | only the driver's own consolidate is excluded; a hand consolidate that half-fails is invisible to a bare --recompute-only. Same as before #358, operator-gated, and the run prints `--wsgs=` recovery. Noted, not flagged |
| kept_hosts.tsv vs failed source released and burned (no groups left on it) | the excluded group is named in no kept file; WARN text points at kept_hosts.tsv | accepted tradeoff (message only) |
| consolidate.tsv rows matched by `cypher@<ip>` | one row per source, written after schema_consolidate returns; truncation reads as missing or as failed | fails closed; sound |

## Findings

- **[fragile]** data-raw/study_area_finish.sh:638-660 (`run_finish_report`, the
  `held` set), reached through the branch's new COV_UNCONS (finish.sh:280-285).
  `held` takes each held host's `CY_BUCKET`, the bucket it was asked to run. The
  branch puts a failed source's whole CY_BUCKET_DONE into COV_MISSING, including a
  group that host finished outside its bucket; its own test pins that case ("a
  failed host's finished group outside its bucket is still classed
  not_consolidated"). That group is not in `held`, so the full-run report lists
  it under "Re-model each of these under this run_uid" with the wsg_run_one.R
  command, though its finished rows sit on the kept host and kept_hosts.tsv's
  `groups` column names it. A bare --recompute-only on the same run reads `held`
  from kept_hosts.tsv (CY_UNCONS) and gives the other advice, "settle per
  kept_hosts.tsv first". So one function gives two answers for one group,
  depending on which record fed it. Nothing is lost: a re-model then makes a later
  hand consolidate of that host refuse at `dest_log_newer`. But the operator is
  told to re-model finished work and then sees a consolidate refusal.

  Probe (copies of both libs, Homebrew bash): `CY_WS_ARR=(a)`, `CY_BUCKET[a]=CCCC`,
  `CY_HOLD[a]=1`, `CY_UNCONS[a]=CCCC,ZZZZ`, `COV_MISSING=COV_UNCONS=CCCC,ZZZZ`,
  `RUN_INCOMPLETE=1`. Then `run_finish_report` prints `re-model only what is still
  missing: CCCC` under the kept-host heading and `Re-model each of these under this
  run_uid: ZZZZ`.

  Suggest: build `held` from the same set kept_hosts.tsv writes for a held host,
  `CY_BUCKET ∪ CY_UNCONS` (or `∪ CY_BUCKET_DONE`), so the two modes read one
  population. (Inside round 2's fix? n. Pre-existing line, newly reachable through
  this branch's COV_UNCONS.)

No other instance of the mechanism is live in the diff. The round-2 fixes are
sound: the in_flight record fails closed on every path that started consolidate,
including a FATAL on its own write (hosts held) and a failed `ok` rewrite (left
in_flight). RO_EXCLUDED is unioned, not intersected. Another run's record, or a
bad header, stops a bare --recompute-only. Excluded groups always reach
COV_MISSING, so they force a non-zero exit in both modes.

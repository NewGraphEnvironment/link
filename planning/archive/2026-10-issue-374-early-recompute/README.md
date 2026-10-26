## Outcome

`study_area_run.sh` now recomputes each group while the legs still run, as soon as it and every group whose barrier rows its walk reads have landed on the dispatcher, instead of one pool after the last leg and consolidate (`data-raw/study_area_recompute.sh`: `recompute_landed`, `recompute_ready`, `recompute_scheduler`; `--recompute-at-end` keeps the old order). The issue's premise was wrong in one load-bearing place: the downstream (outlet) closure is not what a recompute reads, and misses readers in 150 of 241 groups. A watershed group is not one drainage, and gradient barriers are persisted under every group touching a line. The scheduler uses `recompute_deps.R`'s **line** rule, complete by construction. Because a too-early recompute cannot be undone (the habitat gate only clears flags), readiness fails closed, and `recompute_audit.R` is a run post-condition that compares each start with each landing on one clock. It fails on an early start (exit 1) and on anything it cannot prove (exit 2). The plan review found a real lock conflict: `lnk_persist_init()` replaced `streams_habitat_long_vw`, which every recompute reads, once per dispatcher group. It now replaces the view only when a key over its SQL and `pg_get_viewdef()` changes. `/code-check branch` ran three rounds (6, 3 and 4 findings, all fixed); rounds 2 and 3 each found a defect inside the previous fix, so the loop ended on an enumeration of every absence and failure branch the branch added (`review-enumeration.md`), which found one more: an empty ordering that would have hung the final set.

## Measurement

- **Dependency rules over FWA** (`deps.tsv`): closure 965 pairs, owner 1,243, line 2,211 (median 9 per group); closure ⊂ owner ⊂ line in every group.
- **Ownership in `fresh_default`:** 1,224 barrier positions co-held (up to 13 groups), copies differ at 1. 1,864 non-owner rows, of which 2 have no identical copy held by the owner. 285 rows sit on no persisted segment. This is why the owner rule is not complete by construction.
- **Digest test:** TOOD (18 line-rule groups, 6 in closure) and NATR (32 and 4). Recomputing over only the line rule's groups gives 0 rows differing from the all-groups result (97,296 and 47,302 segments); over only the closure, 2 segments differ in each (#361's).
- **Headroom (A-B-A):** the dispatcher's modelling is 1.20x slower beside a `-j4` recompute and 1.99x beside `-j8`, so the database saturates past about four jobs. The recompute jobs themselves did not slow.
- **Replay of 2026-10-23** (`-j8`, line rule): without the stalls and with that load counted, the recompute ends 36.7 min sooner (tail after the last landing 60.6 min, against 110.7). Width 4 saves 22.2 min and none 11.1, so one width is kept. As recorded, the saving is 89.4 min.
- **Runs on the dispatcher and worker1, ten groups:** A (early), B (`--recompute-at-end`) and A2 (early, after the wake fix) are identical in all 13 output tables (348,857 segments); a planted one-row difference was caught. Both verifiers pass, the audit had 18 pairs and 0 early, and no lock waits were sampled. Tails: A 0.8 min, B 0.65, A2 0.5. A's last groups waited 27 s for a 30 s poll, so the scheduler now wakes on the final set within a second.
- **Wrong turns kept:**
  - A drainage-membership test flagged 1.43 M rows "foreign".
  - FWA's `999…` codes made every group depend on 245 others.
  - The line rule by `blue_line_key` first dropped 52 pairs.
  - A log regex matched R's `[1]` and started the baseline pool 44 min late.
  - The coupled replay lost a step per group boundary.
  - `fresh_default` was no negative control (nothing since 0.68.0 changes outputs).
  - I edited `digest_test.R` while NATR's run of it was in flight, and restored it within seconds.

The verdict lives in `research/study_area_run.md` ("Since link#374") and RUNBOOK §8d ("A group is recomputed once what it reads has landed").

## Evidence

`data-raw/logs/recompute_early_374/` (its README indexes it): `deps.tsv`, `sim_*.tsv`, `headroom*/`, `digest*`, `run_a*/`, `run_b/`, `ab_compare*`.

## Owed

- The provincial `default` run's recompute row and critical path fill #377's runs row; #374 stays open for it.
- The control-asymmetry issue (copies of one barrier held by several groups can disagree under group-filtered controls; the narrower owner rule would save ~11 more minutes) is drafted and not filed: it waits for the operator's review of its body.

Closed by: PR (to be opened from branch `374-study-area-run-sh-recompute-each-group-a`)

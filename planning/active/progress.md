# Progress — Provincial run speed-up: one change at a time, measured (#377)

## Session 2026-10-26

- Plan-mode exploration — phases approved by user
- Created branch `377-provincial-run-speed-up-one-change-at-a` off main
- Scaffolded PWF baseline from issue #377 with approved phases
- Next: start Phase 1
- Plan review (Plan agent) returned 1 blocker, 2 gaps, 3 assumptions, acceptance notes: `review-plan.md`; all folded in.
- Phase 1 done: `data-raw/logs/loadall_260/` (`prologue.R`, `measure.sh`, `span.sql`, `shares.R` and outputs). Busy-condition load_all prologue 1.63 s against library(link) 0.92 s; whole pool 0.81 min of a 110.3 min span (0.74 %); switching would save 0.35 min (0.32 %). Under the 5 % stop line: verdict holds.
- Phase 2 done: evidence README, research candidate 1 revised in place (line ref :25-27 → :26-30), research/README row unchanged (still accurate). LNK_LOAD readers counted: 12, not the plan's 13.
- Phase 3 done: #260 body (Measured section, acceptance 1 ticked, 2-3 N/A, stale refs noted) and #377 body (#376 and #260 ticked with measured lines) edited and read back; CLAUDE.md status added.
- /code-check round 1: 4 findings (README verdict reason wrong; overrides note's numbers and mechanism wrong; unrecorded indexing claim; share phrasing), all confirmed by probe and fixed (#260 body phrasing too).
- /code-check round 2: 2 findings — namespace count 19 → 17 in prologue order (inside round 1's fix), and the 'slowest job bounds the pool' reasoning surviving in README, research candidate 2 and #377's #261 line; all fixed.

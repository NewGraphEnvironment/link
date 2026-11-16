# Progress — Backlog move 2: Which fish records count, and what each lift rests on (#470)

## Session 2026-11-16

- Plan-mode exploration — phases approved by user (gate decisions in task_plan.md)
- Created branch `470-backlog-move-2-which-fish-records-count` off origin/main (`2da2db35`)
- Claimed move #470 (`in-flight` label)
- Scaffolded PWF baseline from issue #470 with approved phases
- Phase 1: bcfishpass drops CT alias records (0 of 2,004 keys in its upstream arrays; 99 % of CT and CO
  kept); `observation_date` is a date; both parameters_fresh files are link's own (`879b874d`)
- Before builds started from a worktree of main at `2da2db35` into `zz470_*_pre` (driver `20f44d74`)
- Plan review (Plan agent) returned; findings in `review-plan.md`. Acted on in Phase 2: Blocker 1 (WCT
  floor to NA), 2 (presence columns, stated and tested), 3 (provisional tokens), Gaps 1, 2, 4-8, 10, 11,
  Assumptions 1-3. Folded into Phase 4: Gap 3, Assumption 4-5, the verify guards. Gap 12: 7 records
  carry odd codes (`DVxBT` 6, `" RB"` 1) and stay uncounted. Gap 9: the validator's list default stays
  (back-compat); its driver passes the tracker.
- Phase 2 landed (this commit)
- Next: Phase 3's after builds once the before leg finishes

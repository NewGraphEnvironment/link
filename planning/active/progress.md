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
- Phases 3-5 landed: before/after builds and diff (`f802313e`), head builds and the evidence check
  (`bcc7c716`), NEWS, status block, 0.84.0
- `/code-check branch`:
  - Round 1 (`d6d1ba06`): information_schema lookup by literal table name in the lift's evidence;
    the negative script judged pre-0.84 runs. Both fixed.
  - Round 2 (`d62c9340`): the presence check chained aliases through pooled rows. Fixed.
  - Round 3 (`75f575e7`): mechanism named (the record rule re-derived per consumer); five findings,
    one inside round 1's fix (negative script's judged groups). Fixed; the harness's missing control
    table moved #427's HARR row (+8, not +9), reported to the operator.
  - Round 4: enumeration of 27 places (`review-round4.md`); two findings, one inside round 3's fix
    (the harness also left out habitat lifts, so #427's "added" counts were high: SQAM 4, not 22);
    the dictionary refs for the presence check drifted with round 2's fix. Fixing: the harness now
    calls prepare's own steps.

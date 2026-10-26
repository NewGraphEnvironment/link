## Outcome

This took #377's next item. #376 (persistent workers, v0.68.5) was ticked with its small-run measured line, leaving its provincial numbers owed. #260 asked whether the recompute pool's per-job `pkgload::load_all()` is worth removing, which would change the `LNK_LOAD` contract that 12 `data-raw/` scripts read. It is not, so the contract stays. The one code change is a line in `data-raw/wsg_recompute_one.R` that prints each job's prologue at `t0`, so the next provincial run measures it in place.

What was learned:
- The bench alone understated the in-run cost by a factor of about three.
- The provincial pool is bound by its summed work over its slots, not by its slowest job. That also changes what #261 can buy, and #377's #261 line now says so.

## Measurement

- **Bench** (dispatcher, `prologue.R` stage by stage): the whole prologue before `t0` is 1.10 s in sequence, 1.44 s with 8 at once, and 1.63 s beside 7 CPU-bound R loops. Under `library(link)` it is 0.62 / 0.82 / 0.92 s. With `lnk_stamp()`'s git read (0.10 against 0.04 s), switching saves about 0.78 s per job.
- **In the 2026-10-23 pool** (240 groups, `-j8`, `fresh_default.log_recompute`):
  - the span is 110.3 min and the summed work 837.0 min, so 104.6 min per slot;
  - a slot sat a median 9.70 s between jobs (p10 7.67 s, p90 12.01 s), which is 4.7 min of the span;
  - the bench explains about 3 s of each gap.
- **Bound:** the prologue is at most 4.3 % of the span, and `library(link)` would remove only part of it. The verdict rests on this bound, not on the bench's 0.74 %.

Wrong turns, kept:
- **The bench share.** The first write-up put the prologue at 0.74 % from the bench alone. Round 3's enumeration paired `log_recompute` starts with ends, found the 9.7 s gap, and moved the verdict onto the in-run bound.
- **The critical path.** The plan said short groups never sit on the pool's critical path, and that the slowest job bounds the pool. Both are false at provincial scope: every job counts at one slot in eight.
- **The overrides timing.** The 0.24 against 0.11 s difference in `lnk_load_overrides()` was first blamed on the installed and source versions. It is `library(link)`'s lazy load of 17 namespaces.

Review cost: one plan review and four `/code-check` rounds, five reviewer agents in all. Every round found real wrong claims in the write-up. The loop ended on round 4's enumeration of 72 claims (`review-round{1..4}.md`).

## Evidence

`data-raw/logs/loadall_260/` (its README indexes it).

## Owed

- Next provincial run: read the `[wsg_recompute_one] <WSG> prologue <s> s` lines (added after code-check round 3) and account for the 9.7 s median slot gap; record on #377's runs row.
- Close #260 with the PR (`Fixes #260`) if the verdict holds. #377 stays open.
- #374 is the next tracker item and gets its own `/planning-init 374`.

Closed by: PR (this branch, `377-provincial-run-speed-up-one-change-at-a`)

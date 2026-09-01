# Progress — Parallelise the post-consolidate recompute (#250)

## Session 2026-08-31

- Archived the #246 PWF to `planning/archive/2026-08-issue-246-preflight-gates/`
  with a README (five review rounds preserved)
- Plan-mode exploration; phases approved by the user
- Created branch `250-parallelise-the-post-consolidate-recompute` off main
- Two findings reshaped the plan against the issue as written:
  the `lnk_barriers_views` race (a lock convoy, not just a non-existence window)
  and the fact that recompute failures already cannot fail the run
- Decisions taken: hoist **and** drop the redundant `DROP VIEW`; default
  `--recompute-jobs=4`; `lnk_fanout_judge()`
- Next: Phase 1

## Session 2026-09-01

- Phases 1-7 landed: `4cf9e09` (v0.47.3), `237e094`, `d675cd0`, `dd68a63`, `b7cb5b9`
- **Parity proven**: A == B == C byte-identical across serial / serial-again /
  parallel-shuffled on LKEL,CHWK,CHES,SALR. Idempotence measured, not assumed,
  because `lnk_access(merge = TRUE)` reads its own prior output.
- **Speedup is 1.43x-1.51x, not the ~3.4x #250 projected.** The pool is at
  93% / 79% of the theoretical ceiling for those sets; the ceiling itself is
  low because one WSG (CHWK, 226 s) is 74% / 52% of the work. A pool cannot
  beat its slowest single job.
- **Two wrong diagnoses on the way**, both recorded in
  `research/recompute_parallel_2026_09_01.md`: a Postgres worker-pool theory
  (refuted -- disabling intra-query parallelism made scaling *worse*) and a
  Docker I/O theory (refuted -- 269 wait samples, 100% CPU(running)). Both came
  from theorising about the aggregate rather than reading the per-job
  distribution, which had the answer throughout.
- **Found and fixed a hang I had shipped**: `run_recompute_pool` ended with a
  bare `wait`, which waits for every background job in the calling shell. A
  sampler loop in my own sweep wedged it with all jobs finished. Now waits on
  its own pids; `pool_probe.sh` reproduces it (25/25 on bash 5.3.9 and 3.2.57).
- Also caught: `diff` is shadowed here by a shell function delegating to
  `git diff`, which reported two byte-identical files as different.
- Recompute cost does NOT track segment count -- SALR is 20% larger than CHWK
  and 20x faster. Balancing buckets on segments will not balance recompute.
- Next: full suite, `/code-check`, push, PR.

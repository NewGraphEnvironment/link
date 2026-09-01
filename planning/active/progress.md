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

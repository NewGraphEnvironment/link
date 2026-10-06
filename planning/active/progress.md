# Progress — default MAD ranges for BT, GR, KO and RB, from its own width minima (#307)

## Session 2026-10-06

- Plan-mode exploration — phases approved by user
- Created branch `307-default-mad-ranges-for-bt-gr-ko-and-rb-f` off main
- Scaffolded PWF baseline from issue #307 with approved phases
- Phase 1: producer `data-raw/query_width_mad_equivalent.R` (f52c8f0), /code-check 3 rounds clean.
  Run from a clean worktree at f52c8f0: n 36,601 / 24,509 / 5,977 and medians 0.0214 / 0.04115 /
  0.20103, identical to #302's ad-hoc query, giving 0.021 / 0.041 / 0.20.
- Plan review (Plan agent) folded in: findings.md "Plan review".

# Progress — default MAD ranges for BT, GR, KO and RB, from its own width minima (#307)

## Session 2026-10-06

- Plan-mode exploration — phases approved by user
- Created branch `307-default-mad-ranges-for-bt-gr-ko-and-rb-f` off main
- Scaffolded PWF baseline from issue #307 with approved phases
- Phase 1: producer `data-raw/query_width_mad_equivalent.R` (f52c8f0), /code-check 3 rounds clean.
  Run from a clean worktree at f52c8f0: n 36,601 / 24,509 / 5,977 and medians 0.0214 / 0.04115 /
  0.20103, identical to #302's ad-hoc query, giving 0.021 / 0.041 / 0.20.
- Plan review (Plan agent) folded in: findings.md "Plan review".
- Phase 2: 7 minima + 7 maxima in default's CSV, provenance (`source: link`, checksum `b397dda1`),
  rules.yaml unchanged (temp builds from old and new CSV byte-identical), tests updated
  (default/tuned diff, the #307 pin, `mad_none`, a #307 validator case). Full suite FAIL 0 / WARN 16
  / SKIP 0 / PASS 2449. `audit_configs.R`: no findings. /code-check went 4 rounds: R1 clean;
  R2 found 3 false prose claims; R3 named the mechanism (a fact restated by hand, never
  re-checked against the CSV) and listed its reach; R4 recomputed every number, found 4 low
  leftovers. It ended on a repo-wide grep of the candidate phrasings: every remaining hit is
  fixed or dated history.
- Phase 3: NATR + ADMS prepared once at main into zz307_* and re-classified from main and the
  branch. cw digests identical (all species, both WSGs); under mad, BT/GR/KO/RB stream habitat
  0 -> non-zero, CH/CO/SK identical on ADMS, stream invariant 0. Lake and wetland buckets
  shrink as predicted. Within default, cw vs mad agree within about 5 %. NATR has no NULL
  discharge on the modelled stream edges. `data-raw/logs/habitat_thresholds_307/README.md`.
- Phase 4: research section, RUNBOOK §7, CLAUDE.md status, habitat_score README (#302
  reproduces at v0.58.0 only), research README, habitat_validation, and dated qualifiers on
  the #302 figures. NEWS deferred to the release step.

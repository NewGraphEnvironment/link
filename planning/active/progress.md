# Progress — Score the discharge (mad) habitat model against observations (#300)

## Session 2026-10-02

- Plan-mode exploration; phases approved by user. Gate decisions: species = #302's four
  (BT/GR/RB scored, KO in-sample), size proxy = stream order, verdict of record =
  size-adjusted ratio.
- Created branch `300-score-the-discharge-mad-habitat-model-ag` off main
- Scaffolded PWF baseline from issue #300 with approved phases
- Next: start Phase 1
- Phase 1 committed (`3349b6b`): rule fixed in `research/habitat_thresholds.md`, inputs
  `variants_300.csv` / `wsg_roles_300.csv` (KO in KOTL, PARS; in-sample).
- Phase 2: build takes `--base`; the base is the row with no `step_from` and must be its
  own `equals_bundle` (so #284/#302 files refuse `--base=default_tuned` and vice versa);
  model-only rows validated. Negative checks (scratchpad, `--allow-dirty`, stop before any
  DB write): model-only on cw / with set / from a non-base / with a flag, and both base
  mismatches each stop with their message. `default_tuned`'s thresholds re-write byte for
  byte. `/code-check` deferred to the combined harness diff (Phase 4).
- Phase 4 regression, #302 (score302_* schemas, copied bundles/built.csv, frozen copy
  of the new score script, `--floor=expected`): exit 0, no `model_*` files written.
  summary, totals, verdict, habitat_change byte-identical; bands, bands_pooled,
  bridge_band, taper, elevation, elevation_adjusted equal in shape, text and NA pattern,
  max relative numeric difference 9.5e-15 (the #293 double-precision sum noise).
- Build-side regression (`--step=bundles`, new): #302's 18 bundles regenerate byte for
  byte. #284's thresholds files match; config.yaml descriptions differ (text changed by
  #302); `bt_rear_0p1349`'s `equals_bundle: default_tuned` no longer holds since #302
  moved default_tuned (pre-existing, not this branch).
- Plan review triaged (`review-plan.md`); code-check round 1 (3 findings, all fixed).
- Phase 4 regression, #284 (score284_*, default floor): exit 0. habitat_change, totals
  byte-identical; bands, bands_pooled, bridge_band, elevation, elevation_adjusted, taper
  ulp-level (≤ 8.7e-15). summary and verdict gain only columns added after #284 was
  committed (`model` from #299; floor_of_record / decision_of_record /
  walked_value_of_record from #302); their common columns are identical.
- Score-side negatives: model-only row with obs_stage, with no species, a row stepping
  from a model-only variant, and `--base` mismatch each stop before any DB work.
- Code-check round 2: Clean. Round 3 running.
- Code-check round 3: Clean (named the mechanism: one quantity, two producers, coverage
  assumed equal; every reach checked). Loop ended at 3 rounds with no defect found inside
  a fix. Reports: `review-round{1,2,3}.md`.

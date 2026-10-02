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

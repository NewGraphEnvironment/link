# Progress — Tune MAD (discharge) thresholds for BT, GR, KO and RB (#302)

## Session 2026-10-02

- Plan-mode exploration — phases approved by user
- Gate decisions: build the mad scoring harness here (#300 reuses it); mad_min = P05
  of mad_m3s at stage-located observations, mad_max open (9999) unless literature
  argues a cap
- Created branch `302-tune-mad-discharge-thresholds-for-bt-gr-` off main
- Scaffolded PWF baseline from issue #302 with approved phases
- Next: start Phase 1

## Session 2026-10-02 (cont.) — Phase 1 driver

- Plan review (Plan agent) → `review-plan.md`: three blockers (score `_min` direction,
  BT/GR spawn coupling, KO unscorable held-out); fixes folded in or put to the operator
- Operator decisions mid-run: any-stage fallback for thin spawn cells; expected-count
  floor of record; underpowered walk lands P05 marked unscored
- `data-raw/query_habitat_thresholds_mad.R`: code-check 3 rounds. Round 1 (rear stream
  edges inside waterbodies), round 2 (inside round 1's fix: classifier transcribed
  rules.yaml; now uses fresh's compiled L/W SQL), round 3 Clean by enumeration against
  fresh's compiled `mad` predicates over all 1.88M `fresh_default` segments
- Harness (`habitat_variants_build/score.R`): `model`/`set` columns, anchor rungs,
  `_min` direction, method sha, `--floor`; #284 re-score reproduces all nine outputs
- Literature sweep → `literature.md`
- fresh `wetland_ha_min` defect: issue drafted, awaiting operator review

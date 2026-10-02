## Outcome

`lnk_habitat_validate()` now re-tests each observation's segment on the habitat model its
watershed group classified on. The model comes from the method table of the `cfg` it is
given, resolved by fresh's own `.frs_habitat_models()`, which classify now shares. A
`mad` group's predicates use `frs_habitat_predicates(model = "mad")`, its size relaxation
moves `mad_m3s` (joined from `fwa_stream_networks_discharge` on `linear_feature_id`), and
`width_null` tests discharge. Reason labels are shared across models; `model` and
`mad_m3s` columns split them. New reason `no_mad_threshold`: a `mad` miss that a MAD
range alone would admit, for BT, GR, KO and RB, which have none. Two of the three review
defects came from the `no_mad_threshold` branch being a hand-written copy of the cw
relaxation ladder (it relaxed gradient too, and missed the NULL-size arm); the third,
`.lnk_hv_mad_missing()`, was restating fresh's own rule for when a size test is written.
The loop ended on two enumerations, not on a reviewer going quiet: every miss arm × model ×
NULL pattern, evaluated in Postgres (review round 3), and a case-by-case test of the
missing-range rule against fresh. The state of knowledge is in
[`research/habitat_validation.md`](../../../research/habitat_validation.md) (Method,
"Size model per group"). A follow-up issue for tuning MAD thresholds is drafted in
`draft-issue-mad-thresholds.md`, not filed; #300 covers scoring the mad model.

## Measurement

- **cw output did not move.** ADMS on `fresh_default`, CH/CO/BT, 94 locations: branch and
  main `observations` identical apart from the new columns, `summary` identical apart from
  `model`.
- **The planned acceptance metric did not discriminate.** On ADMS modelled on `mad`,
  "persisted TRUE, re-built predicate FALSE" is 0 on main as well as the branch. The error
  runs the other way: main re-builds the looser cw predicate and calls 27 BT rearing misses
  `post_predicate` (removed by clustering or gating). The branch calls them
  `no_mad_threshold`, and CO's 2 `width_null` (NULL width, never tested on `mad`) become
  `fails_width` on discharge of 0.0127 and 0.018 m³/s.
- Full suite 2,394 tests, 0 failed (16 warnings, the baseline). Validator suite 114 s vs
  main's 90 s, from the two new DB tests.

## Evidence

`data-raw/logs/habitat_validate_299/` — README, scripts and `20261002_*` outputs.

Closed by: PR (this branch, `299-lnk-habitat-validate-scores-mad-watersh`)

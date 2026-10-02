# Task: Tune MAD (discharge) thresholds for BT, GR, KO and RB rather than leave them missing (#302)


`parameters_habitat_thresholds.csv` carries `spawn_mad_*` for CH, CM, CO, PK, SK, ST and
WCT, and `rear_mad_*` for CH, CO, ST and WCT only (`default`, `default_tuned` and
`bcfishpass` alike). The gap was inherited from bcfishpass `example_newgraph`. Under
the `mad` model, fresh writes `FALSE` in place of the size test for a species with no
range, as bcfishpass does. Since #299, `lnk_habitat_validate()` names a miss the missing
range alone explains `no_mad_threshold`. Misses from the same cause also read
`width_null` (no discharge on the line) or `fails_gradient_and_width` (gradient fails
too), so that label is a floor on the loss, not a count of it. On ADMS on `mad`, 27 BT
locations read it against spawning and 8 more read `fails_gradient_and_width`
(`data-raw/logs/habitat_validate_299/`). The operator's direction (2026-10-02,
#299 plan gate): tune and add the thresholds, rather than leave them missing in the long
run.

## Context

Under the `mad` model fresh writes FALSE for the size test of a species with no
`*_mad_*` range, so any group moved to `mad` loses all stream habitat for BT, GR, KO
and RB. Operator direction (#299 plan gate): tune and add the ranges. Decisions at
this gate: **the mad scoring harness is built here** (#300 then reuses it for its own
cw-vs-mad verdict), and **mad_min = P05 of mad_m3s at stage-located observations,
mad_max open (9999)** unless literature argues a cap.

What exploration established:
- Ranges needed (from `default/rules.yaml`, stream rules that inherit thresholds):
  BT spawn + rear, GR spawn + rear, KO spawn only (KO rearing is lake-only),
  RB spawn + rear. Seven `*_mad_min` cells, seven `*_mad_max` = 9999.
- `mad_m3s` is never persisted, but `fresh_default.streams` carries
  `linear_feature_id`, so the obs query can join
  `whse_basemapping.fwa_stream_networks_discharge` directly.
- Discharge coverage in local fwapg: 123 WSGs; **46 of `fresh_default`'s 55** are
  covered (calibration pool). #284's held-out BULL, CLRH, ELKR, LILL, REVL, UARL are
  covered and not in `fresh_default` — natural held-out candidates. Their surviving
  `working_score_*` schemas lack `mad_m3s` (built pre-#286), so the base is rebuilt
  into a new prefix rather than patched.
- Every shipped bundle is all `cw`, so landing MAD values in `default_tuned` changes
  **no output** until a group is moved to `mad`. Scoring therefore needs variant
  bundles that put the focal groups on `mad`.
- Band scoring with the no-range base in the ladder would make the core waterbody-only
  habitat. The core is instead the cw base ∩ every ranged mad step
  (`schema_core` already takes a list), i.e. habitat both models and every step keep.

## Phase 1: Measure — mad_m3s at observations (calibration WSGs)
- [x] ~~Generalise `query_habitat_thresholds_obs.R`~~ — replaced (CH/BT-specific
      throughout) by a sibling driver `data-raw/query_habitat_thresholds_mad.R` that uses
      `lnk_habitat_validate()` as the instrument with every calibration WSG on `mad`;
      decision rule fixed in its header and committed before the first full run
      (P05; any-stage fallback for thin spawn cells; n ≥ 30; floor to 2 s.f.; max 9999)
- [x] ~~Prove the #284 obs outputs reproduce~~ — moot: the #284 script is untouched
- [x] Run for `BT,GR,KO,RB` into `data-raw/logs/habitat_thresholds_302/` over the 46
      discharge-covered `fresh_default` WSGs; coverage recorded (9–28 % of tested
      locations on lines with no discharge)
- [x] BC-native width ↔ MAD equivalence (`width_mad_equivalent.txt`)

## Phase 2: FISS and literature
- [ ] `query_habitat_thresholds_fiss.R`: `--species`, `--out`, snapped segment `mad_m3s`
      (defaults reproduce #284 on today's inputs); run for BT,GR,KO,RB into
      `habitat_thresholds_302/` (aggregates only)
- [x] Literature review (`planning/active/literature.md`; local Zotero full texts; two
      key citations spot-checked against source text)
- [ ] `research/habitat_thresholds.md` "MAD (discharge)" section: verdicts, method, the
      operator's Change 1 (thin-spawn fallback), literature, and the **scoring design
      fixed before any run** (expected-count floor of record; core = the mad rungs)

## Phase 3: Power check, then fix the scoring set
- [ ] `data-raw/logs/habitat_score_302/power_windows.{R,txt}`: counts per MAD window on
      covered non-calibration WSGs before any build
- [ ] `wsg_roles_302.csv` (held-out BT 7, GR 3, RB 6; PARS/KOTL in-sample; HERR/LNTH left
      out for their Fraser closures; 20-WSG closure); KO unscorable (no held-out WSG),
      lands unscored

## Phase 4: mad dimension in the variants harness
- [ ] `model` / `set` columns, method table per `mad` bundle, `method_sha256`, anchor
      rungs, `_min` direction, `--floor`, `--working-prefix` (derived from `--prefix`),
      core of a MAD ladder = its rungs, set restricted to `*_mad_*`, ladder consistency
      checks; #284 re-score reproduces its committed outputs
- [ ] `variants_302.csv`: 6 ladders (BT/GR/RB × spawn/rear), anchor P10 → P05 → P02, the
      other stage's range held fixed in `set`
- [ ] Pre-flight on one held-out WSG, then the full build into `score302_` (detached)

## Phase 5: Score and land
- [ ] `habitat_variants_score.R` over the ladders → `data-raw/logs/habitat_score_302/`
      (verdict.csv, both n-floor readings as in #284), plus capture/cost
      (`share_*`, `*_km`) before/after from `lnk_habitat_validate()`.
- [ ] Land taken values in `default_tuned/parameters_habitat_thresholds.csv`; update its
      provenance checksums and `config.yaml` description; `default` untouched.
- [ ] Results section in `research/habitat_thresholds.md`; RUNBOOK §7 note that
      `default_tuned` now carries MAD ranges for all stream species; NEWS entry.

## Verification
- `devtools::test()` (bundle/dictionary/provenance tests: `test-dictionaries.R`,
  config hash/provenance tests) and `lintr::lint_package()`.
- `lnk_config("default_tuned")` provenance verifies (no `config_drift`).
- Harness: #284 invocation still builds/asserts identically on one WSG; mad variant on
  the pre-flight WSG shows BT stream habitat > 0 where the no-range base had none.
- The band verdicts are read from held-out WSGs only.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

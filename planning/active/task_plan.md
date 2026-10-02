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
- [ ] Run for `BT,GR,KO,RB` into `data-raw/logs/habitat_thresholds_302/` over every
      discharge-covered `fresh_default` WSG; record coverage (share of obs with NULL
      `mad_m3s`)

## Phase 2: FISS and literature
- [ ] Extend `data-raw/query_habitat_thresholds_fiss.R` with `mad_m3s` at FISS sites
      for the four species (aggregates only — link is public).
- [ ] Literature search (Zotero / lit-search) for discharge ranges by species × stage.
- [ ] `research/habitat_thresholds.md`: new "MAD (discharge)" section — one verdict per
      threshold (obs P05, availability, FISS, literature), and the **scoring rule fixed
      before any run** (same 0.5 × core density, n ≥ 10 held-out, walk-outward rule as
      #284; core = cw base ∩ ranged steps).

## Phase 3: Power check, then fix the scoring set
- [ ] Count held-out observation locations per mad window (P02/P05/P10 ladder) per
      species × stage on candidate covered, non-calibration WSGs, before any build.
- [ ] Choose held-out / in-sample WSGs (`data-raw/habitat_score/wsg_roles_302.csv`);
      drop species × stage that cannot reach n ≥ 10, recorded as unscorable (as CH was).

## Phase 4: mad dimension in the variants harness
- [ ] `variants.csv` schema gains `model` (`cw` | `mad`); a `mad` variant's thin bundle
      also writes a `parameters_habitat_method.csv` with the focal WSGs on `mad`.
      Defaults keep #284's files byte-valid (empty `model` = `cw`).
- [ ] Allow a variant to change more than one cell when they are the same
      species × stage's `mad_min`/`mad_max` pair (or seed `mad_max` 9999 in a step 0);
      keep the "differs in exactly the declared cells" assertion.
- [ ] Invariants: cw identity check unchanged; for `mad` variants assert the focal
      groups classified on `mad` (validator's `model` column) and that `mad_m3s` is
      non-NULL on the working streams.
- [ ] `data-raw/habitat_score/README.md` documents the new column; `variants_302.csv`
      holds the ladders. Score script: `schema_core` = cw base + ranged steps.
- [ ] Pre-flight on one small held-out WSG (`--wsgs=`), then the full build into
      prefix `score302_` (detached; repo untouched while it runs).

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

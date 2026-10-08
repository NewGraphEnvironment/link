# Task: wetland_ha_min now gates rearing in fresh (fresh#237); default* outputs move (#311)

NewGraphEnvironment/fresh#237 makes a `waterbody_type: W` rule's `wetland_ha_min` gate the main `rear` predicate. Before, it reached only `wetland_rearing`. link's `default*` bundles declare it for BT, CH, CO, RB, ST and WCT, so `rearing` narrows on the next run.

## Context

fresh v0.38.0 (fresh#237, PR #245) makes a `waterbody_type: W` rule's `wetland_ha_min` gate the main `rear` predicate as well as `wetland_rearing`. link pins fresh v0.36.2, so none of that reaches link until the pin moves. Pinning ≥0.38 also brings in v0.37.0 (fresh#240): buckets are sized by area alone, and BT on NATR goes from 310 to 521 lake km and from 684 to 1,287 wetland km.

The open bundle question was the `edge_types_explicit: [1050, 1150], thresholds: false` wetland-flow carve-out, which has no area floor. Measured read-only on source lines (NATR/PARS/ADMS/BULK): **every** 1050/1150 line sits in a `fwa_wetlands_poly` polygon (no NULL `waterbody_key`, none outside a wetland). 1,875 lines (153 km) are in wetlands under 1 ha and 8,652 (1,702 km) in larger ones. fresh measured ~26 km of NATR BT rearing in the sub-1 ha set.

**Decisions (operator, 2026-10-07):**
1. Floor the carve-out. When a species declares `rear_wetland_ha_min`, the carve-out becomes `waterbody_type: W` + `wetland_ha_min`, so a declared floor bounds all wetland rearing. bcfishpass has no such column, so it does not change.
2. The pin bump lands here, to **v0.39.0** (floor `>= 0.38.0`). #311 measures both movements, so #310 starts from a measured baseline.

**Mechanics that shaped this:**
- fresh picks the bucket rule and the `requires_connected` anchor with `.frs_find_waterbody_rule(rules$rear, "W")`, the **first** W rule (`fresh@v0.38.0 R/frs_habitat_predicates.R:205`). The floored carve-out is therefore emitted **after** the polygon W rule (`R/lnk_rules_build.R:330-366`), so the first W rule and #310's anchor stay the same.
- In the unfloored case the carve-out keeps its current position and shape, which keeps `bcfishpass/rules.yaml` byte-identical.
- The fresh ≥0.37 rules loader rejects `requires_connected` on any rear rule other than the first L/W rule. link emits it only on SK/KO **spawn** rules, so every bundle should load. This gets verified, not assumed.
- `lnk_habitat_validate()` builds its predicates from fresh's compiled SQL, so it follows the change with no code edit.

## Phase 1: Pin fresh v0.39.0
- [ ] `DESCRIPTION`: `Remotes: NewGraphEnvironment/fresh@v0.39.0`, `Imports: fresh (>= 0.38.0)`
- [ ] Install fresh v0.39.0 locally. `frs_params()` loads every bundle's `rules.yaml` (bcfishpass, default, default_extrabreaks, default_rearbreaks) with no loader error
- [ ] `lnk_preflight_fresh()` symbol/formal lists still hold, and the drift guard `.lnk_fresh_callsites()` is green
- [ ] `devtools::test()` is green against v0.39.0

## Phase 2: Floor the wetland-flow carve-out (tests first)
- [ ] Tests in `tests/testthat/test-lnk_rules_build.R`:
  - `rear_wetland_ha_min` set → the carve-out carries `waterbody_type: W`, `wetland_ha_min`, edges 1050/1150, `thresholds: false`, and comes after the polygon W rule;
  - blank, absent or non-numeric → the carve-out is unchanged, with no `waterbody_type` and its current position;
  - the first W rule in the rear list is the polygon rule (edges 1000/1100);
  - the `edge_types = "categories"` branch gets the same treatment;
  - `rear_wetland_polygon = no` + floor set → floored carve-out alone, with the bucket consequence stated in the test.
- [ ] Update the existing guards near `test-lnk_rules_build.R:441,842,942` so they still find the dedicated carve-out
- [ ] `R/lnk_rules_build.R`: emit the floored carve-out after the polygon rule when `rwhm` is finite; otherwise keep the current emission. Comment why the order matters (first W rule = bucket + `requires_connected` anchor)
- [ ] `Rscript data-raw/build_rules.R`, then `git diff` every `rules.yaml`. The default* diffs are only the moved and floored carve-outs for BT, CH, CO, RB, ST and WCT; `bcfishpass/rules.yaml` is byte-identical; provenance checksums are updated
- [ ] `configs/dictionary_dimensions.csv`: the `rear_wetland_ha_min` description says it bounds both wetland rear rules
- [ ] Load every regenerated `rules.yaml` through `fresh::frs_params()` (v0.39.0)

## Phase 3: Measure on one segmentation
Stamp the environment in each log header: link and fresh version + SHA, fwapg state, bcfishobs row count. Logs go to `data-raw/logs/wetland_floor_311/` with a README.
- [ ] Prepare NATR, PARS, BULK and ADMS once each under `default` into scratch schemas, then re-classify/connect three ways (pattern: `data-raw/logs/habitat_thresholds_282/reclassify.R`):
  - **A:** fresh v0.36.2 with the old rules;
  - **B:** v0.39.0 with the old rules (the upstream movement only);
  - **C:** v0.39.0 with the new rules (adds the carve-out floor).
- [ ] Per WSG × species, report:
  - `rearing` km and segments;
  - `lake_rearing` / `wetland_rearing` km and ha;
  - rearing km left in wetlands below the species' floor, which should be ≈0 under C for floored species.

  Frame each as a departure from the bcfishpass reference.
- [ ] Check A→B against fresh's published numbers: NATR BT −40 segments / −2.1 km rearing, PARS BT −60 / −3.1 km, BULK CO −2; NATR BT buckets 310 → 521 lake km and 684 → 1,287 wetland km. Investigate any large mismatch before going on
- [ ] `lnk_habitat_validate()` on NATR BT and CO rearing, A against C: observation capture lost, and km cost

## Phase 4: Docs and issue hygiene
- [ ] `RUNBOOK.md` §7 (~line 720): `wetland_ha_min` now gates rearing; the carve-out is floored in default*; first-W-rule ordering
- [ ] `CLAUDE.md`:
  - new Status entry;
  - correct the stale facts ("fresh's main rear predicate ignores a W rule's `wetland_ha_min`", and "link still pins fresh v0.36.2");
  - note that cyphers need a re-prep for the new pin.
- [ ] Departures list in `configs/default/README.md`. Add a `research/habitat_thresholds.md` section with the measurement
- [ ] Edit the #310 body:
  - decision 7 and the "Not in scope" bullet are stale;
  - the ≥0.37 pin precondition is now met;
  - the floored carve-out sits after the polygon rule, so `add_rc()`'s first-W anchor is still the polygon rule.
- [ ] Edit the #311 body with the outcome
- [ ] NEWS entry (minor bump, because outputs move) as the final commit before the PR


## Critical files
- `DESCRIPTION`
- `R/lnk_rules_build.R` (rear wetland block, lines 330-366)
- `tests/testthat/test-lnk_rules_build.R`
- `inst/extdata/configs/{default,default_extrabreaks,default_rearbreaks}/rules.yaml` (generated) and `config.yaml` provenance
- `inst/extdata/configs/dictionary_dimensions.csv`
- `RUNBOOK.md`, `CLAUDE.md`, `research/habitat_thresholds.md`, `configs/default/README.md`, `NEWS.md`

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

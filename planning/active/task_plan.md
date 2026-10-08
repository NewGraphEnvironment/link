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
- [x] `DESCRIPTION`: `Remotes: NewGraphEnvironment/fresh@v0.39.0`, `Imports: fresh (>= 0.38.0)`
- [x] Install fresh v0.39.0 locally (`e247ca1`, after run A). `frs_params()` loads every bundle's `rules.yaml` (bcfishpass, default, default_extrabreaks, default_rearbreaks, default_tuned, top-level) with no loader error
- [x] `lnk_preflight_fresh()`: "fresh 0.39.0 (floor 0.38.0) - OK, all required symbols present"; drift-guard test green in the suite
- [x] `devtools::test()` against v0.39.0: 0 failures, 16 warnings (the pre-existing "incomplete final line" on a bcfishpass override CSV)

## Phase 2: Floor the wetland-flow carve-out (tests first)
- [x] Tests in `tests/testthat/test-lnk_rules_build.R`:
  - `rear_wetland_ha_min` set → the carve-out carries `waterbody_type: W`, `wetland_ha_min`, edges 1050/1150, `thresholds: false`, and comes after the polygon W rule;
  - blank, absent or non-numeric → the carve-out is unchanged, with no `waterbody_type` and its current position;
  - the first W rule in the rear list is the polygon rule (edges 1000/1100);
  - the `edge_types = "categories"` branch gets the same treatment (cosmetic: that carve-out matches no lines, see findings);
  - *revised after plan review:* `rear_wetland_polygon = no` + floor set → carve-out stays **unfloored**, so there is no W rule and the first L/W rule is still L. A floored carve-out there would become fresh's bucket rule. Mutation-checked: an unconditional floor turns 3 assertions red.
- [x] Existing guard near `test-lnk_rules_build.R:942` (shipped default rules) also asserts BT's carve-out carries `waterbody_type: W` + `wetland_ha_min: 1`; the guards at :441 and :842 need no change
- [x] `R/lnk_rules_build.R`: emit the floored carve-out after the polygon rule when `rwhm` is finite and the polygon rule is emitted; otherwise keep the current emission. Comment says why the order matters (first W rule = bucket + `requires_connected` anchor; first L/W = waterbody-connected spawning)
- [x] Built to tempfiles and diffed first (`build_rules.R` regenerates only `default`, `bcfishpass` and the top-level yaml). The default* and top-level diffs are only the moved and floored carve-outs for BT, CH, CO, RB, ST and WCT (CT/DV are skipped by the builder) plus the `# Generated:` line. `bcfishpass` differs only in that line, so it was not written. `default/rules.yaml` was copied into `default_extrabreaks` and `default_rearbreaks` (byte-identical copies before and after); `checksum` updated in all three `config.yaml`; `lnk_config_verify()` reports 0 drift on all five bundles
- [x] `generator_sha` in the three `config.yaml` → `0ca706b` (Phase 4 commit)
- [x] `inst/extdata/configs/dictionary_dimensions.csv`: `rear_wetland_ha_min`, `rear_wetland` and `rear_wetland_polygon` rows describe the floor, its placement and the polygon = no case
- [x] `data-raw/query_habitat_thresholds_mad.R`: stale comment ("fresh's rear predicate does not apply wetland_ha_min") reworded
- [x] Load every regenerated `rules.yaml` (default*, top-level, and `default_tuned` via `lnk_config()`) through `fresh::frs_params()` v0.39.0; the floored clause compiles for BT CH CO RB ST WCT in every default* bundle and the top-level copy, none in bcfishpass

## Phase 3: Measure on one segmentation
Logs in `data-raw/logs/wetland_floor_311/` (README carries the tables; `measure.csv` stamps link/fresh SHAs and `cfg_hash` per row, `stamp_<run>.txt` the `lnk_stamp()`).
- [x] Built NATR, PARS, BULK and ADMS once each under `default` into `zz311_<wsg>` (frozen worktree at `664ec2d`, fresh 0.36.2), then re-classified three ways: **A** fresh v0.36.2 + old rules; **B** v0.39.0 + old rules; **C** v0.39.0 + new rules (frozen worktree at `0ca706b`). Snapshots in `zz311_snap.<wsg>_<run>`
- [x] Per WSG × species: `rearing` km/segments, bucket km/ha, sub-floor rearing (all edges, and 1050/1150 only), bcfishpass reference km (`summary.csv`). Sub-floor wetland-flow rearing is 0 under C for every floored species
- [x] A→B matches fresh's published numbers exactly (NATR BT −40 / −2.124 km; PARS BT −60 / −3.128 km; BULK CO −2; NATR BT buckets 309.9 → 521.4 lake km, 683.9 → 1,287.3 wetland km)
- [x] Observation exposure, *revised after plan review* to B vs C (the floor) and A vs B (fresh), with a direct query (`obs.R`) because `lnk_habitat_validate()` scores persisted schemas, not scratch working schemas: B→C loses 3 of 2,265 locations on rearing, A→B loses 0
- [x] `research/habitat_thresholds.md`: new section "The wetland floor on `rearing` (#311)"; the #307 bucket bullet updated

## Phase 4: Docs and issue hygiene
- [x] `RUNBOOK.md` §7: buckets area-only since fresh 0.37.0; `wetland_ha_min` gates rearing; the carve-out floor, its order, the polygon = no case, the 40 NULL-key lines, and the stream-rule caveat
- [x] `CLAUDE.md`: new Status entry; stale facts corrected (pin, `wetland_ha_min` ignored, rear range gating buckets, in two entries); cyphers need a re-prep
- [x] `configs/default/README.md` departures list; `research/habitat_thresholds.md` section (Phase 3 commit, corrected here)
- [x] #310 body: decision 7 superseded, "Not in scope" bullet struck, pin precondition met, `add_rc()` must stamp only the first (polygon) W rule
- [x] #311 body: Outcome section
- [x] NEWS entry and version bump: **deferred to `/gh-pr-merge`**, which writes the release commit on main after the merge (repo practice: `885e044 Release v0.59.0` follows merge `d6f8fd1`)
- [x] `/code-check` on the Phase 3 scripts + Phase 1/4 diff (Phase 3 was committed before it ran): round 1 five findings, round 2 eight (one class inside round 1's fixes), all fixed; ended by enumerating the four defect classes round 2 named across every touched doc and both issue bodies

## Validation

- [x] Tests pass (`devtools::test()`: 0 failures; `devtools::check()`: 0 errors, 3 warnings + 2 notes, all in files this branch does not touch; `lintr` on `R/lnk_rules_build.R`: no new lints, 23 → 21)
- [x] `/code-check` on each code commit (Phase 2: 3 clean rounds; Phase 3 scripts: checked post-commit, fixes in the Phase 4 commit)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

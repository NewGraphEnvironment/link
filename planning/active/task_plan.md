# Task: Default lake and wetland rearing: connected to spawning, centrelines kept, km and ha broken out (#310)

In `default`, a species' lake and wetland rearing counts only water it can reach from its own spawning, within a distance the bundle states. CO rears in lakes and wetlands of any size. Rollups report rearing km separately for streams, lake centrelines and wetland centrelines, with lake and wetland hectares beside them, and say that a lake's km and its hectares describe the same water.

## Context

`default`'s lake rear rule admits almost nothing: `lnk_rules_build()` filters it to edge
1000/1100 (`R/lnk_rules_build.R:390-392`), and lake polygons hold **no** 1000/1100 lines.
Measured on NATR/ADMS/PARS/BULK (fwa_stream_networks_sp × fwa_waterbodies):
L polygons carry 1200 (1,242 km), 1450 (725), 1475 (11), 1400 (7), 1300 (4); reservoirs (X)
1200/1400/1450. Buckets (`lake_rearing` / `wetland_rearing`) ignore spawning unless the first
L/W rear rule carries `requires_connected: spawning` + `connected_distance_max` (fresh ≥ 0.37,
validated in fresh `R/frs_params.R:178-205, 376-400`). `add_rc()` today stamps the old
`rear_requires_connected` on *every* rear rule, which fresh refuses once set. CO carries
2 ha / 0.5 ha floors nobody decided on. The rollups slice km by **edge type**
(`1500/1525` shorelines as "lake centerline", `1700` as "wetland centerline"), in two
places plus the bcfp reference side (`R/lnk_compare_wsg.R:236-260, 410-433`,
`R/lnk_compare_rollup.R:196-231`).

Facts that shape the plan:
- `bcfishpass` has only SK's lake-only L rule and zero W rules, so changes confined to the
  additive rear branch leave its `rules.yaml` byte-identical.
- CO's fallback in the bundle thresholds CSV is NA, so blanking the dims cells removes the floor.
- fresh's `.frs_waterbody_tables("L")` already includes `fwa_manmade_waterbodies_poly`
  (decision 5 is true in fresh; link's ha rollup joins only `fwa_lakes_poly` — that is the gap).
- `default_extrabreaks` / `default_rearbreaks` carry copies of default's dims (cols 1-31
  identical) and their own `rules.yaml`; #311 kept them in step, so this does too.
  `default_tuned` inherits.

## Operator decisions at the plan gate (2026-10-07)
- Connected spawning applies to **every** additive-branch lake/wetland rearer: BT, CH, CO, CT, DV, GR, RB, ST, WCT (GR: lake only, `rear_wetland = no`). SK/KO unchanged.
- Rollup columns: **rename + redefine** — `rearing_stream_km`, `rearing_lake_km`, `rearing_wetland_km` by waterbody_key, link and bcfp reference sides; `*_centerline_km` removed (breaking; NEWS says so).
- Wetland 1200/1300/1400 construction lines: **left as scoped**; the 464 km (4 WSGs) recorded in findings, follow-up issue drafted.
- Distances: **I research and pick**, values + reasons reported in the PR for review before merge.

## Phase 1: Distances and literature (research)
- [x] Read fresh `data-raw/logs/bucket_connected_240/` (0.5–10 km ladder, NATR/PARS BT)
- [x] Literature pass (Zotero library read from its local store; the Zotero MCP is unconfigured): adfluvial lake use for BT, RB, GR, ST; CO off-channel / overwintering wetland and lake use; bcfp precedent SK 3 km
- [x] Pick per-species `rear_lake_connected_distance_max` / `rear_wetland_connected_distance_max` (m); write `research/habitat_thresholds.md` section "Lake and wetland rearing connected to spawning" with values, sources, ladder evidence

## Phase 2: Rules builder (tests first)
- [ ] Tests in `tests/testthat/test-lnk_rules_build.R`:
  - additive L rule carries `edge_types_explicit: [1200, 1300, 1400, 1450, 1475]` + `thresholds: false`; with `area_only: true` the rule feeds only the bucket, so the edge set is moot there
  - `requires_connected: spawning` + `connected_distance_max` on the first L and first W rear rule only; the floored 1050/1150 W rule and stream/river rules never carry it
  - result loads through fresh's `frs_params()` validators (no "requires_connected must be on the first" error)
  - `area_only = yes` on the lake rule of a species with `spawn_requires_connected: rearing` (SK/KO) errors at build
  - legacy `rear_requires_connected` / `rear_connected_distance_max`: ignored when empty, error naming the new columns when set
  - bcfishpass `rules.yaml` rebuilt to a tempfile equals the committed one
- [ ] `R/lnk_rules_build.R`: new per-type columns read; `add_rc()` replaced by first-L / first-W stamping; lake edge set + `thresholds: false`; SK/KO area_only refusal; legacy-column guard
- [ ] Confirm the lake edge set against `fwa_edge_type_codes` (1300 "secondary flow", 1400 "other flow/inferred connection" included; 1410 connector, 1425 subsurface excluded) and record in findings

## Phase 3: Bundle data
- [ ] `configs/default/dimensions.csv` (+ `default_extrabreaks`, `default_rearbreaks`, top-level `parameters_habitat_dimensions.csv` mirror): add the two distance columns with Phase 1 values; CO blank `rear_lake_ha_min` / `rear_wetland_ha_min`; legacy columns left empty
- [ ] `dictionary_dimensions.csv`: rows for the two new columns; legacy rows marked retired (test-dictionaries union coverage holds)
- [ ] `data-raw/build_rules.R` → regenerate all rules.yaml; `git diff` matches intent (L edges, connected keys, CO floors gone; bcfishpass untouched); update provenance checksums in each touched `config.yaml`

## Phase 4: Rollups (tests first)
- [ ] `lnk_rollup_wsg()`: expose `waterbody_type` alias (LEFT JOIN `whse_basemapping.fwa_waterbodies` on `waterbody_key`; L and X → lake, W → wetland, R/none → stream); default metrics gain `rearing_stream_km`, `rearing_lake_km`, `rearing_wetland_km`
- [ ] Persist path `.lnk_compare_rollup_link()` and working path `.lnk_compare_wsg_rollup_link()`: replace edge-type slices with the waterbody_key partition; `lake_rearing_ha` joins lakes ∪ manmade polygons
- [ ] bcfp reference side (`.lnk_compare_wsg_rollup_bcfishpass`): same partition (bcfishpass.streams.waterbody_key) and lakes ∪ manmade for ha, so diff columns stay like-for-like
- [ ] Tests: SQL-text tests for the partition; invariant stream + lake + wetland = `rearing_km` (live-DB test, skipped without DB); roxygen states km and ha pairs overlap and are never added; `devtools::document()`

## Phase 5: Validation on one segmentation
Run decisions: config `default` (link's own), scratch working schemas only (never persist to
`fresh` / `fresh_default`), WSGs NATR (all lake species) and ADMS (CO control), build once at
main then `reclassify` at branch — the `data-raw/logs/wetland_floor_311/run.R` pattern, new dir
`data-raw/logs/lake_connected_310/` with stamps.
- [ ] Measure and diff: rearing rises by lake-centreline km for lake species; CO gains sub-2 ha lakes / sub-0.5 ha wetlands; lake/wetland ha drop where disconnected; stream+lake+wetland = total; SK/KO spawning unchanged
- [ ] Count the "known divergence" (ha kept, centreline km dropped) per species; note whether it warrants its own issue
- [ ] Log README with numbers + units

## Phase 6: Docs and upstream drafts
- [ ] `configs/default/README.md` departures list; RUNBOOK §7; `research/habitat_thresholds.md` #307 section (bucket shrink under `mad` was the fresh#240 artifact); CLAUDE.md status; NEWS entry
- [ ] Draft (not file) link follow-up: wetland construction lines (1200/1300/1400) not admitted to wetland rearing
- [ ] Draft (not file) fresh issue: `.frs_run_connectivity()` 200 ha silent fallback for SK/KO when the L rule has no `lake_ha_min`; reservoir-in-bucket is already true in fresh — draft only a doc note if `frs_habitat()` docs don't say so. Drafts shown in the final report for body review.

## Validation
- [ ] Tests pass (`devtools::test()`), lintr clean, `devtools::check()` for the release
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion, then `/gh-pr-push` (merge is a separate instruction)


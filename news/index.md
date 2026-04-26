# Changelog

## link 0.9.0

[`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md)
now overlays known habitat from `user_habitat_classification.csv` onto
`fresh.streams_habitat` after rule-based classification. Closes
[\#55](https://github.com/NewGraphEnvironment/link/issues/55).

- After `frs_habitat_classify()` finishes, calls `frs_habitat_overlay()`
  (fresh ≥ 0.21.0) when the manifest declares `habitat_classification`.
  Loaded long-format table is overlaid via a 3-way bridge join through
  `fresh.streams` (range containment on `[drm, urm]`).
- Closes the gap surfaced in research doc §5/§7: bcfishpass’s published
  `streams_habitat_linear.spawning_sk > 0` blends model +
  observation-curated knowns; link’s pipeline previously only emitted
  the model side.
- 5-WSG rerun (digest `0f00c713`) shows BABL SK spawning under
  bcfishpass bundle rises from 57.6 → 85.2 km (+27.6 km from overlay).
  ADMS SK +5.14 km, BULK SK +0.8 km. Default bundle similar magnitudes.
- Requires fresh ≥ 0.21.0 (overlay rename + bridge support; see
  fresh#175).

## link 0.8.0

Default NewGraph habitat-classification config bundle ships alongside
the bcfishpass reproduction bundle
([\#51](https://github.com/NewGraphEnvironment/link/issues/51)).

- New `inst/extdata/configs/default/` bundle — intentional
  methodological departures from bcfishpass: intermittent streams
  included in rearing, wetland rearing added for resident species, lake
  rearing extended to species beyond SK/KO with per-species
  `rear_lake_ha_min` thresholds, `river_skip_cw_min = yes`. Loadable via
  `link::lnk_config("default")`.
- Per-species `rear_lake_ha_min` via a new column in
  `configs/default/dimensions.csv`.
  [`lnk_rules_build()`](https://newgraphenvironment.github.io/link/reference/lnk_rules_build.md)
  prefers that value over the shared
  `fresh::parameters_habitat_thresholds` default when present, keeping
  bcfishpass bundle at its 200 ha threshold for SK/KO while letting
  default express species-specific biology (CO 2 ha, BT/WCT/RB/CT/DV 10
  ha, GR 40 ha, ST 60 ha, CH 100 ha, SK/KO 200 ha). Non-numeric entries
  in the dimensions CSV fall through to the fresh fallback rather than
  silently disabling it.
- Per-species `rear_wetland_ha_min` via a new column in
  `configs/default/dimensions.csv`.
  [`lnk_rules_build()`](https://newgraphenvironment.github.io/link/reference/lnk_rules_build.md)
  now emits both `edge_types: wetland` (for rearing km) AND
  `waterbody_type: W` (drives `wetland_rearing_ha` rollup) rules when
  `rear_wetland = yes`. Thresholds: CO 0.5 ha (beaver complexes),
  BT/CH/CT/DV/RB/ST/WCT 1 ha.
- SK + KO spawn_connected block — added five columns to
  `configs/default/dimensions.csv` (`rear_stream_order_bypass`,
  `spawn_connected_direction`, `spawn_connected_gradient_max`,
  `spawn_connected_cw_min`, `spawn_connected_edge_types`) so
  [`lnk_rules_build()`](https://newgraphenvironment.github.io/link/reference/lnk_rules_build.md)
  emits the `spawn_connected:` block with `direction: downstream` for
  lake-obligate species. `spawn_lake = no` for SK/KO to prevent
  lake-centerline inflation (Babine Lake alone is 177 km).
- `data-raw/compare_bcfishpass_wsg()` emits a compound rollup with 7
  rows per species × WSG × config: `spawning`/`rearing` km,
  `lake_rearing`/`wetland_rearing` ha, plus three edge-type slice rows
  (`rearing_stream`, `rearing_lake_centerline`,
  `rearing_wetland_centerline`) for decomposing the rearing total.
  Reference side uses the same `habitat_linear_<sp>` +
  `fwa_{lakes,wetlands}_poly` methodology as link, so both sides are
  apples-to-apples.
- `data-raw/_targets.R` runs both bundles side-by-side across all 5
  validation WSGs (ADMS, BULK, BABL, ELKR, DEAD) — 10 comparison
  targets, unified rollup with a `config` identity column. Rollup digest
  `e3eaf5f62df44d6713bfed32cd08fc5d` (357 rows) on M1 with fresh 0.17.1.
- New research doc `research/default_vs_bcfishpass.md` — methodology
  comparison, per-WSG per-species results, 9 observations covering the
  debugging journey (SK spawning over-inflation root causes, bcfishpass
  known-habitat overlay via `streams_habitat_known`, gradient-floor
  calibration, segment-averaging risk).
- Three companion maps (`data-raw/maps/sk_spawning_BABL*.R`) — mapgl
  overlays of SK spawning BABL comparing bundle-vs-bundle and
  default-vs-bcfishpass-published (model + known); per-layer toggle,
  popups with `id_segment` / `segmented_stream_id` / plain-language
  edge_type / gradient / length.
- Requires `fresh >= 0.17.1` for `waterbody_type: L/W` rear-rule
  honouring + `lake_ha_min` / `wetland_ha_min` thresholds.
- `tests/testthat/test-lnk_rules_build.R` — new suite with 56 tests
  covering lake + wetland rule emission (per-config ha_min, fresh
  fallback, rear_lake=no / rear_wetland=no), spawn rules (stream+canal
  vs explicit codes, spawn_lake, spawn_requires_connected,
  spawn_connected block), rear precedence (no_fw, lake_only, all_edges),
  river polygon + river_skip_cw_min, species skipping,
  rear_stream_order_bypass, non-numeric ha_min fallthrough.

## link 0.7.0

`user_barriers_definite` no longer eligible for observation-based
override
([\#48](https://github.com/NewGraphEnvironment/link/issues/48)).

- `.lnk_pipeline_prep_natural()` previously unioned `barriers_definite`
  into `natural_barriers`, which
  [`lnk_barrier_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_barrier_overrides.md)
  iterates over. Net effect: the 227 reviewer-added user-definite
  positions (EXCLUSION zones, MISC detections the model misses) could be
  re-opened by observations clearing the species threshold. Confirmed
  active on ELKR pre-fix — 4 override rows at Erickson Creek exclusion
  and Spillway MISC positions that bcfishpass keeps as permanent
  barriers.
- bcfishpass’s `model_access_*.sql` builds the barriers CTE from
  gradient + falls + subsurfaceflow only and appends
  `barriers_user_definite` post-filter via `UNION ALL`. Observations and
  habitat filters never see user-definite rows, so they’re never
  overridable. link now matches this shape: `natural_barriers` is
  gradient + falls only; `barriers_definite` stays consumed separately
  as a break source in
  [`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md)
  and as a direct `UNION ALL` entry into `fresh.streams_breaks` via
  [`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md).
- ELKR rollup shifts toward bcfishpass: BT spawning +3.4% → +2.8%, WCT
  spawning +4.0% → +2.6%, WCT rearing +1.6% → +0.3%. Other four WSGs
  unchanged (ADMS/BABL/DEAD have empty `barriers_definite`; BULK has 87
  rows but no observation-threshold matches to any of them).

## link 0.6.0

Honour `user_barriers_definite_control.csv` at the observation-override
step.

- [`lnk_barrier_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_barrier_overrides.md)
  now excludes observations upstream of control-flagged positions from
  counting toward the override threshold, matching bcfishpass’s access
  SQL. Previously controlled positions (concrete dams, long impassable
  falls, diversions) could be re-opened by upstream historical
  observations
  ([\#44](https://github.com/NewGraphEnvironment/link/issues/44)).
- Gated per-species by a new `observation_control_apply` column in
  `parameters_fresh.csv` — TRUE for CH/CM/CO/PK/SK/ST; FALSE for BT/WCT;
  NA for CT/DV/RB. Residents routinely inhabit reaches upstream of
  anadromous-blocking falls (post-glacial headwater connectivity, no
  ocean-return requirement), so their observations still override.
  Matches bcfishpass’s per-model application.
- Habitat-confirmation override path intentionally bypasses the control
  table — expert-confirmed habitat is higher-trust than observations,
  and bcfishpass’s `hab_upstr` CTE has no control join either.
- `.lnk_pipeline_prep_overrides` now passes the control table to
  [`lnk_barrier_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_barrier_overrides.md)
  when the config manifest declares `barriers_definite_control`.
  Manifest key is the contract; no DB probe.
- `.lnk_pipeline_prep_load_aux` now always creates a schema-valid
  (possibly empty) `barriers_definite_control` table when the manifest
  declares the key — fixes an asymmetric gating bug that would have
  raised “relation does not exist” on AOIs with zero control rows.
- End-to-end validation WSG: DEAD (Deadman River) added to
  `data-raw/_targets.R`. It has a single `barrier_ind = TRUE` control
  row at FALLS (356361749, 45743) with six anadromous observations
  upstream and zero habitat coverage — the unique combination that
  actively exercises the filter. All four prior WSGs
  (ADMS/BULK/BABL/ELKR) were rescued by either the observation threshold
  or habitat path, making them parity checks rather than filter tests.

## link 0.5.0

Documentation and narrative for the targets pipeline.

- New vignette: “Reproducing bcfishpass with link + fresh” — three-line
  entrypoint, rollup interpretation, BULK chinook habitat map (mapgl),
  reproducibility framing. Data-prep script at
  `data-raw/vignette_reproducing_bcfishpass.R` generates
  `inst/extdata/vignette-data/{rollup,bulk_ch}.rds` from a real run;
  vignette loads the `.rds` so pkgdown builds don’t need fwapg access.
  Follows the CLAUDE.md convention for vignettes that need external
  resources
  ([\#38](https://github.com/NewGraphEnvironment/link/issues/38))
- Research doc (`research/bcfishpass_comparison.md`) updated with
  bit-identical rollup numbers from 2026-04-22 and a new “Targets
  orchestration” section showing how `_targets.R` composes the per-WSG
  runs.
- `mapgl`, `sf` added to DESCRIPTION Suggests.
- Retired `data-raw/compare_bcfishpass.R` — `data-raw/_targets.R` +
  `data-raw/compare_bcfishpass_wsg.R` supersede it. Git history
  preserves the prior form.

## link 0.4.0

Targets-driven comparison pipeline for all four validated watershed
groups.

- Add `data-raw/_targets.R` —
  `tar_map(wsg = c("ADMS", "BULK", "BABL", "ELKR"))` over a per-AOI
  target function, synchronous execution,
  [`dplyr::bind_rows`](https://dplyr.tidyverse.org/reference/bind_rows.html)
  rollup. `fresh.streams` is a shared schema so single-host parallelism
  would collide — runs serially today; distributed runs (M4 + M1) are a
  follow-up alongside a fresh upstream change for per-AOI output paths
  ([\#38](https://github.com/NewGraphEnvironment/link/issues/38))
- Add `data-raw/compare_bcfishpass_wsg(wsg, config)` — per-AOI target
  function. Wraps the six `lnk_pipeline_*` phases, diffs the output
  against `bcfishpass.habitat_linear_*` reference on the tunnel DB,
  returns a ~10-row tibble
  (`wsg × species × habitat_type × link_km × bcfishpass_km × diff_pct`).
  KB-scale — safe to ship over SSH.
- Promote `.lnk_pipeline_classify_species` to an exported
  `lnk_pipeline_species(cfg, aoi)` — canonical public API for “species
  this config classifies in this AOI.” Used by `lnk_pipeline_classify`
  and `lnk_pipeline_connect` internally and by the targets per-AOI
  function externally. Removes the duplicate private helper that was
  briefly inlined in `data-raw/`.
- End-to-end verification
  (`data-raw/logs/20260422_11_tar_make_final.txt`) — 4 WSGs / 34 rows
  produced over 8.5 minutes wall clock (serial). **Reproducibility:**
  consecutive
  [`tar_make()`](https://docs.ropensci.org/targets/reference/tar_make.html)
  invocations on the same DB state produce bit-identical rollup tibbles.
  **Parity to bcfishpass (informational):** all 34 `diff_pct` values
  within 5% of reference; research-doc drift (BT rearing: -0.7 → -1.1
  pp) traces to env state between 2026-04-15 and today, not to pipeline
  non-determinism.

## link 0.3.0

Pipeline phase helpers extract the bcfishpass comparison orchestration
into composable building blocks. The 635-line
`data-raw/compare_bcfishpass.R` is now 136 lines of sequenced helper
calls.

- Add
  [`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md)
  — create the per-run working schema
  ([\#38](https://github.com/NewGraphEnvironment/link/issues/38))
- Add
  [`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md)
  — load crossings and apply modelled-fix and PSCIS overrides
- Add
  [`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md)
  — load falls / definite / control / habitat CSVs, detect gradient
  barriers, compute per-species barrier skip list, reduce to minimal set
  via
  [`fresh::frs_barriers_minimal()`](https://newgraphenvironment.github.io/fresh/reference/frs_barriers_minimal.html),
  load base segments
- Add
  [`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md)
  — sequential `frs_break_apply` over observations / gradient / definite
  / habitat / crossings in config-defined order
- Add
  [`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md)
  — assemble access-gating breaks table and run
  [`fresh::frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.html)
- Add
  [`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md)
  — per-species rearing-spawning clustering and connected-waterbody
  rules
- Canonical signature `(conn, aoi, cfg, schema)` — `aoi` follows fresh
  convention (WSG code today; extends to ltree / sf polygons / mapsheets
  later), `schema` is the caller’s per-run namespace (`working_<aoi>` by
  convention) so parallel runs do not collide
- `cfg$species` parsed from the rules YAML at
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md)
  load — intersects with `cfg$wsg_species` presence to pick per-AOI
  classify targets
- Requires fresh 0.14.0 (for `frs_barriers_minimal`)

## link 0.2.0

Config bundles for pipeline variants.

- Add `lnk_config(name_or_path)` — load a config bundle (rules YAML,
  dimensions CSV, parameters_fresh, overrides, pipeline knobs) as one
  list object. Bundles live at `inst/extdata/configs/<name>/` with a
  `config.yaml` manifest, or any directory containing `config.yaml` for
  custom variants
  ([\#37](https://github.com/NewGraphEnvironment/link/issues/37))
- Relocate bcfishpass config files into
  `inst/extdata/configs/bcfishpass/` (rules.yaml, dimensions.csv,
  parameters_fresh.csv, overrides/). All R scripts and data-raw/
  references updated.

## link 0.0.0.9000

Initial release. Crossing connectivity interpretation layer — scores,
overrides, and prioritizes crossings for fish passage using configurable
severity thresholds and multi-source data integration.

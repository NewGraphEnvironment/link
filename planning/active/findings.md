# Findings — Per-bundle habitat thresholds CSV in config.yaml (#282)

## Issue context

**If we do it:** a config bundle can carry its own species gradient, channel-width and MAD thresholds, so a tuned bundle can differ while the `bcfishpass` bundle stays a frozen parity reference. **If we never do:** any threshold change has to go into fresh's shared CSV and moves every bundle at once, parity included.

## Problem

The numeric habitat thresholds (`spawn_gradient_max`, `spawn_channel_width_min`, `rear_gradient_max`, …) come from fresh's `inst/extdata/parameters_habitat_thresholds.csv`. `lnk_pipeline_classify()` and `lnk_pipeline_connect()` take a `thresholds_csv` argument that defaults to fresh's copy (`R/lnk_pipeline_classify.R:58-62`, `R/lnk_pipeline_connect.R:66-69`). `lnk_pipeline_run()` never passes one (`R/lnk_pipeline_run.R:185-188`), and `config.yaml` has no key for it. `dimensions.csv` → `lnk_rules_build()` emits edge, waterbody and area rules but no gradient or channel width, so the rules inherit fresh's CSV at classify time.

Every bundle — `bcfishpass`, `default`, `default_rearbreaks`, `default_extrabreaks` — therefore runs identical thresholds.

Related staleness: `default/config.yaml`'s description says the bundle ships `spawn_gradient_min 0.0025`. `default/parameters_fresh.csv` ships 0; the floor was tested and reverted (`research/default_vs_bcfishpass.md:443-450`).

## Proposed Solution

1. Add `parameters_habitat_thresholds` under `files:` in `config.yaml`, with provenance like the other entries. `lnk_load_overrides()` loads it and `lnk_pipeline_run()` threads it to classify and connect. If a bundle has no such entry, fall back to fresh's copy, with a message saying so.
2. `bcfishpass` bundle: vendor the current fresh CSV, recording the upstream (bcfishpass) SHA. Its values must never change by accident.
3. `default` bundle: its own copy, identical for now.
4. Scaffold a `default_tuned` bundle (`extends: default`), which is where calibrated CH/BT values land.
5. Fix the stale `spawn_gradient_min` sentence in `default/config.yaml`.
6. Test: a bundle with a changed `rear_gradient_max` classifies differently, and `bcfishpass` output is unchanged.

Alternative considered: per-rule `gradient`/`channel_width` in `rules.yaml` (fresh#116 supports it) generated from new `dimensions.csv` columns. It works, but spreads thresholds across two files; a per-bundle CSV keeps one table per bundle and reuses an argument that already exists.

## Provenance of the thresholds CSV

fresh `inst/extdata/parameters_habitat_thresholds.csv` = bcfishpass `parameters/example_newgraph/parameters_habitat_thresholds.csv` (fetched by fresh `data-raw/bcfishpass_params.R`; bcfishpass last touched it at `4699d0f`) + fresh-added `spawn_edge_types`/`rear_edge_types` (fresh#104, `4f52123`). Installed fresh 0.33.0 (`7f12d99`) byte-identical to the v0.34.0 checkout. bcfishpass `example_testing` and `example_cwf` carry *different* CH values (e.g. CH spawn 0.04 / 0.03) — the parity reference is example_newgraph.

## Errors Encountered

| Error | Resolution |
|-------|------------|

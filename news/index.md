# Changelog

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

# Findings: lnk_config (#37)

## Current state of config data

Scattered across the repo:

- `inst/extdata/parameters_habitat_rules_bcfishpass.yaml` — built rules YAML
- `inst/extdata/parameters_habitat_dimensions_bcfishpass.csv` — source of rules YAML
- `inst/extdata/parameters_fresh_bcfishpass.csv` — spawn_gradient_min etc. overrides
- `inst/extdata/wsg_species_presence.csv` — species per watershed group
- `inst/extdata/observation_exclusions.csv` — obs IDs to skip
- Override CSVs — referenced from `data-raw/compare_bcfishpass.R` but live in bcfishpass/data (external)
- Break order, cluster params, spawn_connected rules — hardcoded in `compare_bcfishpass.R`

## Decision: directory-per-config with manifest

Each variant = `inst/extdata/configs/<name>/` with `config.yaml` manifest pointing at all files.

Benefits:
- Portable — user can drop a directory anywhere, pass absolute path to `lnk_config()`
- One place to look — no more hunting across `inst/extdata/` roots
- Per-variant README — each bundle documents its intent

## Return shape (from issue #37)

```r
list(
  name              = "bcfishpass",
  dir               = "<path to config dir>",
  rules_yaml        = "<path to rules.yaml>",
  dimensions_csv    = "<path to dimensions.csv>",
  parameters_fresh  = tibble(...),
  wsg_species       = tibble(...),
  observation_excl  = tibble(...),
  overrides         = list(
    modelled_fixes       = tibble(...),
    pscis_barrier_status = tibble(...),
    pscis_xref           = tibble(...),
    barriers_definite    = tibble(...)
  ),
  break_order       = c("observations", "gradient_minimal", "habitat_endpoints", "crossings"),
  cluster_params    = list(three_phase = TRUE, distance_cap = ...),
  spawn_connected   = list(SK = list(gradient_max = 0.05, ...))
)
```

Keys: `name`, `dir`, `rules_yaml`, `dimensions_csv` stay as paths (rules YAML is consumed by `frs_habitat_classify()` as a path, no reason to parse it here). Other CSVs load eagerly into tibbles.

## Manifest schema (first draft)

```yaml
# inst/extdata/configs/bcfishpass/config.yaml
name: bcfishpass
description: |
  Validation config — reproduces bcfishpass output exactly for regression.
  Do not modify without running the full comparison suite.
files:
  rules_yaml: rules.yaml
  dimensions_csv: dimensions.csv
  parameters_fresh: parameters_fresh.csv
  wsg_species: wsg_species_presence.csv
  observation_exclusions: observation_exclusions.csv
overrides:
  modelled_fixes: overrides/user_modelled_crossing_fixes.csv
  pscis_barrier_status: overrides/user_pscis_barrier_status.csv
  pscis_xref: overrides/pscis_modelledcrossings_streams_xref.csv
  barriers_definite: overrides/user_barriers_definite.csv
pipeline:
  break_order: [observations, gradient_minimal, habitat_endpoints, crossings]
  cluster:
    three_phase: true
  spawn_connected:
    SK:
      gradient_max: 0.05
      distance_max: ...
```

All file paths in the manifest are relative to the config dir.

## Not in scope for #37

- Actually running the pipeline (that's `_targets.R`, link#38)
- Populating `default/` with real departures from bcfishpass (intermittent streams etc. — #19, #20, #21)
- Per-WSG overrides (AOI-agnostic; pipeline handles per-WSG)

## Cross-refs

- rtj/docs/distributed-fwapg.md — targets will use the `$schema_working` convention `working_<wsg>`; `lnk_config` is AOI-agnostic, schema naming is the pipeline's job
- `fresh` package — consumers of `lnk_config` (`frs_habitat_classify`, etc.) are already wired for the file paths/tibbles this returns

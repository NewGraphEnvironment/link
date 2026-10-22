# Build habitat eligibility rules YAML from dimensions CSV

Transforms a species habitat dimensions CSV into the rules YAML format
consumed by
[`fresh::frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.html).
The CSV is the human-edited source of truth; the YAML is the derived
artifact.

## Usage

``` r
lnk_rules_build(
  csv,
  to,
  thresholds = system.file("extdata", "parameters_habitat_thresholds.csv", package =
    "fresh"),
  edge_types = c("categories", "explicit")
)
```

## Arguments

- csv:

  Path to a dimensions CSV with columns: `species`, `spawn_lake`,
  `spawn_stream`, `rear_lake`, `rear_lake_only`, `rear_no_fw`,
  `rear_stream`, `rear_wetland`. Optional columns: `river_skip_cw_min`
  (yes/no — skip channel_width_min on river polygon segments), `notes`.
  `rear_lake_connected_distance_max` /
  `rear_wetland_connected_distance_max` (metres) keep a species' lake /
  wetland rearing bucket only where same-species spawning lies within
  that distance (`requires_connected: spawning` on its first rear L / W
  rule). The additive lake rule admits lake centrelines (FWA
  construction lines) with no channel-width test. `rear_wetland_flow`
  (`stream`, `gradient` or `free`; blank is `free`) sets how flow
  through a wetland (FWA 1050 / 1150) rears: `stream` emits a rule that
  inherits the species' gradient, size and near-river thresholds as the
  stream rule does, `gradient` a rule with the rear gradient only,
  `free` a rule with no test. `rear_near_river` (`both`, `stream` or
  `wetland_flow`; blank is `both`) sets which rear rules take the
  species' near-river pair. The pair's numbers live in the thresholds
  CSV (`<stage>_river_*`) and fresh inherits them; this function writes
  no numbers, only `near_river: false` on the rules outside the scope
  and on every river-polygon rule, because a river polygon is the river.
  See `configs/dictionary_dimensions.csv` for every column.

- to:

  Path to write the output YAML.

- thresholds:

  Path to the habitat thresholds CSV (from fresh). Used to look up
  `rear_lake_ha_min` per species, and `rear_gradient_max` for a
  `rear_wetland_flow = gradient` rule. Default uses the copy shipped
  with fresh.

- edge_types:

  Character. How to express stream edge types in rules: `"categories"`
  (default) uses fresh categories (`stream`, `canal`). `"explicit"` uses
  integer FWA edge_type codes (`1000, 1100, 2000, 2300`).

## Value

Invisible path to the written YAML file.

## Examples

``` r
if (FALSE) { # \dontrun{
# NGE defaults
lnk_rules_build(
  csv = system.file("extdata", "parameters_habitat_dimensions.csv", package = "link"),
  to = "inst/extdata/parameters_habitat_rules.yaml"
)

# bcfishpass comparison variant
lnk_rules_build(
  csv = system.file("extdata", "configs", "bcfishpass", "dimensions.csv",
                    package = "link"),
  to = "inst/extdata/configs/bcfishpass/rules.yaml",
  edge_types = "explicit"
)
} # }
```

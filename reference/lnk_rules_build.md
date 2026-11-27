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
  edge_types = c("categories", "explicit"),
  strict = FALSE
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

- strict:

  Logical. Every column of `csv` is checked against the column
  dictionary, `configs/dictionary_dimensions.csv`, whose rendered form
  is `configs/README.md`. A column the dictionary does not list is a
  warning by default and an error when `strict = TRUE`; either way it
  reaches no rule.

## Value

Invisible path to the written YAML file.

## Examples

``` r
# The default bundle's rules, built with its own thresholds
cfg <- system.file("extdata", "configs", "default", package = "link")
out <- tempfile(fileext = ".yaml")
lnk_rules_build(
  csv = file.path(cfg, "dimensions.csv"),
  to = out,
  thresholds = file.path(cfg, "parameters_habitat_thresholds.csv"),
  edge_types = "explicit"
)
#> Skipping CT: no thresholds in fresh CSV
#> Skipping DV: no thresholds in fresh CSV
#> Wrote /tmp/RtmpmjxLwK/file1dc336b6f3f7.yaml (11 species, explicit edge types)
# Bull trout's rear rules: an edge-type rule or a waterbody polygon each
vapply(yaml::read_yaml(out)$BT$rear, function(r) {
  if (is.null(r$waterbody_type)) {
    paste("edges", paste(r$edge_types_explicit, collapse = "/"))
  } else {
    paste("waterbody", r$waterbody_type)
  }
}, character(1))
#> [1] "edges 1000/1100/2000/2300" "waterbody R"              
#> [3] "edges 1050/1150"           "waterbody W"              
#> [5] "waterbody L"              

# A column the dictionary does not list is refused under strict = TRUE
bad <- tempfile(fileext = ".csv")
d <- utils::read.csv(file.path(cfg, "dimensions.csv"))
d$rear_strem <- "yes"
utils::write.csv(d, bad, row.names = FALSE)
try(lnk_rules_build(bad, out, strict = TRUE))
#> Error : Dimensions CSV column(s) not in dictionary_dimensions.csv (they reach no rule): rear_strem
```

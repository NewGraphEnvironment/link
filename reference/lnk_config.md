# Load a Pipeline Config Bundle

Reads a config bundle manifest (`config.yaml`) and returns a single list
object containing everything a pipeline needs to classify habitat for a
given interpretation variant — rules YAML, parameters, overrides,
observation exclusions, habitat confirmations, and pipeline knobs (break
order, cluster params, spawn_connected rules).

## Usage

``` r
lnk_config(name_or_path)
```

## Arguments

- name_or_path:

  Character. Either a bundled config name (`"bcfishpass"`, `"default"`)
  or an absolute path to a config directory. Bundled names resolve to
  `system.file("extdata", "configs", name, package = "link")`.

## Value

An `lnk_config` S3 list with these slots:

- `name` — config name (from `name_or_path` or the manifest)

- `dir` — absolute path to the config directory

- `rules_yaml` — absolute path to the rules YAML (consumed by
  [`fresh::frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.html))

- `dimensions_csv` — absolute path to the dimensions CSV (source of
  `rules_yaml` via
  [`lnk_rules_build()`](https://newgraphenvironment.github.io/link/reference/lnk_rules_build.md))

- `parameters_fresh` — data frame of per-species fresh overrides

- `habitat_classification` — data frame of expert-confirmed habitat
  endpoints (or `NULL` if the manifest does not reference one)

- `observation_exclusions` — data frame of observation IDs to skip (or
  `NULL`)

- `wsg_species` — data frame of species per watershed group (or `NULL`)

- `overrides` — named list of data frames, one per override CSV listed
  in the manifest

- `pipeline` — named list of pipeline knobs from the manifest
  (`break_order`, `cluster`, `spawn_connected`)

## Details

A config bundle is a directory under `inst/extdata/configs/<name>/` (for
bundled variants) or an arbitrary directory path (for custom variants)
containing `config.yaml` plus the files the manifest references. All
file paths in the manifest are resolved relative to the bundle
directory.

The returned list is the single object passed around the pipeline (e.g.
into `_targets.R`), so pipeline variants become a config authoring
exercise, not a code fork.

## Examples

``` r
# Load the bundled bcfishpass variant
cfg <- lnk_config("bcfishpass")

# Inspect
cfg$name
#> [1] "bcfishpass"
cfg$dir
#> [1] "/home/runner/work/_temp/Library/link/extdata/configs/bcfishpass"
file.exists(cfg$rules_yaml)
#> [1] TRUE
head(cfg$parameters_fresh)
#>   species_code access_gradient_max spawn_gradient_min rear_gradient_min
#> 1           BT                0.25                  0                 0
#> 2           CH                0.15                  0                 0
#> 3           CM                0.15                  0                 0
#> 4           CO                0.15                  0                 0
#> 5           CT                0.25                  0                 0
#> 6           DV                0.25                  0                 0
#>   cluster_rearing cluster_direction cluster_bridge_gradient
#> 1            TRUE              both                    0.05
#> 2            TRUE              both                    0.05
#> 3           FALSE                                        NA
#> 4            TRUE              both                    0.05
#> 5           FALSE                                        NA
#> 6           FALSE                                        NA
#>   cluster_bridge_distance cluster_confluence_m cluster_spawning
#> 1                   10000                   10            FALSE
#> 2                   10000                   10            FALSE
#> 3                      NA                   NA            FALSE
#> 4                   10000                   10            FALSE
#> 5                      NA                   NA            FALSE
#> 6                      NA                   NA            FALSE
#>   cluster_spawn_direction cluster_spawn_bridge_gradient
#> 1                                                    NA
#> 2                                                    NA
#> 3                                                    NA
#> 4                                                    NA
#> 5                                                    NA
#> 6                                                    NA
#>   cluster_spawn_bridge_distance cluster_spawn_confluence_m
#> 1                            NA                         NA
#> 2                            NA                         NA
#> 3                            NA                         NA
#> 4                            NA                         NA
#> 5                            NA                         NA
#> 6                            NA                         NA
#>   observation_threshold observation_date_min observation_buffer_m
#> 1                     1           1990-01-01                   20
#> 2                     5           1990-01-01                   20
#> 3                     5           1990-01-01                   20
#> 4                     5           1990-01-01                   20
#> 5                    NA                 <NA>                   NA
#> 6                    NA                 <NA>                   NA
#>    observation_species
#> 1 BT;CH;CO;SK;PK;CM;ST
#> 2       CH;CM;CO;PK;SK
#> 3       CH;CM;CO;PK;SK
#> 4       CH;CM;CO;PK;SK
#> 5                 <NA>
#> 6                 <NA>
names(cfg$overrides)
#> [1] "modelled_fixes"            "pscis_barrier_status"     
#> [3] "pscis_xref"                "barriers_definite"        
#> [5] "barriers_definite_control" "crossings_misc"           
cfg$pipeline$break_order
#> [1] "observations"      "gradient_minimal"  "barriers_definite"
#> [4] "habitat_endpoints" "crossings"        

if (FALSE) { # \dontrun{
# Custom config: point at any directory containing config.yaml
my_cfg <- lnk_config("/path/to/my/variant")

# Feed into the pipeline
fresh::frs_habitat_classify(conn, ...,
  rules = cfg$rules_yaml,
  params = cfg$parameters_fresh)
} # }
```

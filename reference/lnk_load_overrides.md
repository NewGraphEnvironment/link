# Materialize the Tabular Data Files Declared in a Config Bundle

Walks `cfg$files` and returns a named list of tibbles, one per entry.
Entries with a `canonical_schema` field dispatch through
[`crate::crt_ingest()`](https://newgraphenvironment.github.io/crate/reference/crt_ingest.html)
(which handles canonicalization across upstream variants). Entries
without `canonical_schema` fall through to a local read dispatched on
the path's extension (`.csv` today; more formats can be added without
schema changes).

## Usage

``` r
lnk_load_overrides(cfg)
```

## Arguments

- cfg:

  An `lnk_config` object returned by
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md),
  or a character (config name or path) — for ergonomic call.

## Value

Named list of tibbles. Order matches `cfg$files`.

## Details

Returned list keys match the entry keys in `cfg$files` exactly
(filename-stem convention — see
`inst/extdata/configs/<name>/config.yaml`).

## Examples

``` r
cfg <- lnk_config("bcfishpass")
loaded <- lnk_load_overrides(cfg)
names(loaded)
#>  [1] "parameters_fresh"                    
#>  [2] "user_habitat_classification"         
#>  [3] "observation_exclusions"              
#>  [4] "wsg_species_presence"                
#>  [5] "user_modelled_crossing_fixes"        
#>  [6] "user_pscis_barrier_status"           
#>  [7] "pscis_modelledcrossings_streams_xref"
#>  [8] "user_barriers_definite"              
#>  [9] "user_barriers_definite_control"      
#> [10] "user_crossings_misc"                 
head(loaded$user_habitat_classification)
#> # A tibble: 6 × 11
#>   blue_line_key downstream_route_measure upstream_route_measure
#>           <int>                    <dbl>                  <dbl>
#> 1     356366321                        0                   1030
#> 2     356385867                        0                    208
#> 3     356392414                        0                    170
#> 4     356397040                        0                    314
#> 5     356404889                        0                     15
#> 6     356413411                        0                    169
#> # ℹ 8 more variables: watershed_group_code <chr>, species_code <chr>,
#> #   spawning <int>, rearing <int>, reviewer_name <chr>, review_date <chr>,
#> #   source <chr>, notes <chr>
head(loaded$parameters_fresh)
#> # A tibble: 6 × 19
#>   species_code access_gradient_max spawn_gradient_min rear_gradient_min
#>   <chr>                      <dbl>              <int>             <int>
#> 1 BT                          0.25                  0                 0
#> 2 CH                          0.15                  0                 0
#> 3 CM                          0.15                  0                 0
#> 4 CO                          0.15                  0                 0
#> 5 CT                          0.25                  0                 0
#> 6 DV                          0.25                  0                 0
#> # ℹ 15 more variables: cluster_rearing <lgl>, cluster_direction <chr>,
#> #   cluster_bridge_gradient <dbl>, cluster_bridge_distance <int>,
#> #   cluster_confluence_m <int>, cluster_spawning <lgl>,
#> #   cluster_spawn_direction <chr>, cluster_spawn_bridge_gradient <dbl>,
#> #   cluster_spawn_bridge_distance <int>, cluster_spawn_confluence_m <int>,
#> #   observation_threshold <int>, observation_date_min <chr>,
#> #   observation_buffer_m <int>, observation_species <chr>, …

if (FALSE) { # \dontrun{
# Same call shape with a project-experimental config that extends default
loaded_proj <- lnk_load_overrides("/path/to/project/config")
} # }
```

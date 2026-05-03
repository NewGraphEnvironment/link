# Load a Pipeline Config Bundle (Manifest)

Reads a config bundle manifest (`config.yaml`) and returns a single list
object describing what a pipeline variant does — paths, file
declarations, pipeline knobs, provenance — but **no parsed data**.

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

- `name` — config name from the manifest

- `dir` — absolute path to the config directory

- `description` — manifest's free-text description (or `NULL`)

- `rules` — absolute path to the rules YAML (consumed by
  [`fresh::frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.html))

- `dimensions` — absolute path to the dimensions CSV (input to
  [`lnk_rules_build()`](https://newgraphenvironment.github.io/link/reference/lnk_rules_build.md))

- `species` — character vector of species the rules YAML classifies
  (parsed from `rules.yaml` top-level keys)

- `files` — named list of file declarations. Each entry is a list with
  `path` (resolved absolute path) and optionally `source` (free-text
  provenance label) and `canonical_schema` (`"<source>/<file_name>"` —
  keys into crate's registry to dispatch ingest via
  [`crate::crt_ingest()`](https://newgraphenvironment.github.io/crate/reference/crt_ingest.html))

- `pipeline` — named list of pipeline knobs (`apply_habitat_overlay`,
  `break_order`, `cluster`, `spawn_connected`)

- `provenance` — named list of per-file provenance metadata, keyed by
  file path relative to `dir`. Drift detection against these checksums
  lives in
  [`lnk_config_verify()`](https://newgraphenvironment.github.io/link/reference/lnk_config_verify.md).

- `extends` — character or `NULL`, the parent config name/path this
  manifest declared (post-resolution; not used by callers beyond audit)

## Details

Tabular data (override CSVs, habitat classifications, parameters) is
loaded by
[`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md),
which dispatches each declared file through
[`crate::crt_ingest()`](https://newgraphenvironment.github.io/crate/reference/crt_ingest.html)
for source-registered entries and falls through to local reads
otherwise. This split keeps `lnk_config()` cheap to call (no CSV
parsing) and lets provenance-only consumers like
[`lnk_config_verify()`](https://newgraphenvironment.github.io/link/reference/lnk_config_verify.md)
and
[`lnk_stamp()`](https://newgraphenvironment.github.io/link/reference/lnk_stamp.md)
work without touching data.

A config bundle is a directory under `inst/extdata/configs/<name>/` (for
bundled variants) or an arbitrary directory path (for custom variants)
containing `config.yaml` plus the files the manifest references. All
file paths in the manifest are resolved relative to the bundle
directory.

Configs may declare `extends: <parent>` to inherit from another config.
The parent is resolved (recursively, if it also extends) and merged
shallowly: child entries override parent entries with the same key in
`files:`, `pipeline:`, and `provenance:`; top-level scalars
(`description`, `rules`, `dimensions`) override directly.

## Examples

``` r
cfg <- lnk_config("bcfishpass")
cfg$name
#> [1] "bcfishpass"
cfg$rules
#> [1] "/home/runner/work/_temp/Library/link/extdata/configs/bcfishpass/rules.yaml"
names(cfg$files)
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
#> [11] "cabd_exclusions"                     
#> [12] "cabd_blkey_xref"                     
#> [13] "cabd_passability_status_updates"     
#> [14] "cabd_additions"                      
cfg$files$user_habitat_classification
#> $source
#> [1] "bcfp"
#> 
#> $path
#> [1] "/home/runner/work/_temp/Library/link/extdata/configs/bcfishpass/overrides/user_habitat_classification.csv"
#> 
#> $canonical_schema
#> [1] "bcfp/user_habitat_classification"
#> 
cfg$pipeline$break_order
#> [1] "observations"      "gradient_minimal"  "falls"            
#> [4] "barriers_definite" "subsurfaceflow"    "habitat_endpoints"
#> [7] "crossings"        

if (FALSE) { # \dontrun{
# Custom config: point at any directory containing config.yaml
my_cfg <- lnk_config("/path/to/my/variant")

# Materialize the data tables declared in the manifest
loaded <- lnk_load_overrides(my_cfg)
loaded$user_habitat_classification
} # }
```

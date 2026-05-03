# Resolve the Species Set for an AOI

The species the config classifies, filtered to those present in the AOI.
Used by
[`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md)
and
[`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md)
to pick which species to run, and exposed for callers that need to
derive the same list outside the pipeline (e.g. a custom
`compare_bcfishpass_wsg()` that queries bcfishpass reference tables only
for these species).

## Usage

``` r
lnk_pipeline_species(cfg, loaded, aoi)
```

## Arguments

- cfg:

  An `lnk_config` object from
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md).

- loaded:

  Named list of tibbles from
  [`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md).
  Carries `parameters_fresh` and `wsg_species_presence`.

- aoi:

  Character. AOI identifier — today a watershed group code (e.g.
  `"BULK"`) matched against
  `loaded$wsg_species_presence$watershed_group_code`.

## Value

Character vector of species codes. Empty when neither config nor AOI
carries species.

## Details

The returned set is the intersection of:

- `cfg$species` — species the rules YAML classifies (parsed at
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md)
  load time)

- species flagged present for `aoi` in `loaded$wsg_species_presence` —
  the wide-form presence table where each species column (`bt`, `ch`,
  `cm`, ...) holds `"t"` for present and `"f"` for absent

When `loaded$wsg_species_presence` is not populated the function returns
`cfg$species` unfiltered. When the AOI is not found in the table the
function returns `character(0)`.

## See also

Other pipeline:
[`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md),
[`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md),
[`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md),
[`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md),
[`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md),
[`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md)

## Examples

``` r
cfg    <- lnk_config("bcfishpass")
loaded <- lnk_load_overrides(cfg)
#> Warning: incomplete final line found by readTableHeader on '/home/runner/work/_temp/Library/link/extdata/configs/bcfishpass/overrides/cabd_blkey_xref.csv'
lnk_pipeline_species(cfg, loaded, "BULK")
#> [1] "BT" "CH" "CO" "PK" "SK" "ST"
lnk_pipeline_species(cfg, loaded, "ADMS")
#> [1] "BT" "CH" "CO" "SK"
```

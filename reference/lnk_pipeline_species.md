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
lnk_pipeline_species(cfg, loaded, aoi, paused = FALSE)
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

- paused:

  Logical. Also count the species the bundle pauses. Default `FALSE`:
  the species classified.

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

A species the bundle pauses (`cfg$species_paused`, from its
`species_modelled.csv`) is not classified, so it is left out unless
`paused = TRUE`. That form answers whether a group is modelled at all: a
group where only paused species are present is still built for its
segments and barriers, which other groups' access reads, and gets no
habitat.

It answers "which species does this build classify here", so it reads
the presence cells as written.
[`lnk_presence()`](https://newgraphenvironment.github.io/link/reference/lnk_presence.md)
answers a wider question, "which species count as present here", and
promotes a whole species group when any member is present (link#153):
for ADMS under `bcfishpass` this function gives BT, CH, CO and SK, and
[`lnk_presence()`](https://newgraphenvironment.github.io/link/reference/lnk_presence.md)
also CM, CT, DV, PK and RB. Mapping codes read
[`lnk_presence()`](https://newgraphenvironment.github.io/link/reference/lnk_presence.md),
and a species it holds that is not classified reads 0 spawning and
rearing, as bcfishpass's are.

## See also

Other pipeline:
[`lnk_habitat_gate()`](https://newgraphenvironment.github.io/link/reference/lnk_habitat_gate.md),
[`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md),
[`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md),
[`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md),
[`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md),
[`lnk_pipeline_crossings()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_crossings.md),
[`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md),
[`lnk_pipeline_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_mapping_code.md),
[`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md),
[`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md),
[`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md),
[`lnk_presence()`](https://newgraphenvironment.github.io/link/reference/lnk_presence.md)

## Examples

``` r
cfg    <- lnk_config("bcfishpass")
loaded <- lnk_load_overrides(cfg)
lnk_pipeline_species(cfg, loaded, "BULK")
#> [1] "BT" "CH" "CO" "PK" "SK" "ST"

# default pauses KO: KOTL's kokanee is left out unless paused = TRUE
cfg <- lnk_config("default")
loaded <- lnk_load_overrides(cfg)
lnk_pipeline_species(cfg, loaded, "KOTL")
#> [1] "BT"  "WCT" "RB" 
lnk_pipeline_species(cfg, loaded, "KOTL", paused = TRUE)
#> [1] "BT"  "WCT" "RB"  "KO" 
lnk_pipeline_species(cfg, loaded, "ADMS")
#> [1] "BT" "CH" "CO" "PK" "SK" "RB"
```

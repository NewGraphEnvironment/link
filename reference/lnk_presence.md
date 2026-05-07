# Per-AOI species presence with bcfp species-group expansion

Reads a single AOI's row from a `wsg_species_presence` tibble and
returns structured presence info: the per-species TRUE/FALSE flags from
the row, expanded by user-supplied species groups so that "any group
member present" promotes the whole group to present. Mirrors bcfp's
`wsg_salmon` / `wsg_ct_dv_rb` JOIN logic in `load_streams_access.sql` —
useful as input to per-species pipeline loops that should skip absent
species.

## Usage

``` r
lnk_presence(
  wsg_species_presence,
  aoi,
  groups = list(salmon = c("ch", "cm", "co", "pk", "sk"), ct_dv_rb = c("ct", "dv", "rb"))
)
```

## Arguments

- wsg_species_presence:

  Data frame or tibble matching the `loaded$wsg_species_presence` shape
  (per
  [`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md)):
  `watershed_group_code`, then per-species columns (`bt`, `ch`, ...),
  plus optional `notes`. Values may be character (`"t"`/`""`/`NA`, the
  CSV-bundled form) or logical (`TRUE`/`FALSE`/`NA`, the PostgreSQL
  form). `notes` and `watershed_group_code` are excluded from the
  species list.

- aoi:

  Character. Watershed group code (e.g. `"ADMS"`).

- groups:

  Named list of character vectors. Each name is a group tag (e.g.
  `"salmon"`); each value lists species codes that share group-presence
  semantics. Default mirrors bcfp:

  - `salmon = c("ch", "cm", "co", "pk", "sk")`

  - `ct_dv_rb = c("ct", "dv", "rb")`

  A species in a group is reported present iff **any** group member is
  present in the AOI row. Pass
  [`list()`](https://rdrr.io/r/base/list.html) to disable expansion.

## Value

A list with:

- `aoi`: echo of input.

- `row`: the raw 1-row tibble for `aoi`.

- `present`: character vector of species codes present after group
  expansion.

- `absent`: character vector of species codes not present.

- `is_present(sp)`: vectorised function returning `TRUE` for species in
  `present`.

## Details

Coexists with
[`lnk_pipeline_species()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_species.md),
which returns the intersection of `cfg$species` with AOI-present species
as a plain vector. `lnk_presence()` is the structured / group-aware
sibling.

## See also

Other pipeline:
[`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md),
[`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md),
[`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md),
[`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md),
[`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md),
[`lnk_pipeline_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_mapping_code.md),
[`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md),
[`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md),
[`lnk_pipeline_species()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_species.md)

## Examples

``` r
if (FALSE) { # \dontrun{
loaded <- lnk_load_overrides(lnk_config("default_extrabreaks"))

# ADMS — BT + salmon-group + ct_dv_rb-group present.
pres <- lnk_presence(loaded$wsg_species_presence, "ADMS")
pres$present                           # bt, ch, co, sk + cm, pk (group-expanded)
pres$absent                            # st, wct, gr, ko
pres$is_present(c("bt", "st", "cm"))   # TRUE FALSE TRUE

# ELKR — salmon all NULL, no group expansion fires.
pres <- lnk_presence(loaded$wsg_species_presence, "ELKR")
pres$is_present("ch")                  # FALSE

# Disable group expansion.
pres <- lnk_presence(loaded$wsg_species_presence, "ADMS",
                     groups = list())
pres$is_present("cm")                  # FALSE (only literal cm column matters)
} # }
```

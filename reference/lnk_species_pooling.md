# Resolve which observation species count as each model species, per WSG

Reads a bundle's pooling tracker (`species_pooling.csv`) and species
groups (`species_groups.csv`) and returns, for each watershed group in
`aoi` and each model species present there, the observation species
whose records count as evidence for it. The tool knows nothing about any
particular species: pooling Dolly Varden records into bull trout, or all
salmon together, is a row in the tracker.

## Usage

``` r
lnk_species_pooling(loaded, aoi, species, regions = NULL)
```

## Arguments

- loaded:

  Named list from
  [`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md).
  Uses `wsg_species_presence` (required: its species columns are also
  the set of known species codes), `species_pooling` and
  `species_groups` (both optional; without a tracker nothing is pooled).

- aoi:

  Character vector of watershed group codes.

- species:

  Character vector of model species codes.

- regions:

  Data frame with `watershed_group_code`, `region` and `subregion`, or
  `NULL` (default) for the package's `inst/extdata/wsg_regions.csv`.

## Value

A data frame, one row per WSG x model species x observation species:
`watershed_group_code`, `species_code`, `obs_species`, `scope_level`
(`self` for the species itself, else the winning row's level), `scope`,
`rule` (the winning row's number in the tracker, `NA` for `self`) and
`obs_year_max` (the winning row's year limit, `NA` for none; always `NA`
for `self`). Consumers apply the year limit per record, and an undated
record does not meet one. Codes are upper case.

## Details

A tracker row is `species_code` (the model species or a group of them),
`species_obs` (the observation species or a group), `scope_level`
(`region`, `subregion` or `wsg`), `scope` (a name in
`inst/extdata/wsg_regions.csv`, or a WSG code) and `pool` (`yes` /
`no`). An optional `obs_year_max` limits a pooling row to records dated
in or before that year, for evidence whose meaning changed over time (a
name that was applied to another species until recording practice caught
up). Empty means no limit. Other columns (`confidence`, `rationale`,
`source`, `verified`, `issue`) are the record of why, and are not read
here.

For each WSG, target and observation species pair, the applicable rows
are resolved in order:

1.  the most specific scope wins (`wsg` over `subregion` over `region`);

2.  at equal scope, the row naming fewer groups wins (a
    species-to-species row beats one that names a group);

3.  rows still tied must agree on `pool` and `obs_year_max`, or the call
    errors.

Anything no row covers is not pooled. A species always counts as itself,
and a model species yields rows only where `wsg_species_presence` marks
it present.

## See also

[`lnk_presence()`](https://newgraphenvironment.github.io/link/reference/lnk_presence.md),
[`lnk_habitat_validate()`](https://newgraphenvironment.github.io/link/reference/lnk_habitat_validate.md)

## Examples

``` r
cfg <- lnk_config("default")
loaded <- suppressWarnings(lnk_load_overrides(cfg))

# Which observation species count as each model species in three groups
# on different drainages?
p <- lnk_species_pooling(loaded, aoi = c("MORR", "ELKR", "COMX"),
                         species = c("BT", "CO"))
p
#>   watershed_group_code species_code obs_species scope_level
#> 1                 COMX           CO          CO        self
#> 2                 ELKR           BT          BT        self
#> 3                 ELKR           BT          DV   subregion
#> 4                 MORR           BT          BT        self
#> 5                 MORR           BT          DV   subregion
#> 6                 MORR           CO          CO        self
#>                   scope rule obs_year_max
#> 1                  <NA>   NA           NA
#> 2                  <NA>   NA           NA
#> 3              Kootenay    5           NA
#> 4                  <NA>   NA           NA
#> 5 Skeena above Hazelton    6           NA
#> 6                  <NA>   NA           NA

# The pooled rows alone, with the tracker row that decided each one
p[p$scope_level != "self", ]
#>   watershed_group_code species_code obs_species scope_level
#> 3                 ELKR           BT          DV   subregion
#> 5                 MORR           BT          DV   subregion
#>                   scope rule obs_year_max
#> 3              Kootenay    5           NA
#> 5 Skeena above Hazelton    6           NA
```

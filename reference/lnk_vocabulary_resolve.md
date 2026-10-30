# Name a config's output in the vocabulary

Derives each axis's specification from what a build under `cfg` would
actually read, and matches it against
[`lnk_vocabulary_read()`](https://newgraphenvironment.github.io/link/reference/lnk_vocabulary_read.md):

## Usage

``` r
lnk_vocabulary_resolve(cfg, loaded = NULL)
```

## Arguments

- cfg:

  An `lnk_config` object from
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md).

- loaded:

  Named list from
  [`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md).
  Loaded from `cfg` when `NULL`.

## Value

A named character vector `c(cut = , acc = , grad = , flow = )`.

## Details

- **cut:** the break sources in the order applied
  (`pipeline: break_order`, or its default), the observation breaks
  (`all` or `top_per_species`; only when `observations` is a source) and
  the gradient classes streams are broken at
  (`pipeline: gradient_classes`, or bcfishpass's 15 / 20 / 25 / 30 %),
  and which of the definite barrier, barrier control and habitat
  classification files the bundle declares (their rows are data, which
  the build record carries).

- **acc:** a sha256 digest of the access rules, which decide where
  gradient barriers cut streams as well as what is accessible: the
  species the rules model, each species' `access_gradient_max` and
  `observation_*` lift parameters, the species presence table, and the
  two access rules held in code (the gradient class each access label
  maps to, and
  [`lnk_presence()`](https://newgraphenvironment.github.io/link/reference/lnk_presence.md)'s
  species groups). The digest is over the parsed values, so a change in
  quoting or column order is not a new rule set.

- **grad:** `gradient=segment`, the only measure link builds today.

- **flow:** `pipeline: discharge_source` and `pipeline: discharge_fill`.

A config whose specification matches no token, or only a retired one, is
refused: the new output gets a name (a row in
`inst/extdata/vocabulary.csv`) before anything is built.

## See also

Other vocabulary:
[`lnk_vocabulary_read()`](https://newgraphenvironment.github.io/link/reference/lnk_vocabulary_read.md)

## Examples

``` r
lnk_vocabulary_resolve(lnk_config("default"))
#>            cut            acc           grad           flow 
#> "cut-full-top"       "acc-v1"     "grad-seg"      "q-fwapg" 
lnk_vocabulary_resolve(lnk_config("bcfishpass"))
#>                cut                acc               grad               flow 
#> "cut-full-ssf-all"         "acc-bcfp"         "grad-seg"          "q-fwapg" 
```

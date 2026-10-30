# Read link's output vocabulary

The table of tokens that name what an output is: how its streams were
cut (`cut`), which access rules decided where gradient barriers cut them
(`acc`), how its gradient was measured (`grad`) and where its discharge
came from (`flow`).
[`lnk_vocabulary_resolve()`](https://newgraphenvironment.github.io/link/reference/lnk_vocabulary_resolve.md)
matches a config against it, and every
[`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md)
records the four tokens in its `<schema>.log` row.

## Usage

``` r
lnk_vocabulary_read()
```

## Value

A data frame, one row per token, with columns `token`, `axis` (`cut`,
`acc`, `grad` or `flow`), `definition` (prose), `spec` (the canonical
string or digest
[`lnk_vocabulary_resolve()`](https://newgraphenvironment.github.io/link/reference/lnk_vocabulary_resolve.md)
matches), `introduced` (the link version that added it) and `retired`
(the link version that retired it, `NA` while live).

## Details

Tokens are lowercase, never renamed and never reused. A changed
definition is a new token, and a retired token stays in the table so old
names still decode. Consumers read this table (or
`inst/extdata/vocabulary.csv` at a release tag) rather than copying it.

## See also

Other vocabulary:
[`lnk_vocabulary_resolve()`](https://newgraphenvironment.github.io/link/reference/lnk_vocabulary_resolve.md)

## Examples

``` r
v <- lnk_vocabulary_read()
v[, c("token", "axis", "introduced")]
#>              token axis introduced
#> 1     cut-full-top  cut     0.70.0
#> 2 cut-full-ssf-all  cut     0.70.0
#> 3         acc-bcfp  acc     0.70.0
#> 4           acc-v1  acc     0.70.0
#> 5         grad-seg grad     0.70.0
#> 6          q-fwapg flow     0.70.0
#> 7       q-wet-fill flow     0.70.0
#> 8           acc-v2  acc     0.72.0
#> 9       acc-bcfp-2  acc     0.72.0
```

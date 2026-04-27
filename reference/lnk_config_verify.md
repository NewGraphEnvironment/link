# Verify Config Bundle File Checksums

Recomputes sha256 for every file declared in the bundle's `provenance:`
block and compares against the recorded checksum. Returns a tibble of
expected vs observed; flags drift.

## Usage

``` r
lnk_config_verify(cfg, strict = FALSE)
```

## Arguments

- cfg:

  An `lnk_config` object from
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md).

- strict:

  Logical. When `TRUE`, errors if any file has drifted. Default `FALSE`
  warns and returns the tibble for inspection.

## Value

A tibble with columns:

- `file` — path relative to `cfg$dir`

- `expected` — checksum recorded in the manifest (sha256 hex)

- `observed` — checksum recomputed from the current file (sha256 hex)

- `drift` — logical, `TRUE` when expected != observed

- `missing` — logical, `TRUE` when the file no longer exists on disk
  (observed is `NA` in this case)

The tibble carries one row per provenanced file. When the bundle has no
`provenance:` block (`cfg$provenance` is `NULL`) returns an empty tibble
with the same columns.

## Details

Use this at run time to detect silent drift — a file that was edited
without re-recording its checksum, or an external CSV that was re-synced
under the same path. Drift between two pipeline runs on the same DB
state with the same package versions almost always traces back to a
config-file edit; `lnk_config_verify()` is the fastest way to localize
the change.

## Examples

``` r
cfg <- lnk_config("bcfishpass")
verify <- lnk_config_verify(cfg)
verify
#>                                                  file
#> 1                                          rules.yaml
#> 2                                      dimensions.csv
#> 3                                parameters_fresh.csv
#> 4           overrides/user_habitat_classification.csv
#> 5                overrides/observation_exclusions.csv
#> 6                  overrides/wsg_species_presence.csv
#> 7          overrides/user_modelled_crossing_fixes.csv
#> 8             overrides/user_pscis_barrier_status.csv
#> 9  overrides/pscis_modelledcrossings_streams_xref.csv
#> 10               overrides/user_barriers_definite.csv
#> 11       overrides/user_barriers_definite_control.csv
#> 12                  overrides/user_crossings_misc.csv
#>                                                                   expected
#> 1  sha256:b4a693cf204c2ee23f1672521f051c32c805e2417858eaf24661c1e354daf6b7
#> 2  sha256:650ab993d23fba8b88cdbbb43030d8f6595b320bb20044db88aaff951cc8a15d
#> 3  sha256:1cc4c33c729d37a40672540dfb92f4f7dadf50653bd4f211a485c9d51722088f
#> 4  sha256:c605a8aa61b127f3525562e24ae3ab8f26cd62c1e3e556edf5b8c564c735b830
#> 5  sha256:ad901c57ca42e71e4affffd6e583045a2ce423f15088c211c9c2f72976f5d36a
#> 6  sha256:3c3dc66d1b9b299d91e73d6edcccb56cc827641be494e26981ed580ff51e15ec
#> 7  sha256:0c0e97f8f0d4c834837631f68f10aa8fc8f502cad954fd266fe41d4e1f214d10
#> 8  sha256:9b4929f882ac46e5632bdbe3c587421be42ac31c0005cd2b7e4d1028fa2a47ac
#> 9  sha256:f76470febe3a4d26e13ada144b594c2571033fa00676b7622f3c628fed21206f
#> 10 sha256:56c66cddf279a1c2b0c0be1fc9ba9c758dc93d4ad820e0bf2c5caf4ecce05fb6
#> 11 sha256:8f34e2c006733e0f06248a90dc0b8abe4719880590f497581f80fe5f62fde203
#> 12 sha256:19fa9f1322f78e0b2025aed509b7ac1402b7f99876e7b9e6404b22cce5491d5e
#>                                                                   observed
#> 1  sha256:b4a693cf204c2ee23f1672521f051c32c805e2417858eaf24661c1e354daf6b7
#> 2  sha256:650ab993d23fba8b88cdbbb43030d8f6595b320bb20044db88aaff951cc8a15d
#> 3  sha256:1cc4c33c729d37a40672540dfb92f4f7dadf50653bd4f211a485c9d51722088f
#> 4  sha256:c605a8aa61b127f3525562e24ae3ab8f26cd62c1e3e556edf5b8c564c735b830
#> 5  sha256:ad901c57ca42e71e4affffd6e583045a2ce423f15088c211c9c2f72976f5d36a
#> 6  sha256:3c3dc66d1b9b299d91e73d6edcccb56cc827641be494e26981ed580ff51e15ec
#> 7  sha256:0c0e97f8f0d4c834837631f68f10aa8fc8f502cad954fd266fe41d4e1f214d10
#> 8  sha256:9b4929f882ac46e5632bdbe3c587421be42ac31c0005cd2b7e4d1028fa2a47ac
#> 9  sha256:f76470febe3a4d26e13ada144b594c2571033fa00676b7622f3c628fed21206f
#> 10 sha256:56c66cddf279a1c2b0c0be1fc9ba9c758dc93d4ad820e0bf2c5caf4ecce05fb6
#> 11 sha256:8f34e2c006733e0f06248a90dc0b8abe4719880590f497581f80fe5f62fde203
#> 12 sha256:19fa9f1322f78e0b2025aed509b7ac1402b7f99876e7b9e6404b22cce5491d5e
#>    drift missing
#> 1  FALSE   FALSE
#> 2  FALSE   FALSE
#> 3  FALSE   FALSE
#> 4  FALSE   FALSE
#> 5  FALSE   FALSE
#> 6  FALSE   FALSE
#> 7  FALSE   FALSE
#> 8  FALSE   FALSE
#> 9  FALSE   FALSE
#> 10 FALSE   FALSE
#> 11 FALSE   FALSE
#> 12 FALSE   FALSE

if (FALSE) { # \dontrun{
# In a verification log: error if anything drifted
lnk_config_verify(cfg, strict = TRUE)
} # }
```

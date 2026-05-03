# Verify Config Bundle File Checksums and Shape

Recomputes sha256 byte and shape checksums for every file declared in
the bundle's `provenance:` block and compares against the recorded
values. Returns a tibble of expected vs observed; flags drift on each
axis separately.

## Usage

``` r
lnk_config_verify(cfg, strict = FALSE)
```

## Arguments

- cfg:

  An `lnk_config` object from
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md).

- strict:

  Logical. When `TRUE`, errors if any file has drifted on either axis.
  Default `FALSE` warns and returns the tibble for inspection.

## Value

A tibble with columns:

- `file` — path relative to `cfg$dir`

- `byte_expected` — byte checksum recorded in the manifest

- `byte_observed` — byte checksum recomputed from the current file

- `byte_drift` — logical, `TRUE` when byte checksums differ

- `shape_expected` — shape checksum recorded in the manifest, or `NA`
  when the manifest has no `shape_checksum` field

- `shape_observed` — shape checksum recomputed from the current file's
  header line

- `shape_drift` — logical, `TRUE` when shape checksums differ (and the
  manifest had a `shape_expected` to compare against)

- `missing` — logical, `TRUE` when the file no longer exists on disk
  (observed values are `NA`)

The tibble carries one row per provenanced file. When the bundle has no
`provenance:` block (`cfg$provenance` is `NULL`) returns an empty tibble
with the same columns.

## Details

**Byte drift** (`byte_drift`) — file content changed (rows
added/edited/removed, or whole-file re-shape). Detected via sha256 of
the full file. Catches every kind of change but doesn't tell you WHAT
kind.

**Shape drift** (`shape_drift`) — file's *header* changed (column added
/ renamed / removed / reshaped). Detected via sha256 of the first line
of the file (whitespace-normalized). A pure-value change (rows added
with no column change) shows `byte_drift = TRUE` but
`shape_drift = FALSE`. A column rename shows both TRUE. Header-only
fingerprint catches the dominant failure mode (column structure change);
type changes within stable columns are not detected — they require
value-level inspection that's out of scope here.

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
#> Warning: Config bundle 'bcfishpass' has 4 file(s) drifted from recorded checksum:
#>   - rules.yaml (byte drift)
#>   - dimensions.csv (byte + shape drift)
#>   - parameters_fresh.csv (byte drift)
#>   - overrides/wsg_species_presence.csv (byte + shape drift)
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
#>                                                              byte_expected
#> 1  sha256:93a49f4071140a307b7cb8f2c3d580e8edbd08fa337e398ace47cabccc4eb00a
#> 2  sha256:a623ac2ae551b2f150b8015a7fd17d76bcd6c81db60e30ec18f6e412b23baaa9
#> 3  sha256:1cc4c33c729d37a40672540dfb92f4f7dadf50653bd4f211a485c9d51722088f
#> 4  sha256:cc6aff6448e940613913c2d9dd847db72d6bfb63db8b50ad3293c76ef17c5740
#> 5  sha256:ad901c57ca42e71e4affffd6e583045a2ce423f15088c211c9c2f72976f5d36a
#> 6  sha256:3c3dc66d1b9b299d91e73d6edcccb56cc827641be494e26981ed580ff51e15ec
#> 7  sha256:0c0e97f8f0d4c834837631f68f10aa8fc8f502cad954fd266fe41d4e1f214d10
#> 8  sha256:9b4929f882ac46e5632bdbe3c587421be42ac31c0005cd2b7e4d1028fa2a47ac
#> 9  sha256:f76470febe3a4d26e13ada144b594c2571033fa00676b7622f3c628fed21206f
#> 10 sha256:56c66cddf279a1c2b0c0be1fc9ba9c758dc93d4ad820e0bf2c5caf4ecce05fb6
#> 11 sha256:8f34e2c006733e0f06248a90dc0b8abe4719880590f497581f80fe5f62fde203
#> 12 sha256:19fa9f1322f78e0b2025aed509b7ac1402b7f99876e7b9e6404b22cce5491d5e
#>                                                              byte_observed
#> 1  sha256:0ca482819e7ff619cfe067765fc86ac91ed63142a39bf44266a03d92b590748d
#> 2  sha256:92abd809a1e47a070b9644e18fc330e8dd366b7100334ad2a643ec64c1b717e5
#> 3  sha256:a877ec23b0e0853514d545fbd8b8f218718382dc44a72377ffcc45526e63984e
#> 4  sha256:cc6aff6448e940613913c2d9dd847db72d6bfb63db8b50ad3293c76ef17c5740
#> 5  sha256:ad901c57ca42e71e4affffd6e583045a2ce423f15088c211c9c2f72976f5d36a
#> 6  sha256:cd42f2dff62cb76f77f4b055436329a74ba44fe1466dec5d7801aa5221360185
#> 7  sha256:0c0e97f8f0d4c834837631f68f10aa8fc8f502cad954fd266fe41d4e1f214d10
#> 8  sha256:9b4929f882ac46e5632bdbe3c587421be42ac31c0005cd2b7e4d1028fa2a47ac
#> 9  sha256:f76470febe3a4d26e13ada144b594c2571033fa00676b7622f3c628fed21206f
#> 10 sha256:56c66cddf279a1c2b0c0be1fc9ba9c758dc93d4ad820e0bf2c5caf4ecce05fb6
#> 11 sha256:8f34e2c006733e0f06248a90dc0b8abe4719880590f497581f80fe5f62fde203
#> 12 sha256:19fa9f1322f78e0b2025aed509b7ac1402b7f99876e7b9e6404b22cce5491d5e
#>    byte_drift
#> 1        TRUE
#> 2        TRUE
#> 3        TRUE
#> 4       FALSE
#> 5       FALSE
#> 6        TRUE
#> 7       FALSE
#> 8       FALSE
#> 9       FALSE
#> 10      FALSE
#> 11      FALSE
#> 12      FALSE
#>                                                             shape_expected
#> 1  sha256:4fec0f2db7523d71ba7542e0d52217c91d9bab5b55d714b689f614380f5c2eb9
#> 2  sha256:a33cd8cff1c4a101534c255738931dd0821d114f6a3855797cf6bae622179c5e
#> 3  sha256:52dcadd062f584fa7e7828d580fbf6f3dd44261d6a6d37e7b831aa0e0b9be2d3
#> 4  sha256:35604598f352c0cc958e8330e80627ec65154e4eaba9dbba8cac92c8516706a0
#> 5  sha256:c0c0c5a6e478bae9d98c0251870fb73ef12ec5033de08589bad08ed03be02a31
#> 6  sha256:161bef58151083d80bd226022a46aed5a35a5acd1526dfc3deac42cb6ae952fc
#> 7  sha256:acbddab3bd06ac4790eb129201198e614c1d4c08b83cd18ee94e4cdfafa09ab2
#> 8  sha256:fb611fc77ebbe15429826d7acfe57d487118d7815dea9b2ad5a3f94f03a487e8
#> 9  sha256:c2cebcc7398ddd12d0803eefafbe219f3551e6948051f18d89d7984130c1589d
#> 10 sha256:d39b1ef2a8b3fd26974a3138a3f4e9516a65bddd34e9b50ab65c50a0cbfdc9c1
#> 11 sha256:2a6dd20fd0fe0d9ebc4d54bedafa95054ba3167ac255f98cd2a76dd082800591
#> 12 sha256:463bc63156786be38c39d5479bfe07ce7b593e1174ecba6f7d9e5ac52c2c6bfd
#>                                                             shape_observed
#> 1  sha256:4fec0f2db7523d71ba7542e0d52217c91d9bab5b55d714b689f614380f5c2eb9
#> 2  sha256:bb238447f12e8d11aca39893be56b02ded19ff156bd8eb6ec53f232fbe2b4996
#> 3  sha256:52dcadd062f584fa7e7828d580fbf6f3dd44261d6a6d37e7b831aa0e0b9be2d3
#> 4  sha256:35604598f352c0cc958e8330e80627ec65154e4eaba9dbba8cac92c8516706a0
#> 5  sha256:c0c0c5a6e478bae9d98c0251870fb73ef12ec5033de08589bad08ed03be02a31
#> 6  sha256:1298cae181b9af892584328d635430224297672a4a0eced4a2dd66d15652128c
#> 7  sha256:acbddab3bd06ac4790eb129201198e614c1d4c08b83cd18ee94e4cdfafa09ab2
#> 8  sha256:fb611fc77ebbe15429826d7acfe57d487118d7815dea9b2ad5a3f94f03a487e8
#> 9  sha256:c2cebcc7398ddd12d0803eefafbe219f3551e6948051f18d89d7984130c1589d
#> 10 sha256:d39b1ef2a8b3fd26974a3138a3f4e9516a65bddd34e9b50ab65c50a0cbfdc9c1
#> 11 sha256:2a6dd20fd0fe0d9ebc4d54bedafa95054ba3167ac255f98cd2a76dd082800591
#> 12 sha256:463bc63156786be38c39d5479bfe07ce7b593e1174ecba6f7d9e5ac52c2c6bfd
#>    shape_drift missing
#> 1        FALSE   FALSE
#> 2         TRUE   FALSE
#> 3        FALSE   FALSE
#> 4        FALSE   FALSE
#> 5        FALSE   FALSE
#> 6         TRUE   FALSE
#> 7        FALSE   FALSE
#> 8        FALSE   FALSE
#> 9        FALSE   FALSE
#> 10       FALSE   FALSE
#> 11       FALSE   FALSE
#> 12       FALSE   FALSE

if (FALSE) { # \dontrun{
# In a verification log: error on either drift kind
lnk_config_verify(cfg, strict = TRUE)
} # }
```

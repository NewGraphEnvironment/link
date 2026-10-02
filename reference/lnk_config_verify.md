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
verify
#>                                                  file
#> 1                                          rules.yaml
#> 2                                      dimensions.csv
#> 3                                parameters_fresh.csv
#> 4                   parameters_habitat_thresholds.csv
#> 5                       parameters_habitat_method.csv
#> 6           overrides/user_habitat_classification.csv
#> 7                overrides/observation_exclusions.csv
#> 8                  overrides/wsg_species_presence.csv
#> 9          overrides/user_modelled_crossing_fixes.csv
#> 10            overrides/user_pscis_barrier_status.csv
#> 11 overrides/pscis_modelledcrossings_streams_xref.csv
#> 12               overrides/user_barriers_definite.csv
#> 13       overrides/user_barriers_definite_control.csv
#> 14                  overrides/user_crossings_misc.csv
#>                                                              byte_expected
#> 1  sha256:a24df9f0865f8506151922207b94264914b61ce3c55622f16ddd79c1a7057d60
#> 2  sha256:92abd809a1e47a070b9644e18fc330e8dd366b7100334ad2a643ec64c1b717e5
#> 3  sha256:a877ec23b0e0853514d545fbd8b8f218718382dc44a72377ffcc45526e63984e
#> 4  sha256:7b904a18c29c724737ff24a27750bf05d7bfa281aa4fc1f7ac27c00238db042d
#> 5  sha256:9802bb71bdd7f7d296e917d138567f096a69dab12dbc7c0f331e55206e5f6a0a
#> 6  sha256:80b69d0954563660c13bc481b2e955000748e0597d4e10ce0c16462d9a5df966
#> 7  sha256:ad901c57ca42e71e4affffd6e583045a2ce423f15088c211c9c2f72976f5d36a
#> 8  sha256:cd42f2dff62cb76f77f4b055436329a74ba44fe1466dec5d7801aa5221360185
#> 9  sha256:d5c84fb00906acae110249c2976907860b829d4430e43ffaf2671e02e8e40037
#> 10 sha256:66c11defba1a1cab36adb56b395536279d83e481bcb948f93fb04db580753027
#> 11 sha256:cd9202d46904fac2865acff36be1b4d104c299f3b803bde6993d537e8bc03ead
#> 12 sha256:56c66cddf279a1c2b0c0be1fc9ba9c758dc93d4ad820e0bf2c5caf4ecce05fb6
#> 13 sha256:8f34e2c006733e0f06248a90dc0b8abe4719880590f497581f80fe5f62fde203
#> 14 sha256:e569fdfcf8c98eb0c7928b52a3de894a3c46e2599cafb04e746d4f858dffc711
#>                                                              byte_observed
#> 1  sha256:a24df9f0865f8506151922207b94264914b61ce3c55622f16ddd79c1a7057d60
#> 2  sha256:92abd809a1e47a070b9644e18fc330e8dd366b7100334ad2a643ec64c1b717e5
#> 3  sha256:a877ec23b0e0853514d545fbd8b8f218718382dc44a72377ffcc45526e63984e
#> 4  sha256:7b904a18c29c724737ff24a27750bf05d7bfa281aa4fc1f7ac27c00238db042d
#> 5  sha256:9802bb71bdd7f7d296e917d138567f096a69dab12dbc7c0f331e55206e5f6a0a
#> 6  sha256:80b69d0954563660c13bc481b2e955000748e0597d4e10ce0c16462d9a5df966
#> 7  sha256:ad901c57ca42e71e4affffd6e583045a2ce423f15088c211c9c2f72976f5d36a
#> 8  sha256:cd42f2dff62cb76f77f4b055436329a74ba44fe1466dec5d7801aa5221360185
#> 9  sha256:d5c84fb00906acae110249c2976907860b829d4430e43ffaf2671e02e8e40037
#> 10 sha256:66c11defba1a1cab36adb56b395536279d83e481bcb948f93fb04db580753027
#> 11 sha256:cd9202d46904fac2865acff36be1b4d104c299f3b803bde6993d537e8bc03ead
#> 12 sha256:56c66cddf279a1c2b0c0be1fc9ba9c758dc93d4ad820e0bf2c5caf4ecce05fb6
#> 13 sha256:8f34e2c006733e0f06248a90dc0b8abe4719880590f497581f80fe5f62fde203
#> 14 sha256:e569fdfcf8c98eb0c7928b52a3de894a3c46e2599cafb04e746d4f858dffc711
#>    byte_drift
#> 1       FALSE
#> 2       FALSE
#> 3       FALSE
#> 4       FALSE
#> 5       FALSE
#> 6       FALSE
#> 7       FALSE
#> 8       FALSE
#> 9       FALSE
#> 10      FALSE
#> 11      FALSE
#> 12      FALSE
#> 13      FALSE
#> 14      FALSE
#>                                                             shape_expected
#> 1  sha256:4fec0f2db7523d71ba7542e0d52217c91d9bab5b55d714b689f614380f5c2eb9
#> 2  sha256:bb238447f12e8d11aca39893be56b02ded19ff156bd8eb6ec53f232fbe2b4996
#> 3  sha256:52dcadd062f584fa7e7828d580fbf6f3dd44261d6a6d37e7b831aa0e0b9be2d3
#> 4  sha256:8de9bc1fcc2c703176a57d8a982bd26da1c49a885af3053f00078003a7e9283f
#> 5  sha256:cf285e3c204249a6b628424979ef780baa271add44cc8ea6512a44d6671a9eb5
#> 6  sha256:35604598f352c0cc958e8330e80627ec65154e4eaba9dbba8cac92c8516706a0
#> 7  sha256:c0c0c5a6e478bae9d98c0251870fb73ef12ec5033de08589bad08ed03be02a31
#> 8  sha256:1298cae181b9af892584328d635430224297672a4a0eced4a2dd66d15652128c
#> 9  sha256:acbddab3bd06ac4790eb129201198e614c1d4c08b83cd18ee94e4cdfafa09ab2
#> 10 sha256:fb611fc77ebbe15429826d7acfe57d487118d7815dea9b2ad5a3f94f03a487e8
#> 11 sha256:c2cebcc7398ddd12d0803eefafbe219f3551e6948051f18d89d7984130c1589d
#> 12 sha256:d39b1ef2a8b3fd26974a3138a3f4e9516a65bddd34e9b50ab65c50a0cbfdc9c1
#> 13 sha256:2a6dd20fd0fe0d9ebc4d54bedafa95054ba3167ac255f98cd2a76dd082800591
#> 14 sha256:463bc63156786be38c39d5479bfe07ce7b593e1174ecba6f7d9e5ac52c2c6bfd
#>                                                             shape_observed
#> 1  sha256:4fec0f2db7523d71ba7542e0d52217c91d9bab5b55d714b689f614380f5c2eb9
#> 2  sha256:bb238447f12e8d11aca39893be56b02ded19ff156bd8eb6ec53f232fbe2b4996
#> 3  sha256:52dcadd062f584fa7e7828d580fbf6f3dd44261d6a6d37e7b831aa0e0b9be2d3
#> 4  sha256:8de9bc1fcc2c703176a57d8a982bd26da1c49a885af3053f00078003a7e9283f
#> 5  sha256:cf285e3c204249a6b628424979ef780baa271add44cc8ea6512a44d6671a9eb5
#> 6  sha256:35604598f352c0cc958e8330e80627ec65154e4eaba9dbba8cac92c8516706a0
#> 7  sha256:c0c0c5a6e478bae9d98c0251870fb73ef12ec5033de08589bad08ed03be02a31
#> 8  sha256:1298cae181b9af892584328d635430224297672a4a0eced4a2dd66d15652128c
#> 9  sha256:acbddab3bd06ac4790eb129201198e614c1d4c08b83cd18ee94e4cdfafa09ab2
#> 10 sha256:fb611fc77ebbe15429826d7acfe57d487118d7815dea9b2ad5a3f94f03a487e8
#> 11 sha256:c2cebcc7398ddd12d0803eefafbe219f3551e6948051f18d89d7984130c1589d
#> 12 sha256:d39b1ef2a8b3fd26974a3138a3f4e9516a65bddd34e9b50ab65c50a0cbfdc9c1
#> 13 sha256:2a6dd20fd0fe0d9ebc4d54bedafa95054ba3167ac255f98cd2a76dd082800591
#> 14 sha256:463bc63156786be38c39d5479bfe07ce7b593e1174ecba6f7d9e5ac52c2c6bfd
#>    shape_drift missing
#> 1        FALSE   FALSE
#> 2        FALSE   FALSE
#> 3        FALSE   FALSE
#> 4        FALSE   FALSE
#> 5        FALSE   FALSE
#> 6        FALSE   FALSE
#> 7        FALSE   FALSE
#> 8        FALSE   FALSE
#> 9        FALSE   FALSE
#> 10       FALSE   FALSE
#> 11       FALSE   FALSE
#> 12       FALSE   FALSE
#> 13       FALSE   FALSE
#> 14       FALSE   FALSE

if (FALSE) { # \dontrun{
# In a verification log: error on either drift kind
lnk_config_verify(cfg, strict = TRUE)
} # }
```

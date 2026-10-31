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
#> 9          overrides/wsg_species_presence_overlay.csv
#> 10         overrides/user_modelled_crossing_fixes.csv
#> 11            overrides/user_pscis_barrier_status.csv
#> 12 overrides/pscis_modelledcrossings_streams_xref.csv
#> 13               overrides/user_barriers_definite.csv
#> 14       overrides/user_barriers_definite_control.csv
#> 15                  overrides/user_crossings_misc.csv
#> 16                       overrides/cabd_additions.csv
#> 17                      overrides/cabd_blkey_xref.csv
#> 18                      overrides/cabd_exclusions.csv
#> 19      overrides/cabd_passability_status_updates.csv
#> 20              overrides/dfo_known_sockeye_lakes.csv
#> 21                      overrides/wcrp_watersheds.csv
#>                                                              byte_expected
#> 1  sha256:e9b9ea721ac24e33ada3e2972ec789b6a00c7ef441b4ad269f76a4a3f6d2b6f7
#> 2  sha256:a48aadd609e2c5dd49501ed23f61bdf85386a41359a7a100394b648f04ffb496
#> 3  sha256:a877ec23b0e0853514d545fbd8b8f218718382dc44a72377ffcc45526e63984e
#> 4  sha256:0220ade85955bb29a1b1c898b4414ebf2143ab667917867fc8d3d2777f984aab
#> 5  sha256:9802bb71bdd7f7d296e917d138567f096a69dab12dbc7c0f331e55206e5f6a0a
#> 6  sha256:80b69d0954563660c13bc481b2e955000748e0597d4e10ce0c16462d9a5df966
#> 7  sha256:ad901c57ca42e71e4affffd6e583045a2ce423f15088c211c9c2f72976f5d36a
#> 8  sha256:2ea57578dbc5836d0e24ea6468534f081c7f5f37c72534ca2e3c0f06a6be4c18
#> 9  sha256:841e8780a1cba082be7ef32e98c9536a64f429f4fbf04f6944a60e65e13bfd14
#> 10 sha256:d5c84fb00906acae110249c2976907860b829d4430e43ffaf2671e02e8e40037
#> 11 sha256:66c11defba1a1cab36adb56b395536279d83e481bcb948f93fb04db580753027
#> 12 sha256:cd9202d46904fac2865acff36be1b4d104c299f3b803bde6993d537e8bc03ead
#> 13 sha256:56c66cddf279a1c2b0c0be1fc9ba9c758dc93d4ad820e0bf2c5caf4ecce05fb6
#> 14 sha256:8f34e2c006733e0f06248a90dc0b8abe4719880590f497581f80fe5f62fde203
#> 15 sha256:e569fdfcf8c98eb0c7928b52a3de894a3c46e2599cafb04e746d4f858dffc711
#> 16 sha256:75022b62d83d8a3dafd3d19e7cc8871948818e4b75e84af8e775b1199786e930
#> 17 sha256:3f55fcf2726fdc9aa2bb2b5bb3d22f989bc29d5aab971e82de8d4d432744a2dc
#> 18 sha256:fa22681c9dd0a881b4a4ba7f03c46cee20393faf0d77ce3bc30f759772e8efa6
#> 19 sha256:671793805fe2f4ec30a2844bd12db648b3e04e059d40470a1e01177349c6a00b
#> 20 sha256:4a8d7d1a3a3697d1536c5463364805916077aa171bd1e4d19fc8a9e2250979f7
#> 21 sha256:52c7544b5bc9a033e2c50fe39f41b722598700cb2faa8655ca07010f342f21f8
#>                                                              byte_observed
#> 1  sha256:e9b9ea721ac24e33ada3e2972ec789b6a00c7ef441b4ad269f76a4a3f6d2b6f7
#> 2  sha256:a48aadd609e2c5dd49501ed23f61bdf85386a41359a7a100394b648f04ffb496
#> 3  sha256:a877ec23b0e0853514d545fbd8b8f218718382dc44a72377ffcc45526e63984e
#> 4  sha256:0220ade85955bb29a1b1c898b4414ebf2143ab667917867fc8d3d2777f984aab
#> 5  sha256:9802bb71bdd7f7d296e917d138567f096a69dab12dbc7c0f331e55206e5f6a0a
#> 6  sha256:80b69d0954563660c13bc481b2e955000748e0597d4e10ce0c16462d9a5df966
#> 7  sha256:ad901c57ca42e71e4affffd6e583045a2ce423f15088c211c9c2f72976f5d36a
#> 8  sha256:2ea57578dbc5836d0e24ea6468534f081c7f5f37c72534ca2e3c0f06a6be4c18
#> 9  sha256:841e8780a1cba082be7ef32e98c9536a64f429f4fbf04f6944a60e65e13bfd14
#> 10 sha256:d5c84fb00906acae110249c2976907860b829d4430e43ffaf2671e02e8e40037
#> 11 sha256:66c11defba1a1cab36adb56b395536279d83e481bcb948f93fb04db580753027
#> 12 sha256:cd9202d46904fac2865acff36be1b4d104c299f3b803bde6993d537e8bc03ead
#> 13 sha256:56c66cddf279a1c2b0c0be1fc9ba9c758dc93d4ad820e0bf2c5caf4ecce05fb6
#> 14 sha256:8f34e2c006733e0f06248a90dc0b8abe4719880590f497581f80fe5f62fde203
#> 15 sha256:e569fdfcf8c98eb0c7928b52a3de894a3c46e2599cafb04e746d4f858dffc711
#> 16 sha256:75022b62d83d8a3dafd3d19e7cc8871948818e4b75e84af8e775b1199786e930
#> 17 sha256:3f55fcf2726fdc9aa2bb2b5bb3d22f989bc29d5aab971e82de8d4d432744a2dc
#> 18 sha256:fa22681c9dd0a881b4a4ba7f03c46cee20393faf0d77ce3bc30f759772e8efa6
#> 19 sha256:671793805fe2f4ec30a2844bd12db648b3e04e059d40470a1e01177349c6a00b
#> 20 sha256:4a8d7d1a3a3697d1536c5463364805916077aa171bd1e4d19fc8a9e2250979f7
#> 21 sha256:52c7544b5bc9a033e2c50fe39f41b722598700cb2faa8655ca07010f342f21f8
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
#> 15      FALSE
#> 16      FALSE
#> 17      FALSE
#> 18      FALSE
#> 19      FALSE
#> 20      FALSE
#> 21      FALSE
#>                                                             shape_expected
#> 1  sha256:4fec0f2db7523d71ba7542e0d52217c91d9bab5b55d714b689f614380f5c2eb9
#> 2  sha256:65b9416981cf2687332a98923d9e4cdfc6800f4d55a85c5d0348c64cafb41155
#> 3  sha256:52dcadd062f584fa7e7828d580fbf6f3dd44261d6a6d37e7b831aa0e0b9be2d3
#> 4  sha256:b837e5dabbce8e69488a1523214bf111827682e4edf87526557231c377fa538e
#> 5  sha256:cf285e3c204249a6b628424979ef780baa271add44cc8ea6512a44d6671a9eb5
#> 6  sha256:35604598f352c0cc958e8330e80627ec65154e4eaba9dbba8cac92c8516706a0
#> 7  sha256:c0c0c5a6e478bae9d98c0251870fb73ef12ec5033de08589bad08ed03be02a31
#> 8  sha256:161bef58151083d80bd226022a46aed5a35a5acd1526dfc3deac42cb6ae952fc
#> 9  sha256:eb72f24aa4e2850578d9ce3feadf0125eb8bd1c95a16215705e8c57dc8aee324
#> 10 sha256:acbddab3bd06ac4790eb129201198e614c1d4c08b83cd18ee94e4cdfafa09ab2
#> 11 sha256:fb611fc77ebbe15429826d7acfe57d487118d7815dea9b2ad5a3f94f03a487e8
#> 12 sha256:c2cebcc7398ddd12d0803eefafbe219f3551e6948051f18d89d7984130c1589d
#> 13 sha256:d39b1ef2a8b3fd26974a3138a3f4e9516a65bddd34e9b50ab65c50a0cbfdc9c1
#> 14 sha256:2a6dd20fd0fe0d9ebc4d54bedafa95054ba3167ac255f98cd2a76dd082800591
#> 15 sha256:463bc63156786be38c39d5479bfe07ce7b593e1174ecba6f7d9e5ac52c2c6bfd
#> 16 sha256:cca1f4ecdd08ae9acfaa968767f2d911ce23115500ea2aa595b393c0e76b2cb9
#> 17 sha256:62169e677bf9a7e50893f2407408a573a8137011e7797685a14d979d27e0d171
#> 18 sha256:6f13d737481c9e94be585861490fe8c35a81cc026875b5e873345e47ec59ad0e
#> 19 sha256:0975cea50456c610de6a229949f2e6d7233613ec57e1aa7dfdb51d05c1216ef8
#> 20 sha256:33ac6f1f2766d6b4d138782b549d4f7156d7fe05485d8f66b4a9a55a431f88cb
#> 21 sha256:2b0eaf185855f06731bfb8f98294a0c7938aef26a5c7265beec167ce0bb46f41
#>                                                             shape_observed
#> 1  sha256:4fec0f2db7523d71ba7542e0d52217c91d9bab5b55d714b689f614380f5c2eb9
#> 2  sha256:65b9416981cf2687332a98923d9e4cdfc6800f4d55a85c5d0348c64cafb41155
#> 3  sha256:52dcadd062f584fa7e7828d580fbf6f3dd44261d6a6d37e7b831aa0e0b9be2d3
#> 4  sha256:b837e5dabbce8e69488a1523214bf111827682e4edf87526557231c377fa538e
#> 5  sha256:cf285e3c204249a6b628424979ef780baa271add44cc8ea6512a44d6671a9eb5
#> 6  sha256:35604598f352c0cc958e8330e80627ec65154e4eaba9dbba8cac92c8516706a0
#> 7  sha256:c0c0c5a6e478bae9d98c0251870fb73ef12ec5033de08589bad08ed03be02a31
#> 8  sha256:161bef58151083d80bd226022a46aed5a35a5acd1526dfc3deac42cb6ae952fc
#> 9  sha256:eb72f24aa4e2850578d9ce3feadf0125eb8bd1c95a16215705e8c57dc8aee324
#> 10 sha256:acbddab3bd06ac4790eb129201198e614c1d4c08b83cd18ee94e4cdfafa09ab2
#> 11 sha256:fb611fc77ebbe15429826d7acfe57d487118d7815dea9b2ad5a3f94f03a487e8
#> 12 sha256:c2cebcc7398ddd12d0803eefafbe219f3551e6948051f18d89d7984130c1589d
#> 13 sha256:d39b1ef2a8b3fd26974a3138a3f4e9516a65bddd34e9b50ab65c50a0cbfdc9c1
#> 14 sha256:2a6dd20fd0fe0d9ebc4d54bedafa95054ba3167ac255f98cd2a76dd082800591
#> 15 sha256:463bc63156786be38c39d5479bfe07ce7b593e1174ecba6f7d9e5ac52c2c6bfd
#> 16 sha256:cca1f4ecdd08ae9acfaa968767f2d911ce23115500ea2aa595b393c0e76b2cb9
#> 17 sha256:62169e677bf9a7e50893f2407408a573a8137011e7797685a14d979d27e0d171
#> 18 sha256:6f13d737481c9e94be585861490fe8c35a81cc026875b5e873345e47ec59ad0e
#> 19 sha256:0975cea50456c610de6a229949f2e6d7233613ec57e1aa7dfdb51d05c1216ef8
#> 20 sha256:33ac6f1f2766d6b4d138782b549d4f7156d7fe05485d8f66b4a9a55a431f88cb
#> 21 sha256:2b0eaf185855f06731bfb8f98294a0c7938aef26a5c7265beec167ce0bb46f41
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
#> 15       FALSE   FALSE
#> 16       FALSE   FALSE
#> 17       FALSE   FALSE
#> 18       FALSE   FALSE
#> 19       FALSE   FALSE
#> 20       FALSE   FALSE
#> 21       FALSE   FALSE

if (FALSE) { # \dontrun{
# In a verification log: error on either drift kind
lnk_config_verify(cfg, strict = TRUE)
} # }
```

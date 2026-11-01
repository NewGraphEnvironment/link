# CSV sync -- 2026-10-31 -- TOKEN REVIEW

Pinned to bcfp build `v0.7.15-51-g3bd2824` (head_sha `3bd2824`, completed `2026-10-28T04:44:44Z`).

## Needs review before merging

A run of the bundle below refuses until each item is resolved:
a moved spec needs a row in `inst/extdata/vocabulary.csv` (and the
row it replaces retired, with a version bump); a bundle that does not
load needs its overlay fixed.

- `bcfishpass`'s `acc` spec moves, so it needs a new vocabulary row (and the old one retired): `sha256:970ea40bcda8ac3df0337b237b4f73a8ba5677a2b7ddd17a696069f839378bed`

Synced 7 bundle file(s) from `s3://fresh-bc/bcfishpass/csvs/`:

| bundle | file | drift | old byte | new byte |
|---|---|---|---|---|
| `bcfishpass` | `overrides/wsg_species_presence.csv` | byte | `sha256:3c3dc66` | `sha256:2ea5757` |
| `bcfishpass` | `overrides/cabd_blkey_xref.csv` | byte | `sha256:3a0771a` | `sha256:3f55fcf` |
| `bcfishpass` | `overrides/cabd_passability_status_updates.csv` | byte | `sha256:dd69c2a` | `sha256:6717938` |
| `bcfishpass` | `overrides/wcrp_watersheds.csv` | byte | `sha256:acadc8d` | `sha256:52c7544` |
| `default` | `overrides/cabd_blkey_xref.csv` | byte | `sha256:3a0771a` | `sha256:3f55fcf` |
| `default` | `overrides/cabd_passability_status_updates.csv` | byte | `sha256:dd69c2a` | `sha256:6717938` |
| `default` | `overrides/wcrp_watersheds.csv` | byte | `sha256:acadc8d` | `sha256:52c7544` |

Each bundle syncs only the copies its own provenance declares. Run
`Rscript -e 'devtools::load_all("."); lnk_config_verify(lnk_config("bcfishpass"))'`
after pulling to confirm clean state.

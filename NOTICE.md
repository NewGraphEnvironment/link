# NOTICE

`link` builds on upstream data and software from
[smnorris](https://github.com/smnorris) and is grateful to those
projects.

## Upstream sources

| Source                                                                   | License                  | How `link` uses it                                                            |
|--------------------------------------------------------------------------|--------------------------|-------------------------------------------------------------------------------|
| [smnorris/fwapg](https://github.com/smnorris/fwapg)                      | MIT                      | Runtime SQL access to BC’s Freshwater Atlas. Not redistributed.               |
| [smnorris/bcfishobs](https://github.com/smnorris/bcfishobs)              | Apache 2.0               | Runtime read of fish observation data (via tunnel DB). Not redistributed.     |
| [smnorris/bcfishpass](https://github.com/smnorris/bcfishpass) (software) | Apache 2.0               | Reference for habitat-classification parity. Not redistributed.               |
| [smnorris/bcfishpass](https://github.com/smnorris/bcfishpass) (data)     | ODbL + DATABASE CONTENTS | **Redistributed** — the override CSVs in `inst/extdata/configs/*/overrides/`. |

## Redistributed data

`link` redistributes the following files from
[smnorris/bcfishpass](https://github.com/smnorris/bcfishpass) under the
terms of `LICENSE-bcfishpass` (a verbatim copy at this repository’s
root):

- `inst/extdata/configs/bcfishpass/overrides/user_habitat_classification.csv`
- `inst/extdata/configs/bcfishpass/overrides/user_modelled_crossing_fixes.csv`
- `inst/extdata/configs/bcfishpass/overrides/user_pscis_barrier_status.csv`
- `inst/extdata/configs/bcfishpass/overrides/pscis_modelledcrossings_streams_xref.csv`
- `inst/extdata/configs/bcfishpass/overrides/user_barriers_definite.csv`
- `inst/extdata/configs/bcfishpass/overrides/user_barriers_definite_control.csv`
- `inst/extdata/configs/bcfishpass/overrides/user_crossings_misc.csv`

The same files are mirrored under
`inst/extdata/configs/default/overrides/`. Provenance metadata (upstream
commit SHA, sync date, byte + shape checksums) for each file is recorded
in the corresponding `config.yaml` under the `provenance:` block.

## `link`’s own license

`link` itself is MIT-licensed; see `LICENSE` for `link`’s code license.
This `NOTICE` file documents attribution for upstream redistributions
and runtime dependencies; it does not modify the terms under which
`link`’s own code is distributed.

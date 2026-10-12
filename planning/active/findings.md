# Findings — Build DUNC into fresh_default (config default) for the floodplains Columbia region (#328)

## Issue context

## Ask

Build watershed group **DUNC** (Duncan Lake, Lardeau River) into `fresh_default` under config `default`, the same way KOTL, LARL and SLOC are built there.

## Why

`floodplains` is moving its Columbia region (KOTL, LARL, SLOC, DUNC) to whole-network floodplains (`species: all`, order >= 2, see NewGraphEnvironment/floodplains#104). A floodplains region reads its network from one schema, and the four groups are split across two today (measured 2026-10-12):

| group | `fresh_default.streams`, order >= 2 | `fresh.streams`, order >= 2 |
|---|---|---|
| KOTL | 5,723 km, habitat tables present | absent |
| LARL | 4,540 km, habitat tables present | absent |
| SLOC | 2,636 km, habitat tables present | absent |
| DUNC | absent | 3,493 km, `streams_habitat_bt` / `_wct` present |

Each figure matches the bcfishpass reference view (`fresh.streams_vw_bcfp`) to the kilometre.

Reading DUNC from `fresh` instead would put a `bcfishpass`-config group inside a region whose other groups are `default`-config, so the habitat flags would not be comparable across the region.

## Also observed

DUNC is in `fresh.streams` and `fresh.streams_habitat_*` (it ran in the 2026-04-30 provincial parity run, `data-raw/logs/20260430_2155_provincial_parity.txt`), but has **no rows in `fresh.streams_access` and no row in `fresh.log`**. Noting it in case that is not intended; floodplains does not depend on it.

## Done when

- `fresh_default.streams` and `fresh_default.streams_habitat_bt` / `_wct` hold DUNC.
- `fresh_default.log` (or its equivalent) carries a row for the DUNC build, so floodplains records its config hash and FWA version.

Relates: NewGraphEnvironment/floodplains#104, NewGraphEnvironment/floodplains#120

## Plan-mode exploration (2026-10-12)

- `fresh_default.log` has 4 rows: PINE (2026-08-06), LARL, KOTL, SLOC (2026-08-27, run_label `columbia_default`, link 0.45.1, fresh 0.33.0). KOTL and SLOC: link `322389a` clean, config_hash `sha256:3cfde7…`; LARL: `8c8c29b` dirty, hash `44e452…`.
- `fresh_default` holds 55 groups; most predate the log and #223 segmentation.
- `lnk_wsg_downstream_check(DUNC, default)`: pass, 6 dams downstream, all in KOTL.
- `lnk_pipeline_species(default, DUNC)`: BT WCT RB.
- DUNC in `fresh`: 26,827 segments, built in the 2026-04-30 parity run. That predates `streams_access` (v0.40.0, 2026-05-19) and the log tables (#127, 2026-08-06). In `fresh`, 98 groups have streams, 59 have `streams_access`, 39 have log rows.
- floodplains `config/regions/columbia.yml` grabs the network from `fresh_default` and cites link 0.45.1; floodplains#125 keeps the published KOTL/LARL/SLOC bt_ff04 items.

## Errors Encountered

| Error | Resolution |
|-------|------------|

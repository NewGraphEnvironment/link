# Findings — #51 (configs/default/ + compound rollup)

## Architecture audit already done (before PR)

- fresh code has zero hardcoded `fresh.streams` references (fresh#163 closed clean). Pipeline helpers honour caller-supplied table paths.
- `frs_aggregate()` already polygon-capable. `fwa_lakes_poly` + `fwa_wetlands_poly` both have `wscode_ltree`, `localcode_ltree`, `area_ha` — aggregation is a one-liner at the link rollup layer. No fresh extension needed.
- `frs_habitat_classify()` now has `wetland_rearing` column (fresh 0.16.0 via PR #164). Same pattern as `lake_rearing`, joined to `fwa_wetlands_poly`.

## Source material already in repo

- `inst/extdata/parameters_habitat_dimensions.csv` — the newgraph-default dimensions CSV. Per-species booleans for lake/wetland/stream spawn+rear, `river_skip_cw_min`, connectivity requirements. Already encodes the expected deltas from bcfishpass (e.g. BT: `rear_lake=yes, rear_wetland=yes, river_skip_cw_min=yes`; bcfishpass variant has `rear_lake=no, rear_wetland=no`).
- `inst/extdata/configs/bcfishpass/dimensions.csv` — 19-column schema (has bcfishpass-specific columns like `rear_stream_order_bypass`, `spawn_connected_*`).
- `inst/extdata/parameters_habitat_dimensions.csv` — 15-column schema (missing the 4 bcfishpass-specific columns).

Open question: does `lnk_rules_build()` handle both schemas cleanly? The default CSV is a subset of the bcfishpass CSV columns — probably fine, but verify during Phase 1.

## bcfishpass-specific columns we skip in the default

`rear_stream_order_bypass`, `spawn_connected_direction`, `spawn_connected_gradient_max`, `spawn_connected_cw_min`, `spawn_connected_edge_types` — these are bcfishpass method-specific features we intentionally don't ship in the default. The default dimensions CSV reflects this by omitting the columns entirely.

## Documented biological departures from bcfishpass (to encode + defend)

From archived planning + the dimensions CSV:

| Decision | bcfishpass | NGE default | Present in default dimensions.csv |
|---|---|---|---|
| Intermittent streams | excluded | included | needs edge-type rule check |
| Wetland segments | limited | CO rearing 1050/1150 | `rear_wetland=yes` for CO/BT/others |
| Spawn gradient min | 0 | 0.0025 | check `parameters_fresh.csv` or rules |
| River polygon cw_min | applied | skipped | `river_skip_cw_min=yes` |
| Lake rearing species | SK/KO only | expanded | `rear_lake=yes` for BT/CO/ST/WCT |

Research doc captures each with biological rationale + link to literature as discovered.

## Rollup decision (resolved)

Option B — three compound columns. Never fold to one. Enables queries like "areas with lots of wetland but short linear extent" that the user flagged as important.

- `rearing_km` — sum segment length where rearing = TRUE. **Probably exclude lake/wetland centerlines** to avoid double-counting with the `_ha` columns. Finalize in Phase 2.
- `lake_rearing_ha` — sum `area_ha` from `fwa_lakes_poly` upstream of point + waterbody_key matches accessible segment's lake_rearing = TRUE.
- `wetland_rearing_ha` — same against `fwa_wetlands_poly`.

## Temperature / thermal out of scope

Deferred to a separate config variant (e.g. `configs/default-thermal/`) once Poisson SSN + Hillcrest CW regression + water-temp-bc compose. Multi-month integration.

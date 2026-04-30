# dimensions.csv audit (bcfishpass-bundle)

Triggered 2026-04-30 by finding `rear_stream_in_waterbody = no` for **all** species when bcfp's per-species rear rule has different waterbody handling depending on species. Systematic per-column, per-species review.

## Per-species bcfp rear-rule waterbody filter

Read directly from `bcfishpass/model/02_habitat_linear/sql/load_habitat_linear_<sp>.sql`, "REARING ON SPAWNING STREAMS" INSERT.

| species | rear-rule waterbody filter | edge types | wetland-flow (1050/1150) | dimensions mapping |
|---|---|---|---|---|
| **BT** | **none** (no waterbody filter, no edge filter) | all | yes | `rear_all_edges = yes` |
| **CH** | strict: `wb='R' OR (wb IS NULL AND edge IN list)` | 1000/1100/2000/2300 | no | `rear_stream_in_waterbody = no`, `rear_wetland = no` |
| **CM** | no freshwater rearing | — | — | `rear_no_fw = yes` |
| **CO** | permissive: `wb='R' OR wb IS NULL OR edge IN list` | 1000/1100/2000/2300/**1050/1150** | **yes** | `rear_stream_in_waterbody = yes`, `rear_wetland = yes` |
| **PK** | no freshwater rearing | — | — | `rear_no_fw = yes` |
| **SK** | lake only | — | — | `rear_lake_only = yes` |
| **ST** | permissive: `wb='R' OR wb IS NULL OR edge IN list` | 1000/1100/2000/2300 | no | `rear_stream_in_waterbody = yes`, `rear_wetland = no` |
| **WCT** | strict: `wb='R' OR (wb IS NULL AND edge IN list)` | 1000/1100/2000/2300 | no | `rear_stream_in_waterbody = no`, `rear_wetland = no` |

## Per-species spawn-rule waterbody filter

bcfp's spawn rule is **strict** for every species (matches `spawn_stream_in_waterbody = no`):

```sql
( wb.waterbody_type = 'R' OR (wb.waterbody_type IS NULL AND s.edge_type IN (1000,1100,2000,2300)) )
```

No mismatches in `spawn_stream_in_waterbody` column today (all `no` correctly). Leave alone.

## Mismatches in current bcfishpass-bundle dimensions.csv

| species | column | current | should be (parity) | impact |
|---|---|---|---|---|
| **ST** | `rear_stream_in_waterbody` | `no` | **`yes`** | ~50 km MORR ST under-credit gap. Stream-edge segments inside waterbody polygons (waterbody_key set, edge=1000) currently dropped by link's `in_waterbody:false`; bcfp credits them. |
| **CO** | `rear_stream_in_waterbody` | `no` | **`yes`** | similar to ST; bcfp's CO rule is permissive |

**No other column-level mismatches detected** in this audit pass.

## Other columns reviewed (no changes needed)

- `rear_all_edges = yes` for BT — verified bcfp BT rear rule has no waterbody/edge filter at all. Current value matches.
- `rear_lake_only = yes` for SK — verified bcfp SK rearing is lake-only (`area_ha >= 200 ha`, lakes/reservoirs).
- `rear_no_fw = yes` for CM and PK — verified bcfp doesn't model freshwater rearing for these species.
- `rear_wetland = yes` for CO only — verified bcfp's CO rule is unique in including 1050/1150 wetland-flow edges.
- `spawn_stream_in_waterbody = no` for all — bcfp spawn rule is strict for every species.
- `river_skip_cw_min = yes` for all — bcfp uses `cw.channel_width > t.spawn_channel_width_min OR r.waterbody_key IS NOT NULL` in spawn (river-polygon segments skip cw_min check).

## Open questions for review

1. **Default-bundle decisions**: should NewGraph default also flip ST and CO to `rear_stream_in_waterbody = yes`? Or is the more restrictive `no` better for NewGraph methodology (less likely to over-credit rearing in waterbody-flowing reaches)?
2. **`rear_wetland = no` for ST and WCT**: bcfp doesn't include wetland-flow edges for these species. Is that ecologically right? Steelhead juveniles do use wetland edges in some basins. Methodology choice.
3. **`rear_all_edges = yes` for BT**: pulls in lake centerline (edge 1500), wetland centerline (1700), construction lines, etc. Bcfp's BT rule has no edge filter. Ecologically defensible? Bull trout do use lake habitat. NewGraph methodology might want stricter.
4. **`rear_stream_order_bypass`**: currently `no` for all species in bcfishpass-bundle, with the comment "bcfishpass: stream order bypass handled in compare script Step 7b." That step was in the legacy compare script — no longer exists. Possibly stale; if bcfp's rear rule has the bypass inline (`stream_order_parent >= 5 AND stream_order = 1`), this column should reflect that. Check.

## Action

Pure dimensions.csv edits (no code changes):

1. Flip **ST** `rear_stream_in_waterbody`: `no` → `yes` in `inst/extdata/configs/bcfishpass/dimensions.csv`.
2. Flip **CO** `rear_stream_in_waterbody`: `no` → `yes` in `inst/extdata/configs/bcfishpass/dimensions.csv`.
3. Investigate (4) — if `rear_stream_order_bypass` should be wired in via the dimension, flip values per-species accordingly.
4. Regenerate `rules.yaml` via `lnk_rules_build()` and `data-raw/build_rules.R`.
5. Re-install link, re-run MORR ST + KISP SK + 10-WSG `tar_make` for parity confirmation.

Default-bundle is left alone in this pass. NewGraph methodology decisions on the open questions need a separate discussion before any default-bundle edits.

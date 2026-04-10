# Findings: ADMS Comparison

## bcfishpass v0.5.0 code review findings

- `break_streams('crossings', wsg)` breaks at ALL crossings — confirmed from SQL function source
- barrier_status only used in `load_streams_access.sql` for access codes (0/1/2)
- `load_dnstr()` indexes downstream features as ID arrays per segment
- Access codes: 0 = barrier downstream, 1 = no barrier but unconfirmed, 2 = confirmed by observations
- ADMS uses model = "cw" (channel width), species BT, CH, CO, SK classified
- bcfishpass GENERATES gradient barriers at 8 classes (5,7,10,12,15,20,25,30%) in `gradient_barriers` table but only species access barriers (15/20/25/30) end up in `barriers_${MODEL}` tables that drive `break_streams()`. Streams NOT broken at 5/7/10/12.
- `gradient_barriers_load.sql` uses 100m vertex-level sampling AND island detection (one entry per island, minimum downstream measure). Same approach as fresh.

## Parameter differences
- `parameters_habitat_thresholds.csv` identical between fresh and bcfishpass
- `parameters_fresh.csv` adds `spawn_gradient_min` (0.0025) — bcfishpass doesn't use this. Set to 0 for comparison.
- `waterbody_type='R'` join: bcfishpass skips cw_min on river polygon segments (fresh#116 adds per-rule threshold overrides for this)

## Function consolidation (completed)
- 12 → 8 functions
- Key renames: lnk_break_source → lnk_source, lnk_habitat_upstream → lnk_aggregate
- lnk_match now handles xref_csv directly (no separate PSCIS/MOTI wrappers)

## Comparison results

### Sub-basin (wscode 432966) — fresh 0.12.2 with bcfishpass-matching rules YAML

| Species | Habitat | fresh | bcfishpass | diff |
|---------|---------|-------|-----------|------|
| **BT** | **spawning** | **13.07** | **12.86** | **+1.6%** ✓ |
| **BT** | **rearing** | **30.02** | **30.18** | **-0.5%** ✓ |
| **CH** | **spawning** | **9.18** | **9.18** | **0.0%** ✓ |
| **CH** | **rearing** | **10.15** | **10.15** | **0.0%** ✓ |
| **CO** | **spawning** | **10.21** | **10.21** | **0.0%** ✓ |
| **CO** | **rearing** | **10.87** | **10.94** | **-0.6%** ✓ |
| SK | spawning | 2.20 | NA | n/a (no lake in sub-basin) |
| SK | rearing | 0.00 | NA | ✓ (lake-only rule works) |

CH spawning: **exact**. CH rearing: **exact**. CO spawning: **exact**. All within 5%.

### Full ADMS — current results (fresh 0.12.3 + fixes)

| Species | Habitat | fresh | bcfishpass | diff | Notes |
|---------|---------|-------|-----------|------|-------|
| BT | spawning | 314.69 | 361.71 | -13.0% | Channel width data gap |
| BT | rearing | 616.38 | 674.19 | -8.6% | Close |
| CH | spawning | 221.28 | 277.61 | -20.3% | Channel width data gap |
| CH | rearing | 244.35 | 308.23 | -20.7% | + cluster connectivity |
| CO | spawning | 250.85 | 310.98 | -19.3% | Channel width data gap |
| CO | rearing | 269.20 | 351.19 | -23.3% | + cluster connectivity |
| SK | spawning | 194.70 | 85.70 | +127.2% | fresh#120 missing |
| SK | rearing | 132.14 | 229.85 | -42.5% | Lake area difference |

BT accessible: 6,837 of 30,327 (22.5%)
CH/CO/SK accessible: 3,572 of 30,327 (11.8%)

### Fixes applied (session 2026-04-10)

1. **BARRIER label fix** — changed label_map from `"BARRIER" = "blocked"` to `"BARRIER" = "barrier"`. bcfishpass natural access = gradient + falls only; crossing barrier_status does NOT block natural access. This fixed the ~93% undercount.

2. **River polygon rearing** — bcfishpass rearing SQL includes `waterbody_type = 'R'` as an OR with edge_type filter. Edge_type 1250/1350/1450 segments in river polygons get rearing. Added `rear_river` rule to all species with stream rearing. Added ~150 km CH rearing, ~150 km CO rearing.

3. **Double clustering fix** — fresh 0.12.3 runs frs_cluster internally in frs_habitat. Removed external frs_cluster call from compare_adms.R to avoid double-removal of disconnected rearing.

4. **CSV-driven YAML generation** — both build_bcfishpass_rules_yaml.R and build_habitat_rules_yaml.R now read from parameters_habitat_dimensions.csv. bcfishpass builder applies known deviations via override list.

### Remaining gaps explained

1. **Channel width data gap (-13 to -20% on spawning)** — Docker fwapg has MODELLED widths only; bcfishpass tunnel has FIELD_MEASUREMENT updates. More segments have cw data in bcfishpass → more pass threshold checks.

2. **Cluster connectivity (-20-23% on CH/CO rearing)** — frs_cluster may remove more disconnected rearing than bcfishpass's 3-phase approach. bcfishpass has Phase 2 (downstream of spawning, no distance cap) and Phase 3 (upstream, 10km cap). frs_cluster uses ST_ClusterDBSCAN which may handle bridge gradients differently.

3. **SK spawning +127%** — fresh#120 not implemented. bcfishpass limits SK spawning to within 3km of a rearing lake >= 200 ha.

4. **SK rearing -42.5%** — lake area calculation differences. bcfishpass may count lake segments differently.

5. **bcfishobs not loaded** — observations upgrade access in bcfishpass. Not yet available on Docker.

## Architecture findings

1. **bcfishpass gates habitat on natural access** — `barriers_bt_dnstr = array[]::text[]` in habitat_linear SQL. Fresh does the same via gradient barriers + label_block.

2. **Crossings don't block natural access** — `barriers_bt_dnstr` tracks gradient barriers + falls, NOT crossing barrier_status. POTENTIAL/BARRIER crossings are anthropogenic. Crossings should break geometry only.

3. **Falls are natural barriers** — 7 in ADMS, 0 in test sub-basin.

4. **Species use different access arrays**: BT at 25%, CO/CH/SK at 15%.

5. **SK spawning requires lake proximity** — bcfishpass classifies SK spawning only within 3km upstream/downstream of rearing lakes ≥ 200 ha. Fresh classifies SK spawning on gradient+cw alone. fresh#120 filed.

## Edge type filtering
- bcfishpass filters spawning to edge_type 1000/1100/2000/2300 only (excludes wetland-flow 1050/1150)
- fresh `stream` category includes 1050/1150 by default
- bcfishpass-matching rules YAML uses `edge_types_explicit: [1000, 1100, 2000, 2300]`
- waterbody_type='R' skips cw_min (river polygon data fix)

## Rearing-connectivity model (bcfishpass v0.5.0)
Three phases, sequential. See link#18 for full detail.
- Phase 1: rearing on spawning streams
- Phase 2: rearing downstream of spawning (no distance cap)
- Phase 3: rearing upstream of spawning (10km cap, 5% bridge gradient)
- BT cluster_rearing = FALSE (rear independently). CH/CO/SK = TRUE.

## Gradient barrier resolution
- bcfishpass `gradient_barriers_load.sql` and fresh `frs_break_find` both use 100m vertex-level sampling with island detection
- fresh#118 fixed: min_length default changed from 100 to 0 (was dropping short barriers)
- Sub-basin: 137 gradient_15 barriers (fresh) vs 241 (bcfishpass) — closer but not exact. At full ADMS: 5,571 vs ~7,127 (bcfishpass). Need to verify if the remaining gap is from the min_length change or other differences.

## bcfishobs integration (2026-04-10)

### Upstream status
- smnorris/bcfishobs `main` branch: completely restructured from our `master`
- No more Makefile — replaced by `load_supporting_data.sh` + `process.sh`
- Source data now from **parquet on NRS object storage** (`nrs.objectstore.gov.bc.ca`) via ogr2ogr `/vsicurl/` — no more bcdata WFS download
- Single `sql/process.sql` — consolidated all numbered SQL files into one transaction
- Output table: `bcfishobs.observations` (not the old view `fiss_fish_obsrvtn_events_vw`)
- DB migrations: `db/v0.2.0.sql` through `db/v0.3.2.sql`
- Requires: pgcrypto extension, whse_fish schema (species_cd, wdic_waterbodies), fwapg

### How bcfishpass uses observations
- Observations upgrade access from "unknown" to "known accessible" per species
- `load_streams_access.sql`: if species observed upstream of a barrier, access = 2 (confirmed)
- This means segments behind barriers with fish observations are still classified as accessible
- BT rears above barriers — many populations have been resident since post-glacial (10k years)

### Decision: use bcfishobs as-is
- bcfishobs does the hard work of snapping observations to FWA (lake/wetland + stream matching)
- fresh already has `frs_fish_obs()` that queries the output table
- Clean boundary: bcfishobs (snap to network) -> bcfishobs.observations -> fresh reads it
- Avoids re-implementing tested snapping logic in fresh
- NGE fish data and e-fishing densities are a separate concern (link#20) — load as additional sources later

### db_newgraph integration
- `db_newgraph/jobs/bcfishobs` script: clones smnorris/bcfishobs, runs make, dumps to S3 as FlatGeobuf
- GHA workflow `bcfishpass.yaml` runs bcfishobs as part of the bcfishpass rebuild pipeline
- Same pattern for local Docker: run process.sh with DATABASE_URL pointing to fwapg

## fresh issues filed (from this comparison)
- #96 ✓ — AOI support
- #98 ✓ — gate + label_block
- #100 ✓ — edge_type filtering
- #101 ✓ — breaks_gradient param
- #102 ✓ — expose params on frs_habitat
- #105 — feature_codes categories
- #107 ✓ — frs_cluster (rearing connectivity)
- #110 — gradient dedupe precision
- #113 ✓ — rules YAML format
- #114 — Phase 2 MAD support
- #116 ✓ — per-rule threshold overrides
- #118 ✓ — min_length filter fix
- #120 — SK spawning requires lake proximity

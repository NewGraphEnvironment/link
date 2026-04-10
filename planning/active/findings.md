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

### Full ADMS — massive undercount (BUG)

| Species | Habitat | fresh | bcfishpass | diff |
|---------|---------|-------|-----------|------|
| BT | spawning | 25.52 | 361.71 | -92.9% |
| BT | rearing | 31.85 | 674.19 | -95.3% |
| CH | spawning | 21.00 | 277.61 | -92.4% |
| CO | spawning | 21.62 | 310.98 | -93.0% |
| SK | spawning | 12.79 | 85.70 | -85.1% |

bcfishpass: 5,262 of 15,764 segments BT-accessible (33%)
fresh: 1,288 of 30,327 segments BT-accessible (4.2%)

Access gating is far too aggressive at full WSG scale. Sub-basin validates the classification logic; full WSG breaks the access model.

### Hypotheses for full-ADMS access undercount

1. **min_length=0 generating too many short gradient barriers** — fresh#118 set min_length default to 0. This might create thousands of spurious barrier points from DEM noise at single vertices, each blocking everything upstream. bcfishpass's island detection in `gradient_barriers_load.sql` may implicitly filter short islands differently. Investigate: how many of the 5,571 gradient_1500 barriers are from single-vertex noise vs sustained steep sections?

2. **Crossing barrier_status labels blocking access** — label_map maps BARRIER→"blocked". In the sub-basin there were 0 BARRIER crossings (all POTENTIAL/PASSABLE). At full ADMS there are 39 BARRIER crossings. If fresh treats "blocked" crossings as access barriers (via label_block), they'd block everything upstream — but bcfishpass does NOT use crossing barrier_status for natural access (only gradient + falls). Check if the 39 BARRIER crossings are being treated as natural access barriers by fresh when they shouldn't be.

3. **Both effects compounding** — too many gradient barriers + BARRIER crossings both blocking access → cascading undercount.

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

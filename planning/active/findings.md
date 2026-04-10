# Findings: ADMS Comparison

## bcfishpass code review findings

- `break_streams('crossings', wsg)` breaks at ALL crossings — confirmed from SQL function source
- barrier_status only used in `load_streams_access.sql` for access codes (0/1/2)
- `load_dnstr()` indexes downstream features as ID arrays per segment
- Access codes: 0 = barrier downstream, 1 = no barrier but unconfirmed, 2 = confirmed by observations
- ADMS uses model = "cw" (channel width), species BT and CO

## Parameter differences
- `parameters_habitat_thresholds.csv` identical between fresh and bcfishpass
- `parameters_fresh.csv` adds `spawn_gradient_min` (0.0025) — bcfishpass doesn't use this
- For comparison: set spawn_gradient_min = 0

## Function consolidation (completed)
- 12 → 8 functions
- Key renames: lnk_break_source → lnk_source, lnk_habitat_upstream → lnk_aggregate
- lnk_match now handles xref_csv directly (no separate PSCIS/MOTI wrappers)

## Comparison results (sub-basin: wscode 432966, 385 segments)

### Current numbers (fresh vs bcfishpass)

Raw (no edge_type filter):

| Metric | fresh | bcfishpass | diff |
|--------|-------|-----------|------|
| BT spawning | 14.63 km | 12.86 km | +13.8% |
| BT rearing | 29.37 km | 30.18 km | -2.7% ✓ |
| CO spawning | 14.07 km | 10.21 km | +37.8% |
| CO rearing | 14.72 km | 10.94 km | +34.6% |

With edge_type filter on spawning (bcfishpass excludes wetlands/lakes from spawning):

| Metric | fresh | bcfishpass | diff | Notes |
|--------|-------|-----------|------|-------|
| **BT spawning** | **13.29 km** | **12.86 km** | **+3.3%** ✓ | Edge type was the gap |
| **BT rearing** | **29.37 km** | **30.18 km** | **-2.7%** ✓ | No edge filter on rearing |
| CO spawning | 12.72 km | 10.21 km | +24.6% | Rearing-connectivity |
| CO rearing | 14.72 km | 10.94 km | +34.6% | Rearing-connectivity |

### Architecture findings

1. **bcfishpass gates habitat on natural access** — `barriers_bt_dnstr = array[]::text[]` in the habitat_linear SQL means segments must have NO natural barriers downstream. Fresh does the same via gradient barriers — this is correct.

2. **Crossings don't block natural access** — `barriers_bt_dnstr` tracks gradient barriers + falls, NOT crossing barrier status. POTENTIAL crossings are anthropogenic features tracked separately. Crossings should break geometry only (`label = "gradient_0"`).

3. **Falls are natural barriers** — included as `label = "blocked"` break sources. 7 in ADMS, 0 in our test sub-basin.

4. **Species use different access arrays**:
   - BT: `barriers_bt_dnstr` (gradient barriers at 25%)
   - CO: `barriers_ch_cm_co_pk_sk_dnstr` (gradient barriers at 15%)
   - Fresh handles this correctly via `access_gradient_max` per species

5. **BT rearing matches (-2.7%)** — validates core pipeline (segmentation, gradient+width classification, access gating).

### Remaining differences explained

**BT spawning +13.8%**: Segmentation boundary effects. Different break points → different segment gradient averages → segments cross the 0.0549 threshold differently. Also `spawn_gradient_min = 0.0025` in fresh excludes gradient 0 segments (minor, ~108m).

**CO spawning/rearing +35-38%**: Two factors:
- bcfishpass rearing model requires spawning connectivity (rearing must be downstream of or connected to spawning). Fresh classifies rearing on gradient+width alone without this spatial relationship.
- Different segmentation → different threshold crossings (same as BT spawning)

### Edge type filtering

bcfishpass filters spawning by edge_type — only streams/rivers (`1000, 1100, 2000, 2300`) and waterbody_type R. Wetlands (1050), lakes, ditches excluded from spawning. Rearing edge types vary by species:
- BT rearing: no edge_type filter (all segments if gradient+width met + connected to spawning)
- CO rearing: includes wetlands (1050, 1150) explicitly

fresh does NOT filter by edge_type. This is the primary cause of the +14% BT spawning difference (1.35 km on wetland edge_type 1050).

### Rearing-connectivity model (bcfishpass)

Three phases, sequential:
1. **Rearing on spawning streams** — if segment is spawning AND meets rearing thresholds → rearing
2. **Rearing downstream of spawning** — cluster adjacent rearing candidates, check if spawning exists upstream. No distance cap.
3. **Rearing upstream of spawning** — trace downstream along mainstem, find spawning within 10km, no >5% grade between. Uses ST_ClusterDBSCAN.

This is why CO differs so much — CO rearing requires spawning connectivity. BT rearing is closer because the 10km cap is less restrictive for BT (rearing primarily downstream of spawning).

Known issues (smnorris/bcfishpass):
- **#612**: ST rearing < CO rearing anomaly — ST spawning requires wider channels (4m), so narrow streams with no ST spawning get no ST rearing, even if physically suitable
- **#138**: Original issue that broadened model from adjacency to 10km trace
- **#589**: Gradient calculations based on arbitrary FWA segment lengths
- Simon: connectivity rules "can definitely be improved / are up for discussion"

### fresh issues identified (updated)

1. **Edge type filtering missing** — fresh classifies all edge types. Need species-specific edge_type filters matching bcfishpass. Fresh issue needed.

2. **`label_block` convention done** (fresh#98) — `gate` param and `label_block` for configurable access. "potential", "passable", custom labels don't block by default.

3. **MAD not used in classification** — parsed by `frs_params` but never applied. Matters for `mad` model WSGs only.

4. **Rearing not spatially linked to spawning** — bcfishpass requires connectivity via cluster analysis. Fresh classifies independently. Design decision — see biological notes below.

5. **fresh#96 done** — `frs_habitat()` accepts `aoi` + `species` for sub-WSG iteration.

### Biological notes on rearing-connectivity

The requirement that rearing must connect to spawning is defensible but has problems:
- **BT**: spawn in cold headwaters, rear in larger mainstem — rearing far downstream. Model handles this (Phase 2, no distance cap). Works OK.
- **CO**: spawn and rear in same small streams — connectivity makes sense. But misses lake rearing (NGE #7).
- **ST**: connectivity creates false negatives (#612) — narrow streams (2-3m) are excellent ST rearing but never get ST spawning modelled (requires 4m).
- **For prioritization** (link's domain): false negatives are worse than false positives. Missing a high-value crossing because rearing wasn't classified upstream is worse than overestimating habitat.

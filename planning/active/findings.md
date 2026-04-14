# Findings

## Confirmed: what matches bcfishpass

### Base segments
`localcode_ltree IS NOT NULL`, `edge_type != 6010`, `wscode_ltree <@ '999' IS FALSE`. 10,458 segments on ADMS — exact match.

### Gradient barrier detection
50,063 barriers across 8 classes, matching to 3/50,063. Island grouping, vertex extraction, 100m lookahead — identical algorithm.

### Non-minimal barrier removal
`fwa_upstream` self-join deletes barriers with another barrier downstream. ADMS: 27,443 → 677. Without this: +149% segments.

### Sequential breaking
Observations → gradient barriers → habitat endpoints → crossings. GENERATED columns recompute. 1m guard. Matches bcfishpass `break_streams()`.

### Access model
bcfishpass uses ONLY natural barriers for access (`barriers_bt_dnstr`, `barriers_ch_cm_co_pk_sk_dnstr`, etc.). Anthropogenic barriers (crossings) are recorded but do NOT block access. Our `label_block = "blocked"` is correct. Tested `label_block = c("blocked", "barrier", "potential")` — caused -52% across all species.

### Channel width
Synced from tunnel (75,736 field measurements). Tightened results ~0.5%.

### Observation filtering
Species filtered by `wsg_species_presence.csv`. CT remaps (CCT, ACT, CT/RB). 179 vs 178 unique positions on ADMS.

### Habitat endpoints
Both `downstream_route_measure` and `upstream_route_measure` as break positions. 143 vs 145 on ADMS.

### SK rearing
Exact match on all WSGs (0.0%).

## Confirmed: what doesn't match

### ST spawning/rearing -22%/-25% (BABL) — ROOT CAUSE FOUND
Segment-level comparison: 223 bcfishpass-only ST spawning segments. 382 of 383 overlapping segments are **inaccessible in our system**. The falls at BLK 360886207 DRM 4127 blocks them. Overridden for BT/CH/CM/CO/PK/SK but NOT for ST.

Cause: `observation_species` in `parameters_fresh_bcfishpass.csv` was `"ST"` (only ST obs counted). bcfishpass `model_access_st.sql` counts ALL salmon + steelhead: `'CH','CM','CO','PK','SK','ST'` with threshold >= 5 post-1990. Zero ST obs upstream but salmon obs exist → barrier stays for ST in our system but gets removed in bcfishpass.

Fix: changed `observation_species` for ST from `"ST"` to `"CH;CM;CO;PK;SK;ST"`.

**Result: ST spawning -22.0% → +3.8%, ST rearing -25.4% → +2.4%.** One CSV cell.

### WCT observation override missing
bcfishpass `model_access_wct.sql` uses WCT-only observations with threshold = 1 (any WCT obs removes barrier). Our CSV had `observation_threshold = NA` (no override). Fixed to threshold = 1, species = WCT.

**Result: WCT spawning -3.4% → +4.0%, WCT rearing -4.2% → +3.0%.** 685 barriers overridden on ELKR.

### SK spawning -22.6% (BULK, after ST/WCT fix)
Segment-level comparison: 13 bcfishpass-only segments (7.26 km), 9 ours-only (2.16 km). All bcfishpass-only segments are accessible in our system — it's not access. They're on 3 BLKs near rearing lakes (edge_type 1050/1200 wetland/lake + 1000 stream), low gradient, good channel width. The downstream trace from rearing lakes in bcfishpass reaches these segments but our `frs_connected_spawning` doesn't. 

This is a boundary effect at the 3km distance cap. The bcfishpass-only segments on BLK 360846413 are 3.0-3.4 km from the rearing lake outlet (our outlet DRM 9718, segments start at DRM 6362). Different segment boundaries resolve the cumulative distance slightly differently — some segments fall just inside 3km in bcfishpass but just outside in our system.

**Root cause found and proven:** `.frs_connected_spawning` line 1385 picks lake outlets with `ORDER BY s2.downstream_route_measure ASC`. bcfishpass uses `ORDER BY s.waterbody_key, s.wscode_ltree, s.localcode_ltree, s.downstream_route_measure`. DRM ordering picks an arbitrary segment on any BLK with the smallest measure. wscode ordering picks the actual network-topological outlet.

Example: waterbody_key 329064462 spans 10 BLKs. Fresh picks BLK 360504780 DRM 0 (wrong tributary). bcfishpass picks BLK 360846413 DRM 9718 (actual outlet). Downstream trace from the wrong outlet misses 7+ km of spawning habitat.

**Proven:** Correcting the outlet ordering and partitioning by waterbody_key: SK spawning BULK 18.88 km → 24.41 km (bcfishpass 24.38 km). From -22.6% to +0.1%.

Fix: fresh#147 line 1385 change `ORDER BY s2.waterbody_key, s2.downstream_route_measure ASC` to `ORDER BY s2.waterbody_key, s2.wscode_ltree, s2.localcode_ltree, s2.downstream_route_measure`. Also change Phase 1 partition from `lo.blue_line_key` to `lo.waterbody_key`.

The ST/WCT observation_species fix improved SK from -39.9% to -22.6% by opening access at barriers that previously blocked salmon-accessible habitat.

### BT rearing +5.4% to +7.1% (BULK, ELKR)
Slightly over. Stream order exception added more segments (+7.1% on ELKR). May be from segment boundary differences or classification predicates we're applying that bcfishpass doesn't.

### WCT -3.4% spawning, -4.2% rearing (ELKR)
Stream order exception closed 1 point on rearing. Same unknown cause as ST but less severe.

## Tested and eliminated as ST/WCT cause

| Hypothesis | Test | Result |
|-----------|------|--------|
| Per-model non-minimal removal | Built bt/salmon/st/wct barrier tables, removed non-minimal within each | No change on ST/WCT |
| Crossings blocking access | `label_block = c("blocked", "barrier", "potential")` | -52% all species, wrong |
| Stream order rearing bypass | Post-classification UPDATE for stream_order=1, parent>=5 | +3 points ST rearing, not main cause |
| Gradient/channel_width thresholds | Compared params_obj vs tunnel parameters_habitat_thresholds | Exact match |
| Access gating mechanism | Compared access counts | Close (12,728 vs 11,673 ST accessible on BABL) |

## Bugs found

### bcfishpass access_st checks SK instead of ST
`load_streams_access.sql` line 120: `'SK' = any(obsrvtn_species_codes_upstr)` should be `'ST'`. Copy-paste from SK block. Filed NewGraphEnvironment/bcfishpass#9, referenced in link#33. Does not affect access blocking, only the access code label (1 vs 2).

## Methodology lessons

### Segment-level comparison finds root causes in minutes
Guessing from SQL differences wasted hours — tested per-model non-minimal, label_block, stream order exception, three-phase rearing. None were the cause. Dumping bcfishpass segments to a local table, diffing by spatial overlap, and checking accessibility on mismatches found the real cause (wrong observation_species) in one query chain. Do this first next time.

### One CSV cell can account for -22%
The ST gap was entirely from `observation_species = "ST"` instead of `"CH;CM;CO;PK;SK;ST"` in `parameters_fresh_bcfishpass.csv`. Always verify per-species params against the actual bcfishpass SQL before guessing at architectural causes.

### Read the per-model SQL, don't assume symmetry
Each bcfishpass model_access_*.sql has different observation species lists and thresholds. BT counts all salmon+steelhead (threshold 1). Salmon counts salmon only (threshold 5, post-1990). ST counts all salmon+steelhead (threshold 5, post-1990). WCT counts WCT only (threshold 1, any date). Don't assume they're all the same.

### Network topology ordering matters for spatial queries
`ORDER BY downstream_route_measure` picks an arbitrary segment with the smallest measure on any BLK. `ORDER BY wscode_ltree, localcode_ltree, downstream_route_measure` picks the actual network-topological position. For lake outlets spanning multiple BLKs, these give completely different results. DRM is a measure within a BLK — it says nothing about where that BLK sits in the network. wscode is the network position. Any DISTINCT ON query that needs "the most downstream point" must use wscode ordering, not DRM.

### Prove before filing
We guessed three times at the SK cause (per-model non-minimal, label_block, boundary effect) and filed/commented on fresh#147 prematurely. Each guess wasted time and muddied the issue. The segment comparison found the real cause (wrong outlet ordering) in minutes. The proof query (24.41 vs 24.38 km) took one SQL statement. Always prove with data before attributing a cause.

## Unverified hypotheses

### Rearing waterbody filter OR vs AND
bcfishpass rearing: `wb.waterbody_type = 'R' OR (wb.waterbody_type IS NULL OR edge_type IN (...))` — permissive, includes NULL waterbody.
bcfishpass spawning: `wb.waterbody_type = 'R' OR (wb.waterbody_type IS NULL AND edge_type IN (...))` — restrictive.
Not verified whether our rules produce the same SQL. Could add rearing segments on non-standard edge types.

### Three-phase rearing
bcfishpass rearing runs 3 phases for BT/CH/CO/ST/WCT:
1. On spawning streams (spawning AND rearing thresholds, no connectivity)
2. Downstream of spawning (cluster + fwa_upstream trace)
3. Upstream of spawning (cluster + fwa_downstream trace, 10km, 5% gradient bridge)

Our frs_cluster does a single pass removing disconnected rearing. Not verified whether the three-phase approach classifies more rearing.

### Stream order exception across species
Applied to BT, CH, CO, ST, WCT in bcfishpass. Tested as post-classification UPDATE. Adds segments but not enough to explain gaps. CM, PK, SK do not have the exception. CM/PK have spawning only (no rearing model).

## Results summary (latest: ST/WCT obs fix + stream order exception)

BULK and ELKR updated with ST/WCT observation_species fix. SK spawning proven +0.1% with outlet ordering fix (not yet in fresh).

| Species | Metric | ADMS | BULK | BABL | ELKR |
|---------|--------|------|------|------|------|
| BT | spawn | +1.8% | +3.1% | +4.1% | +3.4% |
| BT | rear | -0.3% | +1.3% | +0.4% | +1.7% |
| CH | spawn | +0.5% | +1.9% | +3.8% | — |
| CH | rear | +2.1% | +6.0% | +6.1% | — |
| CO | spawn | +1.6% | +3.1% | +4.8% | — |
| CO | rear | -1.0% | +0.9% | +0.0% | — |
| PK | spawn | — | +2.3% | — | — |
| SK | spawn | +2.6% | -22.6% (proven +0.1% with fix) | -13.6% | — |
| SK | rear | +0.0% | +0.0% | +0.0% | — |
| ST | spawn | — | +1.9% | +3.8% | — |
| ST | rear | — | +3.6% | +2.4% | — |
| WCT | spawn | — | — | — | +4.0% |
| WCT | rear | — | — | — | +3.0% |

### BT rearing +7% — ROOT CAUSE FOUND
Segment comparison: 646 ours-only segments (224 km) vs 36 bcfishpass-only (8.6 km). We over-classify. BT `cluster_rearing = FALSE` in our params — no rearing connectivity filter. bcfishpass applies three-phase rearing connectivity to BT (on-spawning, downstream, upstream). 224 km of disconnected rearing included in our results.

Fix: set BT `cluster_rearing = TRUE`. **Result: BT rearing BULK +7.0% → +1.3%, ELKR +7.1% → +1.7%, BABL +2.8% → +0.4%, ADMS +2.6% → -0.3%.** All within 5%.

### CH rearing +6.0% BULK, +6.1% BABL — CONFIRMED: frs_cluster more permissive
Segment comparison: 442 ours-only (103 km) vs 26 bcfishpass-only (8.5 km). Breakdown:
- 14.6 km from stream order exception (we add rearing, bcfishpass doesn't at this stage)
- 46.7 km on BLKs with CH spawning — should be "on-spawning rearing" in bcfishpass but isn't classified
- 41.6 km on BLKs WITHOUT CH spawning — our frs_cluster considers connected, bcfishpass three-phase doesn't reach

Our frs_cluster connects rearing to spawning via network proximity (upstream/downstream within bridge_gradient + bridge_distance). bcfishpass three-phase is more restrictive: on-spawning only (Phase 1), then downstream clusters connected to spawning (Phase 2), then upstream clusters within 10km + 5% gradient bridge (Phase 3).

Not a CSV bug — architectural difference. Closing requires replicating three-phase rearing in fresh, or accepting +6% as the cost of simpler connectivity. The 14.6 km stream order exception should be removed from the comparison since bcfishpass also applies it (just at a different pipeline stage).

### CO spawning: +4.8% BABL — borderline

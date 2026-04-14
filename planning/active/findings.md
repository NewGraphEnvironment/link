# Findings

## bcfishpass access model does NOT use anthropogenic barriers

`load_streams_access.sql` computes `access_bt`, `access_ch`, etc. from `barriers_bt_dnstr`, `barriers_ch_cm_co_pk_sk_dnstr` — natural barriers only. `barriers_anthropogenic_dnstr` is recorded but never checked in the access columns. Crossings do NOT block habitat access.

Our `label_block = "blocked"` is correct. Testing `label_block = c("blocked", "barrier", "potential")` caused -52% across all species — confirmed crossings should not block.

## bcfishpass access_st has a bug

Line 120 of `load_streams_access.sql`:
```sql
when b.barriers_st_dnstr is null and 'SK' = any(obsrvtn_species_codes_upstr) then 2
```
Checks for SK observations for ST access. Should be 'ST'. Copy-paste from the SK block.

## Stream order exception for rearing (root cause of ST/WCT gap)

bcfishpass `load_habitat_linear_st.sql` lines 99-101:
```sql
(cw.channel_width >= t.rear_channel_width_min OR
 (s.stream_order_parent >= 5 AND s.stream_order = 1))
```

First-order streams with parent order >= 5 bypass the rearing channel width minimum. This captures small tributaries of large rivers — below the cw threshold by measurement but biologically used for rearing.

Applied in: `load_habitat_linear_bt.sql`, `load_habitat_linear_ch.sql`, `load_habitat_linear_co.sql`, `load_habitat_linear_st.sql`, `load_habitat_linear_wct.sql`.

NOT in our rules YAML — the rules system has no way to express stream order predicates.

This likely accounts for the ST -22% rearing gap (small tributaries excluded) and contributes to BT +6.5% (we classify MORE because we don't have this exception working correctly — wait, we'd classify LESS without the exception... need to check direction).

## Rearing waterbody filter difference

bcfishpass rearing (ST lines 88-91):
```sql
wb.waterbody_type = 'R' OR (wb.waterbody_type IS NULL OR s.edge_type IN (1000,1100,2000,2300))
```

NULL waterbody_type included regardless of edge_type (the OR makes it permissive).

bcfishpass spawning (ST lines 51-53):
```sql
wb.waterbody_type = 'R' OR (wb.waterbody_type IS NULL AND s.edge_type IN (1000,1100,2000,2300))
```

AND vs OR — spawning is restrictive, rearing is permissive for NULL waterbody.

Need to verify our rules YAML produces the same filter logic.

## Three-phase rearing in bcfishpass

ST rearing runs in 3 phases:
1. **On spawning streams** (lines 68-112): segments that are spawning AND meet rearing thresholds
2. **Downstream of spawning** (lines 119-205): cluster rearing segments, find clusters downstream of spawning via fwa_upstream, keep connected clusters
3. **Upstream of spawning** (lines 213-360): cluster rearing segments, trace downstream to find nearest spawning within 10km with 5% gradient bridge, keep clusters connected to spawning

Our `frs_cluster` does a single pass. The three-phase approach may classify more rearing by finding clusters in both directions from spawning.

## Per-model non-minimal: correct but not the ST cause

Implemented per-model barrier tables (bt: 25/30, salmon: 15-30, st: 20-30, wct: 20-30). No effect on ST or WCT numbers. The gap is classification, not segmentation or access.

## Per-model barrier counts (BABL)

| Model | Before | After minimal |
|-------|--------|--------------|
| bt | 5,090 | 678 |
| ch_cm_co_pk_sk | 17,314 | 1,075 |
| st | 9,982 | 879 |
| wct | 9,982 | 879 |
| Union | — | 2,267 |

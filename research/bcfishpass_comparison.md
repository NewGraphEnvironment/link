# bcfishpass v0.5.0 Comparison Research

## Summary

fresh 0.13.2 + link 0.1.0 vs bcfishpass v0.5.0 on three watershed groups.

### Results (2026-04-12)

| WSG | Species | Spawning diff | Rearing diff |
|-----|---------|--------------|-------------|
| ADMS | BT | +3.8% | +3.2% |
| ADMS | CH | +1.4% | +2.9% |
| ADMS | CO | +2.8% | -0.4% |
| ADMS | SK | +34.7% (fresh#147) | +0.2% |
| BULK | BT | +2.7% | +6.0% |
| BULK | CH | +1.3% | +6.6% |
| BULK | CO | +2.6% | +0.2% |
| BULK | ST | +1.1% | +3.9% |
| BABL | BT | +8.4% | +4.9% |
| BABL | CH | +4.5% | +7.2% |
| BABL | CO | +8.7% | +2.4% |
| BABL | SK | +94.0% (fresh#147) | 0.0% |

Consistent positive bias on spawning (+1 to +9%) and rearing (+2 to +7%). CO rearing closest (ADMS -0.4%, BULK +0.2%, BABL +2.4%). SK rearing exact (BABL 0.0%). SK spawning pending fresh#147.

## Confirmed identical

### FWA data
- ADMS: 10,458 segments, 3,487 BLKs — identical on both systems
- BULK: 30,046 segments, 10,142 BLKs — identical
- BABL: 24,179 segments, 6,524 BLKs — identical

### PostgreSQL / PostGIS versions
- Local Docker: PG 17.5, PostGIS 3.5.2, GEOS 3.9.0, aarch64 (ARM)
- Tunnel: PG 16.2, PostGIS 3.4.2, GEOS 3.10.2, x86_64 (Intel)
- Tested: gradient computation on specific segments produces identical results despite version/architecture differences

### Gradient barrier detection
Algorithm comparison (line by line):

| Step | bcfishpass | fresh | Match |
|------|-----------|-------|-------|
| Vertex extraction | generate_series(1, NPoints-1) | Same | ✓ |
| Measure | ST_LineLocatePoint * length + drm | Same | ✓ |
| Elevation | ST_Z(ST_PointN(geom, n)) | Same | ✓ |
| Upstream point | ST_LocateAlong(geom, drm+100) | Same | ✓ |
| Gradient | (z_up - z_vertex) / 100, round 4 | Same | ✓ |
| BLK filter | blue_line_key = watershed_key | blk_filter=TRUE (same) | ✓ |
| Edge types (vertices) | 1000,1050,1100,1150,1250,1350,1410,2000,2300 | Same | ✓ |
| Edge types (upstream) | edge_type != 6010 | Same | ✓ |
| CASE classes | 8 (5,7,10,12,15,20,25,30) | 4 or 8 (configurable) | ✓ |
| Island grouping | lag(grade_class) <> grade_class | Same pattern | ✓ |
| Island entry | min(downstream_route_measure) | Same | ✓ |

Barrier counts per class (ADMS, fresh with 8 classes):

| Class | fresh | bcfishpass | diff |
|-------|-------|-----------|------|
| 5 | 4,983 | 4,983 | 0 |
| 7 | 5,732 | 5,732 | 0 |
| 10 | 5,674 | 5,674 | 0 |
| 12 | 6,231 | 6,230 | +1 |
| 15 | 7,138 | 7,136 | +2 |
| 20 | 7,452 | 7,452 | 0 |
| 25 | 7,402 | 7,402 | 0 |
| 30 | 5,451 | 5,451 | 0 |

6 of 8 classes exact. Class 12 off by 1, class 15 off by 2. Total: 3 out of 50,063. Cause unknown — possibly rounding edge case at exact threshold values.

### Gradient computation after segmentation
- bcfishpass: GENERATED ALWAYS column from segment geometry
- fresh: `frs_col_generate()` drops and re-adds GENERATED columns after splitting
- Formula identical: `round(((ST_Z(PointN(geom,-1)) - ST_Z(PointN(geom,1))) / ST_Length(geom))::numeric, 4)`
- Tested: `ST_LocateBetween` on same segment produces identical child gradient on both systems

### Geometry splitting
- Both: `(ST_Dump(ST_LocateBetween(geom, drm, urm))).geom`
- Identical PostGIS function, identical results

## Confirmed different

### Segment count
- ADMS: fresh 40,227 vs bcfishpass 15,764
- fresh segments at ALL gradient barriers (27,443 unique positions)
- bcfishpass segments sequentially per barrier table, skipping breaks within 1m of existing boundaries
- More segments in fresh → different segment boundaries → different per-segment gradients after recomputation

### Break sequence
- bcfishpass: sequential `break_streams()` calls — observations → barriers_bt → barriers_ch_cm_co_pk_sk → barriers_st → user_habitat_endpoints → crossings
- fresh: all break sources merged, segmented in one pass
- Sequential breaking means later tables skip positions already broken by earlier tables (>1m dedup)
- Single-pass breaking creates all breaks at once

### Barrier identity in breaks table
- bcfishpass: separate barrier tables persist independently, never merged
- fresh: all merged into streams_breaks, labels deduplicated at shared positions (fresh#145 partially addresses)
- Affects barrier_overrides alignment

## Remaining +3-8% spawning bias — source unknown

### What it's NOT
- Not FWA data (identical)
- Not barrier detection (counts match to within 3/50,000)
- Not gradient formula (identical GENERATED columns)
- Not floating point / architecture (tested, identical results)
- Not 4-vs-8 gradient classes (tested, same barrier count)

### What it likely IS
- Different segment boundaries from single-pass vs sequential breaking
- More segments in fresh → more segments near thresholds → net positive bias (more segments qualify than don't)
- The bias is always positive (fresh classifies MORE habitat) which supports this: finer segmentation creates more small segments that individually pass thresholds

### How to verify
- Run bcfishpass on the same Docker DB and compare segment-for-segment
- Or: implement sequential breaking in fresh to match bcfishpass exactly

## SK spawning (+34-94%)

Separate issue (fresh#147). bcfishpass uses two different algorithms:
1. Downstream: `FWA_Downstream()` + cumulative distance + 3km cap + 5% gradient barrier
2. Upstream: `FWA_Upstream()` + `ST_ClusterDBSCAN` + `st_dwithin(cluster, lake_poly, 2)`

fresh uses generic `frs_cluster` with `connected_distance_max` which cannot replicate either algorithm precisely.

## Versions

- fresh: 0.13.2
- bcfishpass: v0.5.0
- link: 0.1.0
- fwapg: Docker local (FWA 20240830)
- PostgreSQL: local 17.5 (aarch64), tunnel 16.2 (x86_64)
- PostGIS: local 3.5.2, tunnel 3.4.2

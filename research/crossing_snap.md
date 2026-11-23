# Where a crossing snaps

**Verified:** 2026-11-23 · **Issues:** #478 (#313, #314, #383) · **Produced by:** `data-raw/logs/snap_tie_478/` (`snap_pick.R`, `diff.R`, `sweep.R`, `run.sh`), local docker fwapg, link `2b12adf0`, fresh 0.55.1

## The rule

PSCIS crossings and CABD dams are placed on the FWA network by a nearest-segment snap.

- **Candidates.** `lnk_points_snap()` is `fresh::frs_point_snap()` with the input's columns kept. Placeholder streams (`wscode_ltree <@ '999'`) and unmapped tributaries (NULL local code) are never candidates, nor subsurface flow (edge 1425). The PSCIS build keeps five candidates within 150 m and picks one by bcfishpass's scores (`02_pscis_streams_150m.sql`, `04_pscis.sql`); the dam snap keeps the nearest within 65 m.
- **The measure** is a whole metre, bcfishpass's formula: the position rounded down, never below the segment's start rounded up.
- **Ties.** A point nearest to a vertex two segments share is at exactly the same distance from both. Measures resolve `[downstream, upstream)`, so the tie goes to the segment that starts at the vertex: first a candidate whose snapped point is not its segment's upstream end, then the higher raw segment start, then the lower `linear_feature_id`. Applied in the PSCIS pick (`.lnk_pscis_pick_order`) and the dam snap (`.lnk_dams_matched_sql()`).

On one stream this is fwapg's rule for `fwa_indexpoint()` (NewGraphEnvironment/fwapg#41) and fresh's snap order. It departs from bcfishpass, which ends the PSCIS pick and its dam snap on `linear_feature_id` alone, so a tie there falls to the lower id whatever its position.

## Why not fwapg's rule across two streams

fwapg orders a tie by the higher `downstream_route_measure`. Two segments of one stream meeting at a vertex: the upper one starts where the lower ends, so the higher measure is the segment starting there. Across two streams the comparison means nothing.

On the CABD dams it moved one barrier dam (`94dec15b…`, Delta, 49.105 N 123.072 W). CABD names its waterbody Crescent Slough. It is 15.4 m from a vertex where the slough's first segment (blue line 356326465, a 17 m connector, code `100.005065`) starts and a Fraser side channel (blue line 355991966, edge 1350, code `100`) ends. Under the lower id it sat at the slough's mouth, with 16 segments (7.7 km) upstream. Under fwapg's rule it went to the side channel's top end, and because that line carries the Fraser's own code, 17,657 segments (7,892 km) of the lower Fraser counted as upstream of it (`claims.sql`, `claims.txt`; the measure-aware `fwa_upstream`, equivalents in, 1 m). The start test keeps it at the slough's mouth, and agrees with fwapg's rule on all 49 same-stream dam ties.

## What moved, province-wide

All 19,905 PSCIS assessments and 2,554 CABD dams, snapped and picked at main (`5be4fb32`) and at the branch, without the xref overrides (`summary.csv`, `picks_moved.csv`, `dams_moved.csv`, `before/` and `after/counts.csv`):

| | before | after |
|---|---|---|
| PSCIS candidates within 150 m (5 a point) | 37,992 | 37,972 |
| candidates on a placeholder stream | 20 | 0 |
| PSCIS picks | 17,377 | 17,369 |
| picks on a placeholder stream | 11 | 0 |
| points with an exact-distance tie on one stream | 305 | 305 |
| picks on a stream with a tied candidate | 33 | 33 |
| dams snapped | 2,554 | 2,554 |

- **14 PSCIS picks change.** The 11 that sat on a placeholder line: 8 now have no pick (each had only that one candidate within 150 m, and now has none; `claims.txt`), 3 move to a real stream (KHOR 807, GRAI 1467, LILL 63483). Three move 1 m up to the segment starting at their vertex (NASR 20, SHUL 3703, NIMP 101956). 17,363 are unchanged, with distances equal to 1.6e-10 m (fresh measures distance to the segment, link measured it to the snapped point).
- **17 dams change segment**, each on the same stream to the segment starting at its vertex, the measure moving under 1 mm. 50 dams tie (`claims.txt`): 49 on one stream, one across two (the Crescent Slough dam, which stays).
- **Tie counts do not change** because they count candidates, not picks: what changes is which tied segment wins.

Groups holding a moved pick: BABL, GRAI, JERV, KETL, KHOR, LILL, NASR, NIMP, REVL, SHUL. Groups holding a moved dam: BULK, BULL, FRAN, GUIC, HORS, KNIG, LARL, LNIC, NICL, OKAN, SQAM, USHU, VICT.

## The re-model, main against the branch

Seven groups holding a moved pick or dam (NASR, SHUL, JERV, KETL, LILL, GUIC, USHU), built under `bcfishpass` at main (`5be4fb32`) and at the branch (`2b12adf0`) into scratch schemas, each persisted table compared row for row by segment position, not `id_segment`, which any added segment renumbers (`run.sh`, `compare_builds.R`, `compare_bcfishpass.csv`):

- **Barriers:** one row moves in each of GUIC and USHU (a dam on the segment starting at its vertex, under 1 mm of measure), in SHUL (PSCIS 3703, 63 m to 64 m, one of the three 1 m pick moves) and in KETL (a PSCIS barrier gone with its placeholder pick). JERV loses three, its three placeholder picks. LILL loses one (63502, its placeholder pick) and gains one (a freed modelled crossing, below).
- **Segments and everything on them** move only in LILL, which gains two segments with their habitat, access and mapping-code rows: one on blue line 356260867, where PSCIS 63483's new pick (its placeholder candidate gone) splits a 1,247 m segment at 666 m, and one on blue line 356248078 (below), with one segment's access and mapping code above it. NASR and the other groups' segments, access, habitat and mapping codes are identical.
- **LILL's move is the snap, one step removed.** PSCIS 63445's fifth candidate is an exact tie between two streams at 91.7 m; the old order took the lower id, fresh's takes the higher start, so the fifth candidate changed streams. On the new one it loses bcfishpass's duplicate-match step, which clears every modelled-crossing match of a PSCIS that loses one (`WHERE stream_crossing_id IN to_update`), including modelled crossing 10702238 on blue line 356248078. That crossing then stands alone at 64 m: a barrier and a break. Every other moved row lies on a blue line holding a moved pick or dam.

The `default` config's re-model did not run here. Its first build (NASR, 2.2 minutes in the provincial run) sat in fresh's near-river walk twice, 30 and then 17 minutes, each time beside another session's walk, the stall #487 tracks, and was cancelled both times (`stalled_before_default_NASR.log`, `stalled2_before_default_NASR.log` carry the samples). `default` reads the same crossings code; its scratch re-model is owed.

## FWA_LocateAlong, before and after fwapg#41's rework (#383)

link places stored measures with `FWA_LocateAlong`: `lnk_barriers_unify()` through `.lnk_sql_locate()`, whose fallback (interpolating on the nearest segment of the line) hides a miss, and `data-raw/query_habitat_thresholds_obs.R`, whose upper locate is capped at the blue line's top. `sweep.R` calls it on link's inputs on the local docker fwapg (base: neither `202610131654__watershedatmeasure_drop_exbc` nor `202610240132__indexpoint_tiebreak` applied), once on committed state and once with both migrations from fwapg's `indexpoint-tiebreak-41` branch (`a8d00b97`) applied inside a transaction `fresh::frs_migration_trial()` rolls back (`sweep.csv`; the function's source hash differs between the passes):

| input | positions | no point before | no point after | errors |
|---|---|---|---|---|
| PSCIS picks, whole-metre measures | 17,369 | 0 | 0 | 0 |
| `fresh_default.barriers`: every position at a line's top, plus 20,000 sampled | 20,006 | 22 (6 at a top) | 14 (0 at a top) | 0 |
| the threshold script's upper locate at a line's top | 581 | 581 | 21 | 0 |

- **A whole-metre measure never misses**, before or after: the snap's measure stays below a head's top.
- **The head case is real for barriers and decisive for the threshold script.** Every capped upper locate failed before (its `gradient_w100` was NULL for each such record); 21 still fail after, not classified here.
- **The barrier misses left after** sit, 10 of 14, in FWA's gap between consecutive segments under any rounding (`claims.txt`); `.lnk_sql_locate()`'s fallback places them. The other 4 are not classified.
- **Live tests** (`tests/testthat/test-lnk_fwapg_gate.R`, gate in `helper-fwapg.R`, ported from fresh): a stored measure at Willow River's top is located by `FWA_LocateAlong` itself, and the threshold script's form finds a point there. Without the migration they skip, naming it (3 skip, 3 pass); under `LNK_FWAPG_TRIAL` with both files they pass, asserting the red side on a plain connection (7 pass, 1 skip); under `LNK_FWAPG_CURRENT=true` with no trial they fail (4 fail; `gate_runs.txt`).

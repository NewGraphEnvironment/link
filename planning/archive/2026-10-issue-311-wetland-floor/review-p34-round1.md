# Review p34, round 1 (df1362f measurement + uncommitted pin/docs diff)

Every number in `data-raw/logs/wetland_floor_311/README.md`, the research section and the new
CLAUDE.md Status entry was recomputed from `measure.csv`, `summary.csv` and `obs_*.csv`. All of
these match:
- the B->C table (segments, km, 1050/1150 km, other-edge km);
- 198.8 km and 2,078 segment-species;
- the A->B checks against fresh's published numbers;
- the A sub-floor figures (26.6 / 46.7 / 19.1 / 18.0);
- 2,265 / 3 observations;
- the segment and source-line counts, the bcfishobs row count and the fresh SHAs.

The following were checked read-only in the DB and hold:
- No segment gains rearing B->C.
- Spawning and both buckets are identical B->C.
- Every remaining sub-floor rearing segment under C is edge 1000.
- Every 1050/1150 line in the four WSGs has a key in `fwa_wetlands_poly`.
- Province-wide, 40 edge-1050 lines (6.64 km) have no key.
- `(id_segment, species_code)` is unique in the snapshots.
- No `lake_rearing` line sits on a reservoir key.

The SQL semantics are right:
- **Sub-floor test.** `max(area_ha) < floor` is the complement of fresh's `waterbody_key IN (... WHERE area_ha >= floor)`.
- **Lake hectares.** fresh's bucket predicate uses `fwa_lakes_poly` only, so `lake_rear_ha` from `fwa_lakes_poly` matches the bucket.
- **The DISTINCT/window in `ha`** yields one row per (species, key).
- **obs.R.** Every one of the 2,805 observations matched exactly one segment.

The fresh v0.39.0 claims also hold: the first W rule is the bucket rule and the `requires_connected` anchor (`.frs_find_waterbody_rule`), waterbody-connected spawning takes the first L/W rear rule, the 0.37.0/0.38.0 attributions are correct, and the `wetland` category is edge 1700, which `fwa_stream_networks_sp` does not carry (0 rows).

## Findings

- **[fragile]** `data-raw/logs/wetland_floor_311/obs.R:41`: the filter `o.source IS DISTINCT FROM 'Releases Database'` excludes nothing.
  - bcfishobs `source` values for stocking records read `Releases Database: release_id 26528` and so on, so an exact match never fires. The four WSGs hold 14 such A/B records.
  - The validator compares a prefix (`R/lnk_habitat_validate.R:686`, `left(coalesce(source,''), …)`).
  - I re-ran both pairs with a prefix filter (`left(coalesce(o.source,''),17) <> 'Releases Database'`). The counts are identical: 2,805 matched, 2,265 on rearing, 0 lost A->B and 3 lost B->C. So the committed numbers stand.
  - The script header and the README ("no Releases Database") still claim a filter that is not applied, and any reuse of the script would count stocked fish. Use a prefix comparison.

- **[wrong-number, minor]** `data-raw/logs/wetland_floor_311/README.md` ("Against bcfishpass") and `research/habitat_thresholds.md` (the B -> C bullet "the departure moves by at most 1.2 points … PARS BT from +1.8 % to +0.6 %") present the bcfishpass departure movement as the floor's (B -> C).
  - The movement is actually computed A -> C (`vs_bcfp_pct_A` against `vs_bcfp_pct_C`), so it includes fresh's own A -> B movement.
  - From `summary.csv`, B -> C gives:
    - NATR BT 13.77 -> 12.66 (1.1 pt);
    - PARS BT **+1.7** -> +0.6 (1.0 pt);
    - BULK ST 13.82 -> 12.76 (1.1 pt).
  - So the floor moves the departure by at most **1.1** points, not 1.2.
  - Either label the figures A -> C, or quote the B values.

- **[fragile / stale doc]** `CLAUDE.md:70` (the #307 Status, "Facts not worth re-deriving") still says in the present tense: "**A rear range also gates `lake_rearing` / `wetland_rearing`.** On NATR under `mad`, BT lakes drop 521 → 304 km …".
  - With the pin at v0.39.0 this is false: `build_wb_pred()` is polygon membership plus the floor under both models (fresh 0.37.0).
  - This diff corrected the same claim in the 10-02 Status entry and in the RUNBOOK, but missed this one. The block exists so the fact is not re-derived, so a wrong entry there gets acted on.

- **[doc, false about behaviour]** The new `CLAUDE.md` Status (title "a wetland floor bounds all wetland rearing", and the bullet "a declared `rear_wetland_ha_min` bounds all wetland rearing") overstates the floor. So does `inst/extdata/configs/default/README.md:9`, "Wetland rearing in wetlands of at least `rear_wetland_ha_min` … on both the 1050/1150 wetland-flow lines and the mainlines through wetland polygons".
  - The first rear rule (`edge_types_explicit: [1000, 1100, 2000, 2300]`, no waterbody predicate, inheriting gradient and width) still admits mainlines inside sub-floor wetlands.
  - Under C, `rear_km_subfloor_C` is 0.13–0.618 km per floored species on BULK, NATR and PARS. All of it is edge 1000 (checked in `zz311_snap.*_c`).
  - The data-raw README says this correctly ("The stream rule admits those by design"). CLAUDE.md and the bundle README do not.
  - Suggested fix: say the floor bounds the wetland rules (the polygon mainline rule and the wetland-flow rule). Mainlines that pass the stream rule's gradient and width keep rearing in any wetland.

- **[wrong-number, label]** The "3 of 2,265 observation locations on rearing" in the README, the research section, CLAUDE.md and the commit message counts species × location pairs, not distinct locations.
  - obs.R takes DISTINCT locations per species and the counts are then summed across species.
  - A location holding records of, say, BT and RB counts once per species.
  - Call it "species-locations", as the 2,078 "segment-species" figure already does, or count distinct locations.

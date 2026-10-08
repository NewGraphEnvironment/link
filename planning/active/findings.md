# Findings — wetland_ha_min now gates rearing in fresh (fresh#237); default* outputs move (#311)

## Issue context

NewGraphEnvironment/fresh#237 makes a `waterbody_type: W` rule's `wetland_ha_min` gate the main `rear` predicate. Before, it reached only `wetland_rearing`. link's `default*` bundles declare it for BT, CH, CO, RB, ST and WCT, so `rearing` narrows on the next run.

Measured on `fresh_default` (fresh `data-raw/rear_wetland_floor_check.R`): persisted rearing loses at least 40 segments (2.1 km) on NATR BT, 60 (3.1 km) on PARS BT and 2 on BULK CO. `cluster_rearing` may drop more.

Open question for the bundle: the `edge_types_explicit: [1050, 1150], thresholds: false` rear rule has no area floor. About 307 segments (26.4 km) of NATR BT rearing stay on wetland-flow lines in wetlands under 1 ha. If `rear_wetland_ha_min` should bound all wetland rearing, that rule can carry it today as `waterbody_type: W` + `wetland_ha_min`.


## Plan-mode measurements (2026-10-07)

- fresh v0.38.0 carries #237; v0.39.0 is the latest tag (frs_channel_width, frs_break fix; neither used by link).
- Every 1050/1150 source line in NATR/PARS/ADMS/BULK sits in a `fwa_wetlands_poly` polygon. By the max polygon area per `waterbody_key` (fresh's "any polygon meets it" rule): 1,875 lines / 153 km in wetlands < 1 ha, 8,652 / 1,702 km in ≥ 1 ha.
- fresh's bucket and `requires_connected` anchor = first W rule (`.frs_find_waterbody_rule`, fresh@v0.38.0 `R/frs_habitat_predicates.R:205`).
- `requires_connected` in link's rules.yaml appears only on SK/KO spawn rules → loads under fresh ≥0.37.

## Plan review (Plan agent, 2026-10-07) — what changed because of it

- **`rear_wetland_polygon = no` + floor** would have made the floored carve-out the only W rule, so fresh's `wetland_rearing` bucket would flip FALSE → every line in a wetland ≥ floor, and with `rear_lake = yes` the first L/W rule (waterbody-connected spawning, `frs_habitat.R:1252-1262`) would change. Fixed: floor only when the polygon rule is emitted.
- **Province-wide, 40 edge-1050 lines (~6.6 km) have a NULL `waterbody_key`** (BABL 12, LDEN 12, …); the floored carve-out drops them. None point at a non-wetland key; 1150 has none. The four sampled WSGs had none.
- **The `categories` carve-out matches nothing:** `edge_types: [wetland]` resolves to 1700 only, which `fwa_stream_networks_sp` does not carry; 1050/1150 are category `stream` and enter through the stream rule with thresholds. No shipped bundle uses categories. Pre-existing; issue drafted, not filed.
- **Sub-floor acceptance must be 1050/1150-only:** the stream rule (`[1000, 1100, 2000, 2300]`, no `in_waterbody` filter in default) admits mainlines in sub-floor wetlands by design. `run.R` carries `rear_km_subfloor_wetflow`.
- **Score the floor B vs C, the upstream movement A vs B** (the validator's rear stage ORs the buckets, which #240 widened).
- fresh's bundled `inst/extdata/parameters_habitat_rules.yaml` mirrors link's and will now diverge (still unfloored).
- `load_all()` **errors** (not warns) when the installed fresh is below the Imports floor, so tests run from a scratch copy with the old floor until v0.39.0 is installed.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `run.R`: `data.frame()` "differing number of rows: 1, 5" | `count(*)` arrives as integer64, which `data.frame()` does not recycle; coerce with `as.numeric()` |

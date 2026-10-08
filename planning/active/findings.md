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

## Errors Encountered

| Error | Resolution |
|-------|------------|

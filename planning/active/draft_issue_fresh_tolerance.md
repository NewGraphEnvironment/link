Title (fresh): frs_habitat_classify(): a measure tolerance on the same-line access test and the override match

## Problem

`frs_habitat_classify()` decides `accessible` on the same line with an exact comparison, and matches an override to a break with exact equality (fresh@v0.39.0, `R/frs_habitat_classify.R:455`, `:459`, `:473`):

```sql
AND b.downstream_route_measure <= s.downstream_route_measure
...
AND ovr.downstream_route_measure = b.downstream_route_measure
```

A caller whose break positions and segment starts come from different sources disagrees with `fwa_downstream()` by millimetres. link writes its breaks at metre-rounded positions (link@ca4a58ef, `R/lnk_pipeline_classify.R:212-254`, and `natural_barriers` in prepare), while its streams start at FWA feature starts (mm precision). On `fresh_default` (241 groups) that leaves 6,999 BT segments accessible because the rounded break lands just above a segment start, and 7,636 more where the barrier sits 0–5 mm above the start, which `fwa_downstream(…, tolerance = 1)` calls downstream and `<=` does not (link#349, `data-raw/logs/access_disagree_349/classes.csv`). Every species shows the same two halves.

Dropping link's rounding alone does not fix it: the override match is exact `=`, so unrounded breaks against rounded overrides would end every observation lift.

## Proposal

- An optional `tolerance_m` (default 0, so behaviour is unchanged) applied to the same-line test (`b.drm <= s.drm + tolerance_m`) and to the override match (`abs(ovr.drm - b.drm) < tolerance_m`, or `=` at 0).
- link then drops its rounding in prepare and classify together and passes a tolerance matching its own access walk (1 m), so classify-time `accessible` agrees with `streams_access` on the same barriers.

## Not in scope

Barriers in another watershed group (fresh's breaks table is filtered to the AOI) are settled after classification in link (`lnk_habitat_gate()`, link#349); a classify-time fix cannot see a barrier persisted after the group classified.

## Acceptance

- `tolerance_m = 0` reproduces today's output byte for byte on a fixture.
- With `tolerance_m = 1`, a segment starting 3 mm above a break and one starting 3 mm below an unrounded break are both blocked, and an override 0.4 m from its break still lifts it.

# Findings — Falls not used as segmentation break source (#96)

## Issue context

`falls` is not used as a segmentation break source in the pipeline, so the FWA stream network is never broken at fall positions. When a fall sits between FWA-native segment boundaries and no other `break_order` source coincides with it, the resulting `fresh.streams` segment spans across the fall — its upper portion is incorrectly classified as accessible because the segment as a whole has no barrier between it and downstream.

`R/lnk_pipeline_break.R` lines 10–13 already document bcfp's break order as `observations → gradient_minimal → barriers_definite → falls → habitat_endpoints → crossings` (note `falls`). But the `source_tables` list (line ~107) omits `falls`, and the `break_order` default (line ~97) doesn't include it either. Implementation has drifted from the documented intent.

### Evidence — HORS BLK 356357296 (Horsefly River, BT)

Two falls 41 m apart in `working_hors.falls`:

| DRM | source coincidence in `working_hors.*` | landed in `fresh.streams`? |
|---|---|---|
| 67523.86 | falls + gradient_min (`gradient_min` is in `break_order`) | yes — segment break |
| 67548 | observations × 3 (`observations` is in `break_order`) | yes — segment break |
| 67564.98 | falls only | **no — falls not in `break_order`** |

Result: link's segment 12671 spans DRM 67548 → 68995 (1447 m), straddling the second fall. Link reports `accessible = TRUE`, `rearing = TRUE` on the entire segment. bcfp's analogous segment (which DOES break at 67565) carries `barriers_bt_dnstr = {f5270089-…}` for everything above the fall and is correctly inaccessible.

bcfp segments at every fall:

```
356357296.67524  -- below fall #1
356357296.67548  -- between falls
356357296.67565  -- above fall #2 → barriers_bt_dnstr non-empty → inaccessible
356357296.68995
```

link segments:

```
12670 (DRM 67524, len 24m)
12671 (DRM 67548, len 1447m)  ← spans the second fall, wrong
```

Symptom on the HORS BT comparison map: 12671 shows as `link_only` rearing — link credits 1447 m of mainstem Horsefly River that bcfp correctly excludes.

### Fix (per issue)

```r
# R/lnk_pipeline_break.R

source_tables <- list(
  observations      = paste0(schema, ".observations_breaks"),
  gradient_minimal  = paste0(schema, ".gradient_barriers_minimal"),
  falls             = paste0(schema, ".falls"),                 # NEW
  barriers_definite = paste0(schema, ".barriers_definite"),
  subsurfaceflow    = paste0(schema, ".barriers_subsurfaceflow"),
  habitat_endpoints = paste0(schema, ".habitat_endpoints"),
  crossings         = paste0(schema, ".crossings_breaks")
)

break_order <- cfg$pipeline$break_order %||% c(
  "observations", "gradient_minimal",
  "falls",                                                       # NEW
  "barriers_definite", "habitat_endpoints", "crossings"
)
```

Also add `"falls"` to the bcfp-bundle's `pipeline.break_order` in `inst/extdata/configs/bcfishpass/config.yaml` and the default-bundle equivalent.

`<schema>.falls` table already exists (built by `prep_load_aux`). `frs_break_apply` already accepts a table with `(blue_line_key, downstream_route_measure)`. No new prep work.

## Out of scope (per issue body)

- Per-species barrier overrides for falls — already handled in `prep_natural` for obs/habitat lift.
- Reduction of falls via `barriers_minimal` — falls should NOT be reduced; each fall is its own barrier.
- Restoring 12671's link-only credit via `frs_order_child` — different mechanism, parked on the wire-up branch (now archived at `planning/archive/2026-05-fresh158-frs-order-child-wire/`).

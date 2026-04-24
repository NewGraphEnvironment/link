# default vs bcfishpass — per-WSG comparison

link ships two config bundles today: `"bcfishpass"` (validation: reproduces bcfishpass exactly for regression) and `"default"` (NewGraph method, intentionally diverges). This doc captures the per-WSG per-species comparison and the biological rationale for each divergence.

Companion to `research/bcfishpass_comparison.md` (which covers link vs bcfishpass on the bcfishpass bundle, i.e. reproduction fidelity). This doc covers the default-vs-bcfishpass method-level comparison.

## What the rollup measures

From `data-raw/_targets.R` → `compare_bcfishpass_wsg()`, both bundles produce per-WSG × per-species × per-habitat-type values in one of two units:

| habitat_type | unit | link side | bcfishpass side |
|---|---|---|---|
| `spawning` | km | sum(segment length where `spawning = TRUE`) | same on `habitat_linear_<sp>` |
| `rearing` | km | sum(segment length where `rearing = TRUE`) | same |
| `lake_rearing` | ha | sum(DISTINCT `fwa_lakes_poly.area_ha`) where segments match `waterbody_key` AND `lake_rearing = TRUE` | sum(DISTINCT `fwa_lakes_poly.area_ha`) where segments match `waterbody_key` AND `rearing = TRUE` |
| `wetland_rearing` | ha | same on `fwa_wetlands_poly` AND `wetland_rearing = TRUE` | same on `fwa_wetlands_poly` AND `rearing = TRUE` |

**Known asymmetries** in the methodology:

1. **Linear km double-counts lake/wetland centerlines** when combined with the `_ha` columns — a 20 m lake centerline contributes 20 m to `rearing_km` AND its polygon's full area contributes to `lake_rearing_ha`. Decision for now: keep linear centerlines in `rearing_km` (#51 comment). Revisit when comparing against bcfishpass's WCRP approach (`co_spawningrearing_km = co_spawning_km + 0.5 × co_rearing_ha`).
2. **bcfishpass's segment-level classification has no wetland/lake distinction** — single `rearing` boolean in `habitat_linear_<sp>`. So bcfishpass's `lake_rearing_ha` and `wetland_rearing_ha` are derived by filtering `rearing = TRUE` segments whose `waterbody_key` happens to match the polygon table. That captures bcfishpass's *de-facto* lake/wetland rearing area (what the model assigns), not what bcfishpass explicitly intends.
3. **Option B (separate columns, no multiplier)** — bcfishpass folds lake ha into km via a 0.5× multiplier for CO/SK in `crossings_upstream_habitat_wcrp`. We don't. Separate columns preserve information for queries like "lots of wetland upstream, short linear extent."

## Departures from bcfishpass (intentional)

The default bundle encodes these deliberate method differences:

### 1. Lake rearing extended beyond SK/KO

| Species | bcfishpass `rear_lake_ha_min` | default `rear_lake` |
|---|---|---|
| BT | NA (no lake rearing) | yes |
| CH | 100 | yes (unchanged) |
| CM | NA | no (unchanged) |
| CO | 40 | yes (unchanged) |
| KO | 200 | yes (unchanged) |
| PK | NA | no (unchanged) |
| SK | 200 | yes |
| ST | 60 | yes (unchanged) |
| WCT | 40 | yes (unchanged) |

Rationale: literature supports lake rearing for more species than bcfishpass's SK/KO-only treatment of area-based rearing. [TODO: citations for BT lake rearing — Babine/Quesnel/Kootenay/Stuart populations; SK lake rearing in smaller systems without the 200 ha threshold; ST lake-rearing documentation.]

### 2. Wetland rearing added

`rear_wetland = yes` in default dimensions CSV for BT, CO, CT, DV, GR, RB, SK, ST, WCT. Bcfishpass doesn't flag wetland-rearing at the segment-classification level. Wetland reaches (edge_type 1050/1150) support juvenile CO specifically (side channels, beaver complexes) and sub-adult rearing for resident species. [TODO: citations.]

### 3. Intermittent streams included

bcfishpass excludes intermittent streams from rearing sets. Default includes them — seasonal use by CO juveniles documented in FWCP and interior BC literature. [TODO: edge-type mechanism in the rules YAML + citations.]

### 4. Spawn gradient minimum 0 → 0.0025

bcfishpass: no minimum spawn gradient (zero). Default: `spawn_gradient_min = 0.0025` excludes depositional reaches too flat for gravel retention. Arbitrary-ish cutoff; to be refined. [TODO: substrate literature.]

### 5. River-polygon channel-width threshold skipped

`river_skip_cw_min = yes` in default dimensions CSV. Channel-width thresholds are applied to stream-type segments (single-thread channel) but meaningless on river polygons (multi-thread, braided, anabranching) where the channel_width attribute is a poor proxy.

## Results

Numbers populate from `tar_read(rollup)` after the first clean `tar_destroy + tar_make()`. Table format: one block per WSG, rows = species × habitat_type, columns = bcfishpass bundle value / default bundle value / diff (default − bcfishpass) with unit suffix.

### ADMS

| Species | Habitat | bcfishpass | default | Δ | Unit |
|---|---|---|---|---|---|
| TBD | | | | | |

### BULK

| Species | Habitat | bcfishpass | default | Δ | Unit |
|---|---|---|---|---|---|
| TBD | | | | | |

### BABL

| Species | Habitat | bcfishpass | default | Δ | Unit |
|---|---|---|---|---|---|
| TBD | | | | | |

### ELKR

| Species | Habitat | bcfishpass | default | Δ | Unit |
|---|---|---|---|---|---|
| TBD | | | | | |

### DEAD

| Species | Habitat | bcfishpass | default | Δ | Unit |
|---|---|---|---|---|---|
| TBD | | | | | |

## Observations / surprises to investigate

- [TODO: fill in after first full run.]

## Versions

- fresh: 0.16.0
- link: 0.7.0 → target 0.8.0 at PR merge
- bcfishpass: ea3c5d8
- fwapg: Docker (FWA 20240830)

## Related

- `research/bcfishpass_comparison.md` — reproduction fidelity of the bcfishpass bundle.
- [link#51](https://github.com/NewGraphEnvironment/link/issues/51) — this work.
- [link#52](https://github.com/NewGraphEnvironment/link/issues/52) — channel-class as break position research.
- [link#21](https://github.com/NewGraphEnvironment/link/issues/21) — temperature / thermal energy (out of scope for default today).

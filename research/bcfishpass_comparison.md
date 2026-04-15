# bcfishpass Comparison

fresh 0.13.8 + link vs bcfishpass (tunnel v0.7.12+, CSVs synced @ ea3c5d8).

## Results (2026-04-15)

All species within 5% on all 4 WSGs. Three-phase cluster, no stream order bypass.

### ADMS

| Species | Spawning | Rearing |
|---------|----------|---------|
| BT | +1.8% | -0.7% |
| CH | +0.5% | +2.5% |
| CO | +1.6% | +0.1% |
| SK | +3.7% | +0.0% |

### BULK

| Species | Spawning | Rearing |
|---------|----------|---------|
| BT | +3.1% | -2.2% |
| CH | +1.9% | +2.6% |
| CO | +3.1% | +0.4% |
| PK | +2.3% | N/A |
| SK | -0.7% | +0.0% |
| ST | +1.9% | -0.1% |

### BABL

| Species | Spawning | Rearing |
|---------|----------|---------|
| BT | +4.1% | -0.6% |
| CH | +3.8% | +3.6% |
| CO | +4.8% | +1.6% |
| SK | -2.8% | +0.0% |
| ST | +3.8% | +1.9% |

### ELKR

| Species | Spawning | Rearing |
|---------|----------|---------|
| BT | +3.4% | +0.2% |
| WCT | +4.0% | +2.5% |

## Pipeline

### 1. Detect gradient barriers on raw FWA

`frs_break_find` on `fwa_stream_networks_sp`. 4 classes (15/20/25/30%). Barrier counts match bcfishpass to within 3/50,063.

### 2. Build barrier overrides

`lnk_barrier_overrides` counts observations upstream of each barrier via `fwa_upstream()`. Per-species thresholds:
- BT: >= 1 obs (BT + all salmon/steelhead), any date
- CH/CM/CO/PK/SK: >= 5 obs (salmon only), post-1990
- ST: >= 5 obs (all salmon + steelhead), post-1990
- WCT: >= 1 obs (WCT only), any date

### 3. Remove non-minimal barriers

`fwa_upstream()` self-join deletes barriers with another barrier downstream. 27,443 → 677 on ADMS.

### 4. Load base segments

Raw FWA with filters: `localcode_ltree IS NOT NULL`, `edge_type != 6010`, `wscode_ltree <@ '999' IS FALSE`. Channel width joined from `fwa_stream_networks_channel_width`. Stream order parent from `fwa_stream_networks_order_parent`.

### 5. Sequential breaking

Observations → gradient barriers (minimal) → habitat endpoints (both DRM and URM) → crossings. Each round: `frs_break_apply` in-place, GENERATED columns recompute, 1m guard, `id_segment` reassigned.

### 6. Access gating + classification

`frs_habitat_classify` with full gradient barriers for access gating (not minimal). Barrier overrides selectively open access per species. Rules YAML defines edge types, waterbody types, thresholds.

### 7. Three-phase rearing connectivity

`frs_cluster` with three-phase approach (fresh 0.13.8):
- Phase 1: on-spawning segments always valid (both spawning AND rearing)
- Phase 2: upstream boolean (rearing below spawning)
- Phase 3: `FWA_Downstream` on broken streams table, mainstem only, gradient bridge + distance cap (rearing above spawning)

### 8. Connected waterbody spawning (SK)

`frs_connected_waterbody` with `spawn_connected` rules:
- Subtractive: remove spawning not connected to rearing lake
- Additive: add spawning for segments in downstream trace meeting permissive thresholds (gradient_max 0.05, no cw minimum, all edge types)
- Outlet ordering: `wscode_ltree, localcode_ltree, downstream_route_measure` (network topology, not just DRM)

## Key fixes during comparison

| Fix | Impact | Type |
|-----|--------|------|
| ST observation_species: "ST" → "CH;CM;CO;PK;SK;ST" | -22% → +3.8% | CSV cell |
| WCT observation_threshold: NA → 1 | -4.2% → +3.0% | CSV cell |
| BT cluster_rearing: FALSE → TRUE | +7% → +1.3% | CSV cell |
| SK outlet ordering: DRM → wscode | -22.6% → -0.7% | fresh code (0.13.5) |
| SK spawn_connected additive step | -9.6% → -0.7% | fresh code (0.13.6) |
| Three-phase cluster | CH +6% → +2.6% | fresh code (0.13.8) |
| Index input tables | 228s → 6.6s classification | fresh code (0.13.4) |

## Remaining gaps

### BT rearing -2.2% (BULK)

bcfishpass applies `stream_order = 1 AND stream_order_parent >= 5` as a rearing cw bypass in all three rearing phases. We don't replicate this because the bypass interacts with clustering — applying it pre-cluster inflates rearing, applying it post-cluster adds segments without connectivity constraints. The 68 km gap is the bypass segments we don't capture.

`frs_order_child` (fresh#158) will address this with a biologically-tuned approach: direct children only (`stream_order = stream_order_max`), distance cap from tributary mouth.

### Spawning +1-4% consistent positive bias

All species show +1-4% spawning excess. From segment boundary differences — our single-pass non-minimal barrier removal creates slightly different segment boundaries than bcfishpass per-model sequential breaking. Different boundaries → different per-segment gradients → different threshold pass/fail at edges.

## Break sources

All positions pre-computed. No snapping during breaking.

| Source | Origin |
|--------|--------|
| Gradient barriers | Computed from FWA vertex geometry |
| Observations | bcfishobs (species-filtered via wsg_species_presence.csv) |
| Crossings | crossings.csv in fresh (pre-computed) |
| Habitat endpoints | user_habitat_classification.csv (both DRM and URM) |
| Falls | falls.csv in fresh |

## Versions

- fresh: 0.13.8
- link: main (7f5d880)
- bcfishpass: ea3c5d8 (post-v0.7.13), tunnel model run v0.7.12
- fwapg: Docker (FWA 20240830, channel_width synced from tunnel 2026-04-13)

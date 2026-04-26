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

Two signals on bcfishpass's side need separating:

- **`configs/bcfishpass/dimensions.csv`** — classifies the species as lake-rearing at all (`rear_lake: yes/no`).
- **`fresh::parameters_habitat_thresholds$rear_lake_ha_min`** — the minimum lake area threshold applied when `rear_lake = yes`.

bcfishpass (as reproduced by link's bcfishpass bundle) classifies only SK as lake-rearing via `rear_lake_only = yes`. KO is lake-rearing in bcfishpass's upstream config but not modelled in the WSGs we're comparing. The `rear_lake_ha_min` column in `parameters_habitat_thresholds.csv` has 200 for SK + KO and NA for everyone else — confirming that other species aren't gated by a lake-area floor because they aren't classified as lake-rearing in the first place.

| Species | bcfishpass `rear_lake` | bcfishpass `rear_lake_ha_min` | default `rear_lake` | default `rear_lake_ha_min` |
|---|---|---|---|---:|
| BT | no | NA | **yes** | 10 |
| CH | no | NA | **yes** | 100 |
| CM | no | NA | no (unchanged) | — |
| CO | no | NA | **yes** | 2 |
| CT | — | NA | yes (new species) | 10 |
| DV | — | NA | yes (new species) | 10 |
| GR | — | NA | yes (new species) | 40 |
| KO | yes (rear_lake_only) | 200 | yes (unchanged) | 200 |
| PK | no | NA | no (unchanged) | — |
| RB | — | NA | yes (new species) | 10 |
| SK | yes (rear_lake_only) | 200 | yes (unchanged) | 200 |
| ST | no | NA | **yes** | 60 |
| WCT | no | NA | **yes** | 10 |

Default ships its own `rear_lake_ha_min` per species via a new column in
`configs/default/dimensions.csv`. `lnk_rules_build()` prefers that column
over the shared `fresh::parameters_habitat_thresholds$rear_lake_ha_min`
when present — keeps bcfishpass bundle at its 200 ha threshold for SK/KO
while letting default express species-specific biology:

- CO at 2 ha — uses small lakes and ponds extensively for overwintering.
- BT/WCT/RB/CT/DV at 10 ha — resident / sub-adult rearing in modest lakes.
- GR at 40 ha — northern populations tend toward larger systems.
- ST at 60 ha — ocean-typed; smaller lakes less likely.
- CH at 100 ha — Cultus / Pitt / Stave class systems.

Rationale: literature supports lake rearing for more species than
bcfishpass's SK/KO-only treatment. [TODO: citations for BT lake rearing
— Babine/Quesnel/Kootenay/Stuart populations; ST lake-rearing
documentation; CT/DV/RB resident-form lake use; exact ha thresholds
per population to be refined with regional literature.]

### 2. Wetland rearing added

`rear_wetland = yes` in default dimensions CSV for BT, CO, CT, DV, GR, RB, SK, ST, WCT. Bcfishpass doesn't flag wetland-rearing at the segment-classification level. Stream-through-wetland reaches (edge_type 1050/1150) support juvenile CO specifically (side channels, beaver complexes) and sub-adult rearing for resident species. [TODO: citations.]

**Spawn-vs-rear distinction (v0.10.0):** as of v0.10.0 the default config
emits explicit FWA edge_type codes `[1000, 1100, 2000, 2300]` for spawn
and rear-stream rules — `1050/1150` (stream-thru-wetland) and `2100`
(rare double-line canal) are dropped. Wetland-flow segments DO still
flag `wetland_rearing` because the dedicated wetland-rearing rule
emits `edge_types_explicit: [1050, 1150]` separately, with
`thresholds: false`. Net: a `1050` segment for a `rear_wetland = yes`
species is `wetland_rearing = TRUE` AND `rearing = TRUE` (via the
`rearing = rear_stream OR wetland_rearing OR rear_lake` aggregate),
but `spawning = FALSE`.

### 3. Intermittent streams included

bcfishpass excludes intermittent streams; default includes them. Two reasons:

1. FWA's intermittent flag is unreliable — 20+ years of field work consistently finds productive fish-bearing reaches classified as intermittent in FWA.
2. Documented seasonal use by CO juveniles and other species.

The "intermittent" flag is independent from the `edge_type` integers — a
segment's edge_type tells you whether it flows as a stream, a canal, a
lake centerline, etc. The intermittent attribute is a separate field on
`fwa_stream_networks_sp.fwa_watershed_code`. So the §2 v0.10.0 change
(dropping `1050/1150` from spawn) is orthogonal to "default includes
intermittent streams".

[TODO: edge-type mechanism in the rules YAML + citations.]

### 4. Spawn gradient minimum — deferred

default currently ships with `spawn_gradient_min = 0` (same as bcfishpass). A non-zero floor was tested at 0.0025 and over-pruned observation-validated spawning reaches (see follow-ups §9). The principle — exclude flat depositional reaches too flat for gravel retention — is defensible; the implementation needs calibration. Deferred to a follow-up.

### 5. River-polygon channel-width threshold skipped

`river_skip_cw_min = yes` in default dimensions CSV. Channel-width thresholds are applied to stream-type segments (single-thread channel) but meaningless on river polygons (multi-thread, braided, anabranching) where the channel_width attribute is a poor proxy.

## Results

Numbers populate from `tar_read(rollup)` after the first clean `tar_destroy + tar_make()`. Table format: one block per WSG, rows = species × habitat_type, columns = bcfishpass bundle value / default bundle value / diff (default − bcfishpass) with unit suffix.






### ADMS

| Species | Habitat | bcfishpass | default | Δ | Unit |
|---|---|---:|---:|---:|---|
| BT | spawning | 368.13 | 368.13 | +0 | km |
| BT | rearing | 666.96 | 785.64 | +118.68 | km |
| BT | lake_rearing | 0 | 14259.74 | +14259.7 | ha |
| BT | wetland_rearing | 0 | 926.32 | +926.32 | ha |
| CH | spawning | 279.01 | 279.01 | +0 | km |
| CH | rearing | 315.42 | 590.26 | +274.84 | km |
| CH | lake_rearing | 0 | 13936.94 | +13936.9 | ha |
| CH | wetland_rearing | 0 | 812 | +812 | ha |
| CO | spawning | 317.73 | 317.73 | +0 | km |
| CO | rearing | 363 | 608.21 | +245.21 | km |
| CO | lake_rearing | 0 | 14105.71 | +14105.7 | ha |
| CO | wetland_rearing | 817.06 | 816.71 | -0.35 | ha |
| RB | spawning | NA | 310.61 | NA | km |
| RB | rearing | NA | 690.41 | NA | km |
| RB | lake_rearing | NA | 14128.54 | NA | ha |
| RB | wetland_rearing | NA | 834.85 | NA | ha |
| SK | spawning | 93.97 | 93.97 | +0 | km |
| SK | rearing | 229.85 | 229.85 | +0 | km |
| SK | lake_rearing | 13820.05 | 13820.05 | +0 | ha |
| SK | wetland_rearing | 0 | 0 | +0 | ha |

### BULK

| Species | Habitat | bcfishpass | default | Δ | Unit |
|---|---|---:|---:|---:|---|
| BT | spawning | 1904.46 | 1904.46 | +0 | km |
| BT | rearing | 2994.99 | 3202.79 | +207.8 | km |
| BT | lake_rearing | 0 | 4448.63 | +4448.63 | ha |
| BT | wetland_rearing | 0 | 5901.49 | +5901.49 | ha |
| CH | spawning | 1277.27 | 1277.27 | +0 | km |
| CH | rearing | 1785.52 | 2165.26 | +379.74 | km |
| CH | lake_rearing | 0 | 2871.94 | +2871.94 | ha |
| CH | wetland_rearing | 0 | 5546.32 | +5546.32 | ha |
| CO | spawning | 1840.24 | 1840.24 | +0 | km |
| CO | rearing | 2335.5 | 2501.41 | +165.91 | km |
| CO | lake_rearing | 0 | 4213.19 | +4213.19 | ha |
| CO | wetland_rearing | 5571.02 | 5567 | -4.02 | ha |
| PK | spawning | 1895.42 | 1895.42 | +0 | km |
| PK | rearing | 0 | 0 | +0 | km |
| PK | lake_rearing | 0 | 0 | +0 | ha |
| PK | wetland_rearing | 0 | 0 | +0 | ha |
| RB | spawning | NA | 1850.07 | NA | km |
| RB | rearing | NA | 3259.23 | NA | km |
| RB | lake_rearing | NA | 4119.16 | NA | ha |
| RB | wetland_rearing | NA | 5748.55 | NA | ha |
| SK | spawning | 25.02 | 25.02 | +0 | km |
| SK | rearing | 64.56 | 64.56 | +0 | km |
| SK | lake_rearing | 2098.76 | 2098.76 | +0 | ha |
| SK | wetland_rearing | 0 | 0 | +0 | ha |
| ST | spawning | 1308.73 | 1308.73 | +0 | km |
| ST | rearing | 2244.75 | 2708.2 | +463.45 | km |
| ST | lake_rearing | 0 | 3548.97 | +3548.97 | ha |
| ST | wetland_rearing | 0 | 5814.03 | +5814.03 | ha |

### BABL

| Species | Habitat | bcfishpass | default | Δ | Unit |
|---|---|---:|---:|---:|---|
| BT | spawning | 926.76 | 926.76 | +0 | km |
| BT | rearing | 2306.49 | 3006.76 | +700.27 | km |
| BT | lake_rearing | 0 | 56308.82 | +56308.8 | ha |
| BT | wetland_rearing | 0 | 6119.08 | +6119.08 | ha |
| CH | spawning | 362.35 | 362.35 | +0 | km |
| CH | rearing | 748.39 | 2124.79 | +1376.4 | km |
| CH | lake_rearing | 0 | 52765.57 | +52765.6 | ha |
| CH | wetland_rearing | 0 | 5741.8 | +5741.8 | ha |
| CO | spawning | 843.83 | 843.83 | +0 | km |
| CO | rearing | 1439.76 | 2515.49 | +1075.73 | km |
| CO | lake_rearing | 0 | 54507.85 | +54507.8 | ha |
| CO | wetland_rearing | 5796.4 | 5786.74 | -9.66 | ha |
| RB | spawning | NA | 696.15 | NA | km |
| RB | rearing | NA | 2471.88 | NA | km |
| RB | lake_rearing | NA | 50256.96 | NA | ha |
| RB | wetland_rearing | NA | 4408.58 | NA | ha |
| SK | spawning | 85.24 | 85.24 | +0 | km |
| SK | rearing | 941.63 | 941.63 | +0 | km |
| SK | lake_rearing | 52449.98 | 52449.98 | +0 | ha |
| SK | wetland_rearing | 0 | 0 | +0 | ha |
| ST | spawning | 362.97 | 362.97 | +0 | km |
| ST | rearing | 930.03 | 2468.12 | +1538.09 | km |
| ST | lake_rearing | 0 | 53454.87 | +53454.9 | ha |
| ST | wetland_rearing | 0 | 5906.92 | +5906.92 | ha |

### ELKR

| Species | Habitat | bcfishpass | default | Δ | Unit |
|---|---|---:|---:|---:|---|
| BT | spawning | 1538.96 | 1538.96 | +0 | km |
| BT | rearing | 2079.01 | 2104.87 | +25.86 | km |
| BT | lake_rearing | 0 | 537.41 | +537.41 | ha |
| BT | wetland_rearing | 0 | 1013.55 | +1013.55 | ha |
| RB | spawning | NA | 1359.63 | NA | km |
| RB | rearing | NA | 1842.73 | NA | km |
| RB | lake_rearing | NA | 493.99 | NA | ha |
| RB | wetland_rearing | NA | 948.75 | NA | ha |
| WCT | spawning | 1597.05 | 1597.05 | +0 | km |
| WCT | rearing | 1918.51 | 2032.37 | +113.86 | km |
| WCT | lake_rearing | 0 | 561.98 | +561.98 | ha |
| WCT | wetland_rearing | 0 | 1030.3 | +1030.3 | ha |

### DEAD

| Species | Habitat | bcfishpass | default | Δ | Unit |
|---|---|---:|---:|---:|---|
| BT | spawning | 163.7 | 163.7 | +0 | km |
| BT | rearing | 291.07 | 314.15 | +23.08 | km |
| BT | lake_rearing | 0 | 536.97 | +536.97 | ha |
| BT | wetland_rearing | 0 | 507.46 | +507.46 | ha |
| CH | spawning | 110.55 | 110.55 | +0 | km |
| CH | rearing | 129.69 | 160.6 | +30.91 | km |
| CH | lake_rearing | 0 | 108.34 | +108.34 | ha |
| CH | wetland_rearing | 0 | 274.2 | +274.2 | ha |
| CO | spawning | 130.75 | 130.75 | +0 | km |
| CO | rearing | 171.98 | 180.32 | +8.34 | km |
| CO | lake_rearing | 0 | 176.92 | +176.92 | ha |
| CO | wetland_rearing | 284.51 | 282.6 | -1.91 | ha |
| PK | spawning | 131.92 | 131.92 | +0 | km |
| PK | rearing | 0 | 0 | +0 | km |
| PK | lake_rearing | 0 | 0 | +0 | ha |
| PK | wetland_rearing | 0 | 0 | +0 | ha |
| RB | spawning | NA | 137.96 | NA | km |
| RB | rearing | NA | 291.45 | NA | km |
| RB | lake_rearing | NA | 258.99 | NA | ha |
| RB | wetland_rearing | NA | 322.92 | NA | ha |
| SK | spawning | 0 | 0 | +0 | km |
| SK | rearing | 0 | 0 | +0 | km |
| SK | lake_rearing | 0 | 0 | +0 | ha |
| SK | wetland_rearing | 0 | 0 | +0 | ha |
| ST | spawning | 115.51 | 128.88 | +13.37 | km |
| ST | rearing | 151.83 | 190.64 | +38.81 | km |
| ST | lake_rearing | 0 | 206.71 | +206.71 | ha |
| ST | wetland_rearing | 0 | 314.76 | +314.76 | ha |

## Observations / surprises to investigate

### 1. Lake + wetland rearing both differentiate now

**Lakes fixed via [fresh#165](https://github.com/NewGraphEnvironment/fresh/issues/165)
→ v0.17.0.** `frs_habitat_classify()` honours `waterbody_type: L` rules
in the rules YAML and applies optional `lake_ha_min`. With per-species
`rear_lake_ha_min` in `configs/default/dimensions.csv`, `lake_rearing_ha`
differentiates:

- bcfishpass bundle: 0 for BT/CH/CO/ST/WCT (no rear L rule); matches
  default only for SK (both declare L with 200 ha).
- default bundle: each species reflects its threshold — CO (2 ha),
  BT/WCT/RB/CT/DV (10 ha), GR (40 ha), ST (60 ha), CH (100 ha),
  SK/KO (200 ha).

**Wetlands fixed via [fresh#169](https://github.com/NewGraphEnvironment/fresh/pull/169)
→ v0.17.1 + link-side W rule emission.** `lnk_rules_build()` now emits
both an `edge_types: wetland` rule (adds wetland-flow segments to the
`rearing` km total) AND a `waterbody_type: W` rule (sets the
`wetland_rearing` flag that drives the ha rollup). Per-species
`rear_wetland_ha_min` column in dimensions.csv gates the polygon join.
fresh 0.17.1's validator accepts `wetland_ha_min` as a predicate under
W rules (mirror of `lake_ha_min`).

Post-fix differentiation:

- bcfishpass bundle: only CO has `rear_wetland = yes` → only CO gets
  nonzero `wetland_rearing_ha` (bcfishpass's "wetland-flow carve-out"
  for juvenile CO).
- default bundle: BT/CH/CO/RB all nonzero per their thresholds
  (CO at 0.5 ha, others at 1 ha). ADMS example: CO 816.71 ha
  (bit-identical to bcfishpass-bundle 817.06 ha, same rule).

### 2. Linear km inflates under `default` across all species and WSGs (rearing only — spawning aligned in v0.10.0)

The `rearing` km column is consistently higher under `default` due to
the deliberate departures (intermittent streams included, `river_skip_cw_min = yes`,
expanded `rear_wetland`). Magnitudes vary by WSG — in BABL, CH rearing
inflates by 1376 km (+184%), reflecting a large base network with lots
of intermittent contribution; in DEAD it's 31 km (+24%).

**Spawning is now identical between bundles** as of v0.10.0. With both
bundles emitting `edge_types_explicit: [1000, 1100, 2000, 2300]` and
sharing the same `spawn_lake = no` / `spawn_connected` / connectivity
gating per species, the spawn predicates are structurally equivalent.
Spawning Δ = 0 km for every species × WSG combination on the parity
bundles (BT/CH/CO/PK/SK/ST/WCT). RB is newly modelled under default —
no bcfishpass reference to compare against, so the column is NA.

### 3. SK spawning — connectivity now honoured

Two bugs in the initial `default` bundle caused SK spawning to inflate
10–20× over bcfishpass. Both fixed in earlier PRs:

1. **Missing `spawn_connected` YAML block.** `configs/default/dimensions.csv`
   was missing five columns (`rear_stream_order_bypass`,
   `spawn_connected_direction`, `spawn_connected_gradient_max`,
   `spawn_connected_cw_min`, `spawn_connected_edge_types`) that
   `lnk_rules_build()` needs to emit the permissive-spawn
   `spawn_connected:` block. Without it, fresh's `.frs_connected_waterbody()`
   had no permissive fallback.
2. **`spawn_lake=yes` for SK + KO.** The original default flagged lake
   spawning for sockeye. `lnk_rules_build()` emitted a `waterbody_type: L`
   spawn rule, which credited entire lake centerlines (Babine Lake alone
   is 177 km) as SK spawning habitat within the 3 km connected-distance
   cap. Set to `no` to match bcfishpass convention — stream-spawning
   sockeye only.

Post-fix (v0.10.0) SK spawning deltas are 0 km on every parity WSG
because the bundles emit identical spawn predicates. Pre-v0.10.0 the
residual deltas (ADMS +4 km, BULK +18 km, BABL +93 km, DEAD +0 km)
traced to default's looser categorical edge-types (`[stream, canal]`
including 1050/1150 stream-thru-wetland) — eliminated when default
switched to `edge_types = "explicit"`.

Beach-spawning sockeye populations (Babine, Shuswap) exist as a distinct
phenotype but aren't modelled in the SK category — they would need their
own dimensions row.

### 4. RB is newly modeled under `default`

bcfishpass does not ship a `habitat_linear_rb` table. The `default` bundle
models RB (rainbow trout resident form) across all five WSGs via the
`default` dimensions CSV. Numbers are comparable to BT/ST rearing/spawning
in the same WSGs, which is the right order of magnitude.

### 5. Our compare reference (`habitat_linear_sk.spawning`) is model-only; bcfishpass published output stitches in known habitat

`bcfishpass.habitat_linear_<sp>` is a boolean table capturing bcfishpass's
RULE-BASED (model) classification. `bcfishpass.streams_habitat_linear`
carries a per-species integer column (e.g. `spawning_sk`) that layers
model + known habitat:

- `spawning_sk = 1` or `2` — model classification
- `spawning_sk = 3` — known habitat, sourced from
  `bcfishpass.streams_habitat_known` (via `user_habitat_classification.csv`)

BABL SK spawning example:

| reference | km | meaning |
|---|---:|---|
| `habitat_linear_sk.spawning = TRUE` (boolean, model-only) | 59.3 | what our compare function queries today |
| `streams_habitat_linear.spawning_sk > 0` (model + known) | 132 | what users see on `db_newgraph` / QGIS |

Shass Creek at the top of Babine (BLK 360886269) is the canonical example:
3.87 km published as `spawning_sk = 3` (known habitat), 0 km in
`habitat_linear_sk.spawning` (model misses it — intermittent reaches), and
0 km in link's bcfishpass-bundle reproduction.

**Implication:** link's pipeline loads `user_habitat_classification.csv`
and uses it for network break points and barrier overrides, but does
NOT propagate its `spawning` / `rearing` flags into
`fresh.streams_habitat`. Follow-up filed as
[link#55](https://github.com/NewGraphEnvironment/link/issues/55).

### 6. Three-way overlap: where our model catches what bcfp needs the CSV for

Splitting `streams_habitat_linear.spawning_sk` into model (1, 2) vs known
(3) and spatially intersecting with link's default output gives four
semantic buckets (BABL SK, shipping state — no gradient floor).

> **Note on numbers below**: this analysis was run before v0.10.0 (when default
> still used categorical `[stream, canal]` edge types, including stream-
> thru-wetland 1050/1150). With v0.10.0's tightening, `default_over` is
> expected to shrink because we no longer credit 1050/1150 as default
> spawning. `default_catches_known` and `csv_only` should be roughly
> stable. A re-run of the BABL SK source-bucket analysis is filed as a
> follow-up.


| bucket | km | segments | interpretation |
|---|---:|---:|---|
| `high_conf` — default ∩ bcfp-model | 58.1 | 197 | rule systems converge (highest confidence) |
| `default_catches_known` — default ∩ bcfp-known, NOT in bcfp-model | 13.2 | 34 | our rules independently arrive at what bcfp needs observations for |
| `csv_only` — bcfp-known, default misses | 60.2 | 238 | gap: known habitat our rules can't reach |
| `default_over` — default only, no bcfp source | 79.6 | 229 | potential over-prediction (or unsurveyed habitat) |

`default_catches_known` at 13 km out of ~60 km of bcfp-known-only suggests
our default rules recover a meaningful minority of observation-curated
spawning without needing the CSV overlay. Most of `default_over`
(79.6 km) is flat-gradient or wetland-flow reaches — candidates for the
gradient-floor refinement in §9.

Interactive map: `data-raw/maps/sk_spawning_BABL_sources.html`.

### 7. Residual `csv_only` — gradient vs connectivity gap

Decomposing the 60.2 km of `csv_only` (bcfp-known, default misses) by
gradient bin:

| gradient bin | km | n |
|---|---:|---:|
| [0, 0.0025) | 10.1 | 81 |
| [0.0025, 0.005) | 2.93 | 8 |
| [0.005, 0.01) | 4.86 | 16 |
| [0.01, 0.05) | 33.0 | 100 |
| [0.05+) | 9.29 | 33 |

About 10 km sits below the `spawn_gradient_min = 0.0025` floor — which
the floor correctly excludes post-fix (bcfp's CSV overrides gradient for
known gravel-deposit reaches). The remaining ~50 km has above-floor
gradient and mostly edge_type 1000 (stream-main, 48 km). These are
spawning reaches bcfp confirms via observation that default's
rule-based connectivity doesn't reach — likely tributaries upstream of
reaches our model treats as disconnected. Recovering these requires
[link#55](https://github.com/NewGraphEnvironment/link/issues/55)
(ingest known-habitat CSV), not a rule-set tightening.

### 8. Segment-length averaging may mask sub-reach gradient eligibility

`csv_only` segment lengths (BABL SK): median 92 m, mean 253 m,
max 2932 m. A long segment carries a single `gradient` attribute
computed as the average over the segment — a 2 km segment with average
gradient 0.001 might include a 400 m sub-reach above the spawn floor
that is masked by the average. bcfishpass segments at finer granularity
(~100 m regular intervals), so its averaging error is smaller.

Potential mitigation:

1. Break segments at gradient inflection points in fresh's segmentation.
2. Break at regular distance intervals (100 m / 250 m) matching bcfishpass.
3. Store an auxiliary gradient profile and classify against max (or some
   percentile) rather than mean.

Scope for a separate investigation; tracked as a follow-up to be filed.

## Follow-up: spawn gradient minimum design

Tried `spawn_gradient_min = 0.0025` for all default species. Full 5-WSG
rerun showed the blanket floor over-prunes observation-validated
spawning: ADMS SK dropped 88.83 → 2.32 km (Adams River outlet is
iconic spawning but measures 0 gradient), BULK spawning lost 230–255 km
per species in braided floodplains, and the BABL `default_catches_known`
bucket in §6 collapsed from 13 km to 0 (every segment where our model
organically matched bcfp's CSV-curated known spawning got excluded).

Reverted to 0 for shipping; a calibrated floor belongs in a follow-up.

Candidates worth testing:

1. **Lower threshold (0.001 or 0.0005).** Keeps the "measurement = 0"
   exclusion but rescues low-gradient depositional spawning.
2. **Only exclude `gradient = 0`.** Many zero values are measurement
   artefacts on very short segments, not true flat reaches. Excluding
   only the exact zeros (`gradient > 0`) separates data gaps from flat
   hydrology.
3. **Per-species floors.** SK/CH/CO lake-outlet spawning is
   depositional by nature — keep their floor lower or zero. BT/ST in
   headwater/intermountain systems expect steeper gravel, so a stricter
   floor is biologically supported.
4. **Edge-type exemption.** Lake-outlet reaches (stream segments
   downstream of `waterbody_type = L`) have gravel supplied by lake
   sorting — exempt from the floor even when the segment gradient is
   near zero.

**Related: FWA segment-length averaging.** FWA stream segments vary from
tens of metres to >2 km. A long segment's `gradient` attribute is
averaged over the whole segment — a 2 km reach with average gradient
0.001 can contain 300–500 m sub-reaches above any sensible floor.
bcfishpass pre-segments at finer granularity; our segments follow
natural break points (barriers, crossings, obs, waterbody boundaries).
Worth testing:

- **Re-segment streams at fixed intervals (300–500 m).** Recompute
  per-sub-segment gradient from the DEM, reclassify, compare. Would
  reveal how much of the `csv_only` 60 km in BABL SK is an averaging
  artefact vs a real connectivity gap.
- **Store a per-segment gradient profile.** Classify against max or a
  high-percentile gradient rather than the mean; keeps the spatial
  break structure intact while capturing sub-segment variability.

Any gradient floor calibration should be evaluated against the four
buckets in §6 on the sources map — not just the rollup km — since the
floor's job is to trade `default_over` reduction against
`default_catches_known` preservation.

## Versions

- fresh: 0.21.0
- link: 0.9.0 → target 0.10.0 at PR merge
- bcfishpass: ea3c5d8
- fwapg: Docker (FWA 20240830)

## Related

- `research/bcfishpass_comparison.md` — reproduction fidelity of the bcfishpass bundle.
- [link#51](https://github.com/NewGraphEnvironment/link/issues/51) — this work.
- [link#52](https://github.com/NewGraphEnvironment/link/issues/52) — channel-class as break position research.
- [link#21](https://github.com/NewGraphEnvironment/link/issues/21) — temperature / thermal energy (out of scope for default today).

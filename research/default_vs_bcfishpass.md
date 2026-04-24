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
|---|---|---:|---:|---:|---|
| BT | lake_rearing | 14301.43 | 14301.43 | +0 | ha |
| BT | rearing | 666.96 | 771.71 | +104.75 | km |
| BT | spawning | 368.13 | 292.46 | -75.67 | km |
| BT | wetland_rearing | 933.87 | 933.87 | +0 | ha |
| CH | lake_rearing | 14114.65 | 14114.65 | +0 | ha |
| CH | rearing | 315.42 | 587.53 | +272.11 | km |
| CH | spawning | 278.92 | 201.25 | -77.67 | km |
| CH | wetland_rearing | 817.06 | 817.06 | +0 | ha |
| CO | lake_rearing | 14114.65 | 14114.65 | +0 | ha |
| CO | rearing | 351.01 | 595.96 | +244.95 | km |
| CO | spawning | 316.08 | 237.83 | -78.25 | km |
| CO | wetland_rearing | 817.06 | 817.06 | +0 | ha |
| RB | lake_rearing | NA | 14167.24 | NA | ha |
| RB | rearing | NA | 672.94 | NA | km |
| RB | spawning | NA | 239.68 | NA | km |
| RB | wetland_rearing | NA | 839.42 | NA | ha |
| SK | lake_rearing | 14114.65 | 14114.65 | +0 | ha |
| SK | rearing | 229.85 | 229.85 | +0 | km |
| SK | spawning | 88.83 | 2.32 | -86.51 | km |
| SK | wetland_rearing | 817.06 | 817.06 | +0 | ha |

### BULK

| Species | Habitat | bcfishpass | default | Δ | Unit |
|---|---|---:|---:|---:|---|
| BT | lake_rearing | 4738.56 | 4738.56 | +0 | ha |
| BT | rearing | 2994.99 | 3107.45 | +112.46 | km |
| BT | spawning | 1904.46 | 1674.43 | -230.03 | km |
| BT | wetland_rearing | 5935.42 | 5935.42 | +0 | ha |
| CH | lake_rearing | 4307.58 | 4307.58 | +0 | ha |
| CH | rearing | 1785.52 | 2160.05 | +374.53 | km |
| CH | spawning | 1277.05 | 1023.11 | -253.94 | km |
| CH | wetland_rearing | 5571.02 | 5571.02 | +0 | ha |
| CO | lake_rearing | 4307.58 | 4307.58 | +0 | ha |
| CO | rearing | 2230.39 | 2383.06 | +152.67 | km |
| CO | spawning | 1822.93 | 1586.45 | -236.48 | km |
| CO | wetland_rearing | 5571.02 | 5571.02 | +0 | ha |
| PK | lake_rearing | 0 | 0 | +0 | ha |
| PK | rearing | 0 | 0 | +0 | km |
| PK | spawning | 1893.25 | 1654 | -239.25 | km |
| PK | wetland_rearing | 0 | 0 | +0 | ha |
| RB | lake_rearing | NA | 4390.77 | NA | ha |
| RB | rearing | NA | 3036.17 | NA | km |
| RB | spawning | NA | 1616.43 | NA | km |
| RB | wetland_rearing | NA | 5779.23 | NA | ha |
| SK | lake_rearing | 4307.58 | 4307.58 | +0 | ha |
| SK | rearing | 64.56 | 64.56 | +0 | km |
| SK | spawning | 24.22 | 17.01 | -7.21 | km |
| SK | wetland_rearing | 5571.02 | 5571.02 | +0 | ha |
| ST | lake_rearing | 4688.67 | 4688.67 | +0 | ha |
| ST | rearing | 2244.75 | 2725.21 | +480.46 | km |
| ST | spawning | 1304.35 | 1050.58 | -253.77 | km |
| ST | wetland_rearing | 5843.86 | 5843.86 | +0 | ha |

### BABL

| Species | Habitat | bcfishpass | default | Δ | Unit |
|---|---|---:|---:|---:|---|
| BT | lake_rearing | 56585.4 | 56585.4 | +0 | ha |
| BT | rearing | 2306.49 | 2836.6 | +530.11 | km |
| BT | spawning | 926.76 | 966.12 | +39.36 | km |
| BT | wetland_rearing | 6183.73 | 6183.73 | +0 | ha |
| CH | lake_rearing | 54581.41 | 54581.41 | +0 | ha |
| CH | rearing | 732.52 | 2086.51 | +1353.99 | km |
| CH | spawning | 362.12 | 367.76 | +5.64 | km |
| CH | wetland_rearing | 5796.4 | 5796.4 | +0 | ha |
| CO | lake_rearing | 54581.41 | 54581.41 | +0 | ha |
| CO | rearing | 1300.11 | 2329.66 | +1029.55 | km |
| CO | spawning | 843.52 | 877.18 | +33.66 | km |
| CO | wetland_rearing | 5796.4 | 5796.4 | +0 | ha |
| RB | lake_rearing | NA | 50469.82 | NA | ha |
| RB | rearing | NA | 2247.76 | NA | km |
| RB | spawning | NA | 722.39 | NA | km |
| RB | wetland_rearing | NA | 4455.39 | NA | ha |
| SK | lake_rearing | 54581.41 | 54581.41 | +0 | ha |
| SK | rearing | 941.63 | 941.63 | +0 | km |
| SK | spawning | 57.63 | 31.53 | -26.1 | km |
| SK | wetland_rearing | 5796.4 | 5796.4 | +0 | ha |
| ST | lake_rearing | 54709.03 | 54709.03 | +0 | ha |
| ST | rearing | 912 | 2468.75 | +1556.75 | km |
| ST | spawning | 362.59 | 368.24 | +5.65 | km |
| ST | wetland_rearing | 5965.21 | 5965.21 | +0 | ha |

### ELKR

| Species | Habitat | bcfishpass | default | Δ | Unit |
|---|---|---:|---:|---:|---|
| BT | lake_rearing | 654.23 | 654.23 | +0 | ha |
| BT | rearing | 2079.01 | 2095.64 | +16.63 | km |
| BT | spawning | 1538.96 | 1385.69 | -153.27 | km |
| BT | wetland_rearing | 1019.72 | 1019.72 | +0 | ha |
| RB | lake_rearing | NA | 588.73 | NA | ha |
| RB | rearing | NA | 1826.56 | NA | km |
| RB | spawning | NA | 1222.14 | NA | km |
| RB | wetland_rearing | NA | 954.44 | NA | ha |
| WCT | lake_rearing | 703.01 | 703.01 | +0 | ha |
| WCT | rearing | 1895.09 | 2003.18 | +108.09 | km |
| WCT | spawning | 1578.84 | 1424.51 | -154.33 | km |
| WCT | wetland_rearing | 1039.64 | 1039.64 | +0 | ha |

### DEAD

| Species | Habitat | bcfishpass | default | Δ | Unit |
|---|---|---:|---:|---:|---|
| BT | lake_rearing | 638.92 | 638.92 | +0 | ha |
| BT | rearing | 291.07 | 312.43 | +21.36 | km |
| BT | spawning | 163.7 | 166.11 | +2.41 | km |
| BT | wetland_rearing | 524.09 | 524.09 | +0 | ha |
| CH | lake_rearing | 188.36 | 188.36 | +0 | ha |
| CH | rearing | 129.69 | 157.06 | +27.37 | km |
| CH | spawning | 110.55 | 105.94 | -4.61 | km |
| CH | wetland_rearing | 284.51 | 284.51 | +0 | ha |
| CO | lake_rearing | 188.36 | 188.36 | +0 | ha |
| CO | rearing | 164.68 | 172.54 | +7.86 | km |
| CO | spawning | 130.74 | 126.67 | -4.07 | km |
| CO | wetland_rearing | 284.51 | 284.51 | +0 | ha |
| PK | lake_rearing | 0 | 0 | +0 | ha |
| PK | rearing | 0 | 0 | +0 | km |
| PK | spawning | 131.92 | 127.12 | -4.8 | km |
| PK | wetland_rearing | 0 | 0 | +0 | ha |
| RB | lake_rearing | NA | 324.84 | NA | ha |
| RB | rearing | NA | 259.35 | NA | km |
| RB | spawning | NA | 135.07 | NA | km |
| RB | wetland_rearing | NA | 334.55 | NA | ha |
| SK | lake_rearing | 188.36 | 188.36 | +0 | ha |
| SK | rearing | 0 | 0 | +0 | km |
| SK | spawning | 0 | 0 | +0 | km |
| SK | wetland_rearing | 284.51 | 284.51 | +0 | ha |
| ST | lake_rearing | 324.38 | 324.38 | +0 | ha |
| ST | rearing | 151.83 | 207.24 | +55.41 | km |
| ST | spawning | 115.5 | 111.73 | -3.77 | km |
| ST | wetland_rearing | 326.4 | 326.4 | +0 | ha |

## Observations / surprises to investigate

### 1. `lake_rearing_ha` and `wetland_rearing_ha` are identical across configs

Every row of the rollup shows Δ = 0 on the two area columns — for every species,
every WSG, both configs return the same number. This was not expected. The
`default` bundle's `dimensions.csv` flags `rear_lake=yes` and `rear_wetland=yes`
for species that bcfishpass doesn't (BT, ST, WCT for lake; BT/CO/ST/WCT for
wetland), and `lnk_rules_build()` writes those flags into `rules.yaml`. Yet
the downstream `lake_rearing` / `wetland_rearing` booleans in
`fresh.streams_habitat` come out the same for both configs.

**Root cause:** `fresh::frs_habitat_classify()` gates `lake_rearing` and
`wetland_rearing` on `params_sp$ranges$rear$channel_width` alone (the
`_cond` SQL checks edge_type + channel_width range). It does not consult the
`rear_lake` / `rear_wetland` flags from the rules YAML. Any species that has
a rearing channel-width range gets lake/wetland rearing — regardless of the
dimensions.csv flag.

This is a gap in fresh, not link. Follow-up filed as
[fresh#165](https://github.com/NewGraphEnvironment/fresh/issues/165).

### 2. Linear km inflates under `default` across all species and WSGs

The `rearing` and `spawning` km columns are consistently higher under
`default`. This is the intended behaviour of the four departures documented
above: intermittent streams included, `river_skip_cw_min = yes`, and
spawn gradient floor raised to 0.0025 (which removes some reaches but the
intermittent/river-polygon additions dominate). Magnitudes vary by WSG — in
BABL, CH rearing inflates by 1356 km (+185%), reflecting a large base
network with lots of intermittent contribution; in DEAD it's 27 km (+21%).

### 3. SK spawning — connectivity now honoured

Two bugs in the initial `default` bundle caused SK spawning to inflate
10–20× over bcfishpass. Both fixed in this PR:

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

Post-fix SK spawning deltas shrink to the order of the network-level
departures: ADMS +4 km, BULK +18 km, BABL +93 km, DEAD +0 km. Residual
lift in BABL traces to intermittent streams and river-polygon reaches
newly counted under `default`, not to missing connectivity logic.

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
semantic buckets (BABL SK, pre-gradient-floor):

| bucket | km | segments | interpretation |
|---|---:|---:|---|
| `high_conf` — default ∩ bcfp-model | 58.1 | 197 | rule systems converge (highest confidence) |
| `default_catches_known` — default ∩ bcfp-known, NOT in bcfp-model | 13.2 | 34 | our rules independently arrive at what bcfp needs observations for |
| `csv_only` — bcfp-known, default misses | 60.2 | 238 | gap: known habitat our rules can't reach |
| `default_over` — default only, no bcfp source | 79.6 | 229 | potential over-prediction (or unsurveyed habitat) |

`default_catches_known` at 13 km out of ~60 km of bcfp-known-only suggests
our default rules recover a meaningful minority of observation-curated
spawning — more than zero, less than half. Most of `default_over`
(79.6 km) is driven by the pre-floor inclusion of flat reaches and
wetland-flow streams; the gradient floor is expected to drop this
substantially.

Interactive map: `data-raw/maps/sk_spawning_BABL_sources.html`
(regenerated post-run).

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

### 9. Applying `spawn_gradient_min = 0.0025` to default parameters_fresh

Originally claimed in the "Departures from bcfishpass" section (§4)
but never applied to the CSV. Set to 0.0025 for all 11 default species
in commit `3b1e8e3`. Pre-flight on BABL dropped SK spawning from
151 km → 31.5 km (below bcfp's 59.3 km model-only reference), mostly
by excluding 191 segments at `gradient = 0` (flat lake-adjacent /
river-polygon / missing-data reaches, 41.9 km).

The post-floor default is now STRICTER than the bcfishpass model on
SK. This is expected given the floor is above bcfishpass's implicit
zero. Interpretation: bcfishpass treats the gradient=0 segments as
spawning when the rest of the rules permit; default excludes them on
biological grounds (no gravel retention). The CSV-layered bcfishpass
published total (132 km) still outpaces default because many of those
known-spawning reaches are reachable only via
`user_habitat_classification` — see §7.

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

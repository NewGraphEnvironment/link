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
| BT | lake_rearing | 14301.4 | 14301.4 | +0 | ha |
| BT | rearing | 666.96 | 775.34 | +108.38 | km |
| BT | spawning | 368.13 | 397.17 | +29.04 | km |
| BT | wetland_rearing | 933.87 | 933.87 | +0 | ha |
| CH | lake_rearing | 14114.6 | 14114.6 | +0 | ha |
| CH | rearing | 315.42 | 588.11 | +272.69 | km |
| CH | spawning | 278.92 | 295.4 | +16.48 | km |
| CH | wetland_rearing | 817.06 | 817.06 | +0 | ha |
| CO | lake_rearing | 14114.6 | 14114.6 | +0 | ha |
| CO | rearing | 351.01 | 596.37 | +245.36 | km |
| CO | spawning | 316.08 | 338.67 | +22.59 | km |
| CO | wetland_rearing | 817.06 | 817.06 | +0 | ha |
| RB | lake_rearing | NA | 14167.2 | NA | ha |
| RB | rearing | NA | 672.94 | NA | km |
| RB | spawning | NA | 331.35 | NA | km |
| RB | wetland_rearing | NA | 839.42 | NA | ha |
| SK | lake_rearing | 14114.6 | 14114.6 | +0 | ha |
| SK | rearing | 229.85 | 229.85 | +0 | km |
| SK | spawning | 88.83 | 332.01 | +243.18 | km |
| SK | wetland_rearing | 817.06 | 817.06 | +0 | ha |

### BULK

| Species | Habitat | bcfishpass | default | Δ | Unit |
|---|---|---:|---:|---:|---|
| BT | lake_rearing | 4738.56 | 4738.56 | +0 | ha |
| BT | rearing | 2994.99 | 3111.08 | +116.09 | km |
| BT | spawning | 1904.46 | 2069.15 | +164.69 | km |
| BT | wetland_rearing | 5935.42 | 5935.42 | +0 | ha |
| CH | lake_rearing | 4307.58 | 4307.58 | +0 | ha |
| CH | rearing | 1785.52 | 2160.61 | +375.09 | km |
| CH | spawning | 1277.05 | 1357.11 | +80.06 | km |
| CH | wetland_rearing | 5571.02 | 5571.02 | +0 | ha |
| CO | lake_rearing | 4307.58 | 4307.58 | +0 | ha |
| CO | rearing | 2230.39 | 2383.31 | +152.92 | km |
| CO | spawning | 1822.93 | 1976.53 | +153.6 | km |
| CO | wetland_rearing | 5571.02 | 5571.02 | +0 | ha |
| PK | lake_rearing | 0 | 0 | +0 | ha |
| PK | rearing | 0 | 0 | +0 | km |
| PK | spawning | 1893.25 | 2040.41 | +147.16 | km |
| PK | wetland_rearing | 0 | 0 | +0 | ha |
| RB | lake_rearing | NA | 4390.77 | NA | ha |
| RB | rearing | NA | 3036.17 | NA | km |
| RB | spawning | NA | 2007.67 | NA | km |
| RB | wetland_rearing | NA | 5779.23 | NA | ha |
| SK | lake_rearing | 4307.58 | 4307.58 | +0 | ha |
| SK | rearing | 64.56 | 64.56 | +0 | km |
| SK | spawning | 24.22 | 106.79 | +82.57 | km |
| SK | wetland_rearing | 5571.02 | 5571.02 | +0 | ha |
| ST | lake_rearing | 4688.67 | 4688.67 | +0 | ha |
| ST | rearing | 2244.75 | 2725.91 | +481.16 | km |
| ST | spawning | 1304.35 | 1385 | +80.65 | km |
| ST | wetland_rearing | 5843.86 | 5843.86 | +0 | ha |

### BABL

| Species | Habitat | bcfishpass | default | Δ | Unit |
|---|---|---:|---:|---:|---|
| BT | lake_rearing | 56585.4 | 56585.4 | +0 | ha |
| BT | rearing | 2306.49 | 2846.56 | +540.07 | km |
| BT | spawning | 926.76 | 1154.55 | +227.79 | km |
| BT | wetland_rearing | 6183.73 | 6183.73 | +0 | ha |
| CH | lake_rearing | 54581.4 | 54581.4 | +0 | ha |
| CH | rearing | 732.52 | 2088.21 | +1355.69 | km |
| CH | spawning | 362.12 | 497.69 | +135.57 | km |
| CH | wetland_rearing | 5796.4 | 5796.4 | +0 | ha |
| CO | lake_rearing | 54581.4 | 54581.4 | +0 | ha |
| CO | rearing | 1300.11 | 2333.43 | +1033.32 | km |
| CO | spawning | 843.52 | 1057.39 | +213.87 | km |
| CO | wetland_rearing | 5796.4 | 5796.4 | +0 | ha |
| RB | lake_rearing | NA | 50469.8 | NA | ha |
| RB | rearing | NA | 2247.76 | NA | km |
| RB | spawning | NA | 856.84 | NA | km |
| RB | wetland_rearing | NA | 4455.39 | NA | ha |
| SK | lake_rearing | 54581.4 | 54581.4 | +0 | ha |
| SK | rearing | 941.63 | 941.63 | +0 | km |
| SK | spawning | 57.63 | 1128.03 | +1070.4 | km |
| SK | wetland_rearing | 5796.4 | 5796.4 | +0 | ha |
| ST | lake_rearing | 54709 | 54709 | +0 | ha |
| ST | rearing | 912 | 2470.45 | +1558.45 | km |
| ST | spawning | 362.59 | 498.29 | +135.7 | km |
| ST | wetland_rearing | 5965.21 | 5965.21 | +0 | ha |

### ELKR

| Species | Habitat | bcfishpass | default | Δ | Unit |
|---|---|---:|---:|---:|---|
| BT | lake_rearing | 654.23 | 654.23 | +0 | ha |
| BT | rearing | 2079.01 | 2102.13 | +23.12 | km |
| BT | spawning | 1538.96 | 1590.16 | +51.2 | km |
| BT | wetland_rearing | 1019.72 | 1019.72 | +0 | ha |
| RB | lake_rearing | NA | 588.73 | NA | ha |
| RB | rearing | NA | 1826.56 | NA | km |
| RB | spawning | NA | 1407.91 | NA | km |
| RB | wetland_rearing | NA | 954.44 | NA | ha |
| WCT | lake_rearing | 703.01 | 703.01 | +0 | ha |
| WCT | rearing | 1895.09 | 2007.12 | +112.03 | km |
| WCT | spawning | 1578.84 | 1630.78 | +51.94 | km |
| WCT | wetland_rearing | 1039.64 | 1039.64 | +0 | ha |

### DEAD

| Species | Habitat | bcfishpass | default | Δ | Unit |
|---|---|---:|---:|---:|---|
| BT | lake_rearing | 638.92 | 638.92 | +0 | ha |
| BT | rearing | 291.07 | 312.43 | +21.36 | km |
| BT | spawning | 163.7 | 194.28 | +30.58 | km |
| BT | wetland_rearing | 524.09 | 524.09 | +0 | ha |
| CH | lake_rearing | 188.36 | 188.36 | +0 | ha |
| CH | rearing | 129.69 | 157.06 | +27.37 | km |
| CH | spawning | 110.55 | 122.49 | +11.94 | km |
| CH | wetland_rearing | 284.51 | 284.51 | +0 | ha |
| CO | lake_rearing | 188.36 | 188.36 | +0 | ha |
| CO | rearing | 164.68 | 172.54 | +7.86 | km |
| CO | spawning | 130.74 | 146.63 | +15.89 | km |
| CO | wetland_rearing | 284.51 | 284.51 | +0 | ha |
| PK | lake_rearing | 0 | 0 | +0 | ha |
| PK | rearing | 0 | 0 | +0 | km |
| PK | spawning | 131.92 | 146.94 | +15.02 | km |
| PK | wetland_rearing | 0 | 0 | +0 | ha |
| RB | lake_rearing | NA | 324.84 | NA | ha |
| RB | rearing | NA | 259.35 | NA | km |
| RB | spawning | NA | 157.12 | NA | km |
| RB | wetland_rearing | NA | 334.55 | NA | ha |
| SK | lake_rearing | 188.36 | 188.36 | +0 | ha |
| SK | rearing | 0 | 0 | +0 | km |
| SK | spawning | 0 | 0 | +0 | km |
| SK | wetland_rearing | 284.51 | 284.51 | +0 | ha |
| ST | lake_rearing | 324.38 | 324.38 | +0 | ha |
| ST | rearing | 151.83 | 207.24 | +55.41 | km |
| ST | spawning | 115.5 | 128.87 | +13.37 | km |
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

### 3. SK spawning inflates dramatically

Sockeye spawning km jump under `default` in every WSG that has SK
(ADMS +243 km, BULK +83 km, BABL +1070 km). Under bcfishpass, SK spawning
is restricted to lake-connected reaches via `spawn_connected` (only reaches
with downstream access to a rearing lake count). The `default` rules YAML
currently does not carry this connectivity rule through — all
gradient-passable reaches get flagged for SK spawning, not just the
lake-connected subset. BABL is the extreme case because SK spawning is
already heavily restricted there on the bcfishpass side (58 km baseline).

This is a known gap in the default bundle — the `spawn_connected` rule
needs to be expressed in `dimensions.csv` and emitted by `lnk_rules_build()`.
Blocked on `fresh#133`, same as the ADMS SK cluster.

### 4. RB is newly modeled under `default`

bcfishpass does not ship a `habitat_linear_rb` table. The `default` bundle
models RB (rainbow trout resident form) across all five WSGs via the
`default` dimensions CSV. Numbers are comparable to BT/ST rearing/spawning
in the same WSGs, which is the right order of magnitude.

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

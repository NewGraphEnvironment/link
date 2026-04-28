# Rule flexibility — three configs, one pipeline, one CSV

This page demonstrates that link's habitat classification methodology is fully expressed in `dimensions.csv` cells. Three different models are produced from the same pipeline by swapping a small set of cells per config:

| config | what it expresses |
|---|---|
| **Use case 1** (default bundle today) | linear `rearing_km` includes mainlines through L/W polygons; lake/wetland AREAS roll up via bucket flags |
| **Use case 2** | linear `rearing_km` excludes mainlines through L/W polygons; lake/wetland AREAS still roll up |
| **bcfishpass bundle** | strict partition matching bcfishpass's per-species access SQL; no polygon-area rollup at all |

The mechanism: stream-edge rules with `in_waterbody: false` (link#69 phase 1, [fresh#180](https://github.com/NewGraphEnvironment/fresh/issues/180)) plus L/W polygon rules with `area_only: true` ([fresh#182](https://github.com/NewGraphEnvironment/fresh/issues/182)) plus a `[1000, 1100]` mainlines edge filter on polygon rules. All three knobs surface as per-species columns:

- `rear_stream_in_waterbody` — `yes` = stream rule has no `in_waterbody` filter (matches inside AND outside polygons); `no` = stream rule emits `in_waterbody: false` (outside polygons only).
- `rear_lake_area_only` — `yes` = L polygon rule emits `area_only: true` (drives `lake_rearing` bucket flag only, excluded from main rear); `no` = L rule contributes to both.
- `rear_wetland_area_only` — same shape on the W rule.
- `rear_wetland_polygon` — emit the W polygon rule at all?

## The matrix

The three configs differ only in the cells listed below for the rear path. Spawning rules, gradient/cw thresholds, fresh barriers, breaks, observations — all identical across configs.

| species cohort | dial | use case 1 (default) | use case 2 | bcfishpass |
|---|---|---|---|---|
| rear_wetland=yes, rear_lake=yes species | `rear_stream_in_waterbody` | yes | **no** | **no** |
| | `rear_lake_area_only` | no | **yes** | no |
| | `rear_wetland_area_only` | no | **yes** | no |
| | `rear_lake` | yes | yes | **no** |
| | `rear_wetland_polygon` | yes | yes | **no** |

Bold cells are the flips from default. SK / KO are exempt (they're `rear_lake_only` species — the L rule is the rear classification, must continue matching the whole lake polygon).

## What the pipeline produces

BABL × CO under each config. Rollup numbers from `compare_bcfishpass_wsg("BABL", cfg)`:

| habitat | unit | use_case_1 | use_case_2 | bcfishpass |
| --- | --- | --- | --- | --- |
| spawning | km | 817.32 | 817.32 | 817.32 |
| rearing | km | 1388.90 | 1271.02 | 1271.02 |
| lake_rearing | ha | 54507.85 | 54507.85 | 0.00 |
| wetland_rearing | ha | 5786.74 | 5786.74 | 0.00 |

**bcfishpass parity** (bcfishpass.habitat_linear_co reference, identical for all configs):


| habitat | bcfp_value (km) | uc1 diff_pct | uc2 diff_pct | bcfp diff_pct |
| --- | --- | --- | --- | --- |
| spawning | 805.15 | +1.5% | +1.5% | +1.5% |
| rearing | 1289.90 | +7.7% | -1.5% | -1.5% |

The bcfishpass column also reports the parity comparison number (`diff_pct` against `bcfishpass.habitat_linear_co`). The other two configs are NewGraph methodology — no parity claim.

## Rules.yaml — the CO `rear` block per config

Generated from `dimensions.csv` via `lnk_rules_build()`. The diff between configs is the durable proof: every model decision lives in a CSV cell, not in code.

**use_case_1**

```yaml
CO:
  rear:
  - edge_types_explicit:
    - 1000
    - 1100
    - 2000
    - 2300
  - waterbody_type: R
    channel_width:
    - 0.0
    - 9999.0
  - edge_types_explicit:
    - 1050
    - 1150
    thresholds: no
  - waterbody_type: W
    edge_types_explicit:
    - 1000
    - 1100
    wetland_ha_min: 0.5
  - waterbody_type: L
    edge_types_explicit:
    - 1000
    - 1100
    lake_ha_min: 2.0
```

**use_case_2**

```yaml
CO:
  rear:
  - edge_types_explicit:
    - 1000
    - 1100
    - 2000
    - 2300
    in_waterbody: no
  - waterbody_type: R
    channel_width:
    - 0.0
    - 9999.0
  - edge_types_explicit:
    - 1050
    - 1150
    thresholds: no
  - waterbody_type: W
    edge_types_explicit:
    - 1000
    - 1100
    wetland_ha_min: 0.5
    area_only: yes
  - waterbody_type: L
    edge_types_explicit:
    - 1000
    - 1100
    lake_ha_min: 2.0
    area_only: yes
```

**bcfishpass**

```yaml
CO:
  rear:
  - edge_types_explicit:
    - 1000
    - 1100
    - 2000
    - 2300
    in_waterbody: no
  - waterbody_type: R
    channel_width:
    - 0.0
    - 9999.0
  - edge_types_explicit:
    - 1050
    - 1150
    thresholds: no
```


## How to reproduce

```bash
Rscript data-raw/rule_flexibility_demo.R
Rscript data-raw/rule_flexibility_render.R
```

The demo script clones the default config to a temp dir per use case, swaps the cells listed above, regenerates `rules.yaml`, refreshes provenance checksums, and runs `compare_bcfishpass_wsg("BABL", cfg)`. Output is captured to `research/rule_flexibility_data.rds`. The render script reads the rds and substitutes the rollup table + rules.yaml diffs into this markdown's placeholder comments.

## Why this matters

bcfishpass models the same partition logic, but as `WHERE` clauses inside per-species access SQL templates. To audit a model variant, a reader has to read the SQL. link surfaces the same partition logic as a CSV table — readable in a spreadsheet, diffable in git. A new model variant is a CSV edit and a `lnk_rules_build()` invocation; no code change.

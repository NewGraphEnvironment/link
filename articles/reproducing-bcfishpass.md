# Reproducing bcfishpass with link + fresh

[bcfishpass](https://github.com/smnorris/bcfishpass) is the reference
model for freshwater habitat classification and fish passage
prioritization in British Columbia. link +
[fresh](https://newgraphenvironment.github.io/fresh/) provide a
configurable, reproducible R-side pipeline. The bundled `"bcfishpass"`
config reproduces bcfishpass’s classification method. Other configs can
express other methods; the package is method-agnostic.

This vignette walks through what the bcfishpass configuration does, how
to run it, and how the output compares to bcfishpass reference tables.
Full per-phase pipeline detail lives in
[`research/bcfishpass_comparison.md`](https://github.com/NewGraphEnvironment/link/blob/main/research/bcfishpass_comparison.md).

## How the bcfishpass configuration works

The rollup measures **intrinsic habitat potential conditioned on
accessibility**. Intrinsic potential is a segment’s fit to per-species
habitat rules (edge type, waterbody, channel width, gradient).
Accessibility is whether fish can reach the segment without crossing a
blocking natural barrier. bcfishpass records intrinsic classification on
every segment, together with labels that name the downstream obstacles
blocking it. The rollup in this vignette aggregates only the subset that
is both intrinsically suitable *and* accessible — accessibility and
intrinsic potential are separable in general, and a fuller treatment
would report both.

    FWA streams (raw)
        │
        │   gradient thresholds detect barriers @ 15 / 20 / 25 / 30 %
        ▼
    gradient barriers ─── falls ─── user-identified definite barriers
        │
        │   observations override natural barriers per access model
        ▼
    access model per species
        │
        │   break positions = observations + minimal gradient barriers
        │                     + habitat classification endpoints + crossings
        ▼
    segmented streams (every segment ends where a rule decision can change)
        │
        │   per-species rules from rules.yaml
        │     edge type • waterbody type • channel width • gradient
        ▼
    classify (spawning ? rearing ? per species per segment)
        │
        │   frs_cluster for rearing-spawning connectivity;
        │   connected-waterbody rules for SK
        ▼
    streams_habitat (per-species spawning / rearing booleans per segment)

### Where breaks go, and why

A break is a point where one segment ends and the next begins. Every
segment is one classification unit. Breaks therefore fall at positions
where the decision can change:

- **Observations.** bcfishpass’s per-species access models flip a
  natural-barrier reach to accessible when the count of fish
  observations on the upstream flow path meets a threshold. Thresholds
  and species filters vary per model (see the SQL under
  [`model/access/`](https://github.com/smnorris/bcfishpass/tree/ea3c5d8/model)).
  Per-species parameters used by link live in the bundled `"bcfishpass"`
  config’s
  [`parameters_fresh.csv`](https://github.com/NewGraphEnvironment/link/blob/main/inst/extdata/configs/bcfishpass/parameters_fresh.csv)
  (`observation_threshold`, `observation_date_min`,
  `observation_buffer_m`, `observation_species`). For BULK (bcfishpass
  commit `ea3c5d8`):

  - BT — ≥ 1 observation of BT, CH, CM, CO, PK, SK, or ST; any date
  - CH / CM / CO / PK / SK — ≥ 5 observations in that salmon set, on or
    after 1990-01-01
  - ST — ≥ 5 observations of CH, CM, CO, PK, SK, or ST, on or after
    1990-01-01
  - WCT — ≥ 1 observation of WCT; any date

- **Minimal gradient barriers.** On any flow path with multiple gradient
  barriers, only the downstream-most matters for access — everything
  upstream is already blocked by it. The pipeline reduces to the minimal
  set per species-class (via
  [`fresh::frs_barriers_minimal()`](https://newgraphenvironment.github.io/fresh/reference/frs_barriers_minimal.html))
  so segmentation doesn’t split reaches that would end up in the same
  access state.

- **Habitat classification endpoints** — manual spawning / rearing
  delineations from bcfishpass’s
  [`user_habitat_classification.csv`](https://github.com/smnorris/bcfishpass/blob/ea3c5d8/data/user_habitat_classification.csv)
  (mirrored at
  [`inst/extdata/configs/bcfishpass/overrides/user_habitat_classification.csv`](https://github.com/NewGraphEnvironment/link/blob/main/inst/extdata/configs/bcfishpass/overrides/user_habitat_classification.csv)).
  Each row records `blue_line_key`, `downstream_route_measure`,
  `upstream_route_measure`, `species_code`, and `habitat_ind`. Breaks
  are placed at both measures so the marked reach is its own segment.

- **Crossings** — road, rail, and utility crossings carrying
  `barrier_status` of `PASSABLE`, `POTENTIAL`, or `BARRIER`. Their
  per-segment status is applied but does not alter the natural-access
  model.

### Where classification comes from

Once segmented, each segment is checked against the per-species rules in
[`rules.yaml`](https://github.com/NewGraphEnvironment/link/blob/main/inst/extdata/configs/bcfishpass/rules.yaml).
The YAML is generated from
[`dimensions.csv`](https://github.com/NewGraphEnvironment/link/blob/main/inst/extdata/configs/bcfishpass/dimensions.csv)
via
[`lnk_rules_build()`](https://newgraphenvironment.github.io/link/reference/lnk_rules_build.md).

Top-level keys are species codes. `spawn:` and `rear:` are lists of
alternative match conditions — any match marks the segment. Conditions
combine:

- `edge_types_explicit` — FWA `edge_type` integer codes (1000 / 1100
  stream, 2000 / 2300 river, 1050 / 1150 wetland, 1200 lake). Membership
  is a per-species decision recorded in the rules file.
- `waterbody_type` — `R` river polygon, `L` lake.
- `channel_width` — `[min, max]` metres.
- Gradient bounds for spawning and rearing (via `parameters_fresh.csv`
  and fresh’s thresholds CSV).

### Stream-order bypass — not applied in this config

bcfishpass applies a rearing-side bypass on the channel-width minimum
for BT / CH / CO / ST / WCT when a first-order stream’s parent is order
≥ 5. The bundled `"bcfishpass"` config does not apply that bypass.
Numeric impact and the reasoning are in
[`research/bcfishpass_comparison.md`](https://github.com/NewGraphEnvironment/link/blob/main/research/bcfishpass_comparison.md).

## Running the pipeline

``` r
library(link)
library(targets)

# `_targets.R` lives in data-raw/; run from that directory.
setwd("data-raw")

tar_make()                  # 4 WSGs, serial
rollup <- tar_read(rollup)  # per-WSG × species × habitat tibble
```

[`tar_make()`](https://docs.ropensci.org/targets/reference/tar_make.html)
runs
[`compare_bcfishpass_wsg()`](https://github.com/NewGraphEnvironment/link/blob/main/data-raw/compare_bcfishpass_wsg.R)
once per watershed group (ADMS, BULK, BABL, ELKR). Each call exercises
the six `lnk_pipeline_*` phases and returns a small tibble.

    lnk_config("bcfishpass") ─┬─► comparison_ADMS ─┐
                              ├─► comparison_BULK ─┤
                              ├─► comparison_BABL ─┼─► rollup (34 rows)
                              └─► comparison_ELKR ─┘

## The rollup

``` r
rollup <- readRDS(system.file("extdata", "vignette-data", "rollup.rds",
                               package = "link"))
```

``` r
summary(rollup$diff_pct)
#>    Min. 1st Qu.  Median    Mean 3rd Qu.    Max.    NA's 
#>  -2.800  -0.100   1.600   1.294   3.100   4.800       1
cat("Within 5%: ",
    all(abs(rollup$diff_pct[!is.na(rollup$diff_pct)]) < 5))
#> Within 5%:  TRUE
```

Columns:

- `link_km` — kilometres classified as habitat (spawning or rearing,
  conditioned on accessibility) per species × watershed group
- `bcfishpass_km` — kilometres from bcfishpass reference
  `habitat_linear_*` tables
- `diff_pct` — `(link_km − bcfishpass_km) / bcfishpass_km × 100`

Observed differences come from the stream-order bypass omission (notable
on BT rearing in BULK) and from segmentation-boundary rounding where
per-segment attributes fall near rule thresholds. Numeric detail is in
[`research/bcfishpass_comparison.md`](https://github.com/NewGraphEnvironment/link/blob/main/research/bcfishpass_comparison.md).

## Comparison map — Neexdzii Kwa (Upper Bulkley)

The watershed upstream of the Neexdzii Kwa / Wetzin Kwa (Bulkley /
Morice) confluence, built via
`FWA_WatershedAtMeasure(360873822, 166030.4)`. Sits inside the BULK
watershed group, so the BULK rollup above aggregates this area along
with the rest of the Bulkley.

The link pipeline layer is visible by default; toggle on the bcfishpass
reference layer to compare.

``` r
sub_ch      <- readRDS(system.file("extdata", "vignette-data",
                                    "sub_ch.rds", package = "link"))
sub_ch_bcfp <- readRDS(system.file("extdata", "vignette-data",
                                    "sub_ch_bcfp.rds", package = "link"))

if (requireNamespace("mapgl", quietly = TRUE)) {
  pal_values <- c("spawning only", "rearing only", "spawning + rearing")
  pal_colors <- c("#e31a1c", "#1f78b4", "#6a3d9a")

  mapgl::maplibre(
    bounds = sf::st_bbox(sub_ch),
    style = mapgl::carto_style("positron")
  ) |>
    mapgl::add_line_layer(
      id = "bcfishpass",
      source = sub_ch_bcfp,
      line_color = mapgl::match_expr("habitat",
        values = pal_values, stops = pal_colors, default = "#999999"),
      line_width = 3,
      line_opacity = 0.6,
      visibility = "none"
    ) |>
    mapgl::add_line_layer(
      id = "link",
      source = sub_ch,
      line_color = mapgl::match_expr("habitat",
        values = pal_values, stops = pal_colors, default = "#999999"),
      line_width = 2
    ) |>
    mapgl::add_legend(
      "Neexdzii Kwa (Upper Bulkley) · modelled chinook habitat",
      values = pal_values,
      colors = pal_colors,
      type = "categorical"
    ) |>
    mapgl::add_layers_control(
      collapsible = TRUE,
      position    = "top-left"
    )
} else {
  message("Install `mapgl` (pak::pak('mapgl')) to render this map.")
}
```

## Reproducibility

The pipeline is deterministic. Two
[`tar_make()`](https://docs.ropensci.org/targets/reference/tar_make.html)
invocations on the same fwapg + bcfishobs state produce bit-identical
rollups. When input data shifts — a `channel_width` sync, new
observations loaded into `bcfishobs`, a bcfishpass reference refresh —
outputs will correctly differ.

## Further reading

- [`research/bcfishpass_comparison.md`](https://github.com/NewGraphEnvironment/link/blob/main/research/bcfishpass_comparison.md)
  — per-phase pipeline DAG, parity numbers, documented gaps
- [`?lnk_pipeline_setup`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md)
  /
  [`?lnk_pipeline_load`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md)
  /
  [`?lnk_pipeline_prepare`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md)
  /
  [`?lnk_pipeline_break`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md)
  /
  [`?lnk_pipeline_classify`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md)
  /
  [`?lnk_pipeline_connect`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md)
  — phase helper reference
- [`?lnk_config`](https://newgraphenvironment.github.io/link/reference/lnk_config.md)
  — config bundle structure
- [`inst/extdata/configs/bcfishpass/`](https://github.com/NewGraphEnvironment/link/tree/main/inst/extdata/configs/bcfishpass)
  — bundled config (rules YAML, dimensions CSV, per-species parameters,
  overrides)
- [`data-raw/_targets.R`](https://github.com/NewGraphEnvironment/link/blob/main/data-raw/_targets.R)
  — pipeline definition
- [`data-raw/compare_bcfishpass_wsg.R`](https://github.com/NewGraphEnvironment/link/blob/main/data-raw/compare_bcfishpass_wsg.R)
  — per-AOI target function

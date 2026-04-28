# Modelling spawning and rearing habitat using bcfishpass defaults

This vignette documents link’s reproduction of
[bcfishpass](https://github.com/smnorris/bcfishpass)’s linear habitat
classification — per-segment spawning and rearing booleans, conditioned
on natural accessibility — for the species present in five British
Columbia watershed groups (ADMS, BULK, BABL, ELKR, DEAD).

The bundled
[`"bcfishpass"`](https://github.com/NewGraphEnvironment/link/tree/main/inst/extdata/configs/bcfishpass)
config encodes bcfishpass’s per-species rules and override CSVs as a
self-contained input. Per-phase pipeline detail lives in
[`research/bcfishpass_comparison.md`](https://github.com/NewGraphEnvironment/link/blob/main/research/bcfishpass_comparison.md).

## Prerequisites

Required:

- A PostgreSQL database with [fwapg](https://github.com/smnorris/fwapg)
  loaded — `wscode_ltree` / `localcode_ltree` columns on the FWA stream
  network plus the `fwa_upstream` / `fwa_downstream` /
  `fwa_watershedatmeasure` SQL functions the pipeline uses.
- [bcfishobs](https://github.com/smnorris/bcfishobs) populating
  `bcfishobs.observations`. The bcfishpass bundle’s `break_order` starts
  with `observations`, and `lnk_barrier_overrides` uses observations to
  skip natural barriers where fish have been recorded upstream. Without
  it, segmentation and access both diverge from bcfishpass and the
  parity claim doesn’t hold.

Optional (for the comparison map at the bottom of this vignette only):

- A read-only tunnel to a bcfishpass reference database. Not needed to
  run link.

## Running the pipeline

Six `lnk_pipeline_*` phase calls driven by an
[`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md)
bundle. Each phase writes to a working schema in PostgreSQL; the final
`fresh.streams_habitat` table holds per-segment booleans for `spawning`,
`rearing`, `lake_rearing`, and `wetland_rearing`, per species.

``` r
library(link)
library(DBI)

conn   <- lnk_db_conn()
cfg    <- lnk_config("bcfishpass")
schema <- "working_bulk"

lnk_pipeline_setup(   conn,                  schema, overwrite = TRUE)
lnk_pipeline_load(    conn, aoi = "BULK", cfg = cfg, schema)
lnk_pipeline_prepare( conn, aoi = "BULK", cfg = cfg, schema)
lnk_pipeline_break(   conn, aoi = "BULK", cfg = cfg, schema)
lnk_pipeline_classify(conn, aoi = "BULK", cfg = cfg, schema)
lnk_pipeline_connect( conn, aoi = "BULK", cfg = cfg, schema)
```

Run the same six phases per AOI to build a province-wide picture, or
plug them into a `targets` pipeline as
[`data-raw/_targets.R`](https://github.com/NewGraphEnvironment/link/blob/main/data-raw/_targets.R)
does for cross-WSG regression — Adams (ADMS), Bulkley (BULK), Babine
(BABL), Elk (ELKR), and Deadman (DEAD), binding per-WSG tibbles into one
rollup.

## The rollup

``` r
rollup <- readRDS(system.file("extdata", "vignette-data", "rollup.rds",
                               package = "link"))
```

Percent difference between link’s classification and bcfishpass’s
published `streams_habitat_linear` integer table (model + known habitat
combined) per species × watershed group.
`diff_pct = (link_km − bcfishpass_km) / bcfishpass_km × 100`. Negative =
link under, positive = link over. NA = species not in bcfishpass’s
published output.

``` r
.pivot <- function(rollup, which_habitat) {
  x <- rollup[rollup$config == "bcfishpass" &
              rollup$habitat_type == which_habitat,
              c("species", "wsg", "diff_pct")]
  w <- stats::reshape(x, idvar = "species", timevar = "wsg",
                       direction = "wide", v.names = "diff_pct")
  names(w)[-1] <- sub("diff_pct\\.", "", names(w)[-1])
  cols <- intersect(c("species", "ADMS", "BULK", "BABL", "ELKR", "DEAD"),
    names(w))
  w <- w[order(w$species), cols]
  row.names(w) <- NULL
  w
}

knitr::kable(.pivot(rollup, "spawning"),
  digits = 1,
  caption = "Spawning parity (% diff vs bcfishpass)")
```

| species | ADMS | BULK | BABL | ELKR | DEAD |
|:--------|-----:|-----:|-----:|-----:|-----:|
| BT      |  0.2 |  1.3 |  1.1 |  2.3 |  1.0 |
| CH      |  0.0 |  0.9 |  1.3 |    — |  0.3 |
| CO      |  0.0 |  1.2 |  1.5 |    — |  0.1 |
| PK      |    — |  0.6 |    — |    — |  0.1 |
| SK      |  1.1 | -3.5 | -3.8 |    — |    — |
| ST      |    — |  0.9 |  1.3 |    — |  0.2 |
| WCT     |    — |    — |    — |  2.2 |    — |

Spawning parity (% diff vs bcfishpass)

``` r

knitr::kable(.pivot(rollup, "rearing"),
  digits = 1,
  caption = "Rearing parity (% diff vs bcfishpass)")
```

| species | ADMS | BULK | BABL | ELKR | DEAD |
|:--------|-----:|-----:|-----:|-----:|-----:|
| BT      | -1.1 | -2.3 | -1.8 | -1.2 | -0.2 |
| CH      |  0.0 |  0.0 | -1.7 |    — |  0.0 |
| CO      | -2.0 | -1.6 | -1.7 |    — | -1.4 |
| PK      |    — |    — |    — |    — |    — |
| SK      |  0.0 |  0.0 |  0.0 |    — |    — |
| ST      |    — | -2.8 | -5.0 |    — | -1.3 |
| WCT     |    — |    — |    — | -0.2 |    — |

Rearing parity (% diff vs bcfishpass)

All 42 non-NA rows within ±5% of bcfishpass; 35 of 42 within ±2%; median
1.1%; max 5.0%. Residual deltas come from segmentation-boundary rounding
(per-segment attributes near rule thresholds end up on different sides
of the threshold) and a small rearing-side stream-order bypass that’s a
documented future addition.

## Comparison map — Neexdzii Kwa (Upper Bulkley)

The watershed upstream of the Neexdzii Kwa / Wetzin Kwa (Bulkley /
Morice) confluence, built via
`FWA_WatershedAtMeasure(360873822, 166030.4)`. Inside the BULK watershed
group; the BULK rollup above aggregates this area along with the rest of
the Bulkley. The map below visualizes the spawning/rearing slice for
chinook (CH) — the simplest cut available; per-species ha rollups,
lake/wetland decomposition, and other species are also in
`fresh.streams_habitat`. The link layer is visible by default; toggle on
the bcfishpass reference layer to compare.

``` r
sub_ch      <- readRDS(system.file("extdata", "vignette-data",
                                    "sub_ch.rds", package = "link"))
sub_ch_bcfp <- readRDS(system.file("extdata", "vignette-data",
                                    "sub_ch_bcfp.rds", package = "link"))

if (requireNamespace("mapgl", quietly = TRUE)) {
  # No spawning-only CH segments occur in the Neexdzii Kwa AOI
  # (CH spawning lives on segments that also support rearing here).
  # Drop the unused legend entry — spawning-only segments would still
  # render as grey defaults via `match_expr` if any appeared.
  pal_values <- c("rearing only", "spawning + rearing")
  pal_colors <- c("#1f78b4", "#6a3d9a")

  # mapgl::add_line_layer's popup argument takes a column name. Pre-
  # build a per-segment HTML string in `popup_html` on each side; the
  # rendered map shows that column's value when a segment is clicked.
  # The IDs let a reader QA either side of the comparison by segment.
  fmt_popup <- function(d, header, id_col) {
    paste0(
      "<b>", header, "</b><br>",
      id_col, ": ", d[[id_col]], "<br>",
      "blue_line_key: ", d$blue_line_key, "<br>",
      "downstream_route_measure: ", d$downstream_route_measure, "<br>",
      "length_metre: ", d$length_metre, "<br>",
      "gnis_name: ", ifelse(is.na(d$gnis_name), "—", d$gnis_name), "<br>",
      "habitat: ", d$habitat)
  }
  sub_ch$popup_html      <- fmt_popup(sub_ch, "link", "id_segment")
  sub_ch_bcfp$popup_html <- fmt_popup(sub_ch_bcfp, "bcfishpass",
                                      "segmented_stream_id")

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
      visibility = "none",
      popup = "popup_html"
    ) |>
    mapgl::add_line_layer(
      id = "link",
      source = sub_ch,
      line_color = mapgl::match_expr("habitat",
        values = pal_values, stops = pal_colors, default = "#999999"),
      line_width = 2,
      popup = "popup_html"
    ) |>
    mapgl::add_legend(
      "Neexdzii Kwa (Upper Bulkley) · modelled chinook habitat",
      values = pal_values,
      colors = pal_colors,
      type = "categorical",
      position = "top-right"
    ) |>
    mapgl::add_layers_control(
      collapsible = TRUE,
      position    = "top-left"
    ) |>
    mapgl::add_fullscreen_control(position = "top-right")
} else {
  message("Install `mapgl` (pak::pak('mapgl')) to render this map.")
}
```

## See also

- [`research/bcfishpass_comparison.md`](https://github.com/NewGraphEnvironment/link/blob/main/research/bcfishpass_comparison.md)
  — per-phase pipeline DAG, where breaks go, where classification comes
  from, known-habitat overlay, stream-order bypass, parity numbers
- [`research/rule_flexibility.md`](https://github.com/NewGraphEnvironment/link/blob/main/research/rule_flexibility.md)
  — proof artifact: BABL × CO under three configs (use case 1, use case
  2, bcfishpass) by swapping only `dimensions.csv` cells
- [`inst/extdata/configs/bcfishpass/`](https://github.com/NewGraphEnvironment/link/tree/main/inst/extdata/configs/bcfishpass)
  — bundled config (rules YAML, dimensions CSV, per-species parameters,
  overrides)
- [`inst/extdata/configs/dimensions_columns.csv`](https://github.com/NewGraphEnvironment/link/blob/main/inst/extdata/configs/dimensions_columns.csv)
  — column dictionary for `dimensions.csv` (every per-species knob
  documented: type, group, default, what it emits in `rules.yaml`,
  related fresh issue).
- [`?lnk_config`](https://newgraphenvironment.github.io/link/reference/lnk_config.md),
  [`?lnk_pipeline_setup`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md)
  and family — function reference

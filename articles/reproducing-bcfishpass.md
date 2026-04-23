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

## Prerequisites

The pipeline reads from a PostgreSQL database with
[fwapg](https://github.com/smnorris/fwapg) loaded. fwapg is the
processed form of the BC Freshwater Atlas — it adds `wscode_ltree` and
`localcode_ltree` columns to the stream-network tables (PostgreSQL
`ltree` types encoding watershed topology) and provides the SQL
functions the pipeline uses to traverse the network:
[`fwa_upstream`](https://github.com/smnorris/fwapg/blob/main/sql/functions/FWA_Upstream.sql),
[`fwa_downstream`](https://github.com/smnorris/fwapg/blob/main/sql/functions/FWA_Downstream.sql),
[`fwa_watershedatmeasure`](https://github.com/smnorris/fwapg/blob/main/sql/functions/FWA_WatershedAtMeasure.sql),
and others. See fwapg’s repository for installation.

[bcfishobs](https://github.com/smnorris/bcfishobs) is optional but
recommended — it populates `bcfishobs.observations`, the table that
drives per-species overrides of natural barriers below.

The comparison layer in the map at the end of this vignette reads from a
read-only tunnel to the bcfishpass reference database. That is a
validation convenience, not a requirement for running link.

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

    FWA stream network (via fwapg, ltree-enriched)
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
  natural-barrier reach (gradient barrier, falls, or user-definite
  barrier) to accessible when the count of upstream fish observations
  meets a threshold. Thresholds and species filters vary per model (see
  the SQL under
  [`model/access/`](https://github.com/smnorris/bcfishpass/tree/ea3c5d8/model)).
  Per-species parameters used by link live in the bundled `"bcfishpass"`
  config’s
  [`parameters_fresh.csv`](https://github.com/NewGraphEnvironment/link/blob/main/inst/extdata/configs/bcfishpass/parameters_fresh.csv)
  (`observation_threshold`, `observation_date_min`,
  `observation_buffer_m`, `observation_species`). Override counting is
  done in SQL via
  [`fwa_upstream`](https://github.com/smnorris/fwapg/blob/main/sql/functions/FWA_Upstream.sql)
  by `lnk_barrier_overrides`. For BULK (bcfishpass commit `ea3c5d8`):

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

- **User-identified definite barriers** — positions listed in
  bcfishpass’s
  [`user_barriers_definite.csv`](https://github.com/smnorris/bcfishpass/blob/ea3c5d8/data/user_barriers_definite.csv)
  (mirrored at
  [`inst/extdata/configs/bcfishpass/overrides/user_barriers_definite.csv`](https://github.com/NewGraphEnvironment/link/blob/main/inst/extdata/configs/bcfishpass/overrides/user_barriers_definite.csv)).
  Each row specifies `blue_line_key` and `downstream_route_measure` for
  a barrier that always blocks access. Treated the same as falls —
  always-blocking, always a break position, eligible for per-species
  override via `lnk_barrier_overrides` when enough upstream observations
  clear the threshold.

- **Habitat classification endpoints** — manual spawning / rearing
  delineations from bcfishpass’s
  [`user_habitat_classification.csv`](https://github.com/smnorris/bcfishpass/blob/ea3c5d8/data/user_habitat_classification.csv)
  (mirrored at
  [`inst/extdata/configs/bcfishpass/overrides/user_habitat_classification.csv`](https://github.com/NewGraphEnvironment/link/blob/main/inst/extdata/configs/bcfishpass/overrides/user_habitat_classification.csv)).
  Each row records `blue_line_key`, `downstream_route_measure`,
  `upstream_route_measure`, `species_code`, and `habitat_ind`. Breaks
  are placed at both measures so the marked reach is its own segment.

- **Crossings** — road, rail, and utility crossings carrying
  `barrier_status` of `PASSABLE`, `POTENTIAL`, `BARRIER`, or `UNKNOWN`.
  Each crossing at a distinct position gets its own segment boundary so
  habitat upstream of each can be attributed to it.

Natural accessibility — gradient barriers, falls, and user-definite
barriers — is the only gate in this configuration. Crossings are
segmentation boundaries here, not access blockers: a segment upstream of
a `BARRIER`-status crossing stays classified on its intrinsic rule
match, so rollup kilometres are not reduced by crossings. A different
composition (same pipeline, `label_block = c("blocked", "barrier")`)
answers the distinct question of what habitat would be accessible if
anthropogenic barriers were fixed — worth a separate rollup.

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

tar_make()                  # 5 WSGs, serial
rollup <- tar_read(rollup)  # per-WSG × species × habitat tibble
```

[`tar_make()`](https://docs.ropensci.org/targets/reference/tar_make.html)
runs
[`compare_bcfishpass_wsg()`](https://github.com/NewGraphEnvironment/link/blob/main/data-raw/compare_bcfishpass_wsg.R)
once each for Adams (ADMS), Bulkley (BULK), Babine (BABL), Elk (ELKR),
and Deadman (DEAD), binding the per-WSG tibbles into one rollup. Each
call exercises the six `lnk_pipeline_*` phases. ADMS/BULK/ BABL/ELKR
span the species assemblages used in bcfishpass validation — BT with CH,
CO, SK on ADMS; PK and ST added on BULK and BABL; BT with WCT on ELKR.
DEAD is an end-to-end test for the `barriers_definite_control` wiring:
it has a single `barrier_ind = TRUE` control row with enough anadromous
observations upstream to exercise the filter, which the other four WSGs
don’t. Method agreement across this spread is stronger evidence than
agreement on a single WSG.

## The rollup

``` r
rollup <- readRDS(system.file("extdata", "vignette-data", "rollup.rds",
                               package = "link"))
```

`link_km` and `bcfishpass_km` are kilometres classified as habitat
(spawning or rearing, conditioned on natural accessibility) per species
× watershed group.
`diff_pct = (link_km − bcfishpass_km) / bcfishpass_km × 100`.

``` r
.pivot <- function(rollup, which_habitat) {
  x <- rollup[rollup$habitat_type == which_habitat,
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
| BT      |  1.8 |  3.1 |  4.1 |  3.4 |  2.1 |
| CH      |  0.5 |  1.9 |  3.8 |    — |  1.4 |
| CO      |  1.6 |  3.1 |  4.8 |    — |  1.3 |
| PK      |    — |  2.3 |    — |    — |  1.1 |
| SK      |  3.7 | -0.7 | -2.8 |    — |    — |
| ST      |    — |  1.9 |  3.8 |    — |  1.3 |
| WCT     |    — |    — |    — |  4.0 |    — |

Spawning parity (% diff vs bcfishpass)

``` r

knitr::kable(.pivot(rollup, "rearing"),
  digits = 1,
  caption = "Rearing parity (% diff vs bcfishpass)")
```

| species | ADMS | BULK | BABL | ELKR | DEAD |
|:--------|-----:|-----:|-----:|-----:|-----:|
| BT      | -1.1 | -2.2 | -1.9 | -0.7 | -0.2 |
| CH      |  2.3 |  2.6 |  2.1 |    — |  1.4 |
| CO      | -0.1 |  0.4 |  0.8 |    — | -0.3 |
| PK      |    — |    — |    — |    — |    — |
| SK      |  0.0 |  0.0 |  0.0 |    — |    — |
| ST      |    — | -0.1 | -1.3 |    — |  0.0 |
| WCT     |    — |    — |    — |  1.6 |    — |

Rearing parity (% diff vs bcfishpass)

Observed differences come from the stream-order bypass omission —
visible as the uniformly negative BT rearing column — and from
segmentation-boundary rounding where per-segment attributes fall near
rule thresholds. Numeric detail is in
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
      type = "categorical",
      position = "top-right"
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

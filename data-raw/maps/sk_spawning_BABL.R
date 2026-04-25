suppressPackageStartupMessages({
  library(sf); library(mapgl); library(dplyr)
})
sf_use_s2(FALSE)

base <- "/Users/airvine/Projects/repo/link/data-raw/maps"
d    <- file.path(base, "data")

streams_all <- readRDS(file.path(d, "streams_babl.rds")) |>
  st_transform(4326) |> st_zm()
lakes       <- readRDS(file.path(d, "lakes_babl.rds")) |>
  st_transform(4326) |> st_zm()
sk_default  <- readRDS(file.path(d, "sk_babl_default.rds")) |>
  st_transform(4326) |> st_zm()
sk_bcfp     <- readRDS(file.path(d, "sk_babl_bcfp.rds")) |>
  st_transform(4326) |> st_zm()

et_lookup <- fresh::frs_edge_types() |>
  select(edge_type, edge_desc = description)

# id_segment is regenerated per-pipeline-run and is NOT comparable across
# config runs — classify overlap spatially via ~20m buffer intersect.
bcfp_buf    <- st_union(st_buffer(sk_bcfp, 0.00018))
default_buf <- st_union(st_buffer(sk_default, 0.00018))

sk_default$category <- ifelse(
  lengths(st_intersects(sk_default, bcfp_buf)) > 0,
  "both", "default_only")
sk_bcfp$category <- ifelse(
  lengths(st_intersects(sk_bcfp, default_buf)) > 0,
  "both", "bcfishpass_only")

mk_label <- function(df, tag) {
  df |>
    left_join(et_lookup, by = "edge_type") |>
    mutate(label = paste0(
      "id_segment: ", id_segment,
      " | edge ", edge_type, " (", edge_desc, ")",
      " | gradient ", formatC(gradient, format = "f", digits = 4),
      " | ", round(length_metre), " m | ", tag))
}

sk_combined <- bind_rows(
  sk_bcfp    |> filter(category == "bcfishpass_only") |> mk_label("bcfishpass-only"),
  sk_default |> filter(category == "default_only")    |> mk_label("default-only"),
  sk_default |> filter(category == "both")            |> mk_label("both")
)

pal_values <- c("bcfishpass_only", "default_only", "both")
pal_colors <- c("#1f78b4",        "#e31a1c",      "#6a3d9a")
pal_labels <- c("bcfishpass only", "default only", "both")

bbox <- st_bbox(sk_combined)

m <- maplibre(bounds = bbox, style = carto_style("positron")) |>
  add_fill_layer(
    id = "lakes",
    source = lakes,
    fill_color = "#a6cee3",
    fill_opacity = 0.5,
    popup = "gnis_name"
  ) |>
  add_line_layer(
    id = "streams_all",
    source = streams_all,
    line_color = "#bbbbbb",
    line_width = 0.5,
    line_opacity = 0.6,
    visibility = "visible"
  ) |>
  add_line_layer(
    id = "sk_spawning",
    source = sk_combined,
    line_color = match_expr("category",
      values = pal_values, stops = pal_colors, default = "#999999"),
    line_width = 3,
    line_opacity = 0.85,
    popup = "label"
  ) |>
  add_legend(
    "SK spawning — BABL · default vs bcfishpass",
    values = pal_labels,
    colors = pal_colors,
    type = "categorical",
    position = "top-right"
  ) |>
  add_layers_control(
    collapsible = TRUE,
    position    = "top-left"
  )

out_html <- file.path(base, "sk_spawning_BABL.html")
htmlwidgets::saveWidget(m, out_html, selfcontained = TRUE)
cat("wrote", out_html, "\n")

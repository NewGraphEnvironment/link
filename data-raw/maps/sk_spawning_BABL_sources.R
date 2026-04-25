suppressPackageStartupMessages({
  library(sf); library(mapgl); library(dplyr); library(DBI)
})
sf_use_s2(FALSE)

base <- "/Users/airvine/Projects/repo/link/data-raw/maps"
d    <- file.path(base, "data")

streams_all <- readRDS(file.path(d, "streams_babl.rds")) |>
  st_transform(4326) |> st_zm()
lakes <- readRDS(file.path(d, "lakes_babl.rds")) |>
  st_transform(4326) |> st_zm()

postfloor_rds <- file.path(d, "sk_babl_default_postfloor.rds")
sk_default <- if (file.exists(postfloor_rds)) {
  message("using post-gradient-floor default sf")
  readRDS(postfloor_rds)
} else {
  message("using pre-floor default sf (rerun to refresh after 5-WSG tar_make)")
  readRDS(file.path(d, "sk_babl_default.rds"))
}
sk_default <- sk_default |> st_zm() |> st_transform(4326)

bcfp <- readRDS(file.path(d, "sk_babl_bcfp_split.rds")) |>
  st_transform(4326) |> st_zm()

bcfp_model <- filter(bcfp, bcfp_source == "model")
bcfp_known <- filter(bcfp, bcfp_source == "known")

et_lookup <- fresh::frs_edge_types() |>
  select(edge_type, edge_desc = description)

# Spatial buffers (~20m in degrees)
buf_model   <- st_union(st_buffer(bcfp_model,   0.00018))
buf_known   <- st_union(st_buffer(bcfp_known,   0.00018))
buf_default <- st_union(st_buffer(sk_default,   0.00018))

# Classify each default segment: intersects with bcfp_model, bcfp_known, both, neither
on_model <- lengths(st_intersects(sk_default, buf_model)) > 0
on_known <- lengths(st_intersects(sk_default, buf_known)) > 0

sk_default <- sk_default |>
  mutate(category = case_when(
    on_model                       ~ "high_conf",
    !on_model & on_known           ~ "default_catches_known",
    !on_model & !on_known          ~ "default_over",
    TRUE                           ~ "high_conf"
  )) |>
  left_join(et_lookup, by = "edge_type") |>
  mutate(label = paste0(
    "link default · id_segment: ", id_segment,
    " · edge ", edge_type, " (", edge_desc, ")",
    " · gradient ", formatC(gradient, format = "f", digits = 4),
    " · ", round(length_metre), "m · ", category))

# bcfp known segments not covered by default = csv_only
known_on_default <- lengths(st_intersects(bcfp_known, buf_default)) > 0
bcfp_known <- bcfp_known |>
  filter(!known_on_default) |>
  mutate(category = "csv_only") |>
  left_join(et_lookup, by = "edge_type") |>
  mutate(label = paste0(
    "bcfp known · segmented_stream_id: ", segmented_stream_id,
    " · ", ifelse(is.na(gnis_name), "unnamed", gnis_name),
    " · edge ", edge_type, " (", edge_desc, ")",
    " · gradient ", formatC(gradient, format = "f", digits = 4),
    " · ", round(length_metre), "m · ", category))

combined <- bind_rows(
  sk_default |> select(edge_type, length_metre, category, label, geom = geom),
  bcfp_known |> select(edge_type, length_metre, category, label, geom = geom)
) |> st_as_sf()

pal_values <- c("high_conf", "default_catches_known", "csv_only", "default_over")
pal_colors <- c("#33a02c",  "#1f78b4",               "#6a3d9a",   "#e31a1c")
pal_labels <- c(
  "high confidence (default + bcfp model)",
  "default catches what bcfp needs CSV for",
  "CSV only (known habitat default misses)",
  "default over-predict (no bcfp source)")

summary_tab <- combined |>
  st_drop_geometry() |>
  group_by(category) |>
  summarise(km = round(sum(length_metre)/1000, 2), n = n()) |>
  arrange(match(category, pal_values))
cat("--- BABL SK spawning source breakdown ---\n")
print(summary_tab)

bbox <- st_bbox(combined)

m <- maplibre(bounds = bbox, style = carto_style("positron")) |>
  add_fill_layer(
    id = "lakes", source = lakes,
    fill_color = "#a6cee3", fill_opacity = 0.5,
    popup = "gnis_name_1"
  ) |>
  add_line_layer(
    id = "streams_all", source = streams_all,
    line_color = "#bbbbbb", line_width = 0.5, line_opacity = 0.6
  )

for (i in seq_along(pal_values)) {
  cat_val <- pal_values[i]
  cat_lab <- pal_labels[i]
  cat_col <- pal_colors[i]
  sub <- combined |> filter(category == cat_val)
  if (nrow(sub) == 0) next
  m <- m |>
    add_line_layer(
      id = cat_lab, source = sub,
      line_color = cat_col, line_width = 3, line_opacity = 0.85,
      popup = "label"
    )
}

m <- m |>
  add_legend(
    "SK spawning — BABL · default vs bcfp (model + known split)",
    values = pal_labels, colors = pal_colors,
    type = "categorical", position = "top-right"
  ) |>
  add_layers_control(collapsible = TRUE, position = "top-left")

out_html <- file.path(base, "sk_spawning_BABL_sources.html")
htmlwidgets::saveWidget(m, out_html, selfcontained = TRUE)
cat("wrote", out_html, "\n")

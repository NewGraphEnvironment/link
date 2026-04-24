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
sk_default <- readRDS(file.path(d, "sk_babl_default.rds")) |>
  st_transform(4326) |> st_zm()

bcfp_pub_rds <- file.path(d, "sk_babl_bcfp_published.rds")
if (!file.exists(bcfp_pub_rds)) {
  conn <- dbConnect(RPostgres::Postgres(),
    host = "localhost", port = 63333, dbname = "bcfishpass",
    user = Sys.getenv("PG_USER_SHARE"),
    password = Sys.getenv("PG_PASS_SHARE"))
  bcfp_pub <- st_read(conn, query = "
    SELECT segmented_stream_id, blue_line_key, gnis_name, edge_type,
           length_metre, spawning AS spawning_sk, geom
    FROM bcfishpass.streams_sk_vw
    WHERE watershed_group_code = 'BABL' AND spawning > 0
  ") |> st_transform(4326) |> st_zm()
  saveRDS(bcfp_pub, bcfp_pub_rds)
  dbDisconnect(conn)
} else {
  bcfp_pub <- readRDS(bcfp_pub_rds)
}

# Overlap via 20m buffer intersect (bcfp_pub is the reference set)
bcfp_buf   <- st_union(st_buffer(bcfp_pub, 0.00018))
def_on_bcfp <- lengths(st_intersects(sk_default, bcfp_buf)) > 0

default_buf    <- st_union(st_buffer(sk_default, 0.00018))
bcfp_on_default <- lengths(st_intersects(bcfp_pub, default_buf)) > 0

et_lookup <- fresh::frs_edge_types() |>
  select(edge_type, edge_desc = description)

sk_default$category <- ifelse(def_on_bcfp, "both", "default_only")
bcfp_pub$category   <- ifelse(bcfp_on_default, "both", "published_only")

sk_default <- sk_default |> left_join(et_lookup, by = "edge_type")
bcfp_pub   <- bcfp_pub   |> left_join(et_lookup, by = "edge_type")

sk_default$label <- paste0(
  "link default · id_segment: ", sk_default$id_segment,
  " · edge ", sk_default$edge_type, " (", sk_default$edge_desc, ")",
  " · gradient ", formatC(sk_default$gradient, format = "f", digits = 4),
  " · ", round(sk_default$length_metre), "m · ", sk_default$category)
bcfp_pub$label <- paste0(
  "bcfp published · segmented_stream_id: ", bcfp_pub$segmented_stream_id,
  " · ", ifelse(is.na(bcfp_pub$gnis_name), "unnamed", bcfp_pub$gnis_name),
  " · edge ", bcfp_pub$edge_type, " (", bcfp_pub$edge_desc, ")",
  " · spawning_sk=", bcfp_pub$spawning_sk,
  " · ", round(bcfp_pub$length_metre), "m · ", bcfp_pub$category)

combined <- bind_rows(
  bcfp_pub   |> filter(category == "published_only") |>
    select(edge_type, length_metre, category, label, geom = geom),
  sk_default |> filter(category == "default_only")   |>
    select(edge_type, length_metre, category, label, geom = geom),
  sk_default |> filter(category == "both")           |>
    select(edge_type, length_metre, category, label, geom = geom)
) |> st_as_sf()

pal_values <- c("published_only", "default_only", "both")
pal_colors <- c("#1f78b4",        "#e31a1c",      "#33a02c")
pal_labels <- c("bcfp-published only (known habitat we miss)",
                "link-default only (model-added, not observed)",
                "both (high confidence)")

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
  ) |>
  add_line_layer(
    id = "sk_spawning", source = combined,
    line_color = match_expr("category",
      values = pal_values, stops = pal_colors, default = "#999999"),
    line_width = 3, line_opacity = 0.85,
    popup = "label"
  ) |>
  add_legend(
    "SK spawning — BABL · link default vs bcfp published (model + known)",
    values = pal_labels, colors = pal_colors,
    type = "categorical", position = "top-right"
  ) |>
  add_layers_control(collapsible = TRUE, position = "top-left")

out_html <- file.path(base, "sk_spawning_BABL_published.html")
htmlwidgets::saveWidget(m, out_html, selfcontained = TRUE)
cat("wrote", out_html, "\n")
cat("bcfp published only:", sum(combined$category == "published_only"),
    " | default only:",    sum(combined$category == "default_only"),
    " | both:",            sum(combined$category == "both"), "\n")

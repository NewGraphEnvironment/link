#' Compare link vs bcfishpass habitat classification on a WSG / species / habitat axis.
#'
#' One function, narrow scope: pulls flagged segments from both DBs,
#' classifies each as `link_only` / `bcfp_only` / `both` via 20 m buffer
#' intersect, and writes a selfcontained mapgl HTML showing rearing-or-
#' spawning diff against the WSG underlay + lakes + spawning context.
#'
#' Variants (e.g. published vs sources) compose by passing `extra_layers`
#' — a list of mapgl layer specs that get added after the base layers.
#' No `type` arg, no config struct: caller controls layering.
#'
#' Source layout (selected by `habitat`):
#'   habitat = "rearing"   → fresh.streams_habitat.rearing  vs habitat_linear_<sp>.rearing
#'   habitat = "spawning"  → fresh.streams_habitat.spawning vs habitat_linear_<sp>.spawning
#'
#' Files (all gitignored under data-raw/maps):
#'   <cache_dir>/<wsg>_<sp>_<habitat>_link_<axis>.rds       link-side flagged segments
#'   <cache_dir>/<wsg>_<sp>_<habitat>_bcfp_<axis>.rds       bcfp-side flagged segments
#'   <cache_dir>/<wsg>_streams_underlay.rds                 wsg-wide FWA underlay
#'   <cache_dir>/<wsg>_lakes.rds                            wsg lakes >= 1 ha
#'   <out_html>                                             selfcontained mapgl
#'
#' @param wsg Watershed group code (uppercase, e.g. "MORR").
#' @param species Species code (uppercase, e.g. "ST").
#' @param habitat One of "rearing" or "spawning".
#' @param conn_local Function returning a fresh DBI connection to local
#'   fwapg (link-side). Called per query so connection lifecycle is local.
#' @param conn_ref Function returning a fresh DBI connection to bcfishpass
#'   tunnel.
#' @param out_html Output path. Default
#'   `data-raw/maps/<wsg>_<species>_<habitat>_compare.html`.
#' @param cache_dir Cache directory for RDS pulls. Default
#'   `data-raw/maps/data`.
#' @param underlay Logical. Include FWA streams underlay layer. Default TRUE.
#' @param simplify_m Numeric. dTolerance (BC Albers metres) for st_simplify
#'   before transform to 4326. Default 5.
#' @param extra_layers List of mapgl layer specs. Each entry is a list
#'   with keys `id`, `data` (sf object), `colour`, `width`, `popup_field`.
#'   Added after base layers. Caller responsible for any data fetching.
#'
#' @return Invisibly, the path to the written HTML.
lnk_map_compare <- function(wsg, species, habitat,
                            conn_local, conn_ref,
                            out_html = NULL,
                            cache_dir = NULL,
                            underlay = TRUE,
                            simplify_m = 5,
                            extra_layers = list()) {

  stopifnot(
    is.character(wsg), length(wsg) == 1L, nzchar(wsg),
    is.character(species), length(species) == 1L, nzchar(species),
    habitat %in% c("rearing", "spawning"),
    is.function(conn_local), is.function(conn_ref))

  base    <- "/Users/airvine/Projects/repo/link/data-raw/maps"
  cache_d <- cache_dir %||% file.path(base, "data")
  out_p   <- out_html  %||% file.path(base,
    sprintf("%s_%s_%s_compare.html", wsg, species, habitat))

  dir.create(cache_d, showWarnings = FALSE, recursive = TRUE)

  # ---- pull (cached) ------------------------------------------------------

  cached <- function(rds, fn) {
    if (file.exists(rds)) readRDS(rds) else { x <- fn(); saveRDS(x, rds); x }
  }

  # Aliasing the side-specific id columns to seg_id so popup label is uniform.
  # link: id_segment is per-pipeline-run (not stable across reruns).
  # bcfp: segmented_stream_id is the canonical bcfp segment id.

  bcfp_axis <- cached(
    file.path(cache_d, sprintf("%s_%s_bcfp_%s.rds", wsg, species, habitat)),
    function() {
      c <- conn_ref(); on.exit(DBI::dbDisconnect(c))
      sf::st_read(c, query = sprintf("
        SELECT s.segmented_stream_id::text AS seg_id,
               s.blue_line_key, s.downstream_route_measure,
               s.gnis_name, s.edge_type, s.length_metre, s.gradient,
               s.stream_order, s.geom
        FROM bcfishpass.streams s
        JOIN bcfishpass.habitat_linear_%s h
          ON s.segmented_stream_id = h.segmented_stream_id
        WHERE s.watershed_group_code = '%s' AND h.%s",
        tolower(species), wsg, habitat))
    })

  bcfp_other <- cached(
    file.path(cache_d, sprintf("%s_%s_bcfp_%s.rds", wsg, species,
      if (habitat == "rearing") "spawning" else "rearing")),
    function() {
      c <- conn_ref(); on.exit(DBI::dbDisconnect(c))
      other <- if (habitat == "rearing") "spawning" else "rearing"
      sf::st_read(c, query = sprintf("
        SELECT s.segmented_stream_id::text AS seg_id,
               s.blue_line_key, s.downstream_route_measure,
               s.gnis_name, s.edge_type, s.length_metre, s.gradient,
               s.stream_order, s.geom
        FROM bcfishpass.streams s
        JOIN bcfishpass.habitat_linear_%s h
          ON s.segmented_stream_id = h.segmented_stream_id
        WHERE s.watershed_group_code = '%s' AND h.%s",
        tolower(species), wsg, other))
    })

  link_axis <- cached(
    file.path(cache_d, sprintf("%s_%s_link_%s.rds", wsg, species, habitat)),
    function() {
      c <- conn_local(); on.exit(DBI::dbDisconnect(c))
      sf::st_read(c, query = sprintf("
        SELECT s.id_segment::text AS seg_id,
               s.blue_line_key, s.downstream_route_measure,
               s.edge_type, s.length_metre, s.gradient, s.stream_order, s.geom
        FROM fresh.streams s
        JOIN fresh.streams_habitat h
          ON s.id_segment = h.id_segment AND h.species_code = '%s'
        WHERE s.watershed_group_code = '%s' AND h.%s",
        species, wsg, habitat))
    })

  link_other <- cached(
    file.path(cache_d, sprintf("%s_%s_link_%s.rds", wsg, species,
      if (habitat == "rearing") "spawning" else "rearing")),
    function() {
      c <- conn_local(); on.exit(DBI::dbDisconnect(c))
      other <- if (habitat == "rearing") "spawning" else "rearing"
      sf::st_read(c, query = sprintf("
        SELECT s.id_segment::text AS seg_id,
               s.blue_line_key, s.downstream_route_measure,
               s.edge_type, s.length_metre, s.gradient, s.stream_order, s.geom
        FROM fresh.streams s
        JOIN fresh.streams_habitat h
          ON s.id_segment = h.id_segment AND h.species_code = '%s'
        WHERE s.watershed_group_code = '%s' AND h.%s",
        species, wsg, other))
    })

  streams_under <- cached(file.path(cache_d, sprintf("%s_streams_underlay.rds", wsg)),
    function() {
      c <- conn_local(); on.exit(DBI::dbDisconnect(c))
      sf::st_read(c, query = sprintf("
        SELECT linear_feature_id, blue_line_key, edge_type, geom
        FROM whse_basemapping.fwa_stream_networks_sp
        WHERE watershed_group_code = '%s'", wsg))
    })

  lakes <- cached(file.path(cache_d, sprintf("%s_lakes.rds", wsg)),
    function() {
      c <- conn_local(); on.exit(DBI::dbDisconnect(c))
      sf::st_read(c, query = sprintf("
        SELECT waterbody_key, gnis_name_1 AS gnis_name, area_ha, geom
        FROM whse_basemapping.fwa_lakes_poly
        WHERE watershed_group_code = '%s' AND area_ha >= 1", wsg))
    })

  # ---- transform + simplify ----------------------------------------------

  t4326 <- function(x) {
    x |> sf::st_zm() |> sf::st_simplify(dTolerance = simplify_m) |>
      sf::st_transform(4326)
  }

  streams_under <- t4326(streams_under)
  lakes         <- t4326(lakes)
  bcfp_axis     <- t4326(bcfp_axis)
  bcfp_other    <- t4326(bcfp_other)
  link_axis     <- t4326(link_axis)
  link_other    <- t4326(link_other)

  # ---- categorise --------------------------------------------------------

  buf <- function(x) sf::st_union(sf::st_buffer(x, 0.00018))

  if (nrow(bcfp_axis) > 0 && nrow(link_axis) > 0) {
    bcfp_buf <- buf(bcfp_axis); link_buf <- buf(link_axis)
    bcfp_axis$category <- ifelse(
      lengths(sf::st_intersects(bcfp_axis, link_buf)) > 0,
      "both", "bcfp_only")
    link_axis$category <- ifelse(
      lengths(sf::st_intersects(link_axis, bcfp_buf)) > 0,
      "both", "link_only")
  } else {
    bcfp_axis$category <- if (nrow(bcfp_axis) > 0) "bcfp_only" else character(0)
    link_axis$category <- if (nrow(link_axis) > 0) "link_only" else character(0)
  }

  et_lookup <- fresh::frs_edge_types() |>
    dplyr::select(edge_type, edge_desc = description)

  mk_label <- function(df, side) {
    df |>
      dplyr::left_join(et_lookup, by = "edge_type") |>
      dplyr::mutate(label = paste0(
        side, " | seg_id ", seg_id,
        " | blkey ", blue_line_key,
        " | DRM ", round(downstream_route_measure),
        " | edge ", edge_type, " (", edge_desc, ")",
        " | grad ", formatC(gradient, format = "f", digits = 4),
        " | order ", stream_order,
        " | ", round(length_metre), "m"))
  }

  axis_combined <- dplyr::bind_rows(
    bcfp_axis |> dplyr::filter(category == "bcfp_only") |> mk_label("bcfp-only"),
    link_axis |> dplyr::filter(category == "link_only") |> mk_label("link-only"),
    link_axis |> dplyr::filter(category == "both")      |> mk_label("both"))

  other_label <- if (habitat == "rearing") "spawning" else "rearing"
  other_combined <- dplyr::bind_rows(
    bcfp_other |> mk_label(paste("bcfp", other_label)),
    link_other |> mk_label(paste("link", other_label)))

  # ---- bbox: full WSG (let user zoom) ------------------------------------

  fb <- sf::st_bbox(dplyr::bind_rows(bcfp_axis, link_axis, bcfp_other, link_other))
  pad <- 0.02
  dx <- fb["xmax"] - fb["xmin"]; dy <- fb["ymax"] - fb["ymin"]
  view_bbox <- sf::st_bbox(c(
    xmin = unname(fb["xmin"] - dx*pad), xmax = unname(fb["xmax"] + dx*pad),
    ymin = unname(fb["ymin"] - dy*pad), ymax = unname(fb["ymax"] + dy*pad)),
    crs = 4326)

  # ---- mapgl --------------------------------------------------------------

  pal_values <- c("bcfp_only", "link_only", "both")
  pal_colors <- c("#1f78b4",  "#e31a1c",   "#6a3d9a")
  pal_labels <- c("bcfp only (link missing)", "link only (extra)", "both")
  other_color <- "#33a02c"

  legend_title <- sprintf("%s %s %s — link vs bcfishpass",
    wsg, species, habitat)

  m <- mapgl::maplibre(bounds = view_bbox, style = mapgl::carto_style("positron")) |>
    mapgl::add_fill_layer(
      id = "lakes", source = lakes,
      fill_color = "#a6cee3", fill_opacity = 0.4, popup = "gnis_name")

  if (underlay) {
    m <- m |> mapgl::add_line_layer(
      id = "streams_all", source = streams_under,
      line_color = "#cccccc", line_width = 0.4, line_opacity = 0.6)
  }

  m <- m |>
    mapgl::add_line_layer(
      id = other_label, source = other_combined,
      line_color = other_color, line_width = 1.5, line_opacity = 0.85,
      popup = "label") |>
    mapgl::add_line_layer(
      id = habitat, source = axis_combined,
      line_color = mapgl::match_expr("category",
        values = pal_values, stops = pal_colors, default = "#999999"),
      line_width = 3, line_opacity = 0.9, popup = "label")

  for (lyr in extra_layers) {
    m <- m |> mapgl::add_line_layer(
      id = lyr$id, source = lyr$data,
      line_color = lyr$colour %||% "#888",
      line_width = lyr$width %||% 2,
      line_opacity = 0.85,
      popup = lyr$popup_field %||% NULL)
  }

  m <- m |>
    mapgl::add_legend(
      legend_title,
      values = c(pal_labels, paste(other_label, "(either)")),
      colors = c(pal_colors, other_color),
      type = "categorical", position = "top-right") |>
    mapgl::add_layers_control(collapsible = TRUE, position = "top-left")

  htmlwidgets::saveWidget(m, out_p, selfcontained = TRUE)
  cat("wrote", out_p, "—",
    round(file.info(out_p)$size / 1e6, 1), "MB\n")
  invisible(out_p)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

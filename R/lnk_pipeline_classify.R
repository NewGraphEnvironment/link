#' Classify Stream Segments into Habitat per Species
#'
#' Fifth phase of the habitat classification pipeline. Builds the
#' access-gating break table consumed by classification, then calls
#' [fresh::frs_habitat_classify()] with the rules YAML, thresholds,
#' per-species parameters, and barrier overrides from the config
#' bundle.
#'
#' The access-gating break table (`fresh.streams_breaks`) is assembled
#' from the FULL gradient barrier set (not the minimal one used for
#' segmentation), falls, user-identified definite barriers, and
#' crossings with their AOI-filtered ltree values attached. Filtering
#' to the AOI keeps the O(segments × breaks) access-gating join
#' tractable.
#'
#' Writes to:
#'   - `fresh.streams_breaks` — access-gating breaks
#'   - `fresh.streams_habitat` — per-species classification output
#'     (written by `frs_habitat_classify`)
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param aoi Character. Watershed group code (today; extends to other
#'   spatial filters later).
#' @param cfg An `lnk_config` object from [lnk_config()].
#' @param loaded Named list of tibbles from [lnk_load_overrides()].
#'   Carries `parameters_fresh`, `user_habitat_classification`, and
#'   `wsg_species_presence`.
#' @param schema Character. Working schema name.
#' @param species Character vector. Species codes to classify. Default
#'   derives from `loaded$parameters_fresh$species_code` intersected
#'   with the species present in the AOI (via
#'   `loaded$wsg_species_presence`).
#' @param thresholds_csv Path to the habitat thresholds CSV. Default
#'   uses the copy shipped with fresh.
#'
#' @return `conn` invisibly, for pipe chaining.
#'
#' @family pipeline
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn   <- lnk_db_conn()
#' cfg    <- lnk_config("bcfishpass")
#' loaded <- lnk_load_overrides(cfg)
#' schema <- "working_bulk"
#'
#' lnk_pipeline_setup(conn, schema)
#' lnk_pipeline_load(conn, "BULK", cfg, loaded, schema)
#' lnk_pipeline_prepare(conn, "BULK", cfg, loaded, schema)
#' lnk_pipeline_break(conn, "BULK", cfg, loaded, schema)
#' lnk_pipeline_classify(conn, "BULK", cfg, loaded, schema)
#'
#' DBI::dbDisconnect(conn)
#' }
lnk_pipeline_classify <- function(conn, aoi, cfg, loaded, schema,
                                   species = NULL,
                                   thresholds_csv = system.file(
                                     "extdata",
                                     "parameters_habitat_thresholds.csv",
                                     package = "fresh")) {
  .lnk_validate_identifier(schema, "schema")
  if (!is.character(aoi) || length(aoi) != 1L || !nzchar(aoi)) {
    stop("aoi must be a single non-empty string (watershed group code)",
         call. = FALSE)
  }
  if (!inherits(cfg, "lnk_config")) {
    stop("cfg must be an lnk_config object (from lnk_config())",
         call. = FALSE)
  }
  if (!is.list(loaded)) {
    stop("loaded must be a named list (from lnk_load_overrides())",
         call. = FALSE)
  }
  if (!nzchar(thresholds_csv) || !file.exists(thresholds_csv)) {
    stop("thresholds_csv not found: ", thresholds_csv, call. = FALSE)
  }

  species <- species %||% lnk_pipeline_species(cfg, loaded, aoi)
  if (length(species) == 0L) {
    stop("No species resolved for AOI '", aoi, "'. Either pass `species` ",
         "explicitly or ensure loaded$parameters_fresh and ",
         "loaded$wsg_species_presence cover this AOI.", call. = FALSE)
  }

  .lnk_pipeline_classify_build_breaks(conn, aoi, schema,
    include_subsurfaceflow = "subsurfaceflow" %in%
      (cfg$pipeline$break_order %||% character()))

  params <- fresh::frs_params(
    csv = thresholds_csv,
    rules_yaml = cfg$rules)

  fresh::frs_habitat_classify(conn,
    table = "fresh.streams",
    to = "fresh.streams_habitat",
    species = species,
    params = params,
    params_fresh = loaded$parameters_fresh,
    gate = TRUE,
    label_block = "blocked",
    barrier_overrides = paste0(schema, ".barrier_overrides"),
    verbose = FALSE)

  # Known-habitat overlay (optional). Two gates must both be open:
  #
  #   1. The manifest declares `files.user_habitat_classification` (CSV
  #      is loaded into `<schema>.user_habitat_classification` by the
  #      prepare phase), AND
  #   2. The manifest's `pipeline.apply_habitat_overlay` is not FALSE
  #      (default TRUE; bcfishpass bundle sets FALSE so its output
  #      reproduces bcfishpass's rule-based `habitat_linear_<sp>`,
  #      not the `streams_habitat_linear` post-blend).
  #
  # Source CSV is canonical shape (post-2026-04-26 bcfishpass): one row
  # per (segment x species) with `spawning` and `rearing` indicator
  # columns. The target `fresh.streams_habitat` is keyed by
  # `id_segment` only, and the source is keyed by `(blue_line_key,
  # drm)` with range `[drm, urm]` — so we need a 3-way bridge through
  # `fresh.streams` for range containment. Requires fresh >= 0.22.0.
  apply_overlay <- isTRUE(cfg$pipeline$apply_habitat_overlay %||% TRUE)
  if (!is.null(loaded$user_habitat_classification) && apply_overlay) {
    fresh::frs_habitat_overlay(conn,
      from   = paste0(schema, ".user_habitat_classification"),
      to     = "fresh.streams_habitat",
      bridge = "fresh.streams",
      species = species,
      species_col = "species_code",
      habitat_types = c("spawning", "rearing"),
      verbose = FALSE)
  }

  # fresh#158 stream-order bypass: post-classification, credit direct
  # tributaries of large-order rivers as rearing even when channel
  # width is below threshold. Mirrors bcfp's hard-coded
  # `stream_order_parent >= 5 AND stream_order = 1` predicate in
  # load_habitat_linear_<sp>.sql for BT/CH/CO/ST/WCT.
  #
  # Per-species opt-in driven by `dimensions.csv::rear_stream_order_bypass`,
  # which `lnk_rules_build` propagates into rules.yaml as
  # `rear[].channel_width_min_bypass = list(stream_order, stream_order_parent_min)`.
  # We detect that field's presence on any rear rule and call
  # `frs_order_child` with the embedded parent_order threshold.
  for (sp in species) {
    rear_rules <- params[[sp]][["rules"]][["rear"]]
    bypass <- NULL
    for (rr in rear_rules) {
      if (!is.null(rr[["channel_width_min_bypass"]])) {
        bypass <- rr[["channel_width_min_bypass"]]
        break
      }
    }
    if (!is.null(bypass)) {
      pom    <- bypass[["stream_order_parent_min"]] %||% 5L
      cs_min <- bypass[["stream_order_min"]]
      cs_max <- bypass[["stream_order_max"]]
      dmax   <- bypass[["distance_max"]]
      fresh::frs_order_child(conn,
        table   = "fresh.streams",
        habitat = "fresh.streams_habitat",
        species = sp,
        parent_order_min = pom,
        child_order_min = cs_min,
        child_order_max = cs_max,
        distance_max = dmax,
        verbose = FALSE)
    }
  }

  invisible(conn)
}


#' Build fresh.streams_breaks for access gating
#'
#' Assembles gradient barriers (FULL, not minimal) + falls + definite
#' barriers + crossings, each joined to FWA for ltree values and
#' filtered to the AOI. The FULL gradient set is required because
#' access gating needs every barrier to block access, not just the
#' minimal segmentation set.
#' @noRd
.lnk_pipeline_classify_build_breaks <- function(conn, aoi, schema,
                                                 include_subsurfaceflow = FALSE) {
  subsurf_union <- if (include_subsurfaceflow) {
    sprintf(
      "UNION ALL
       SELECT b.blue_line_key, round(b.downstream_route_measure),
              'blocked', b.wscode_ltree, b.localcode_ltree
       FROM %s.barriers_subsurfaceflow b
       WHERE b.wscode_ltree IS NOT NULL",
      schema)
  } else {
    ""
  }

  .lnk_db_execute(conn, "DROP TABLE IF EXISTS fresh.streams_breaks")
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE fresh.streams_breaks AS
     SELECT g.blue_line_key,
            round(g.downstream_route_measure) AS downstream_route_measure,
            'gradient_' || lpad(g.gradient_class::text, 4, '0') AS label,
            s.wscode_ltree, s.localcode_ltree
     FROM %s.gradient_barriers_raw g
     JOIN whse_basemapping.fwa_stream_networks_sp s
       ON g.blue_line_key = s.blue_line_key
       AND g.downstream_route_measure >= s.downstream_route_measure
       AND g.downstream_route_measure < s.upstream_route_measure
     WHERE s.watershed_group_code = %s
     UNION ALL
     SELECT f.blue_line_key, round(f.downstream_route_measure),
            'blocked', s.wscode_ltree, s.localcode_ltree
     FROM %s.falls f
     JOIN whse_basemapping.fwa_stream_networks_sp s
       ON f.blue_line_key = s.blue_line_key
       AND f.downstream_route_measure >= s.downstream_route_measure
       AND f.downstream_route_measure < s.upstream_route_measure
     WHERE s.watershed_group_code = %s
     UNION ALL
     SELECT d.blue_line_key, round(d.downstream_route_measure),
            'blocked', s.wscode_ltree, s.localcode_ltree
     FROM %s.barriers_definite d
     JOIN whse_basemapping.fwa_stream_networks_sp s
       ON d.blue_line_key = s.blue_line_key
       AND d.downstream_route_measure >= s.downstream_route_measure
       AND d.downstream_route_measure < s.upstream_route_measure
     WHERE s.watershed_group_code = %s
     UNION ALL
     SELECT c.blue_line_key, round(c.downstream_route_measure),
            CASE c.barrier_status
              WHEN 'BARRIER' THEN 'barrier'
              WHEN 'POTENTIAL' THEN 'potential'
              WHEN 'PASSABLE' THEN 'passable'
              ELSE 'unknown'
            END,
            s.wscode_ltree, s.localcode_ltree
     FROM %s.crossings c
     JOIN whse_basemapping.fwa_stream_networks_sp s
       ON c.blue_line_key = s.blue_line_key
       AND c.downstream_route_measure >= s.downstream_route_measure
       AND c.downstream_route_measure < s.upstream_route_measure
     WHERE s.watershed_group_code = %s
     %s",
    schema, .lnk_quote_literal(aoi),
    schema, .lnk_quote_literal(aoi),
    schema, .lnk_quote_literal(aoi),
    schema, .lnk_quote_literal(aoi),
    subsurf_union))

  invisible(NULL)
}

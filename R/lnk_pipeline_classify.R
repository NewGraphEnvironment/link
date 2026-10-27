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
#'   `NULL` uses the config's own `files$parameters_habitat_thresholds`,
#'   falling back (with a message) to the copy shipped with fresh when
#'   the config declares none.
#' @param method_csv Path to the per-watershed-group habitat model table
#'   (`watershed_group_code`, `model` = `"cw"` or `"mad"`), passed to
#'   [fresh::frs_habitat_classify()] as `params_method`. Default `NULL` uses
#'   the config's own `files$parameters_habitat_method`, falling back (with a
#'   message) to fresh's all-`cw` copy when the config declares none. A group
#'   the table does not list classifies on channel width. A `mad` group
#'   classifies on `mad_m3s`, which the prepare phase joins onto the working
#'   streams table from `cfg$pipeline$discharge_source` (filling edge 1250 main stems with no value when
#'   `cfg$pipeline$discharge_fill` is set), and skips the stream-order
#'   rearing bypass. Read from the
#'   path, not from `loaded$parameters_habitat_method`, as the thresholds are,
#'   so editing `loaded` has no effect here.
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
                                   thresholds_csv = NULL,
                                   method_csv = NULL) {
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
  thresholds_csv <- thresholds_csv %||% .lnk_habitat_thresholds_csv(cfg)
  if (!nzchar(thresholds_csv) || !file.exists(thresholds_csv)) {
    stop("thresholds_csv not found: ", thresholds_csv, call. = FALSE)
  }
  method_csv <- method_csv %||% .lnk_habitat_method_csv(cfg)
  if (!nzchar(method_csv) || !file.exists(method_csv)) {
    stop("method_csv not found: ", method_csv, call. = FALSE)
  }
  params_method <- .lnk_habitat_method_read(method_csv)

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

  # fresh keeps <to>_near_river and only replaces the groups it walks, so a
  # table left by an earlier build (another bundle, other pairs, or fresh
  # 0.41.0's shape) would otherwise reach persist as this build's (#364).
  .lnk_db_execute(conn, sprintf(
    "DROP TABLE IF EXISTS %s.streams_habitat_near_river", schema))

  fresh::frs_habitat_classify(conn,
    table = paste0(schema, ".streams"),
    to = paste0(schema, ".streams_habitat"),
    species = species,
    params = params,
    params_fresh = loaded$parameters_fresh,
    params_method = params_method,
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
      to     = paste0(schema, ".streams_habitat"),
      bridge = paste0(schema, ".streams"),
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
  #
  # Channel-width model only (#286): the bypass stands in for a width test,
  # and bcfp applies it inside its cw branch alone. A `mad` group skips it.
  aoi_model <- .lnk_wsg_model(params_method, aoi)
  species_bypass <- if (identical(aoi_model, "mad")) character(0) else species
  for (sp in species_bypass) {
    rear_rules <- params[[sp]][["rules"]][["rear"]]
    bypass <- NULL
    bypass_rule <- NULL
    for (rr in rear_rules) {
      if (!is.null(rr[["channel_width_min_bypass"]])) {
        bypass <- rr[["channel_width_min_bypass"]]
        bypass_rule <- rr
        break
      }
    }
    if (!is.null(bypass)) {
      oc_args <- list(conn,
        table   = paste0(schema, ".streams"),
        habitat = paste0(schema, ".streams_habitat"),
        species = sp,
        parent_order_min = bypass[["stream_order_parent_min"]] %||% 5L,
        child_order_min = bypass[["stream_order_min"]],
        child_order_max = bypass[["stream_order_max"]],
        distance_max = bypass[["distance_max"]],
        verbose = FALSE)
      # bcfishpass's exception sits inside the rest of its rearing test: a
      # line qualifies only with a known width below the minimum and a
      # gradient within the rearing maximum (#326).
      if (isTRUE(bypass[["width_known_below_min"]])) {
        oc_args <- c(oc_args,
                     .lnk_order_child_bounds(params[[sp]], bypass_rule, sp))
      }
      do.call(fresh::frs_order_child, oc_args)
    }
  }

  invisible(conn)
}


#' Width and gradient bounds for the order-1 rearing exception
#'
#' The width minimum comes from the rule carrying the bypass when that rule
#' sets its own `channel_width` range, else from the species' rearing
#' thresholds; the gradient maximum likewise. Either missing is an error: a
#' NULL bound would silently admit every direct child (#326).
#' @noRd
.lnk_order_child_bounds <- function(sp_params, rule, sp) {
  rear <- sp_params[["ranges"]][["rear"]]
  width <- rule[["channel_width"]][[1]] %||% rear[["channel_width"]][[1]]
  gradient <- rule[["gradient"]][[2]] %||% rear[["gradient"]][[2]]
  missing <- c(channel_width_min = is.null(width) || is.na(width),
               gradient_max = is.null(gradient) || is.na(gradient))
  if (any(missing)) {
    stop(sprintf(paste0(
      "%s: the rear rule's channel_width_min_bypass sets ",
      "width_known_below_min, but no rearing %s is set on that rule or in ",
      "the thresholds"), sp,
      paste(names(missing)[missing], collapse = " or ")), call. = FALSE)
  }
  list(channel_width_lt = as.numeric(width),
       gradient_max = as.numeric(gradient))
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

  .lnk_db_execute(conn, sprintf(
    "DROP TABLE IF EXISTS %s.streams_breaks", schema))
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE %s.streams_breaks AS
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
    schema,
    schema, .lnk_quote_literal(aoi),
    schema, .lnk_quote_literal(aoi),
    schema, .lnk_quote_literal(aoi),
    schema, .lnk_quote_literal(aoi),
    subsurf_union))

  invisible(NULL)
}

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
#' @param schema Character. Working schema name.
#' @param species Character vector. Species codes to classify. Default
#'   derives from `cfg$parameters_fresh$species_code` intersected with
#'   the species present in the AOI (via `cfg$wsg_species`).
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
#' conn <- lnk_db_conn()
#' cfg  <- lnk_config("bcfishpass")
#' schema <- "working_bulk"
#'
#' lnk_pipeline_setup(conn, schema)
#' lnk_pipeline_load(conn, "BULK", cfg, schema)
#' lnk_pipeline_prepare(conn, "BULK", cfg, schema)
#' lnk_pipeline_break(conn, "BULK", cfg, schema)
#' lnk_pipeline_classify(conn, "BULK", cfg, schema)
#'
#' DBI::dbDisconnect(conn)
#' }
lnk_pipeline_classify <- function(conn, aoi, cfg, schema,
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
  if (!nzchar(thresholds_csv) || !file.exists(thresholds_csv)) {
    stop("thresholds_csv not found: ", thresholds_csv, call. = FALSE)
  }

  species <- species %||% .lnk_pipeline_classify_species(cfg, aoi)
  if (length(species) == 0L) {
    stop("No species resolved for AOI '", aoi, "'. Either pass `species` ",
         "explicitly or ensure cfg$parameters_fresh and cfg$wsg_species ",
         "cover this AOI.", call. = FALSE)
  }

  .lnk_pipeline_classify_build_breaks(conn, aoi, schema)

  params <- fresh::frs_params(
    csv = thresholds_csv,
    rules_yaml = cfg$rules_yaml)

  fresh::frs_habitat_classify(conn,
    table = "fresh.streams",
    to = "fresh.streams_habitat",
    species = species,
    params = params,
    params_fresh = cfg$parameters_fresh,
    gate = TRUE,
    label_block = "blocked",
    barrier_overrides = paste0(schema, ".barrier_overrides"),
    verbose = FALSE)

  invisible(conn)
}


#' Resolve the species list for an AOI
#'
#' Intersect the species the config's rules YAML classifies
#' (`cfg$species`, parsed at load time) with the species present in
#' the AOI (from `cfg$wsg_species`). Falls back to `cfg$species` if
#' wsg_species is missing.
#' @noRd
.lnk_pipeline_classify_species <- function(cfg, aoi) {
  configured <- cfg$species %||% unique(cfg$parameters_fresh$species_code)

  wsg_sp <- cfg$wsg_species
  if (is.null(wsg_sp)) return(configured)

  row <- wsg_sp[wsg_sp$watershed_group_code == aoi, ]
  if (nrow(row) == 0) return(character(0))

  spp_cols <- c("bt", "ch", "cm", "co", "ct", "dv",
                "pk", "rb", "sk", "st", "wct")
  present <- vapply(spp_cols,
    function(x) identical(row[[x]], "t"), logical(1))
  aoi_species <- toupper(spp_cols[present])

  intersect(configured, aoi_species)
}


#' Build fresh.streams_breaks for access gating
#'
#' Assembles gradient barriers (FULL, not minimal) + falls + definite
#' barriers + crossings, each joined to FWA for ltree values and
#' filtered to the AOI. The FULL gradient set is required because
#' access gating needs every barrier to block access, not just the
#' minimal segmentation set.
#' @noRd
.lnk_pipeline_classify_build_breaks <- function(conn, aoi, schema) {
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
     WHERE s.watershed_group_code = %s",
    schema, .lnk_quote_literal(aoi),
    schema, .lnk_quote_literal(aoi),
    schema, .lnk_quote_literal(aoi),
    schema, .lnk_quote_literal(aoi)))

  invisible(NULL)
}

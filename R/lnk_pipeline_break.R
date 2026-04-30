#' Segment the Stream Network at Configured Break Positions
#'
#' Fourth phase of the habitat classification pipeline. Builds the
#' remaining break-source tables (observations, habitat endpoints,
#' crossings) that depend on AOI- and config-specific data, then runs
#' [fresh::frs_break_apply()] sequentially over the break sources in
#' the order defined by the config. After each round, `id_segment` is
#' reassigned so downstream rounds see contiguous integer IDs.
#'
#' The break-source order matters. bcfishpass processes:
#' observations → gradient_minimal → barriers_definite →
#' habitat_endpoints → crossings. This order is encoded in the bundled
#' bcfishpass config (`cfg$pipeline$break_order`) and is the default
#' when the config does not specify one.
#'
#' Writes to (under the caller's working schema unless noted):
#'   - `<schema>.observations_breaks` — WSG- and species-filtered
#'     observation positions, data-error exclusions applied
#'   - `<schema>.habitat_endpoints` — both DRM and URM from the habitat
#'     classification table (matches bcfishpass convention)
#'   - `<schema>.crossings_breaks` — crossing positions
#'   - Mutates `fresh.streams` in place — adds segment boundaries at
#'     each break source position, reassigns `id_segment`
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param aoi Character. Watershed group code (today; extends to other
#'   spatial filters later).
#' @param cfg An `lnk_config` object from [lnk_config()].
#' @param loaded Named list of tibbles from [lnk_load_overrides()].
#'   Carries `observation_exclusions` and `wsg_species_presence`.
#' @param schema Character. Working schema name.
#' @param observations Character. Schema-qualified observations table
#'   (default `"bcfishobs.observations"`).
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
#'
#' DBI::dbGetQuery(conn,
#'   "SELECT count(*) FROM fresh.streams")
#'
#' DBI::dbDisconnect(conn)
#' }
lnk_pipeline_break <- function(conn, aoi, cfg, loaded, schema,
                                observations = "bcfishobs.observations") {
  .lnk_validate_identifier(schema, "schema")
  .lnk_validate_identifier(observations, "observations table")
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

  .lnk_pipeline_break_obs(conn, aoi, loaded, schema, observations)
  .lnk_pipeline_break_habitat_endpoints(conn, aoi, schema)
  .lnk_pipeline_break_crossings(conn, schema)

  break_order <- cfg$pipeline$break_order %||% c(
    "observations", "gradient_minimal",
    "barriers_definite", "habitat_endpoints", "crossings"
  )
  source_tables <- list(
    observations      = paste0(schema, ".observations_breaks"),
    gradient_minimal  = paste0(schema, ".gradient_barriers_minimal"),
    barriers_definite = paste0(schema, ".barriers_definite"),
    subsurfaceflow    = paste0(schema, ".barriers_subsurfaceflow"),
    habitat_endpoints = paste0(schema, ".habitat_endpoints"),
    crossings         = paste0(schema, ".crossings_breaks")
  )

  for (src_name in break_order) {
    src_table <- source_tables[[src_name]]
    if (is.null(src_table)) {
      stop("Unknown break source in cfg$pipeline$break_order: ", src_name,
           call. = FALSE)
    }
    fresh::frs_break_apply(conn,
      table = "fresh.streams",
      breaks = src_table,
      segment_id = "id_segment",
      measure_precision = 0L)
    .lnk_pipeline_break_reassign_id(conn)
  }

  invisible(conn)
}


#' Build observations_breaks with species filter and data-error exclusions
#' @noRd
.lnk_pipeline_break_obs <- function(conn, aoi, loaded, schema, observations) {
  obs_species <- .lnk_pipeline_break_obs_species(loaded, aoi)
  if (length(obs_species) == 0L) {
    obs_species_sql <- "NULL"
  } else {
    obs_species_sql <- paste0(
      vapply(obs_species, .lnk_quote_literal, character(1)),
      collapse = ", ")
  }

  # Observation exclusions: data errors + release excludes
  excl_filter <- ""
  excl_df <- loaded$observation_exclusions
  if (!is.null(excl_df) && nrow(excl_df) > 0) {
    is_excl <- excl_df$data_error %in% c(TRUE, "t") |
               excl_df$release_exclude %in% c(TRUE, "t")
    keys <- excl_df$fish_observation_point_id[is_excl]
    if (length(keys) > 0) {
      DBI::dbWriteTable(conn,
        DBI::Id(schema = schema, table = "obs_exclusions"),
        data.frame(fish_observation_point_id = keys),
        overwrite = TRUE)
      excl_filter <- sprintf(
        "AND o.fish_observation_point_id NOT IN
          (SELECT fish_observation_point_id FROM %s.obs_exclusions)",
        schema)
    }
  }

  .lnk_db_execute(conn, sprintf(
    "DROP TABLE IF EXISTS %s.observations_breaks", schema))
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE %s.observations_breaks AS
     SELECT DISTINCT o.blue_line_key,
            round(o.downstream_route_measure) AS downstream_route_measure
     FROM %s o
     WHERE o.watershed_group_code = %s
       AND o.species_code IN (%s) %s",
    schema, observations, .lnk_quote_literal(aoi),
    obs_species_sql, excl_filter))

  invisible(NULL)
}


#' Derive the list of observation species codes for an AOI
#' from the wsg_species_presence table.
#' @noRd
.lnk_pipeline_break_obs_species <- function(loaded, aoi) {
  wsg_sp <- loaded$wsg_species_presence
  if (is.null(wsg_sp)) return(character(0))
  row <- wsg_sp[wsg_sp$watershed_group_code == aoi, ]
  if (nrow(row) == 0) return(character(0))

  spp_cols <- c("bt", "ch", "cm", "co", "ct", "dv",
                "pk", "rb", "sk", "st", "wct")
  present <- vapply(spp_cols,
    function(x) identical(row[[x]], "t"), logical(1))
  sp <- toupper(spp_cols[present])

  # bcfishfobs records cutthroat as CT, CCT, ACT, or CT/RB — all
  # resolve to the same species in wsg_species_presence.
  if ("CT" %in% sp) sp <- c(sp, "CCT", "ACT", "CT/RB")
  sp
}


#' Build habitat_endpoints: DRM + URM from user_habitat_classification
#' @noRd
.lnk_pipeline_break_habitat_endpoints <- function(conn, aoi, schema) {
  exists <- DBI::dbGetQuery(conn, sprintf(
    "SELECT 1 FROM information_schema.tables
     WHERE table_schema = %s AND table_name = 'user_habitat_classification'",
    .lnk_quote_literal(schema)))
  if (nrow(exists) == 0) {
    # Create an empty table so the break step is a no-op
    .lnk_db_execute(conn, sprintf(
      "DROP TABLE IF EXISTS %s.habitat_endpoints", schema))
    .lnk_db_execute(conn, sprintf(
      "CREATE TABLE %s.habitat_endpoints
         (blue_line_key integer,
          downstream_route_measure double precision)", schema))
    return(invisible(NULL))
  }

  .lnk_db_execute(conn, sprintf(
    "DROP TABLE IF EXISTS %s.habitat_endpoints", schema))
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE %s.habitat_endpoints AS
     SELECT DISTINCT blue_line_key,
            round(downstream_route_measure) AS downstream_route_measure
     FROM %s.user_habitat_classification
     WHERE watershed_group_code = %s
     UNION
     SELECT DISTINCT blue_line_key,
            round(upstream_route_measure) AS downstream_route_measure
     FROM %s.user_habitat_classification
     WHERE watershed_group_code = %s",
    schema, schema, .lnk_quote_literal(aoi),
    schema, .lnk_quote_literal(aoi)))

  invisible(NULL)
}


#' Build crossings_breaks positions
#' @noRd
.lnk_pipeline_break_crossings <- function(conn, schema) {
  .lnk_db_execute(conn, sprintf(
    "DROP TABLE IF EXISTS %s.crossings_breaks", schema))
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE %s.crossings_breaks AS
     SELECT blue_line_key,
            round(downstream_route_measure) AS downstream_route_measure
     FROM %s.crossings",
    schema, schema))

  invisible(NULL)
}


#' Reassign unique id_segment after a break round
#' @noRd
.lnk_pipeline_break_reassign_id <- function(conn) {
  .lnk_db_execute(conn, "DROP INDEX IF EXISTS fresh.streams_id_segment_idx")
  .lnk_db_execute(conn,
    "WITH numbered AS (
       SELECT ctid, row_number() OVER
         (ORDER BY blue_line_key, downstream_route_measure) AS rn
       FROM fresh.streams
     )
     UPDATE fresh.streams s SET id_segment = numbered.rn
     FROM numbered WHERE s.ctid = numbered.ctid")
  .lnk_db_execute(conn,
    "CREATE UNIQUE INDEX streams_id_segment_idx
       ON fresh.streams (id_segment)")

  invisible(NULL)
}

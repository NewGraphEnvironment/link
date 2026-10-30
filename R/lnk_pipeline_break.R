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
#' observations → gradient_minimal → falls → barriers_definite →
#' habitat_endpoints → crossings. This order is encoded in the bundled
#' bcfishpass config (`cfg$pipeline$break_order`) and is the default
#' when the config does not specify one.
#'
#' ## Break sources
#'
#' Valid entries for `cfg$pipeline$break_order`. Omitting an entry skips its
#' segmentation. Only `subsurfaceflow` is also read off `break_order` for
#' access: it is built and gates access only when listed. The other barrier
#' sources still gate access through classify's breaks table and the access
#' walk's barrier tables, and `access_<sp>` code 2 ("observed upstream") is
#' still computed from `<schema>.observations` by [lnk_pipeline_access()], at
#' the resolution of the segments that remain.
#'
#' | name | source table | role | classify label |
#' |---|---|---|---|
#' | `observations` | `<schema>.observations_breaks` | fish observations from `bcfishobs.observations`, WSG- and species-filtered, exclusions applied. `cfg$pipeline$observation_breaks` picks the positions: `all` (every one, what bcfishpass does; the value when absent) or `top_per_species` (on each `blue_line_key`, each species' farthest-upstream observation; the `default` bundle). Code 2 counts a same-line record only more than 1 m above a segment's start (as bcfishpass does), so a species turns from code 2 to 1 at its own top break, and at a kept top for species recorded only below it | (informational; not a barrier) |
#' | `gradient_minimal` | `<schema>.gradient_barriers_minimal` | each present species' post-lift natural barriers (gradient at its classes, falls, opt-in subsurface flow, minus its overrides, plus user-definite), reduced to the downstream-most position per flow path (#326) | classify gates on the full `gradient_barriers_raw` set with `gradient_<NNNN>` labels |
#' | `falls` | `<schema>.falls` | natural waterfalls from fresh's `inst/extdata/falls.csv` (read by [lnk_pipeline_prepare()]); each fall is its own barrier (NOT minimal-reduced) | `blocked` |
#' | `barriers_definite` | `<schema>.barriers_definite` | `user_barriers_definite.csv` for the AOI | `blocked` |
#' | `subsurfaceflow` | `<schema>.barriers_subsurfaceflow` | FWA `edge_type IN (1410, 1425)` start points; honours `user_barriers_definite_control`. Opt-in (only built when listed) | `blocked` |
#' | `habitat_endpoints` | `<schema>.habitat_endpoints` | DRM and URM from `user_habitat_classification.csv` | (segmentation only; not a barrier) |
#' | `crossings` | `<schema>.crossings_breaks` | PSCIS + modelled crossings (any `barrier_status`) | classify maps `barrier_status` → `barrier`/`potential`/`passable` |
#'
#' Bcfishpass-bundle config opts in to `subsurfaceflow` for parity with
#' bcfishpass natural access. Default-bundle leaves it off pending a
#' NewGraph methodology decision.
#'
#' Writes to (under the caller's working schema unless noted):
#'   - `<schema>.observations_breaks` — WSG- and species-filtered
#'     observation positions, data-error exclusions applied, reduced to each
#'     species' top per line under `observation_breaks: top_per_species`
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

  .lnk_pipeline_break_obs(conn, aoi, loaded, schema, observations,
                          mode = .lnk_observation_breaks(cfg))
  .lnk_pipeline_break_habitat_endpoints(conn, aoi, schema)
  .lnk_pipeline_break_crossings(conn, schema)

  break_order <- .lnk_break_order(cfg)
  # Source table for each valid break_order entry. To add a new break
  # source: register it here, ensure the table is materialized in the
  # appropriate prepare/break helper (gated on the entry being in
  # break_order so opt-out remains zero-cost), and document the entry in
  # this function's roxygen `## Break sources` section + the per-bundle
  # config.yaml comment.
  source_tables <- list(
    observations      = paste0(schema, ".observations_breaks"),
    gradient_minimal  = paste0(schema, ".gradient_barriers_minimal"),
    falls             = paste0(schema, ".falls"),
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
      table = paste0(schema, ".streams"),
      breaks = src_table,
      segment_id = "id_segment",
      measure_precision = 0L)
    .lnk_pipeline_break_reassign_id(conn, schema)
  }

  invisible(conn)
}


#' Build observations_breaks from the per-AOI filtered observations table
#'
#' Reads from `<schema>.observations`, materialized by
#' `.lnk_pipeline_prep_observations()`, which already applies the WSG
#' species-presence filter and the QA exclusions (mirrors bcfp's
#' `bcfishpass.observations` build).
#'
#' `mode` is the bundle's `pipeline: observation_breaks:` value
#' (`.lnk_observation_breaks()`):
#'
#' - `"all"`: every observation position, as bcfishpass cuts.
#' - `"top_per_species"`: on each `blue_line_key`, each species' farthest-
#'   upstream observation (#396). The access walk reads `<schema>.observations`
#'   itself, not this table, and counts a same-line record only more than 1 m
#'   above a segment's start (#399), so each species turns from code 2 to 1 at
#'   its own top break; the tops are also where species recorded only below
#'   them turn.
#'
#' Positions are rounded to the metre either way; `round(max(m))` equals
#' `max(round(m))`, so the tops are a subset of the `"all"` positions.
#' @noRd
.lnk_pipeline_break_obs <- function(conn, aoi, loaded, schema, observations,
                                    mode = "all") {
  .lnk_observation_breaks_check(mode)
  .lnk_db_execute(conn, sprintf(
    "DROP TABLE IF EXISTS %s.observations_breaks", schema))
  if (identical(mode, "top_per_species")) {
    .lnk_db_execute(conn, sprintf(
      "CREATE TABLE %s.observations_breaks AS
       SELECT DISTINCT blue_line_key, downstream_route_measure
       FROM (
         SELECT blue_line_key,
                round(max(downstream_route_measure)) AS downstream_route_measure
         FROM %s.observations
         GROUP BY blue_line_key, species_code
       ) tops",
      schema, schema))
  } else {
    .lnk_db_execute(conn, sprintf(
      "CREATE TABLE %s.observations_breaks AS
       SELECT DISTINCT blue_line_key,
              round(downstream_route_measure) AS downstream_route_measure
       FROM %s.observations",
      schema, schema))
  }

  invisible(NULL)
}


#' The break sources a bundle applies, in order
#'
#' `pipeline: break_order:`, or the default when absent
#' (`subsurfaceflow` left out).
#' @noRd
.lnk_break_order <- function(cfg) {
  cfg$pipeline$break_order %||% c(
    "observations", "gradient_minimal", "falls",
    "barriers_definite", "habitat_endpoints", "crossings"
  )
}

#' Which observation positions break streams
#'
#' A bundle's `pipeline: observation_breaks:`, `"all"` when absent (what
#' bcfishpass does). See `.lnk_pipeline_break_obs()`.
#' @noRd
.lnk_observation_breaks <- function(cfg) {
  v <- cfg$pipeline[["observation_breaks"]] %||% "all"
  .lnk_observation_breaks_check(v, paste0("cfg '", cfg$name %||% "", "'"))
}

#' Validate an observation_breaks value
#' @noRd
.lnk_observation_breaks_check <- function(v, what = "observation_breaks") {
  ok <- c("all", "top_per_species")
  if (!is.character(v) || length(v) != 1L || is.na(v) || !v %in% ok) {
    stop(what, ": observation_breaks must be one of ",
         paste(ok, collapse = ", "), call. = FALSE)
  }
  v
}


#' Derive the list of observation species codes for an AOI
#' from the wsg_species_presence table.
#' @noRd
.lnk_pipeline_break_obs_species <- function(loaded, aoi) {
  wsg_sp <- loaded$wsg_species_presence
  if (is.null(wsg_sp)) return(character(0))
  row <- wsg_sp[wsg_sp$watershed_group_code == aoi, ]
  if (nrow(row) == 0) return(character(0))

  sp <- .lnk_wsg_species_present(row)

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
.lnk_pipeline_break_reassign_id <- function(conn, schema) {
  streams_tbl <- paste0(schema, ".streams")
  .lnk_db_execute(conn, sprintf(
    "DROP INDEX IF EXISTS %s.streams_id_segment_idx", schema))
  .lnk_db_execute(conn, sprintf(
    "WITH numbered AS (
       SELECT ctid, row_number() OVER
         (ORDER BY blue_line_key, downstream_route_measure) AS rn
       FROM %1$s
     )
     UPDATE %1$s s SET id_segment = numbered.rn
     FROM numbered WHERE s.ctid = numbered.ctid", streams_tbl))
  .lnk_db_execute(conn, sprintf(
    "CREATE UNIQUE INDEX streams_id_segment_idx
       ON %s (id_segment)", streams_tbl))

  invisible(NULL)
}

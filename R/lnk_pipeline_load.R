#' Load Crossings and Apply Crossing-Level Overrides
#'
#' Second phase of the habitat classification pipeline. Loads the
#' anthropogenic crossing table for an AOI and applies the two
#' crossing-level override types from the config bundle:
#'
#' 1. **Modelled crossing fixes** — imagery/field corrections where
#'    `structure = "NONE"` or `structure = "OBS"` force the crossing's
#'    `barrier_status` to `"PASSABLE"`. These are modelled culverts
#'    that, on inspection, turned out to be open channels or
#'    observation-only points.
#' 2. **PSCIS barrier status overrides** — expert-curated
#'    `user_barrier_status` values replace the modelled
#'    `barrier_status` for a PSCIS crossing.
#'
#' Falls, user-identified definite barriers, observation exclusions,
#' and habitat classification CSVs are loaded by
#' [lnk_pipeline_prepare()] where they are consumed, not here.
#'
#' Writes to these tables under the caller's working schema:
#'   - `<schema>.crossings` — base crossings + misc crossings, with
#'     overridden `barrier_status` applied
#'   - `<schema>.crossing_fixes` — modelled fixes for the AOI (only
#'     when the config bundle has fixes matching this AOI)
#'   - `<schema>.pscis_fixes` — PSCIS status overrides for the AOI
#'     (only when the config bundle has entries matching this AOI)
#'
#' @param conn A [DBI::DBIConnection-class] object (localhost fwapg,
#'   typically from [lnk_db_conn()]).
#' @param aoi Character. Today accepts a watershed group code (e.g.
#'   `"BULK"`). Filtering against `watershed_group_code` columns in the
#'   CSVs means polygon / ltree AOIs are not yet supported here; those
#'   will come as a follow-up.
#' @param cfg An `lnk_config` object from [lnk_config()].
#' @param loaded Named list of tibbles from [lnk_load_overrides()].
#'   Carries the override CSVs (`user_crossings_misc`,
#'   `user_modelled_crossing_fixes`, `user_pscis_barrier_status`) this
#'   phase needs.
#' @param schema Character. Working schema name (validated). Must
#'   already exist — call [lnk_pipeline_setup()] first.
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
#'
#' schema <- "working_bulk"
#' lnk_pipeline_setup(conn, schema)
#' lnk_pipeline_load(conn, aoi = "BULK", cfg = cfg, loaded = loaded,
#'                   schema = schema)
#'
#' # Inspect the result
#' DBI::dbGetQuery(conn, sprintf(
#'   "SELECT barrier_status, count(*) FROM %s.crossings GROUP BY 1", schema))
#'
#' DBI::dbDisconnect(conn)
#' }
lnk_pipeline_load <- function(conn, aoi, cfg, loaded, schema) {
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

  crossings <- .lnk_pipeline_load_crossings(conn, aoi, loaded, schema)
  .lnk_pipeline_apply_fixes(conn, aoi, loaded, schema, crossings)
  .lnk_pipeline_apply_pscis(conn, aoi, loaded, schema)

  invisible(conn)
}


#' Load base + misc crossings into the working schema
#' @noRd
.lnk_pipeline_load_crossings <- function(conn, aoi, loaded, schema) {
  crossings_path <- system.file("extdata", "crossings.csv",
                                 package = "fresh")
  if (!nzchar(crossings_path)) {
    stop("fresh package crossings.csv not found — is fresh installed?",
         call. = FALSE)
  }

  all_crossings <- utils::read.csv(crossings_path, stringsAsFactors = FALSE)
  crossings <- all_crossings[all_crossings$watershed_group_code == aoi, ]
  crossings$aggregated_crossings_id <- as.character(
    crossings$aggregated_crossings_id)

  DBI::dbWriteTable(conn,
    DBI::Id(schema = schema, table = "crossings"),
    crossings, overwrite = TRUE)

  # Append misc crossings (weirs, unassessed culverts, flood control).
  # Misc IDs are offset into a distinct range so they don't collide with
  # the modelled crossings table.
  misc_all <- loaded$user_crossings_misc
  if (!is.null(misc_all) && nrow(misc_all) > 0) {
    misc <- misc_all[misc_all$watershed_group_code == aoi, ]
    if (nrow(misc) > 0) {
      misc$aggregated_crossings_id <- as.character(
        misc$user_crossing_misc_id + 1200000000L)
      for (col in setdiff(names(crossings), names(misc))) misc[[col]] <- NA
      DBI::dbWriteTable(conn,
        DBI::Id(schema = schema, table = "crossings"),
        misc[, names(crossings)], append = TRUE)
    }
  }

  crossings
}


#' Apply modelled crossing fixes: NONE/OBS → PASSABLE
#' @noRd
.lnk_pipeline_apply_fixes <- function(conn, aoi, loaded, schema, crossings) {
  fixes_all <- loaded$user_modelled_crossing_fixes
  if (is.null(fixes_all) || nrow(fixes_all) == 0) return(invisible(NULL))

  fixes <- fixes_all[fixes_all$watershed_group_code == aoi, ]
  if (nrow(fixes) == 0) return(invisible(NULL))

  names(fixes)[names(fixes) == "modelled_crossing_id"] <-
    "aggregated_crossings_id"
  fixes$aggregated_crossings_id <- as.character(
    fixes$aggregated_crossings_id)

  DBI::dbWriteTable(conn,
    DBI::Id(schema = schema, table = "crossing_fixes"),
    fixes, overwrite = TRUE)

  .lnk_db_execute(conn, sprintf(
    "UPDATE %s.crossings c SET barrier_status = 'PASSABLE'
     FROM %s.crossing_fixes f
     WHERE c.aggregated_crossings_id = f.aggregated_crossings_id::text
       AND f.structure IN ('NONE', 'OBS')",
    schema, schema))

  invisible(NULL)
}


#' Apply PSCIS barrier status overrides
#' @noRd
.lnk_pipeline_apply_pscis <- function(conn, aoi, loaded, schema) {
  pscis_all <- loaded$user_pscis_barrier_status
  if (is.null(pscis_all) || nrow(pscis_all) == 0) return(invisible(NULL))

  pscis <- pscis_all[pscis_all$watershed_group_code == aoi, ]
  if (nrow(pscis) == 0) return(invisible(NULL))

  names(pscis)[names(pscis) == "stream_crossing_id"] <-
    "aggregated_crossings_id"
  names(pscis)[names(pscis) == "user_barrier_status"] <- "barrier_status"
  pscis$aggregated_crossings_id <- as.character(
    pscis$aggregated_crossings_id)

  DBI::dbWriteTable(conn,
    DBI::Id(schema = schema, table = "pscis_fixes"),
    pscis, overwrite = TRUE)

  lnk_override(conn,
    crossings = paste0(schema, ".crossings"),
    overrides = paste0(schema, ".pscis_fixes"),
    col_id = "aggregated_crossings_id",
    cols_update = "barrier_status")

  invisible(NULL)
}

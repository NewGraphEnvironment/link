#' Set Up the Working Schema for a Pipeline Run
#'
#' Creates the per-run working schema and ensures the `fresh` output
#' schema exists. Every downstream pipeline helper (`lnk_pipeline_*`)
#' assumes these schemas are in place.
#'
#' When running multiple AOIs (watershed groups, mapsheets, sub-basins)
#' in parallel on the same host, each run uses its own namespaced
#' working schema so the runs do not collide. The caller decides the
#' schema name — a typical WSG-based choice is
#' `paste0("working_", tolower(aoi))`.
#'
#' @param conn A [DBI::DBIConnection-class] object (localhost fwapg,
#'   typically from [lnk_db_conn()]).
#' @param schema Character. Working schema name for this run. Default
#'   `"working"`. Validated as a SQL identifier.
#' @param overwrite Logical. If `TRUE`, drop `schema` (CASCADE) before
#'   creating. Default `FALSE` — create only if absent so cached
#'   contents from prior runs survive.
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
#'
#' # Single-AOI run, canonical per-WSG schema
#' lnk_pipeline_setup(conn, "working_bulk")
#'
#' # Fresh start: wipe any prior state first
#' lnk_pipeline_setup(conn, "working_bulk", overwrite = TRUE)
#'
#' DBI::dbDisconnect(conn)
#' }
lnk_pipeline_setup <- function(conn, schema = "working",
                                overwrite = FALSE) {
  .lnk_validate_identifier(schema, "schema")

  if (overwrite) {
    .lnk_db_execute(conn,
      sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema))
  }
  .lnk_db_execute(conn,
    sprintf("CREATE SCHEMA IF NOT EXISTS %s", schema))
  .lnk_db_execute(conn, "CREATE SCHEMA IF NOT EXISTS fresh")

  invisible(conn)
}

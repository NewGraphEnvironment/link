#' Set Up the Working Schema for a Habitat Pipeline Run
#'
#' Creates the per-run working schema and ensures the `fresh` output
#' schema exists. Every downstream pipeline helper (`lnk_habitat_*`)
#' assumes these schemas are in place.
#'
#' When running multiple watershed groups in parallel on the same host,
#' each run uses its own namespaced working schema (e.g.
#' `working_bulk`, `working_adms`) so the runs do not collide. The
#' canonical `_targets.R` call is
#' `lnk_habitat_setup_schema(conn, paste0("working_", tolower(wsg)))`.
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
#' @family habitat pipeline
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#'
#' # Single-WSG run, canonical per-WSG schema
#' lnk_habitat_setup_schema(conn, "working_bulk")
#'
#' # Fresh start: wipe any prior state first
#' lnk_habitat_setup_schema(conn, "working_bulk", overwrite = TRUE)
#'
#' DBI::dbDisconnect(conn)
#' }
lnk_habitat_setup_schema <- function(conn, schema = "working",
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

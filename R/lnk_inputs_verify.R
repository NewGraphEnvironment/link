#' Verify that required Postgres tables exist in a connection
#'
#' Fail-loud precondition check used by pipeline phases that assume their
#' input tables are already loaded (typically by a separate snapshot
#' script). Lists every missing `<schema>.<table>` in the error message
#' so the caller knows exactly what to load before re-running.
#'
#' Generic — not specific to any pipeline phase. Likely belongs in a
#' future `pac` package once that's scaffolded; ships in link for now.
#'
#' @param conn A DBI connection.
#' @param required Character vector of fully-qualified `<schema>.<table>`
#'   strings (e.g. `c("whse_fish.pscis_assessment_svw", "fresh.dams")`).
#'   Identifiers are not quoted — bare lowercase form expected.
#'
#' @return `invisible(NULL)` on success. `stop()`s with a list of missing
#'   tables on failure.
#'
#' @details
#' Queries `information_schema.tables` once per call, parameterised with
#' the parsed `(schema, table)` pairs — single round-trip regardless of
#' how many tables are in `required`.
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' lnk_inputs_verify(conn, c(
#'   "whse_fish.pscis_assessment_svw",
#'   "cabd.dams",
#'   "working_adms.modelled_stream_crossings"
#' ))
#' }
#'
#' @family inputs
#' @export
lnk_inputs_verify <- function(conn, required) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(required), length(required) >= 1L,
    all(nzchar(required))
  )

  # Parse "schema.table" pairs. Reject anything malformed.
  parts <- strsplit(required, ".", fixed = TRUE)
  bad <- vapply(parts, function(p) length(p) != 2L || !all(nzchar(p)),
                logical(1))
  if (any(bad)) {
    stop(sprintf(
      "lnk_inputs_verify: expected '<schema>.<table>' format, got: %s",
      paste(required[bad], collapse = ", ")
    ))
  }
  schemas <- vapply(parts, `[`, character(1), 1L)
  tables  <- vapply(parts, `[`, character(1), 2L)

  # Single round-trip: existence-check via information_schema. Values
  # are inline-quoted (RPostgres' parameterized text[] support is finicky;
  # safer to format the VALUES clause directly with dbQuoteString).
  values <- vapply(seq_along(schemas), function(i) {
    sprintf("(%s, %s)",
            DBI::dbQuoteString(conn, schemas[i]),
            DBI::dbQuoteString(conn, tables[i]))
  }, character(1))
  values_sql <- paste(values, collapse = ", ")

  res <- DBI::dbGetQuery(conn, sprintf(
    "SELECT s.schema_name, s.table_name,
            (t.table_name IS NOT NULL) AS exists
     FROM (VALUES %s) AS s(schema_name, table_name)
     LEFT JOIN information_schema.tables t
       ON t.table_schema = s.schema_name
      AND t.table_name   = s.table_name",
    values_sql
  ))

  missing <- res[!res$exists, , drop = FALSE]
  if (nrow(missing) > 0L) {
    stop(sprintf(
      "lnk_inputs_verify: required tables not found in connection:\n  %s",
      paste0(missing$schema_name, ".", missing$table_name, collapse = "\n  ")
    ))
  }

  invisible(NULL)
}

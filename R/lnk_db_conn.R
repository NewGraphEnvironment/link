#' Connect to a PostgreSQL database
#'
#' Thin connection factory with sensible defaults. Reads credentials from
#' environment variables (`PGUSER`, `PGPASSWORD`, `PGHOST`, `PGPORT`,
#' `PGDATABASE`) so connections work without hardcoded secrets.
#'
#' @param dbname Database name. Defaults to `PGDATABASE` env var or `"postgis"`.
#' @param host Host. Defaults to `PGHOST` env var or `"localhost"`.
#' @param port Port. Defaults to `PGPORT` env var or `5432`.
#' @param user User. Defaults to `PGUSER` env var or `"postgres"`.
#' @param password Password. Defaults to `PGPASSWORD` env var or `""`.
#'
#' @return A [DBI::DBIConnection-class] object.
#'
#' @details
#' This is the standard entry point for all `lnk_*` functions that need a
#' database connection. Pass the returned connection as the first argument
#' to any function in the package.
#'
#' Environment variables follow the PostgreSQL convention (`PGUSER`, etc.)
#' so they work alongside `psql`, `ogr2ogr`, and other tools that read
#' the same variables.
#'
#' @examples
#' \dontrun{
#' # Default connection — reads PGUSER, PGPASSWORD from environment
#' conn <- lnk_db_conn()
#'
#' # Override for a specific database
#' conn <- lnk_db_conn(dbname = "fishpass", host = "db.example.com")
#'
#' # Use with other lnk_* functions
#' conn <- lnk_db_conn()
#' lnk_score_severity(conn, "working.crossings")
#'
#' DBI::dbDisconnect(conn)
#' }
#'
#' @export
lnk_db_conn <- function(dbname = Sys.getenv("PGDATABASE", "postgis"),
                        host = Sys.getenv("PGHOST", "localhost"),
                        port = as.integer(Sys.getenv("PGPORT", "5432")),
                        user = Sys.getenv("PGUSER", "postgres"),
                        password = Sys.getenv("PGPASSWORD", "")) {
  DBI::dbConnect(
    RPostgres::Postgres(),
    dbname = dbname,
    host = host,
    port = port,
    user = user,
    password = password
  )
}

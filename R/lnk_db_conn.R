#' Connect to FWA PostgreSQL database
#'
#' Opens a connection to a PostgreSQL database containing fwapg, bcfishpass,
#' and bcfishobs. Defaults to the `PG_*_SHARE` environment variables used
#' by fresh and fpr (Docker-hosted fwapg). Falls back to standard `PG*`
#' variables for local PostgreSQL.
#'
#' @param dbname Database name. Defaults to `PG_DB_SHARE` or `PGDATABASE`.
#' @param host Host. Defaults to `PG_HOST_SHARE` or `PGHOST`.
#' @param port Port. Defaults to `PG_PORT_SHARE` or `PGPORT`.
#' @param user User. Defaults to `PG_USER_SHARE` or `PGUSER`.
#' @param password Password. Defaults to `PG_PASS_SHARE` or `PGPASSWORD`.
#'
#' @return A [DBI::DBIConnection-class] object.
#'
#' @details
#' Checks `PG_*_SHARE` first (the Docker fwapg convention shared with
#' [fresh::frs_db_conn()]), then standard PostgreSQL variables (`PGHOST`,
#' etc.). This means `lnk_db_conn()` works identically to `frs_db_conn()`
#' when both packages connect to the same database.
#'
#' @examples
#' \dontrun{
#' # Default — reads PG_*_SHARE env vars (Docker fwapg)
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
lnk_db_conn <- function(dbname = Sys.getenv("PG_DB_SHARE",
                                            Sys.getenv("PGDATABASE", "postgis")),
                        host = Sys.getenv("PG_HOST_SHARE",
                                          Sys.getenv("PGHOST", "localhost")),
                        port = as.integer(Sys.getenv("PG_PORT_SHARE",
                                                     Sys.getenv("PGPORT", "5432"))),
                        user = Sys.getenv("PG_USER_SHARE",
                                          Sys.getenv("PGUSER", "postgres")),
                        password = Sys.getenv("PG_PASS_SHARE",
                                              Sys.getenv("PGPASSWORD", ""))) {
  DBI::dbConnect(
    RPostgres::Postgres(),
    dbname = dbname,
    host = host,
    port = port,
    user = user,
    password = password
  )
}

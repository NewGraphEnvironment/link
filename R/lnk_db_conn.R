#' Connect to FWA PostgreSQL database
#'
#' Opens a connection to a PostgreSQL database containing fwapg, bcfishpass,
#' and bcfishobs, through [fresh::frs_db_conn()], so link and fresh resolve a
#' connection the same way and a bare call to either reaches the same
#' database.
#'
#' @param dbname Database name. Default `NULL` (resolved as below).
#' @param host Host. Default `NULL`.
#' @param port Port. Default `NULL`.
#' @param user User. Default `NULL`.
#' @param password Password. Default `NULL`.
#' @param connect_timeout Seconds to wait for each connection attempt, a
#'   whole number; `0` waits without limit. Default `NULL`: `PGCONNECT_TIMEOUT`
#'   when set, otherwise 10. Passed to [fresh::frs_db_conn()].
#' @param ... Further libpq connection keywords, passed to
#'   [fresh::frs_db_conn()] (which sets TCP keepalives by default).
#'
#' @return A [DBI::DBIConnection-class] object.
#'
#' @details
#' Parameters resolve in this order, as [fresh::frs_db_conn()] resolves them:
#'
#' 1. Explicit arguments, field by field.
#' 2. The standard libpq variables (`PGHOST`, `PGPORT`, `PGDATABASE`,
#'    `PGUSER`, `PGPASSWORD`, `PGSERVICE`, ...). When any of `PGHOST`,
#'    `PGHOSTADDR`, `PGPORT`, `PGDATABASE`, `PGUSER` or `PGSERVICE` is set,
#'    libpq resolves every field not given, and the `PG_*_SHARE` variables
#'    are not read.
#' 3. The legacy `PG_*_SHARE` variables (`PG_DB_SHARE`, `PG_HOST_SHARE`,
#'    `PG_PORT_SHARE`, `PG_USER_SHARE`, `PG_PASS_SHARE`), only when none of
#'    the standard variables above is set. fresh marks them deprecated and
#'    says so once per R session. A call giving all five fields does not read
#'    them at all, so it neither prints that message nor uses it up.
#' 4. libpq's own defaults (the local socket or `localhost`, the operating
#'    system's user name, `~/.pgpass`).
#'
#' The two groups of variables are never mixed. Before link 0.87.0 this
#' function read `PG_*_SHARE` first and fell back to `postgres@localhost:5432`
#' and the database `postgis`; on a machine setting both groups, a bare call
#' now reaches the `PG*` target, so pass the arguments to reach the other one.
#'
#' @examples
#' \dontrun{
#' # The environment's database: PG* variables, else PG_*_SHARE
#' conn <- lnk_db_conn()
#' DBI::dbDisconnect(conn)
#'
#' # A named database: every field given, so the environment fills nothing
#' conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
#'                     user = "postgres", password = "postgres")
#' DBI::dbDisconnect(conn)
#'
#' # A slow link: wait longer to connect
#' conn <- lnk_db_conn(connect_timeout = 30)
#' DBI::dbDisconnect(conn)
#' }
#'
#' @export
lnk_db_conn <- function(dbname = NULL, host = NULL, port = NULL, user = NULL,
                        password = NULL, connect_timeout = NULL, ...) {
  conn <- function() {
    fresh::frs_db_conn(dbname = dbname, host = host, port = port, user = user,
                       password = password, connect_timeout = connect_timeout,
                       ...)
  }
  given <- list(dbname, host, port, user, password)
  if (!all(vapply(given, .lnk_conn_arg_set, logical(1)))) return(conn())
  # With every field given the PG_*_SHARE variables fill nothing, but fresh
  # reads the environment before the arguments: it would print its deprecation
  # message, and spend its once-per-session notice (set before it prints), so a
  # later call that does read them would say nothing. Unset them for this call.
  share <- c("PG_DB_SHARE", "PG_HOST_SHARE", "PG_PORT_SHARE", "PG_USER_SHARE",
             "PG_PASS_SHARE")
  old <- Sys.getenv(share, unset = NA)
  old <- old[!is.na(old)]
  if (length(old) > 0L) {
    Sys.unsetenv(names(old))
    on.exit(do.call(Sys.setenv, as.list(old)), add = TRUE)
  }
  conn()
}

# A connection field the caller gave, by fresh's own test (NULL, NA and ""
# are unset), so link and fresh agree on which fields the environment fills.
.lnk_conn_arg_set <- function(x) {
  !is.null(x) && length(x) == 1L && !is.na(x) && nzchar(as.character(x))
}

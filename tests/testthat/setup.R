# Shared test helpers and fixtures for link tests
#
# Test data paths
test_thresholds_csv <- function() {
  system.file("extdata", "thresholds_default.csv", package = "link")
}

test_overrides_csv <- function() {
  system.file("extdata", "overrides_example.csv", package = "link")
}

test_crossings_csv <- function() {
  system.file("extdata", "crossings_example.csv", package = "link")
}

# Skip helper for DB-dependent tests
# Tries local Docker fwapg first (writable), then PG_*_SHARE env vars.
# Also checks write permission — read-only connections skip.
skip_if_no_db <- function() {
  # Try local Docker first (fresh/docker setup)
  conn <- tryCatch(
    DBI::dbConnect(RPostgres::Postgres(),
                   dbname = "fwapg", host = "localhost", port = 5432L,
                   user = "postgres", password = "postgres"),
    error = function(e) NULL
  )
  # Fall back to lnk_db_conn (PG_*_SHARE env vars)
  if (is.null(conn)) {
    conn <- tryCatch(lnk_db_conn(), error = function(e) NULL)
  }
  if (is.null(conn)) {
    testthat::skip("No database connection available")
  }
  # Check write permission
  can_write <- tryCatch({
    DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
    TRUE
  }, error = function(e) FALSE)
  if (!can_write) {
    DBI::dbDisconnect(conn)
    testthat::skip("Database is read-only (no write permission)")
  }
  withr::defer(DBI::dbDisconnect(conn), envir = parent.frame())
  conn
}

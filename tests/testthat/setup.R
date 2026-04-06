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
skip_if_no_db <- function() {
  conn <- tryCatch(
    DBI::dbConnect(
      RPostgres::Postgres(),
      dbname = Sys.getenv("PGDATABASE", "postgis"),
      host = Sys.getenv("PGHOST", "localhost"),
      port = as.integer(Sys.getenv("PGPORT", "5432")),
      user = Sys.getenv("PGUSER", "postgres"),
      password = Sys.getenv("PGPASSWORD", "")
    ),
    error = function(e) NULL
  )
  if (is.null(conn)) {
    testthat::skip("No database connection available")
  }
  withr::defer(DBI::dbDisconnect(conn), envir = parent.frame())
  conn
}

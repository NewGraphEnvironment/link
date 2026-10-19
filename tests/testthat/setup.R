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

# Write-path test doubles: a connection that is never used, and a capture of
# the SQL a function would execute, with DBI's probes stubbed.
fake_conn <- function() structure(list(), class = "DBIConnection")

# Capture SQL AND stub the DBI probes the write path makes.
capture_write <- function(expr, probe_rows = 0L, query_result = NULL) {
  captured <- character()
  testthat::local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(conn)
    }
  )
  testthat::with_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      if (!is.null(query_result)) return(query_result)
      if (probe_rows > 0L) data.frame(x = seq_len(probe_rows)) else
        data.frame()
    },
    dbQuoteLiteral = function(conn, x, ...) {
      if (is.logical(x)) return(if (isTRUE(x)) "TRUE" else "FALSE")
      paste0("'", gsub("'", "''", as.character(x)), "'")
    },
    .package = "DBI",
    force(expr)
  )
  captured
}

# Shared by the tests that run data-raw/ bash libs (test-study_area_hosts.R,
# test-study_area_finish.R).
# The libs need bash >= 4 (assoc arrays); macOS /bin/bash is 3.2.
hosts_bash <- function() {
  cands <- unique(c(
    "/opt/homebrew/bin/bash", "/usr/local/bin/bash",
    unname(Sys.which("bash"))
  ))
  for (b in cands[nzchar(cands) & file.exists(cands)]) {
    v <- suppressWarnings(system2(b, c("-c", shQuote("echo ${BASH_VERSINFO[0]}")),
      stdout = TRUE, stderr = FALSE
    ))
    n <- suppressWarnings(as.integer(v))
    if (length(n) == 1L && !is.na(n) && n >= 4L) {
      return(b)
    }
  }
  ""
}

# Gate for live tests that need fwapg's fwa_indexpoint() rework
# (NewGraphEnvironment/fwapg#41), ported from fresh's tests/testthat/helper-db.R
# (fresh v0.55.1) for link#383. The rework also makes FWA_LocateAlong place a
# measure at a stream's head, which link's head-measure locates depend on.
#
# - Without the migration the tests skip, naming it.
# - LNK_FWAPG_TRIAL=<absolute path>[:<path>...] applies the migration file(s)
#   inside a transaction fresh::frs_migration_trial() rolls back when the test
#   ends, so the tests can run against a migration no database has yet.
# - LNK_FWAPG_CURRENT=true says the database should already have it: then a
#   stale database fails instead of skipping, and the gate test in
#   test-lnk_fwapg_gate.R reads committed state on its own direct connection.

# A direct connection to the local docker fwapg: no skip, so the gate test
# fails on an unreachable database rather than passing.
lnk_fwapg_conn <- function() {
  DBI::dbConnect(
    RPostgres::Postgres(),
    host = Sys.getenv("LNK_TEST_PGHOST", "localhost"),
    port = as.integer(Sys.getenv("LNK_TEST_PGPORT", "5432")),
    dbname = Sys.getenv("LNK_TEST_PGDATABASE", "fwapg"),
    user = Sys.getenv("LNK_TEST_PGUSER", "postgres"),
    password = Sys.getenv("LNK_TEST_PGPASSWORD", "postgres"),
    connect_timeout = 10
  )
}

local_fwapg <- function(env = parent.frame()) {
  testthat::skip_on_ci()
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("RPostgres")
  conn <- tryCatch(lnk_fwapg_conn(), error = function(e) NULL)
  if (is.null(conn)) testthat::skip("no local fwapg database")
  withr::defer(DBI::dbDisconnect(conn), envir = env)
  conn
}

# Does this database's fwa_indexpoint() have fwapg#41's rework? The reworked
# one takes include_disconnected. '...'::regproc throws when the function is
# absent or ambiguous; the skip path catches that, the gate test does not.
lnk_indexpoint_current <- function(conn) {
  a <- tryCatch(
    DBI::dbGetQuery(conn,
      "SELECT pg_get_function_arguments('whse_basemapping.fwa_indexpoint'::regproc) AS a")$a,
    error = function(e) NA_character_)
  isTRUE(any(grepl("include_disconnected", a)))
}

# LNK_FWAPG_CURRENT, strictly: a value that is neither true nor false refuses,
# because guessing false would let a stale database skip instead of fail.
lnk_fwapg_current_wanted <- function() {
  v <- tolower(trimws(Sys.getenv("LNK_FWAPG_CURRENT")))
  if (v %in% c("true", "1", "yes", "y", "t", "on")) return(TRUE)
  if (!v %in% c("", "false", "0", "no", "n", "f", "off")) {
    stop("LNK_FWAPG_CURRENT is set to ", sQuote(Sys.getenv("LNK_FWAPG_CURRENT")),
         ", which is neither true nor false: refusing to guess, because guessing ",
         "false would let a stale database skip instead of fail")
  }
  FALSE
}

lnk_fwapg_trial_files <- function() {
  v <- Sys.getenv("LNK_FWAPG_TRIAL")
  if (!nzchar(v)) return(character())
  strsplit(v, .Platform$path.sep, fixed = TRUE)[[1]]
}

# A connection whose fwapg has the rework (committed or trialled), or a skip
# naming the migration that is missing.
local_fwapg_current <- function(env = parent.frame()) {
  conn <- local_fwapg(env)
  files <- lnk_fwapg_trial_files()
  if (length(files)) {
    # testthat runs from tests/testthat, so a relative path names another file
    absent <- files[!file.exists(files)]
    if (length(absent)) {
      stop("LNK_FWAPG_TRIAL names no such file: ", paste(absent, collapse = ", "),
           " (give an absolute path)")
    }
    # `env` passed through, or the rollback fires before the test body runs
    fresh::frs_migration_trial(conn, files, env = env)
  }
  if (!lnk_indexpoint_current(conn) && !lnk_fwapg_current_wanted()) {
    testthat::skip(paste(
      "fwapg predates migration 202610240132__indexpoint_tiebreak's rework",
      "(NewGraphEnvironment/fwapg#41); set LNK_FWAPG_TRIAL to trial it"))
  }
  conn
}

# data-raw/wsg_pipeline_run.R
#
# Modelling-only wrapper around `link::lnk_pipeline_run()` for the
# targets pipeline (data-raw/_targets.R) and the orchestrator scripts
# (run_provincial_parity.R, trifecta_*.sh).
#
# Writes per-WSG segment-level data into the persistent
# <persist_schema>.streams + per-species streams_habitat_<sp> + barriers
# tables. Drops the working schema on exit (cleanup_working = TRUE) so
# the per-WSG run leaves only the canonical persisted state behind.
#
# Responsibilities NOT in the library:
#   - resolve local fwapg env vars into a DBI connection
#   - emit the lnk_stamp markdown block (run provenance for logs)
#
# Return shape: invisible(NULL). Side effects are the writes to PG.

wsg_pipeline_run <- function(wsg, config, dams = TRUE,
                             cleanup_working = TRUE) {
  stopifnot(
    is.character(wsg), length(wsg) == 1L, nzchar(wsg),
    grepl("^[A-Z]{3,5}$", wsg),
    inherits(config, "lnk_config"),
    is.logical(dams), length(dams) == 1L,
    is.logical(cleanup_working), length(cleanup_working) == 1L
  )

  conn <- DBI::dbConnect(RPostgres::Postgres(),
    host = "localhost", port = 5432, dbname = "fwapg",
    user = "postgres", password = "postgres")
  on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

  # Stamp the run before doing any work - captures config provenance,
  # software versions, and DB snapshot counts so two runs on the same
  # state can be diffed for what changed.
  stamp <- link::lnk_stamp(config, conn = conn, aoi = wsg)
  message(format(stamp, "markdown"))

  loaded <- link::lnk_load_overrides(config)

  link::lnk_pipeline_run(
    conn            = conn,
    aoi             = wsg,
    cfg             = config,
    loaded          = loaded,
    dams            = dams,
    cleanup_working = cleanup_working
  )

  invisible(NULL)
}

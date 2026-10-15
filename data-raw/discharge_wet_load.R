#!/usr/bin/env Rscript
# discharge_wet_load.R — load wet's annual discharge pick into this host's
# database, for configs that read `pipeline: discharge_source: wet` (link#331).
#
# prepare joins discharge onto every group, so a host that runs such a config
# needs wet's table before its first WSG. This loads only what the pipeline
# reads (`months = 0, pick_only = TRUE`: about 4.5 M rows), from the published
# parts at fresh-bc/discharge/fwa/v1/, and records nothing else: wet's loader
# writes the manifest, build time and commit into the table's comment, which
# every run copies into <schema>.log_input.
#
#   Rscript data-raw/discharge_wet_load.R [--force]
#
# Idempotent: exits 0 without loading when lnk_preflight_discharge() already
# passes, unless --force. Connects with the PG* environment (PGHOST, PGPORT,
# PGDATABASE, PGUSER, PGPASSWORD), as snapshot_bcfp.sh does; default local
# fwapg. Prints "discharge_wet_load: complete" as its last line on success.

suppressPackageStartupMessages({
  if (identical(Sys.getenv("LNK_LOAD"), "loadall")) {
    pkgload::load_all(quiet = TRUE)
  } else {
    library(link)
  }
})
if (!requireNamespace("wet", quietly = TRUE)) {
  stop("wet is not installed: pak::pkg_install('NewGraphEnvironment/wet')",
       call. = FALSE)
}

env <- function(k, d) {
  v <- Sys.getenv(k)
  if (nzchar(v)) v else d
}
conn <- DBI::dbConnect(RPostgres::Postgres(),
  host = env("PGHOST", "localhost"), port = as.integer(env("PGPORT", "5432")),
  dbname = env("PGDATABASE", "fwapg"), user = env("PGUSER", "postgres"),
  password = env("PGPASSWORD", "postgres"))
cfg <- list(name = "wet", pipeline = list(discharge_source = "wet"))

before <- lnk_preflight_discharge(conn, cfg, quiet = TRUE)
if (before$ok && !"--force" %in% commandArgs(trailingOnly = TRUE)) {
  message("already loaded: ", before$comment)
} else {
  t0 <- Sys.time()
  wet::wet_db_load(conn, wet::wet_catalog(), months = 0, pick_only = TRUE)
  message(sprintf("loaded in %.1f min",
                  as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}
after <- lnk_preflight_discharge(conn, cfg)
DBI::dbDisconnect(conn)
if (!after$ok) quit(status = 1L)
cat("discharge_wet_load: complete\n")

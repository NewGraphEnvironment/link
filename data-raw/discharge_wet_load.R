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
#   Rscript data-raw/discharge_wet_load.R [--force] [--expect-load=<id>]
#
# Idempotent: exits 0 without loading when lnk_preflight_discharge() already
# passes, unless --force.
#
# --force replaces the whole `historical` scenario with the annual pick: on a
# host holding every month and source (103 M rows) it leaves only the pick.
#
# --expect-load: the load every host in a run must hold, the dispatcher's
# table comment without wet's `; subset` suffix
# (link:::.lnk_discharge_wet_load_id()). The published manifest can move on
# between loads, so a host is reloaded when it holds another load, and the
# script fails when the published one is not the expected one either: the
# hosts would classify on different discharge. Connects with the PG* environment (PGHOST, PGPORT,
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

args <- commandArgs(trailingOnly = TRUE)
expect <- sub("^--expect-load=", "", grep("^--expect-load=", args, value = TRUE))
expect <- if (length(expect) == 1L && nzchar(expect)) expect else NA_character_
held <- function(res) link:::.lnk_discharge_wet_load_id(res$comment)

before <- lnk_preflight_discharge(conn, cfg, quiet = TRUE)
current <- before$ok &&
  (is.na(expect) || identical(held(before), expect))
if (current && !"--force" %in% args) {
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
if (!is.na(expect) && !identical(held(after), expect)) {
  message("FAIL this host holds a different wet load from the dispatcher:\n",
          "  here:       ", held(after), "\n  dispatcher: ", expect, "\n",
          "Every host must classify on the same discharge. Reload the ",
          "dispatcher from the published build with ",
          "wet::wet_db_load(conn, wet::wet_catalog()) (every month and ",
          "source); --force here would keep only the annual pick.")
  quit(status = 1L)
}
cat("discharge_wet_load: complete\n")

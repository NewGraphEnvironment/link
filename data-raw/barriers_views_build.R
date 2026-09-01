#!/usr/bin/env Rscript
# barriers_views_build.R — build the per-species `_access` and per-source
# `_unified` barrier views ONCE, for the whole persist schema (link#250).
#
# Why this exists as its own step. Those views are SCHEMA-scoped: every WSG's
# recompute reads the same `<persist>.barriers_<sp>_access`. lnk_access()
# rebuilds them on every call, which is harmless serially and is the one piece
# of shared mutation in an otherwise AOI-partitioned job. Under a fan-out it is
# a lock convoy — `CREATE OR REPLACE VIEW` takes an AccessExclusiveLock, and a
# QUEUED exclusive request blocks every AccessShareLock behind it, so one
# job's DDL stalls every sibling's read until `lock_timeout` kills someone.
#
# So study_area_run.sh calls this once, before it fans out, and each job runs
# with LNK_VIEWS_PREBUILT=1 -> lnk_access(build_views = FALSE).
#
# Species: cfg$species, NOT a per-WSG active set. lnk_pipeline_species()
# returns intersect(configured, present), so every WSG's active set is a
# subset of cfg$species and one build covers all of them. A side effect worth
# knowing: the view family becomes UNIFORM. Before this, the schema held
# whichever subset the last WSG to run happened to need.
#
# Usage: [LNK_LOAD=loadall] [LNK_SCHEMA=<schema>] \
#          Rscript data-raw/barriers_views_build.R [config]

args   <- commandArgs(trailingOnly = TRUE)
config <- if (length(args) >= 1L && nzchar(args[1])) args[1] else "bcfishpass"

if (identical(Sys.getenv("LNK_LOAD"), "loadall")) {
  suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
} else {
  suppressPackageStartupMessages(library(link))
}
suppressPackageStartupMessages({
  library(DBI); library(RPostgres)
})

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

# Same fail-fast contract as wsg_recompute_one.R. This step runs BEFORE any
# job holds a read lock, so it should never wait — if it does, something else
# is wedged and we want to know now rather than after the fan-out starts.
invisible(DBI::dbExecute(conn, "SET statement_timeout = '600000'"))
invisible(DBI::dbExecute(conn, "SET lock_timeout = '60000'"))

cfg <- lnk_config(config)
.lnk_schema_env <- Sys.getenv("LNK_SCHEMA")
if (nzchar(.lnk_schema_env)) cfg$pipeline$schema <- .lnk_schema_env
sch <- cfg$pipeline$schema

species <- cfg$species
if (is.null(species) || length(species) == 0L) {
  loaded  <- lnk_load_overrides(cfg)
  species <- sort(unique(loaded$parameters_fresh$species_code))
}
if (length(species) == 0L) {
  stop("barriers_views_build: no species resolved from config '", config,
       "' — refusing to report success having built nothing", call. = FALSE)
}

t0 <- Sys.time()
lnk_barriers_views(conn, schema = sch, cfg = cfg,
                   species = toupper(species),
                   barriers_table = paste0(sch, ".barriers"))

# Assert what we claim, rather than reporting the absence of an error. This is
# the same set lnk_access(build_views = FALSE) will verify per job, so a
# mismatch here is far cheaper than N identical failures under the fan-out.
sp_set <- tolower(species)
need <- c(paste0(sch, ".barriers_", sp_set, "_access"),
          paste0(sch, ".barriers_", c("anthropogenic", "pscis", "dams"),
                 "_unified"))
absent <- need[!vapply(need, function(v) link:::.lnk_table_exists(conn, v),
                       logical(1))]
if (length(absent)) {
  stop("barriers_views_build: built without error but these are still ",
       "absent: ", paste(absent, collapse = ", "), call. = FALSE)
}

cat(sprintf(
  "[barriers_views_build] %s: %d views verified for %d species in %.1f s\n",
  sch, length(need), length(species),
  as.numeric(difftime(Sys.time(), t0, units = "secs"))))
quit(status = 0)

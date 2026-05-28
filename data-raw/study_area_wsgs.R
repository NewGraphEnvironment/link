#!/usr/bin/env Rscript
# study_area_wsgs.R — given a set of FOCAL watershed groups, print the
# drainage-CLOSED, MODELABLE set in DOWNSTREAM-FIRST order (one comma line).
#
# Thin CLI shim around [link::lnk_wsg_resolve()] — see `?lnk_wsg_resolve`
# for the methodology (FWA drainage closure via fresh::frs_wsg_drainage()
# composed with the bundle's wsg_species_presence filter, link#157).
#
# Stdout: one line — comma-separated WSG codes (DS-first). Used by
# `data-raw/study_area_run.sh` to seed per-host buckets.
#
# Usage: [LNK_LOAD=loadall] Rscript study_area_wsgs.R <FOCAL1,FOCAL2,...> [config]

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L || !nzchar(args[1])) {
  stop("usage: study_area_wsgs.R <FOCAL1,FOCAL2,...> [config]", call. = FALSE)
}
focal  <- toupper(strsplit(args[1], ",")[[1]])
focal  <- focal[nzchar(focal)]
config <- if (length(args) >= 2L && nzchar(args[2])) args[2] else "bcfishpass"

if (identical(Sys.getenv("LNK_LOAD"), "loadall")) {
  suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
} else {
  suppressPackageStartupMessages(library(link))
}

suppressPackageStartupMessages({
  library(DBI); library(RPostgres)
})
# Force local docker fwapg regardless of PG_*_SHARE env (matches every
# other driver script and the pre-#207 inline behaviour) — env-var
# defaults point at the db_newgraph tunnel which is dead on M1.
conn <- DBI::dbConnect(RPostgres::Postgres(), host = "localhost", port = 5432,
                       dbname = "fwapg", user = "postgres", password = "postgres")
on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

cfg    <- lnk_config(config)
loaded <- lnk_load_overrides(cfg)
keep   <- lnk_wsg_resolve(cfg, loaded, wsgs = focal, conn = conn)

if (length(keep) == 0L) {
  stop("no modelable WSGs after species-presence filter", call. = FALSE)
}
cat(paste(keep, collapse = ","), "\n")

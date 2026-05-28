#!/usr/bin/env Rscript
# wsg_run_one.R — run link's modelling + mapping_code pipeline for ONE WSG
# against the LOCAL fwapg (localhost:5432), persisting streams /
# streams_habitat_<sp> / barriers / barrier_overrides / streams_access /
# streams_mapping_code into the bundle's persist schema (cfg$pipeline$schema).
#
# Tunnel-free and host-agnostic: byte-identical invocation on the dispatcher
# and on every cypher. This is the atomic unit of the study-area run
# (data-raw/study_area_run.sh). Run the WSGs of a drainage DS-first (most-
# downstream first) so a WSG's downstream dam barriers are already persisted
# when its access / mapping_code is computed — that is what makes cross-WSG
# `;DAM` appear without any post-consolidate recompute (link#175).
#
# Usage: [LNK_LOAD=loadall] Rscript wsg_run_one.R <WSG> [config]
#   LNK_LOAD=loadall -> pkgload::load_all() (dispatcher dev checkout)
#   default          -> library(link)       (pak-installed, e.g. cyphers)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) stop("usage: wsg_run_one.R <WSG> [config]", call. = FALSE)
wsg    <- toupper(args[1])
config <- if (length(args) >= 2L && nzchar(args[2])) args[2] else "bcfishpass"

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

cfg    <- lnk_config(config)
# LNK_SCHEMA env var (set by study_area_run.sh --schema=) overrides the
# config's YAML default persist schema — used for side-by-side bundle
# compares so e.g. `--config=default --schema=fresh_default` doesn't
# clobber an earlier `--config=bcfishpass` run sitting in `fresh`.
.lnk_schema_env <- Sys.getenv("LNK_SCHEMA")
if (nzchar(.lnk_schema_env)) cfg$pipeline$schema <- .lnk_schema_env
loaded <- lnk_load_overrides(cfg)

# Defensive skip (link#157): a WSG with no bundle-species presence can't be
# modelled — lnk_pipeline_run errors "No species resolved for AOI". The
# study-area closure is already species-filtered (study_area_wsgs.R), so this
# is belt-and-suspenders: skip cleanly (exit 0) rather than fail the host run.
active <- lnk_pipeline_species(cfg, loaded, wsg)
if (length(active) == 0L) {
  cat(sprintf("[wsg_run_one] %s SKIP — no modeled species in this AOI\n", wsg))
  quit(status = 0)
}

t0 <- Sys.time()
lnk_pipeline_run(conn, aoi = wsg, cfg = cfg, loaded = loaded,
                 schema = paste0("working_", tolower(wsg)),
                 mapping_code = TRUE, cleanup_working = FALSE)
cat(sprintf("[wsg_run_one] %s done in %.1f min (persist=%s)\n",
            wsg, as.numeric(difftime(Sys.time(), t0, units = "mins")),
            cfg$pipeline$schema))

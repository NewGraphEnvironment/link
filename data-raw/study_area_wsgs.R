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
# --exact (link#361): no closure. The list is taken as given, in its given
# order, less the groups the config's species presence drops
# (`lnk_wsg_resolve(expand = FALSE)`). For a `study_area_buckets.R --atom=group`
# split, where each host's list is already the exact downstream-first set the
# driver should model, through `study_area_run.sh --buckets-exact`.
#
# Usage: [LNK_LOAD=loadall] Rscript study_area_wsgs.R [--exact] <FOCAL1,FOCAL2,...> <config>

args <- commandArgs(trailingOnly = TRUE)
exact <- "--exact" %in% args
args <- args[args != "--exact"]
if (length(args) < 1L || !nzchar(args[1])) {
  stop("usage: study_area_wsgs.R [--exact] <FOCAL1,FOCAL2,...> <config>", call. = FALSE)
}
focal  <- toupper(strsplit(args[1], ",")[[1]])
focal  <- focal[nzchar(focal)]
config <- if (length(args) >= 2L && nzchar(args[2])) args[2] else ""
if (!nzchar(config)) {
  message("study_area_wsgs.R: config is required. Name a bundle from inst/extdata/configs/ ",
          "(bcfishpass and default both resolve to schema 'fresh'; any bundle ",
          "but bcfishpass needs an explicit LNK_SCHEMA).")
  quit(status = 2)
}

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
keep   <- lnk_wsg_resolve(cfg, loaded, wsgs = focal, expand = !exact, conn = conn)

if (length(keep) == 0L) {
  stop("no modelable WSGs after species-presence filter", call. = FALSE)
}
# The run's species decision (link#278): config x presence, per kept group,
# collapsed to one line per distinct set. Written to LNK_DECISION_FILE when the
# driver names one; the bucket itself stays the only thing on stdout.
.decision_file <- Sys.getenv("LNK_DECISION_FILE")
if (nzchar(.decision_file)) {
  sp <- vapply(keep, function(g) {
    paste(sort(lnk_pipeline_species(cfg, loaded, g, paused = TRUE)), collapse = ",")
  }, character(1))
  lines <- vapply(unique(sp), function(s) {
    g <- keep[sp == s]
    sprintf("    %s: %d group%s (%s%s)", if (nzchar(s)) s else "<none>", length(g),
            if (length(g) == 1L) "" else "s", paste(utils::head(g, 8L), collapse = ","),
            if (length(g) > 8L) ",..." else "")
  }, character(1))
  cat(paste0(c(sprintf("  focal %s: %d kept", paste(focal, collapse = ","), length(keep)), lines),
             "\n"), sep = "", file = .decision_file, append = TRUE)
}
cat(paste(keep, collapse = ","), "\n")

#!/usr/bin/env Rscript
# study_area_wsgs.R — given a set of FOCAL watershed groups, print the
# drainage-CLOSED, MODELABLE set in DOWNSTREAM-FIRST order (one comma line).
#
# Closure: every WSG whose outlet wscode_ltree is an ancestor of (== at or
# downstream of) any focal WSG's outlet — i.e. the WSGs a focal WSG's water
# drains through. DS-first: ordered by outlet ltree depth ascending, so the
# most-downstream WSGs come first. Running a host's bucket in this order
# persists downstream dam barriers before upstream WSGs compute access, which
# is what makes cross-WSG `;DAM` correct from the per-host run (no recompute).
#
# MODELABLE filter (link#157, mirrors data-raw/wsgs_run_host.R): drop closure
# WSGs with no bundle-species presence. lnk_pipeline_run errors hard ("No
# species resolved for AOI") on a species-less WSG (e.g. lower-mainstem groups
# pulled in by closure), which would abort the whole host run. bcfp doesn't
# model those WSGs either, so excluding them matches the proven methodology.
#
# Sources of truth: public.wsg_outlet (closure) + loaded$wsg_species_presence
# (modelable), both in fwapg / the bundle.
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
conn <- DBI::dbConnect(RPostgres::Postgres(), host = "localhost", port = 5432,
                       dbname = "fwapg", user = "postgres", password = "postgres")
on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

# 1. Drainage closure, DS-first.
focal_lit <- paste(DBI::dbQuoteLiteral(conn, focal), collapse = ", ")
q <- sprintf("
  SELECT DISTINCT w.wsg, nlevel(w.outlet) AS depth
  FROM public.wsg_outlet w
  JOIN public.wsg_outlet f ON f.wsg IN (%s)
  WHERE f.outlet <@ w.outlet
  ORDER BY depth ASC, w.wsg ASC", focal_lit)
res <- DBI::dbGetQuery(conn, q)
if (nrow(res) == 0L) {
  stop("no closure found — are the focal WSGs present in public.wsg_outlet?",
       call. = FALSE)
}

# 2. Modelable filter (link#157): keep only WSGs with bundle-species presence.
cfg      <- lnk_config(config)
loaded   <- lnk_load_overrides(cfg)
spp_cols <- tolower(cfg$species)
wp       <- loaded$wsg_species_presence
has_spp  <- apply(wp[, spp_cols, drop = FALSE], 1,
                  function(r) any(r %in% c("t", "TRUE", TRUE)))
modelable <- wp$watershed_group_code[has_spp]

keep <- res$wsg[res$wsg %in% modelable]              # preserves DS-first order
dropped <- setdiff(res$wsg, keep)
if (length(dropped) > 0L) {
  message(sprintf("[study_area_wsgs] dropped %d species-less closure WSG(s): %s",
                  length(dropped), paste(dropped, collapse = ",")))
}
if (length(keep) == 0L) {
  stop("no modelable WSGs after species-presence filter", call. = FALSE)
}
cat(paste(keep, collapse = ","), "\n")

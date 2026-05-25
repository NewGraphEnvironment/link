#!/usr/bin/env Rscript
# study_area_wsgs.R — given a set of FOCAL watershed groups, print the
# drainage-CLOSED set in DOWNSTREAM-FIRST order (one comma-joined line).
#
# Closure: every WSG whose outlet wscode_ltree is an ancestor of (== at or
# downstream of) any focal WSG's outlet — i.e. the WSGs a focal WSG's water
# drains through. DS-first: ordered by outlet ltree depth ascending, so the
# most-downstream WSGs come first. Running a host's bucket in this order
# persists downstream dam barriers before upstream WSGs compute access, which
# is what makes cross-WSG `;DAM` correct from the per-host run (no recompute).
#
# Source of truth: public.wsg_outlet (wsg, outlet ltree, lvl) in fwapg.
#
# Usage: Rscript study_area_wsgs.R <FOCAL1,FOCAL2,...>

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L || !nzchar(args[1])) {
  stop("usage: study_area_wsgs.R <FOCAL1,FOCAL2,...>", call. = FALSE)
}
focal <- toupper(strsplit(args[1], ",")[[1]])
focal <- focal[nzchar(focal)]

suppressPackageStartupMessages({
  library(DBI); library(RPostgres)
})
conn <- DBI::dbConnect(RPostgres::Postgres(), host = "localhost", port = 5432,
                       dbname = "fwapg", user = "postgres", password = "postgres")
on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

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
cat(paste(res$wsg, collapse = ","), "\n")

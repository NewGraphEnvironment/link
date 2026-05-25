#!/usr/bin/env Rscript
# study_area_compare.R — tunnel-free per-WSG mapping_code parity for a set of
# WSGs against the LOCAL bcfp snapshot (fresh.streams_vw_bcfp, loaded by
# snapshot_bcfp.sh --with-bcfp-views). Writes a long CSV
# (wsg, species, total_segs, match_pct, n_diffs, top_pattern,
# top_pattern_count). Run on the dispatcher AFTER consolidate. No tunnel,
# no PG_PASS_SHARE, no :63333 — a single local connection per WSG.
#
# Usage: [LNK_LOAD=loadall] Rscript study_area_compare.R <out.csv> <WSG1,WSG2,...> [config]

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L) {
  stop("usage: study_area_compare.R <out.csv> <wsgs-csv> [config]", call. = FALSE)
}
out_csv <- args[1]
wsgs    <- toupper(strsplit(args[2], ",")[[1]])
wsgs    <- wsgs[nzchar(wsgs)]
config  <- if (length(args) >= 3L && nzchar(args[3])) args[3] else "bcfishpass"

if (identical(Sys.getenv("LNK_LOAD"), "loadall")) {
  suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
} else {
  suppressPackageStartupMessages(library(link))
}
suppressPackageStartupMessages({
  library(DBI); library(RPostgres)
})
source("data-raw/wsg_compare.R")

cfg <- lnk_config(config)

rows <- list()
for (w in wsgs) {
  r <- tryCatch(
    wsg_compare_mapping_code(wsg = w, config = cfg),
    error = function(e) {
      message(sprintf("[study_area_compare] %s ERROR: %s", w, conditionMessage(e)))
      NULL
    })
  if (!is.null(r)) rows[[w]] <- r
}
if (length(rows) == 0L) stop("no WSG produced a compare result", call. = FALSE)
res <- do.call(rbind, rows)
write.csv(res, out_csv, row.names = FALSE)
cat(sprintf("[study_area_compare] %d rows across %d/%d WSGs -> %s\n",
            nrow(res), length(rows), length(wsgs), out_csv))
print(res)

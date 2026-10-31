#!/usr/bin/env Rscript
# presence_evidence_load.R — fetch the evidence the presence check reads
# beside the fish records (link#402), and write it under --out.
#
#   Rscript data-raw/presence_evidence_load.R [--out=data-raw/logs/presence_check_402/evidence]
#
# hist_zones.csv  "BC Historical Fish Distribution - Zones (50,000)", BC Data
#                 Catalogue b665c14f-3d29-414b-b232-cba2a9c3cc55, from its WFS:
#                 one row per stream reach a species is recorded on, with the
#                 reach's 50k watershed code (digits, trailing zeros trimmed),
#                 activity and stock. Geometry is dropped: the check joins on
#                 the code.
# stamp.txt       dataset id, retrieval time, row counts.
#
# "Provincial Fish Ranges - Watersheds" (4e66ac86-aec6-4d79-8462-9e8daf0c0339)
# has no WFS resource (a BC Geographic Warehouse custom download), so it is
# not fetched here.

suppressPackageStartupMessages(library(bcdata))

args <- commandArgs(trailingOnly = TRUE)
known <- c("--out")
bad <- args[!sub("=.*$", "", args) %in% known]
if (length(bad) > 0L) stop("unknown arguments: ", paste(bad, collapse = " "))
hit <- grep("^--out=", args, value = TRUE)
dir_out <- if (length(hit) == 0L) {
  file.path("data-raw", "logs", "presence_check_402", "evidence")
} else {
  sub("^--out=", "", hit[1])
}
fs::dir_create(dir_out)

id_zones <- "b665c14f-3d29-414b-b232-cba2a9c3cc55"
z <- bcdc_query_geodata(id_zones) |> collect()
n_wfs <- nrow(z)
z <- sf::st_drop_geometry(z)

trim_code <- function(x) sub("0+$", "", gsub("-", "", x))
out <- data.frame(
  species_code = toupper(trimws(z$SPECIES_CODE)),
  code50 = trim_code(z$NEW_WATERSHED_CODE),
  gazetted_name = z$GAZETTED_NAME,
  activity_code = z$ACTIVITY_CODE,
  stock_type = z$STOCK_TYPE,
  loc_type = z$LOC_TYPE,
  stringsAsFactors = FALSE
)
out <- unique(out)
out <- out[order(out$species_code, out$code50, out$activity_code,
                 method = "radix"), ]
if (anyNA(out$code50) || any(!nzchar(out$code50))) {
  stop("zones with no watershed code: ", sum(is.na(out$code50) | !nzchar(out$code50)))
}
utils::write.csv(out, file.path(dir_out, "hist_zones.csv"), row.names = FALSE,
                 na = "")

writeLines(c(
  paste0("retrieved: ", format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
  paste0("hist_zones: ", id_zones, " (BC Historical Fish Distribution - Zones (50,000))"),
  paste0("hist_zones_wfs_rows: ", n_wfs),
  paste0("hist_zones_rows_written: ", nrow(out), " (unique species, code, activity, stock, type)"),
  paste0("hist_zones_species: ", length(unique(out$species_code))),
  paste0("bcdata: ", as.character(utils::packageVersion("bcdata")))
), file.path(dir_out, "stamp.txt"))
message("wrote ", nrow(out), " zone rows (", n_wfs, " WFS features) to ", dir_out)

# Usage: Rscript rollup_check.R <repo> <out_dir>
# #317: the shipped link-side rollup (.lnk_compare_wsg_rollup_link) on the
# live #310 working schemas, against measure.csv (from the flag).
args <- commandArgs(trailingOnly = TRUE)
repo <- args[1]; out_dir <- args[2]
suppressMessages(devtools::load_all(repo, quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
m <- utils::read.csv(file.path(out_dir, "measure.csv"))
chk <- do.call(rbind, lapply(c("ADMS", "NATR"), function(w) {
  schema <- paste0("zz311_", tolower(w))
  sp <- DBI::dbGetQuery(conn, sprintf(
    "SELECT DISTINCT species_code FROM %s.streams_habitat ORDER BY 1",
    schema))$species_code
  k <- .lnk_compare_wsg_rollup_link(conn, w, schema, sp)$km
  data.frame(aoi = w, k, row.names = NULL)
}))
x <- merge(chk, m, by = c("aoi", "species_code"))
x$parts_minus_total <- round(x$rearing_stream_km + x$rearing_lake_km +
                               x$rearing_wetland_km - x$rearing_km, 3)
x$total_vs_measure <- round(x$rearing_km - x$rear_km, 3)
x$connection_vs_measure <- round(x$rearing_lake_connection_km -
                                   x$rear_connection_km, 3)
x$flag_vs_measure <- round(x$rearing_km + x$rearing_lake_connection_km -
                             x$rear_flag_km, 3)
out <- x[, c("aoi", "species_code", "rearing_km", "rearing_lake_km",
             "rearing_lake_connection_km", "parts_minus_total",
             "total_vs_measure", "connection_vs_measure", "flag_vs_measure")]
utils::write.csv(out, file.path(out_dir, "rollup_check.csv"), row.names = FALSE)
print(out, row.names = FALSE)
DBI::dbDisconnect(conn)

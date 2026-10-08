# Usage: Rscript summarise.R <measure_csv> <out_dir>
# Reads run.R's per-run rows (A, B, C) and writes summary.csv: per WSG x
# species, the A -> B (fresh v0.36.2 -> v0.39.0, old rules) and B -> C
# (floored carve-out) movement, beside the bcfishpass reference rearing km
# from the local fresh.streams_vw_bcfp snapshot (rearing_<sp> IN (1, 2):
# the view codes 0/1/2/3, see research/bcfp_view_column_coding.md).
args <- commandArgs(trailingOnly = TRUE)
m <- utils::read.csv(args[1], stringsAsFactors = FALSE)
out_dir <- args[2]

cols <- c("n_rear", "rear_km", "rear_km_subfloor_wetflow", "rear_km_subfloor",
          "lake_rear_km", "wetland_rear_km", "lake_rear_ha", "wetland_rear_ha")
key <- c("aoi", "species_code")
wide <- Reduce(function(x, y) merge(x, y, by = key, all = TRUE),
  lapply(c("A", "B", "C"), function(r) {
    d <- m[m$run == r, c(key, cols)]
    names(d)[-(1:2)] <- paste0(names(d)[-(1:2)], "_", r)
    d
  }))

conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg",
                       host = "localhost", port = 5432L,
                       user = "postgres", password = "postgres")
bcfp_cols <- DBI::dbGetQuery(conn, "
  SELECT column_name FROM information_schema.columns
  WHERE table_schema = 'fresh' AND table_name = 'streams_vw_bcfp'
    AND column_name LIKE 'rearing\\_%'")$column_name
wsgs <- unique(wide$aoi)
bcfp <- do.call(rbind, lapply(bcfp_cols, function(cl) {
  d <- DBI::dbGetQuery(conn, sprintf("
    SELECT watershed_group_code AS aoi,
           round((sum(length_metre) FILTER (WHERE %1$s IN (1, 2)) / 1000)::numeric, 3)
             AS bcfp_rear_km
    FROM fresh.streams_vw_bcfp
    WHERE watershed_group_code IN (%2$s)
    GROUP BY 1", cl, paste0("'", wsgs, "'", collapse = ", ")))
  if (nrow(d)) d$species_code <- toupper(sub("^rearing_", "", cl))
  d
}))
DBI::dbDisconnect(conn)
bcfp$bcfp_rear_km <- as.numeric(bcfp$bcfp_rear_km)
wide <- merge(wide, bcfp, by = key, all.x = TRUE)

num <- function(x) suppressWarnings(as.numeric(x))
wide$d_rear_km_AB <- num(wide$rear_km_B) - num(wide$rear_km_A)
wide$d_n_rear_AB <- num(wide$n_rear_B) - num(wide$n_rear_A)
wide$d_rear_km_BC <- num(wide$rear_km_C) - num(wide$rear_km_B)
wide$d_n_rear_BC <- num(wide$n_rear_C) - num(wide$n_rear_B)
for (r in c("A", "C")) {
  wide[[paste0("vs_bcfp_pct_", r)]] <- round(
    100 * (num(wide[[paste0("rear_km_", r)]]) - wide$bcfp_rear_km) /
      wide$bcfp_rear_km, 1)
}
wide <- wide[order(wide$aoi, wide$species_code), ]
wide <- wide[!is.na(num(wide$rear_km_A)) | !is.na(num(wide$rear_km_C)), ]
utils::write.csv(wide, file.path(out_dir, "summary.csv"), row.names = FALSE)

show <- c(key, "n_rear_A", "rear_km_A", "d_n_rear_AB", "d_rear_km_AB",
          "d_n_rear_BC", "d_rear_km_BC", "rear_km_subfloor_wetflow_C",
          "lake_rear_km_A", "lake_rear_km_B", "wetland_rear_km_A",
          "wetland_rear_km_B", "wetland_rear_km_C", "bcfp_rear_km",
          "vs_bcfp_pct_A", "vs_bcfp_pct_C")
print(wide[, show], row.names = FALSE)

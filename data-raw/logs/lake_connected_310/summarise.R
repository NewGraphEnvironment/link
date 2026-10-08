# Usage: Rscript summarise.R <out_dir>
# A -> B per WSG x species from measure.csv into summary.csv.
out_dir <- commandArgs(trailingOnly = TRUE)[1]
m <- utils::read.csv(file.path(out_dir, "measure.csv"), stringsAsFactors = FALSE)
a <- m[m$run == "A", ]
b <- m[m$run == "B", ]
x <- merge(a, b, by = c("aoi", "species_code"), suffixes = c("_A", "_B"))
d <- function(v) round(x[[paste0(v, "_B")]] - x[[paste0(v, "_A")]], 1)
s <- data.frame(
  aoi = x$aoi, species = x$species_code,
  spawn_km_delta = d("spawn_km"),
  rear_km_A = round(x$rear_km_A, 1), rear_km_B = round(x$rear_km_B, 1),
  rear_km_delta = d("rear_km"),
  stream_km_delta = d("rear_stream_km"),
  lake_km_B = round(x$rear_lake_km_B, 1), lake_km_delta = d("rear_lake_km"),
  wetland_km_delta = d("rear_wetland_km"),
  lake_ha_A = round(x$lake_ha_A), lake_ha_B = round(x$lake_ha_B),
  wetland_ha_A = round(x$wetland_ha_A), wetland_ha_B = round(x$wetland_ha_B),
  n_lake_A = x$n_lake_A, n_lake_B = x$n_lake_B,
  n_wetland_A = x$n_wetland_A, n_wetland_B = x$n_wetland_B,
  lake_ha_no_km_B = x$n_lake_ha_no_km_B, lake_km_no_ha_B = x$n_lake_km_no_ha_B,
  wet_ha_no_km_B = x$n_wet_ha_no_km_B, wet_km_no_ha_B = x$n_wet_km_no_ha_B)
# bcfishpass reference rearing km from the local fresh.streams_vw_bcfp
# snapshot (rearing_<sp> IN (1, 2)), as in wetland_floor_311/summarise.R.
conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg",
                       host = "localhost", port = 5432L,
                       user = "postgres", password = "postgres")
bcfp_cols <- DBI::dbGetQuery(conn, "
  SELECT column_name FROM information_schema.columns
  WHERE table_schema = 'fresh' AND table_name = 'streams_vw_bcfp'
    AND column_name LIKE 'rearing\\_%'")$column_name
wsgs <- unique(s$aoi)
bcfp <- do.call(rbind, lapply(bcfp_cols, function(cl) {
  d <- DBI::dbGetQuery(conn, sprintf("
    SELECT watershed_group_code AS aoi,
           (sum(length_metre) FILTER (WHERE %1$s IN (1, 2)) / 1000)::numeric
             AS bcfp_rear_km
    FROM fresh.streams_vw_bcfp
    WHERE watershed_group_code IN (%2$s)
    GROUP BY 1", cl, paste0("'", wsgs, "'", collapse = ", ")))
  if (nrow(d)) d$species <- toupper(sub("^rearing_", "", cl))
  d
}))
DBI::dbDisconnect(conn)
bcfp$bcfp_rear_km <- round(as.numeric(bcfp$bcfp_rear_km), 1)
s <- merge(s, bcfp, by = c("aoi", "species"), all.x = TRUE)
pct <- function(v) round(100 * (v - s$bcfp_rear_km) / s$bcfp_rear_km, 1)
s$vs_bcfp_pct_A <- pct(s$rear_km_A)
s$vs_bcfp_pct_B <- pct(s$rear_km_B)
utils::write.csv(s, file.path(out_dir, "summary.csv"), row.names = FALSE)
print(s, row.names = FALSE)

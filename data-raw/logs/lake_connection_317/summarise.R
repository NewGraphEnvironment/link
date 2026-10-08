# Usage: Rscript summarise.R <out_dir>
# Old (connection lines in rearing km) -> new (kept apart), link against
# bcfishpass under the same rule on both sides, into summary.csv.
out_dir <- commandArgs(trailingOnly = TRUE)[1]
l <- utils::read.csv(file.path(out_dir, "measure.csv"))
r <- utils::read.csv(file.path(out_dir, "reference.csv"))
x <- merge(l, r, by = c("aoi", "species_code"), all.x = TRUE,
           suffixes = c("", "_bcfp"))
pct <- function(a, b) ifelse(b > 0, round(100 * (a - b) / b, 1), NA)
s <- data.frame(
  aoi = x$aoi, species = x$species_code,
  rear_km_old = round(x$rear_flag_km, 1), rear_km_new = round(x$rear_km, 1),
  connection_km = round(x$rear_connection_km, 1),
  lake_km_old = round(x$rear_lake_flag_km, 1),
  lake_km_new = round(x$rear_lake_km, 1),
  bcfp_rear_km_old = round(x$rear_flag_km_bcfp, 1),
  bcfp_rear_km_new = round(x$rear_km_bcfp, 1),
  bcfp_connection_km = round(x$rear_connection_km_bcfp, 1),
  vs_bcfp_pct_old = pct(x$rear_flag_km, x$rear_flag_km_bcfp),
  vs_bcfp_pct_new = pct(x$rear_km, x$rear_km_bcfp))
utils::write.csv(s, file.path(out_dir, "summary.csv"), row.names = FALSE)
print(s, row.names = FALSE)

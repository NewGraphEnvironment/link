# link#331: why BT's MAD percentiles fall on wet. Splits the Phase 3 producer's
# per-location output (mad_fwapg/, mad_wet/ obs_mad.csv) into locations both
# sources value, locations only wet values in groups fwapg covers, and
# locations in groups fwapg does not cover.
#   Rscript data-raw/logs/discharge_wet_331/source_vs_coverage.R
d <- "data-raw/logs/discharge_wet_331"
f <- read.csv(file.path(d, "mad_fwapg/obs_mad.csv")); w <- read.csv(file.path(d, "mad_wet/obs_mad.csv"))
f <- f[f$species_code == "BT", ]; w <- w[w$species_code == "BT", ]
k <- c("species_code", "obs_species", "watershed_group_code", "blue_line_key", "m")
j <- merge(f[, c(k, "mad_m3s", "channel_width")], w[, c(k, "mad_m3s")], by = k,
           suffixes = c("_fwapg", "_wet"))
stopifnot(nrow(j) == nrow(f))
grp <- ifelse(!w$watershed_group_code %in% f$watershed_group_code, "group not on fwapg", NA)
q <- function(x) quantile(x, c(.02, .05, .1, .5), na.rm = TRUE, names = FALSE)
row <- function(set, src, x, cw = NA_real_) data.frame(set = set, source = src,
  n = sum(!is.na(x)), p02 = q(x)[1], p05 = q(x)[2], p10 = q(x)[3], p50 = q(x)[4],
  channel_width_p50 = cw)
both <- !is.na(j$mad_m3s_fwapg) & !is.na(j$mad_m3s_wet)
only_wet <- is.na(j$mad_m3s_fwapg) & !is.na(j$mad_m3s_wet)
extra <- !is.na(grp)
out <- rbind(
  row("valued by both", "fwapg", j$mad_m3s_fwapg[both], median(j$channel_width[both], na.rm = TRUE)),
  row("valued by both", "wet", j$mad_m3s_wet[both], median(j$channel_width[both], na.rm = TRUE)),
  row("valued by wet only, shared groups", "wet", j$mad_m3s_wet[only_wet], median(j$channel_width[only_wet], na.rm = TRUE)),
  row("groups fwapg does not cover", "wet", w$mad_m3s[extra]),
  row("all groups", "wet", w$mad_m3s),
  row("all groups", "fwapg", f$mad_m3s))
out[, 3:8] <- lapply(out[, 3:8], function(x) signif(x, 4))
print(out, row.names = FALSE)
write.csv(out, file.path(d, "source_vs_coverage.csv"), row.names = FALSE)
g <- as.data.frame(table(watershed_group_code = w$watershed_group_code[extra]))
s <- w[w$is_spawn & !is.na(w$mad_m3s) & w$access %in% c(1, 2), ]
cat("\ngroups wet covers and fwapg does not (BT locations):\n"); print(g, row.names = FALSE)
cat("\nwet spawning-staged accessible BT locations by region:\n"); print(table(s$region))
write.csv(g, file.path(d, "source_vs_coverage_groups.csv"), row.names = FALSE)

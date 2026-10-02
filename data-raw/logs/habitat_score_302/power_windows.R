# power_windows.R — observation locations per MAD band window, counts only (link#302).
# Run 2026-10-02 against docker fwapg before any variant was built; output in power_windows.txt.
# FWA line discharge (fwa_stream_networks_discharge on linear_feature_id) of the containing
# FWA segment, A/B matches, Releases dropped, #290 pooling; no access, waterbody or cluster
# filter, so every count is an upper bound. Windows are the loosening steps of each ladder:
# [P05, P10) is what P10 -> P05 adds, [P02, P05) what P05 -> P02 adds (calibration
# quantiles, data-raw/logs/habitat_thresholds_302/quantiles.csv, floored to 2 s.f.).
suppressMessages(pkgload::load_all(quiet = TRUE))
library(DBI)
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg <- lnk_config("default"); loaded <- suppressWarnings(lnk_load_overrides(cfg))
calib <- dbGetQuery(conn, "SELECT DISTINCT watershed_group_code FROM fresh_default.streams")[[1]]
covered <- dbGetQuery(conn, "
  SELECT DISTINCT s.watershed_group_code FROM whse_basemapping.fwa_stream_networks_sp s
  JOIN whse_basemapping.fwa_stream_networks_discharge d USING (linear_feature_id)
  WHERE d.mad_m3s IS NOT NULL")[[1]]
p <- as.data.frame(loaded$wsg_species_presence); names(p) <- tolower(names(p))
species <- c("BT", "GR", "KO", "RB")
pres <- lapply(setNames(species, species), function(sp) toupper(p$watershed_group_code[p[[tolower(sp)]] %in% "t"]))
pool <- lnk_species_pooling(loaded, aoi = sort(unique(unlist(pres))), species = species)
spec <- unique(rbind(pool[, c("watershed_group_code", "species_code", "obs_species")],
  do.call(rbind, lapply(species, function(sp)
    data.frame(watershed_group_code = pres[[sp]], species_code = sp, obs_species = sp)))))
spec <- spec[mapply(function(w, sp) w %in% pres[[sp]], spec$watershed_group_code, spec$species_code), ]
dbWriteTable(conn, "pw_spec", spec, temporary = TRUE, overwrite = TRUE)
o <- dbGetQuery(conn, "
 SELECT sp.species_code, min(o.watershed_group_code) AS watershed_group_code,
   min(d.mad_m3s) AS mad,
   coalesce(bool_or(o.activity_code ~ '\\m(SPL|SPM|S)\\M' OR o.activity ~ 'Spawning'), false) AS is_spawn,
   coalesce(bool_or(o.activity_code ~ '\\m(R|REA)\\M' OR o.activity ~ 'Rearing' OR o.life_stage ~ 'Fry|Parr|Juvenile'), false) AS is_rear
 FROM bcfishobs.observations o
 JOIN pg_temp.pw_spec sp ON sp.watershed_group_code = o.watershed_group_code AND sp.obs_species = o.species_code
 JOIN whse_basemapping.fwa_stream_networks_sp s ON s.blue_line_key = o.blue_line_key
   AND o.downstream_route_measure >= s.downstream_route_measure AND o.downstream_route_measure < s.upstream_route_measure
 LEFT JOIN whse_basemapping.fwa_stream_networks_discharge d ON d.linear_feature_id = s.linear_feature_id
 WHERE left(o.match_type,1) IN ('A','B') AND coalesce(o.source,'') NOT LIKE 'Releases Database%'
 GROUP BY sp.species_code, o.blue_line_key, round(o.downstream_route_measure)")
# ladder: species, stage the step is read on, P02, P05, P10 (floored)
lad <- data.frame(
  ladder = c("BT rear", "BT spawn", "GR rear", "GR spawn", "RB rear", "RB spawn", "KO spawn"),
  sp = c("BT", "BT", "GR", "GR", "RB", "RB", "KO"),
  stage = c("any", "any", "any", "any", "any", "spawn", "spawn"),
  p02 = c(0.0085, 0.0085, 0.0026, 0.0025, 0.0048, 0.0055, 0.51),
  p05 = c(0.027, 0.027, 0.095, 0.095, 0.0094, 0.011, 0.57),
  p10 = c(0.078, 0.078, 0.97, 0.96, 0.019, 0.05, 0.66))
cnt <- function(sel) {
  t(sapply(seq_len(nrow(lad)), function(i) {
    L <- lad[i, ]
    d <- o[sel & o$species_code == L$sp & !is.na(o$mad), ]
    if (L$stage == "spawn") d <- d[d$is_spawn, ]
    c(p10_to_p05 = sum(d$mad >= L$p05 & d$mad < L$p10),
      p05_to_p02 = sum(d$mad >= L$p02 & d$mad < L$p05))
  })) |> `rownames<-`(lad$ladder)
}
heldout_pool <- setdiff(covered, calib)
cat("covered WSGs:", length(covered), "; calibration:", length(calib), "\n")
for (sp in species) cat(sp, "present, covered, non-calibration:", length(intersect(pres[[sp]], heldout_pool)),
                        "; calibration:", length(intersect(pres[[sp]], calib)), "\n")
cat("\nall covered non-calibration WSGs:\n"); print(cnt(o$watershed_group_code %in% heldout_pool))
cat("\ncalibration WSGs:\n"); print(cnt(o$watershed_group_code %in% calib))
cat("\ndensest covered non-calibration WSGs per ladder, both windows together:\n")
for (i in seq_len(nrow(lad))) {
  L <- lad[i, ]
  d <- o[o$watershed_group_code %in% heldout_pool & o$species_code == L$sp & !is.na(o$mad) &
           o$mad >= L$p02 & o$mad < L$p10, ]
  if (L$stage == "spawn") d <- d[d$is_spawn, ]
  t <- sort(table(d$watershed_group_code), decreasing = TRUE)[1:10]
  cat(" ", L$ladder, ":", paste(names(t), t), "\n")
}

# The held-out set chosen from the densest WSGs above, leaving out HERR and LNTH,
# whose drainage closures pull in the upper Fraser (36 closure WSGs with them).
held <- list(BT = c("REVL", "ELKR", "KOTR", "UARL", "MURR", "UBTN", "LHAF"),
             GR = c("UBTN", "MURR", "LHAF"),
             RB = c("SIML", "OKAN", "KETL", "ELKR", "REVL", "KOTR"))
cat("\nchosen held-out set (wsg_roles_302.csv):\n")
print(do.call(rbind, lapply(seq_len(nrow(lad)), function(i) {
  L <- lad[i, ]; if (!L$sp %in% names(held)) return(NULL)
  cnt(o$watershed_group_code %in% held[[L$sp]])[i, , drop = FALSE]
})))

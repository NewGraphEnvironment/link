# power_windows.R — observation locations per band window, counts only (link#284 step 5).
# Run 2026-09-29 against docker fwapg before any variant was built; output in power_windows.txt.
# FWA segment gradient of the containing segment, A/B matches, Releases dropped, #290 pooling;
# no access, width or cluster filter, so every count is an upper bound.
suppressMessages(pkgload::load_all(quiet = TRUE))
library(DBI)
conn <- lnk_db_conn(dbname="fwapg", host="localhost", port=5432L, user="postgres", password="postgres")
cfg <- lnk_config("default"); loaded <- suppressWarnings(lnk_load_overrides(cfg))
calib <- dbGetQuery(conn, "SELECT DISTINCT watershed_group_code FROM fresh_default.streams_access")[[1]]
p <- as.data.frame(loaded$wsg_species_presence); names(p) <- tolower(names(p))
bt_w <- toupper(p$watershed_group_code[p$bt %in% "t"]); ch_w <- toupper(p$watershed_group_code[p$ch %in% "t"])
pool <- lnk_species_pooling(loaded, aoi = sort(unique(c(bt_w, ch_w))), species = c("BT","CH"))
spec <- unique(rbind(pool[, c("watershed_group_code","species_code","obs_species")],
  data.frame(watershed_group_code = bt_w, species_code = "BT", obs_species = "BT"),
  data.frame(watershed_group_code = ch_w, species_code = "CH", obs_species = "CH")))
spec <- spec[(spec$species_code == "BT" & spec$watershed_group_code %in% bt_w) | (spec$species_code == "CH" & spec$watershed_group_code %in% ch_w), ]
dbWriteTable(conn, "pw_spec", spec, temporary = TRUE, overwrite = TRUE)
# One row per species x blue_line_key x metre; staged if any record there is,
# as lnk_habitat_validate() dedups.
o <- dbGetQuery(conn, "
 SELECT sp.species_code, min(o.watershed_group_code) AS watershed_group_code,
   min(s.gradient) AS gradient,
   coalesce(bool_or(o.activity_code ~ '\\m(SPL|SPM|S)\\M' OR o.activity ~ 'Spawning'), false) AS is_spawn,
   coalesce(bool_or(o.activity_code ~ '\\m(R|REA)\\M' OR o.activity ~ 'Rearing' OR o.life_stage ~ 'Fry|Parr|Juvenile'), false) AS is_rear
 FROM bcfishobs.observations o
 JOIN pg_temp.pw_spec sp ON sp.watershed_group_code = o.watershed_group_code AND sp.obs_species = o.species_code
 JOIN whse_basemapping.fwa_stream_networks_sp s ON s.blue_line_key = o.blue_line_key
   AND o.downstream_route_measure >= s.downstream_route_measure AND o.downstream_route_measure < s.upstream_route_measure
 WHERE left(o.match_type,1) IN ('A','B') AND coalesce(o.source,'') NOT LIKE 'Releases Database%'
 GROUP BY sp.species_code, o.blue_line_key, round(o.downstream_route_measure)")
o$is_spawn[is.na(o$is_spawn)] <- FALSE; o$is_rear[is.na(o$is_rear)] <- FALSE
win <- list(bt_1049_1249 = c("BT","any",0.1049,0.1249), bt_1249_1349 = c("BT","any",0.1249,0.1349),
            bt_1349_1449 = c("BT","any",0.1349,0.1449), ch_sp_0299_0449 = c("CH","spawn",0.0299,0.0449),
            ch_sp_0449_0549 = c("CH","spawn",0.0449,0.0549), ch_re_0549_0649 = c("CH","rear",0.0549,0.0649))
cnt <- function(sel) sapply(win, function(w) { d <- o[sel & o$species_code == w[1] & o$gradient > as.numeric(w[3]) & o$gradient <= as.numeric(w[4]), ]
  if (w[2] == "spawn") d <- d[d$is_spawn, ]; if (w[2] == "rear") d <- d[d$is_rear, ]; nrow(d) })
cat("held-out BT ELKR+BULL / CH UNTH+LNTH:\n"); print(cnt(o$watershed_group_code %in% c("ELKR","BULL","UNTH","LNTH")))
cat("widened held-out BT (ELKR BULL UARL REVL CLRH LILL BABL BABR):\n"); print(cnt(o$watershed_group_code %in% c("ELKR","BULL","UARL","REVL","CLRH","LILL","BABL","BABR")))
cat("all 8 pilots:\n"); print(cnt(o$watershed_group_code %in% c("ELKR","BULL","UNTH","LNTH","PARS","KOTL","BULK","MORR")))
cat("all non-calibration WSGs:\n"); print(cnt(!o$watershed_group_code %in% calib))
cat("calibration 55:\n"); print(cnt(o$watershed_group_code %in% calib))
nc <- o[!o$watershed_group_code %in% calib & o$species_code == "BT" & o$gradient > 0.1049 & o$gradient <= 0.1449, ]
cat("top non-calibration BT WSGs, 0.1049-0.1449 window:\n"); print(head(sort(table(nc$watershed_group_code), decreasing = TRUE), 15))
nc2 <- o[!o$watershed_group_code %in% calib & o$species_code == "BT" & o$gradient > 0.1249 & o$gradient <= 0.1349, ]
print(head(sort(table(nc2$watershed_group_code), decreasing = TRUE), 15))
cat("n non-calib BT WSGs:", length(setdiff(bt_w, calib)), "; n non-calib CH WSGs:", length(setdiff(ch_w, calib)), "\n")
cat("densest non-calibration CH WSGs per CH window:\n")
ch <- o[o$species_code == "CH" & !o$watershed_group_code %in% calib, ]
for (w in list(c("spawn", 0.0299, 0.0449), c("spawn", 0.0449, 0.0549), c("rear", 0.0549, 0.0649))) {
  d <- ch[ch$gradient > as.numeric(w[2]) & ch$gradient <= as.numeric(w[3]) &
            (if (w[1] == "spawn") ch$is_spawn else ch$is_rear), ]
  t <- sort(table(d$watershed_group_code), decreasing = TRUE)[1:6]
  cat(" ", w, ":", paste(names(t), t), "\n")
}

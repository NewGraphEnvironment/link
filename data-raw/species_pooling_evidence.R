#!/usr/bin/env Rscript
# species_pooling_evidence.R — how DV and BT are recorded through time and
# space, and how sensitive the #284 BT evidence is to where DV -> BT pooling
# applies (link#290).
#
# Read-only against docker fwapg (:5432): session temp tables only.
#
#   Rscript data-raw/species_pooling_evidence.R [--validate]
#
# Scenarios (pooling DV records into BT), each a scratch tracker built from
# default's species_pooling.csv:
#   S0_whole_skeena      Fraser, Mackenzie, Columbia (incl. Kootenay) and the
#                        whole Skeena (the first seed)
#   S1_hazelton          the committed tracker: the Skeena only above Hazelton
#                        (BULK, MORR, KISP, BABL, BABR, SUST, MSKE, USKE)
#   S2_noskeena          no Skeena
#   S3_pre1995           no Skeena, and interior rows limited to records dated
#                        before 1995 (obs_year_max 1994)
#   S4_hazelton_pre1995  S1 with the interior rows limited to before 1995
#   BT_only              no pooling (the producer's BT_any comparison set)
#
# Every scenario runs through data-raw/query_habitat_thresholds_obs.R. The
# rule is also reimplemented here over the S0 evidence, and the script stops
# unless the two agree for every scenario (the check that the evidence tables
# say what the producer computed). With --validate each is also scored
# through data-raw/habitat_validate.R (default:fresh_default, ~5 min each).
#
# Writes to data-raw/logs/species_pooling_290/:
#   decade_region.csv        BT and DV records by region x decade
#   dv_streams_resampled.csv streams with a DV record: last DV year, re-sampled
#                            after 1995, later recorded as BT
#   wsg_dv_share.csv         per WSG: BT and DV records before / from 1995
#   scenarios.csv            the #284 BT thresholds under each scenario
#   scenarios_dropped.csv    DV evidence rows each scenario drops, by WSG
#   validate_scenarios.csv   (--validate) BT capture and km per scenario
#   stamp.txt
#   fig_*.png

pkgload::load_all(quiet = TRUE)
suppressPackageStartupMessages({
  library(DBI)
  library(dplyr)
  library(ggplot2)
})
sf::sf_use_s2(FALSE)

do_validate <- "--validate" %in% commandArgs(trailingOnly = TRUE)
dir_out <- file.path("data-raw", "logs", "species_pooling_290")
fs::dir_create(dir_out)
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")

upper_skeena <- c("BULK", "MORR", "KISP", "BABL", "BABR", "SUST", "MSKE", "USKE")
year_cut <- 1995L
regions <- utils::read.csv(.lnk_wsg_regions_path(), stringsAsFactors = FALSE,
                           na.strings = "")
named_regions <- c("Fraser", "Mackenzie", "Columbia", "Skeena")
grp_of <- function(w) {
  r <- regions$region[match(w, regions$watershed_group_code)]
  ifelse(r %in% named_regions, r, "Coast and north")
}

# -- 1. records through time --------------------------------------------------
obs <- dbGetQuery(conn, "
  SELECT observation_key, species_code, watershed_group_code, blue_line_key,
         extract(year FROM observation_date)::int AS yr
  FROM bcfishobs.observations
  WHERE species_code IN ('BT', 'DV')
    AND source NOT LIKE 'Releases Database%'")
obs$grp <- grp_of(obs$watershed_group_code)
# a handful of records carry impossible years (2080, 9990): treat as undated
obs$yr[!is.na(obs$yr) & obs$yr > as.integer(format(Sys.Date(), "%Y"))] <- NA
obs$decade <- ifelse(is.na(obs$yr), NA_integer_, pmax(floor(obs$yr / 10) * 10, 1960L))

dec <- obs |>
  filter(!is.na(decade)) |>
  count(grp, decade, species_code) |>
  tidyr::pivot_wider(names_from = species_code, values_from = n, values_fill = 0L) |>
  mutate(n = BT + DV, dv_share = DV / n) |>
  arrange(grp, decade)
readr::write_csv(dec, file.path(dir_out, "decade_region.csv"), na = "")

res <- obs |>
  filter(!is.na(yr)) |>
  group_by(grp, blue_line_key) |>
  filter(any(species_code == "DV")) |>
  summarise(dv_last = max(yr[species_code == "DV"]),
            last_any = max(yr),
            bt_after_dv = any(species_code == "BT" & yr > dv_last),
            .groups = "drop") |>
  # A later BT record is the renaming signal, whenever it came, so it wins.
  mutate(fate = case_when(
    bt_after_dv ~ "later recorded as BT",
    last_any <= year_cut ~ "not sampled after 1995",
    TRUE ~ "sampled after 1995, DV only"))
res_tab <- res |>
  count(grp, fate) |>
  group_by(grp) |>
  mutate(streams = sum(n), share = n / streams) |>
  ungroup()
readr::write_csv(res_tab, file.path(dir_out, "dv_streams_resampled.csv"), na = "")

wsg_share <- obs |>
  filter(!is.na(yr)) |>
  mutate(era = ifelse(yr < year_cut, "before 1995", "1995 on")) |>
  count(watershed_group_code, era, species_code) |>
  tidyr::pivot_wider(names_from = species_code, values_from = n, values_fill = 0L) |>
  mutate(n = BT + DV, dv_share = DV / n)
readr::write_csv(wsg_share, file.path(dir_out, "wsg_dv_share.csv"), na = "")

# -- 2. scenarios through the #284 producer -----------------------------------
tmp <- withr::local_tempdir()
tracker <- utils::read.csv(lnk_config("default")$files$species_pooling$path,
                           stringsAsFactors = FALSE, colClasses = "character",
                           na.strings = character(0))
scenario_bundle <- function(name, rows) {
  d <- file.path(tmp, name)
  fs::dir_create(d)
  utils::write.csv(rows, file.path(d, "species_pooling.csv"), row.names = FALSE)
  writeLines(c(paste("name:", name),
               "description: link#290 pooling scenario (scratch)",
               "extends: default", "files:", "  species_pooling:",
               "    path: species_pooling.csv"), file.path(d, "config.yaml"))
  d
}
hz <- tracker$scope == "Skeena above Hazelton"
sk <- tracker$scope == "Skeena"
interior <- tracker$scope %in% c("Fraser", "Mackenzie", "Columbia", "Kootenay")
if (!any(hz) || !any(sk) || sum(interior) != 4L) {
  stop("default's tracker no longer has the rows these scenarios edit",
       call. = FALSE)
}
pre1995 <- function(x) {
  x$obs_year_max[x$scope %in% c("Fraser", "Mackenzie", "Columbia", "Kootenay")] <-
    as.character(year_cut - 1L)
  x
}
s0 <- tracker[!hz, ]
s0$pool[s0$scope == "Skeena"] <- "yes"
bundles <- list(
  S0_whole_skeena = scenario_bundle("S0_whole_skeena", s0),
  S1_hazelton = scenario_bundle("S1_hazelton", tracker),
  S2_noskeena = scenario_bundle("S2_noskeena", tracker[!hz, ]),
  S3_pre1995 = scenario_bundle("S3_pre1995", pre1995(tracker[!hz, ])),
  S4_hazelton_pre1995 = scenario_bundle("S4_hazelton_pre1995", pre1995(tracker)))
scen_label <- c(S0_whole_skeena = "S0 whole Skeena",
                S1_hazelton = "S1 above Hazelton (adopted)",
                S2_noskeena = "S2 no Skeena",
                S3_pre1995 = "S3 no Skeena, interior pre-1995",
                S4_hazelton_pre1995 = "S4 above Hazelton, interior pre-1995",
                BT_only = "BT records only")

runs <- lapply(names(bundles), function(s) {
  out <- file.path(tmp, paste0("out_", s))
  message("producer: ", s)
  st <- system2("Rscript", c("data-raw/query_habitat_thresholds_obs.R",
                             paste0("--pooling=", bundles[[s]]),
                             paste0("--out=", out)),
                stdout = FALSE, stderr = FALSE)
  if (!identical(st, 0L)) stop("producer failed for ", s, call. = FALSE)
  out
})
names(runs) <- names(bundles)

# -- 3. the rule, reimplemented so S3 can be computed ---------------------------
seg0 <- utils::read.csv(file.path(runs$S0_whole_skeena, "obs_segments.csv"),
                        stringsAsFactors = FALSE)
yr_of <- obs$yr[match(seg0$observation_key, obs$observation_key)]
seg0$yr <- yr_of
snap49 <- function(x) floor(x * 100) / 100 + 0.0049
current <- utils::read.csv(lnk_config("default")$files$parameters_habitat_thresholds$path) |>
  filter(species_code == "BT")

metrics <- function(seg) {
  bt <- seg[seg$species_code == "BT", ]
  bt$loc <- paste(bt$species_code, bt$blue_line_key, round(bt$m))
  pooled <- bt[!duplicated(bt$loc), ]
  acc <- pooled[pooled$accessible %in% TRUE, ]
  g <- acc$gradient[acc$pred_set %in% c("stream", "river_poly") & !is.na(acc$gradient)]
  w <- acc$channel_width[acc$pred_set %in% "stream" & !is.na(acc$channel_width)]
  sp <- seg[seg$obs_species == "DV" & seg$is_spawn %in% TRUE & seg$accessible %in% TRUE, ]
  sg <- sp$gradient[sp$pred_set %in% c("stream", "river_poly") & !is.na(sp$gradient)]
  sw <- sp$channel_width[sp$pred_set %in% "stream" & !is.na(sp$channel_width)]
  q <- function(x, p) if (length(x)) unname(stats::quantile(x, p, type = 7)) else NA
  tibble(
    n_dv_records = sum(bt$obs_species == "DV"),
    rear_n = length(g), rear_gradient_p95 = q(g, 0.95),
    rear_gradient_rule = snap49(q(g, 0.95)),
    rear_width_n = length(w), rear_width_p05 = q(w, 0.05),
    spawn_n = length(sg), spawn_gradient_p95 = q(sg, 0.95),
    spawn_width_n = length(sw), spawn_width_p05 = q(sw, 0.05))
}
pre <- function(s) grp_of(s$watershed_group_code) %in%
  c("Fraser", "Mackenzie", "Columbia") & !is.na(s$yr) & s$yr < year_cut
keep_dv <- list(
  S0_whole_skeena = function(s) rep(TRUE, nrow(s)),
  S1_hazelton = function(s) grp_of(s$watershed_group_code) != "Skeena" |
    s$watershed_group_code %in% upper_skeena,
  S2_noskeena = function(s) grp_of(s$watershed_group_code) != "Skeena",
  S3_pre1995 = function(s) pre(s),
  S4_hazelton_pre1995 = function(s) pre(s) | s$watershed_group_code %in% upper_skeena,
  BT_only = function(s) rep(FALSE, nrow(s)))
scen <- bind_rows(lapply(names(keep_dv), function(s) {
  k <- seg0$obs_species != "DV" | keep_dv[[s]](seg0)
  cbind(scenario = s, metrics(seg0[k, ]))
}))

# The reimplementation must reproduce the producer where both exist.
for (s in names(runs)) {
  cand <- utils::read.csv(file.path(runs[[s]], "candidates.csv"))
  cand <- cand[cand$species_code == "BT" & cand$evidence_set == "BT_any_dv", ]
  mine <- scen[scen$scenario == s, ]
  sp <- utils::read.csv(file.path(runs[[s]], "candidates.csv"))
  sp <- sp[sp$species_code == "BT" & sp$evidence_set == "BT_spawn_dv", ]
  got <- c(cand$n[cand$parameter == "rear_gradient_max"],
           cand$use_quantile[cand$parameter == "rear_gradient_max"],
           cand$n[cand$parameter == "rear_channel_width_min"],
           cand$use_quantile[cand$parameter == "rear_channel_width_min"],
           sp$n[sp$parameter == "spawn_gradient_max"],
           sp$use_quantile[sp$parameter == "spawn_gradient_max"],
           sp$n[sp$parameter == "spawn_channel_width_min"],
           sp$use_quantile[sp$parameter == "spawn_channel_width_min"])
  want <- c(mine$rear_n, mine$rear_gradient_p95, mine$rear_width_n,
            mine$rear_width_p05, mine$spawn_n, mine$spawn_gradient_p95,
            mine$spawn_width_n, mine$spawn_width_p05)
  if (!isTRUE(all.equal(got, want, tolerance = 1e-9))) {
    stop("reimplementation disagrees with the producer for ", s, ": ",
         paste(signif(got, 6), collapse = " "), " vs ",
         paste(signif(want, 6), collapse = " "), call. = FALSE)
  }
}
bridge <- vapply(names(keep_dv), function(s) {
  if (!s %in% names(runs)) return(NA_real_)
  b <- utils::read.csv(file.path(runs[[s]], "bridge_bt.csv"))
  b <- b[b$set == "BT_any_dv", ]
  sum(b$n[b$passes_predicate & !b$rearing & b$accessible]) / sum(b$n)
}, numeric(1))
scen$bridge_loss <- bridge[scen$scenario]
scen$rear_gradient_current <- current$rear_gradient_max
scen$rear_gradient_says <- ifelse(
  abs(scen$rear_gradient_rule - scen$rear_gradient_current) <= 0.005 + 1e-9,
  "keep", "change")
readr::write_csv(scen, file.path(dir_out, "scenarios.csv"), na = "")

dropped <- bind_rows(lapply(setdiff(names(keep_dv), "S0_whole_skeena"), function(s) {
  d <- seg0[seg0$obs_species == "DV" & !keep_dv[[s]](seg0), ]
  if (nrow(d) == 0L) return(NULL)
  count(d, watershed_group_code, name = "dv_rows") |> mutate(scenario = s, .before = 1)
}))
readr::write_csv(dropped, file.path(dir_out, "scenarios_dropped.csv"), na = "")

# -- 4. optional: score every scenario through the validator --------------------
if (do_validate) {
  val <- bind_rows(lapply(names(bundles), function(s) {
    out <- file.path(tmp, paste0("val_", s))
    message("validator: ", s)
    st <- system2("Rscript", c("data-raw/habitat_validate.R",
                               "--bundles=default:fresh_default",
                               paste0("--pooling=", bundles[[s]]),
                               "--species=BT", "--buffers=0",
                               paste0("--out=", out)),
                  stdout = FALSE, stderr = FALSE)
    if (!identical(st, 0L)) stop("validator failed for ", s, call. = FALSE)
    cbind(scenario = s, utils::read.csv(file.path(out, "totals.csv")))
  }))
  keep <- intersect(c("scenario", "species_code", "stage", "n_obs",
                      "share_accessible", "share_spawning", "share_rearing",
                      "share_rearing_any", "rearing_km", "spawning_km"),
                    names(val))
  readr::write_csv(val[keep], file.path(dir_out, "validate_scenarios.csv"), na = "")
}

# -- 5. figures ------------------------------------------------------------------
grp_levels <- c("Columbia", "Fraser", "Mackenzie", "Skeena", "Coast and north")
grp_cols <- c(Columbia = "#1b9e77", Fraser = "#d95f02", Mackenzie = "#7570b3",
              Skeena = "#e7298a", `Coast and north` = "#666666")
theme_set(theme_minimal(base_size = 11) +
            theme(panel.grid.minor = element_blank(), legend.position = "bottom"))

p1 <- ggplot(mutate(dec, grp = factor(grp, grp_levels)),
             aes(decade, dv_share, colour = grp)) +
  geom_vline(xintercept = year_cut, linetype = "dashed", colour = "grey60") +
  annotate("text", x = year_cut, y = 0.03, label = "1995", hjust = -0.15,
           size = 3, colour = "grey45") +
  geom_line(linewidth = 0.8) +
  geom_point(aes(size = n)) +
  scale_colour_manual(values = grp_cols, name = NULL) +
  scale_size_area(max_size = 6, name = "BT + DV records",
                  breaks = c(100, 1000, 2500), labels = scales::comma) +
  scale_x_continuous(breaks = seq(1960, 2020, 10),
                     labels = c("≤ 1960s", paste0(seq(1970, 2020, 10), "s"))) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  labs(x = NULL, y = "DV share of char records") +
  guides(colour = guide_legend(nrow = 2), size = guide_legend(nrow = 1))
ggsave(file.path(dir_out, "fig_dv_share_by_decade.png"), p1, width = 7,
       height = 4.5, dpi = 150, bg = "white")

fate_cols <- c(`later recorded as BT` = "#1b9e77",
               `not sampled after 1995` = "#bdbdbd",
               `sampled after 1995, DV only` = "#e7298a")
p2 <- ggplot(mutate(res_tab, grp = factor(grp, rev(grp_levels)),
                    fate = factor(fate, names(fate_cols))),
             aes(share, grp, fill = fate)) +
  geom_col(width = 0.7) +
  geom_text(data = distinct(res_tab, grp, streams) |>
              mutate(grp = factor(grp, rev(grp_levels))),
            aes(x = 1.01, y = grp, label = scales::comma(streams)),
            inherit.aes = FALSE, hjust = 0, size = 3.2, colour = "grey30") +
  scale_fill_manual(values = fate_cols, name = NULL) +
  scale_x_continuous(labels = scales::percent, limits = c(0, 1.12),
                     breaks = seq(0, 1, 0.25)) +
  labs(x = "Share of streams that carry a DV record (count at right)", y = NULL)
ggsave(file.path(dir_out, "fig_dv_streams_fate.png"), p2, width = 7,
       height = 3.8, dpi = 150, bg = "white")

sc3 <- filter(scen, scenario != "BT_only") |>
  mutate(y = rev(seq_len(n())), lab = scen_label[scenario])
bins <- data.frame(xmin = c(0.12, 0.13, 0.14), xmax = c(0.13, 0.14, 0.15),
                   rule = c("rule gives 0.1249", "rule gives 0.1349\n(default_tuned)",
                            "rule gives 0.1449"),
                   fill = c("#eef3f0", "#e3e0f3", "#eef3f0"))
p3 <- ggplot(sc3, aes(rear_gradient_p95, y)) +
  geom_rect(data = bins, aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
            fill = bins$fill, inherit.aes = FALSE) +
  geom_text(data = bins, aes(x = xmin + 0.0015, y = max(sc3$y) + 0.7,
                             label = rule), inherit.aes = FALSE, size = 3,
            hjust = 0, colour = "grey35", lineheight = 0.9) +
  geom_vline(xintercept = scen$rear_gradient_p95[scen$scenario == "BT_only"],
             linetype = "dotted", colour = "#1b9e77") +
  annotate("text", x = scen$rear_gradient_p95[scen$scenario == "BT_only"],
           y = 0.45, label = "BT records only", size = 3, colour = "#1b9e77",
           hjust = -0.05) +
  geom_point(aes(size = rear_n), colour = "#7570b3") +
  geom_text(aes(label = paste0("n ", scales::comma(rear_n))), nudge_y = 0.32,
            size = 3, colour = "grey30") +
  scale_size_area(max_size = 6, guide = "none") +
  scale_y_continuous(breaks = sc3$y, labels = sc3$lab,
                     limits = c(0.3, max(sc3$y) + 0.9)) +
  scale_x_continuous(limits = c(0.118, 0.15), breaks = c(0.12, 0.13, 0.14),
                     expand = c(0, 0)) +
  labs(x = "BT rearing gradient P95 (accessible, stream + river polygon)",
       y = NULL)
ggsave(file.path(dir_out, "fig_scenarios_rear_gradient.png"), p3, width = 7,
       height = 3.6, dpi = 150, bg = "white")

# -- maps -----------------------------------------------------------------------
wsg <- sf::st_read(conn, query = "
  SELECT watershed_group_code,
         ST_SimplifyPreserveTopology(geom, 1500) AS geom
  FROM whse_basemapping.fwa_watershed_groups_poly", quiet = TRUE)
bc <- sf::st_union(wsg)
hazelton <- sf::st_read(conn, query = "
  SELECT ST_LineInterpolatePoint(ST_LineMerge(geom), 0) AS geom
  FROM whse_basemapping.fwa_stream_networks_sp
  WHERE localcode_ltree = '400.431358'::ltree AND wscode_ltree = '400.431358'::ltree
  ORDER BY downstream_route_measure LIMIT 1", quiet = TRUE)
presence <- utils::read.csv(lnk_config("default")$files$wsg_species_presence$path,
                            stringsAsFactors = FALSE)
bt_present <- toupper(presence$watershed_group_code[presence$bt %in% "t"])

share_map <- wsg |>
  tidyr::crossing(era = c("before 1995", "1995 on")) |>
  left_join(wsg_share, by = c("watershed_group_code", "era")) |>
  mutate(dv_share = ifelse(n >= 10, dv_share, NA),
         era = factor(era, c("before 1995", "1995 on"))) |>
  sf::st_as_sf()
p4 <- ggplot() +
  geom_sf(data = share_map, aes(fill = dv_share), colour = "white", linewidth = 0.1) +
  geom_sf(data = bc, fill = NA, colour = "grey55", linewidth = 0.15) +
  geom_sf(data = hazelton, aes(shape = "Hazelton (Bulkley mouth)"), size = 2.2,
          fill = "white", colour = "black") +
  scale_shape_manual(values = 21, name = NULL) +
  facet_wrap(~era) +
  scale_fill_gradient2(low = "#1b9e77", mid = "#f7f7f7", high = "#e7298a",
                       midpoint = 0.5, labels = scales::percent,
                       na.value = "grey85",
                       name = "DV share of char records\n(grey: < 10 records)") +
  theme_void(base_size = 11) +
  theme(legend.position = "bottom", strip.text = element_text(size = 11),
        legend.key.width = grid::unit(1.6, "cm"))
ggsave(file.path(dir_out, "fig_map_dv_share.png"), p4, width = 9, height = 5.4,
       dpi = 150, bg = "white")

pool_state <- function(s) {
  interior_wsg <- regions$watershed_group_code[
    regions$region %in% c("Fraser", "Mackenzie", "Columbia")]
  full <- switch(s,
    S0_whole_skeena = c(interior_wsg,
                        regions$watershed_group_code[regions$region == "Skeena"]),
    S1_hazelton = c(interior_wsg, upper_skeena),
    S2_noskeena = interior_wsg,
    S4_hazelton_pre1995 = upper_skeena)
  dated <- if (s == "S4_hazelton_pre1995") interior_wsg else character(0)
  w <- wsg$watershed_group_code
  state <- ifelse(!w %in% bt_present, "BT not present",
           ifelse(w %in% full, "DV counts as BT",
           ifelse(w %in% dated, "DV counts as BT (pre-1995 records)",
                  "DV kept separate")))
  transform(wsg, scenario = scen_label[[s]], state = state)
}
pmap <- do.call(rbind, lapply(c("S0_whole_skeena", "S1_hazelton", "S2_noskeena",
                                "S4_hazelton_pre1995"), pool_state))
pmap$scenario <- factor(pmap$scenario, scen_label[c("S0_whole_skeena",
  "S1_hazelton", "S2_noskeena", "S4_hazelton_pre1995")])
state_cols <- c(`DV counts as BT` = "#7570b3",
                `DV counts as BT (pre-1995 records)` = "#b8b3e0",
                `DV kept separate` = "#e7298a", `BT not present` = "grey88")
p5 <- ggplot() +
  geom_sf(data = pmap, aes(fill = state), colour = "white", linewidth = 0.1) +
  geom_sf(data = bc, fill = NA, colour = "grey55", linewidth = 0.15) +
  geom_sf(data = hazelton, aes(shape = "Hazelton (Bulkley mouth)"), size = 1.8,
          fill = "white", colour = "black") +
  scale_shape_manual(values = 21, name = NULL) +
  facet_wrap(~scenario, nrow = 2) +
  scale_fill_manual(values = state_cols, name = NULL, drop = FALSE) +
  theme_void(base_size = 11) +
  theme(legend.position = "bottom", strip.text = element_text(size = 11)) +
  guides(fill = guide_legend(nrow = 2))
ggsave(file.path(dir_out, "fig_map_pooling_scenarios.png"), p5, width = 9,
       height = 8.4, dpi = 150, bg = "white")

# Skeena close-up: DV share from 1995 on, with the Hazelton split
sk <- wsg[grp_of(wsg$watershed_group_code) == "Skeena", ] |>
  left_join(filter(wsg_share, era == "1995 on"), by = "watershed_group_code") |>
  mutate(side = ifelse(watershed_group_code %in% upper_skeena,
                       "above Hazelton", "below Hazelton"))
lab <- sf::st_coordinates(sf::st_point_on_surface(sf::st_geometry(sk)))
lab <- data.frame(x = lab[, 1], y = lab[, 2],
                  label = paste0(sk$watershed_group_code, "\n",
                                 ifelse(is.na(sk$n), "",
                                        paste0(scales::percent(sk$dv_share, 1),
                                               " DV (", sk$n, ")"))))
# LKEL is a sliver beside ZYMO: set its label below, clear of ZYMO's
lab$y[sk$watershed_group_code == "LKEL"] <- lab$y[sk$watershed_group_code == "LKEL"] - 22000
lab$x[sk$watershed_group_code == "LKEL"] <- lab$x[sk$watershed_group_code == "LKEL"] - 15000
p6 <- ggplot(sk) +
  geom_sf(aes(fill = side), colour = "white", linewidth = 0.3) +
  geom_sf(data = hazelton, aes(shape = "Hazelton (Bulkley mouth)"), size = 2.6,
          fill = "white", colour = "black") +
  scale_shape_manual(values = 21, name = NULL) +
  geom_text(data = lab, aes(x, y, label = label), size = 2.6, lineheight = 0.9) +
  scale_fill_manual(values = c(`above Hazelton` = "#c9c5ea",
                               `below Hazelton` = "#f6c6de"), name = NULL) +
  theme_void(base_size = 11) +
  theme(legend.position = "bottom")
ggsave(file.path(dir_out, "fig_map_skeena_hazelton.png"), p6, width = 7,
       height = 6.5, dpi = 150, bg = "white")

# -- stamp ------------------------------------------------------------------------
writeLines(c(
  sprintf("date: %s", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
  sprintf("link: %s @ %s", utils::packageVersion("link"),
          system("git rev-parse --short HEAD", intern = TRUE)),
  "db: docker fwapg localhost:5432",
  sprintf("bcfishobs.observations rows: %s",
          dbGetQuery(conn, "SELECT count(*) FROM bcfishobs.observations")[[1]]),
  sprintf("BT + DV records (not Releases): %d; undated: %d", nrow(obs), sum(is.na(obs$yr))),
  "evidence: data-raw/query_habitat_thresholds_obs.R on fresh_default (55 WSGs), one run per scenario bundle",
  sprintf("reimplementation matched the producer for: %s", paste(names(runs), collapse = ", ")),
  sprintf("validator runs: %s", if (do_validate) paste(names(bundles), collapse = ", ") else "not run")),
  file.path(dir_out, "stamp.txt"))
DBI::dbDisconnect(conn)
message("wrote ", dir_out)

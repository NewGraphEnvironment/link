# Observation use vs availability for CH and BT habitat thresholds (link#284).
#
# For every CH and BT observation in `bcfishobs.observations` that lands in a
# WSG persisted in `fresh_default`, find the segment the model actually tests,
# record its gradient, channel width and waterbody type, then compare with the
# length of accessible network available in the same WSGs. The output is the
# evidence behind the candidate values in `configs/default_tuned/` and
# `research/habitat_thresholds.md`.
#
# Read-only against docker fwapg (:5432). Temp tables only.
#
#   Rscript data-raw/query_habitat_thresholds_obs.R
#
# Writes to data-raw/logs/habitat_thresholds_284/:
#   obs_ledger.csv        counts dropped at each filter step
#   obs_segments.csv      one row per retained observation, with its segment
#   obs_status.csv        pass / fail decomposition against current cutoffs
#   quantiles.csv         use quantiles by species x stage x region x metric
#   selection.csv         use vs availability by gradient / width bin
#   projects.csv          project dominance (top sources per species)
#   bridge_bt.csv         BT observations lost to cluster_rearing (G9)
#   uhc_ch.csv            CH obs inside user_habitat_classification reaches (G7)
#   candidates.csv        the decision rule in task_plan.md, applied mechanically, with the
#                         three later changes recorded in research/habitat_thresholds.md
#   stamp.txt             environment stamp
#   fig_*.png             selection-ratio figures with current cutoffs

pkgload::load_all(quiet = TRUE)
suppressPackageStartupMessages({
  library(DBI)
  library(dplyr)
  library(ggplot2)
})

dir_out <- file.path("data-raw", "logs", "habitat_thresholds_284")
fs::dir_create(dir_out)

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")

schema <- "fresh_default"
species <- c("CH", "BT")
cfg <- lnk_config("default")
th <- readr::read_csv(cfg$files$parameters_habitat_thresholds$path,
                      show_col_types = FALSE) |>
  filter(species_code %in% species)
pf <- readr::read_csv(cfg$files$parameters_fresh$path, show_col_types = FALSE) |>
  filter(species_code %in% species) |>
  distinct(species_code, .keep_all = TRUE)

# -- inputs pushed as temp tables -------------------------------------------
excl <- readr::read_csv(cfg$files$observation_exclusions$path,
                        show_col_types = FALSE, col_types = readr::cols(.default = "c")) |>
  filter(data_error %in% "t" | release_exclude %in% "t") |>
  distinct(observation_key)
presence <- readr::read_csv(cfg$files$wsg_species_presence$path,
                            show_col_types = FALSE, col_types = readr::cols(.default = "c")) |>
  transmute(watershed_group_code,
            bt = bt %in% "t", ch = ch %in% "t", dv = dv %in% "t")
dbWriteTable(conn, "t_excl", excl, temporary = TRUE, overwrite = TRUE)
dbWriteTable(conn, "t_presence", presence, temporary = TRUE, overwrite = TRUE)

wsg_persisted <- dbGetQuery(conn, sprintf(
  "SELECT DISTINCT watershed_group_code FROM %s.streams", schema))$watershed_group_code

# -- observations, every flag kept so the ledger is exact --------------------
# DV rows are pooled with BT where the WSG has BT, as the pipeline already
# treats them (observation_species for BT is BT;DV). Inland, DV records are
# bull trout recorded under the old name; on the coast either species occurs,
# and their habitat biology is close enough not to separate here. bcfishobs
# gives BT no life stage or activity at all, so DV records are also the only
# staged char evidence. Pooled BT+DV is the primary BT evidence; BT-only is
# kept beside it as a comparison, so the evidence exists both ways.
dbExecute(conn, "DROP TABLE IF EXISTS t_obs")
dbExecute(conn, "
  CREATE TEMP TABLE t_obs AS
  SELECT o.observation_key,
         o.species_code AS obs_species,
         CASE WHEN o.species_code = 'DV' THEN 'BT' ELSE o.species_code END AS species_code,
         o.watershed_group_code, o.blue_line_key,
         o.downstream_route_measure AS m,
         left(o.match_type, 1) AS match_class,
         o.activity_code, o.activity, o.life_stage, o.source, o.source_ref,
         o.observation_date,
         o.source LIKE 'Releases Database%' AS is_release,
         o.observation_key IN (SELECT observation_key FROM t_excl) AS is_excluded,
         (o.species_code <> 'DV' OR coalesce(p.bt, false)) AS dv_ok
  FROM bcfishobs.observations o
  LEFT JOIN t_presence p ON p.watershed_group_code = o.watershed_group_code
  WHERE o.species_code IN ('CH', 'BT', 'DV')")

# The segment the model tests. Observations are break points (the pipeline
# breaks at round(downstream_route_measure)), so a point usually sits on a
# boundary: take the segment that STARTS within 1 m (the upstream one), else
# the one containing the point. n_cand > 1 is reported, not silently resolved.
dbExecute(conn, "DROP TABLE IF EXISTS t_obs_seg")
dbExecute(conn, sprintf("
  CREATE TEMP TABLE t_obs_seg AS
  SELECT o.observation_key, s.id_segment, s.watershed_group_code AS seg_wsg,
         s.n_cand, s.gradient, s.channel_width, s.channel_width_source,
         s.edge_type, s.stream_order, s.waterbody_key, s.length_metre,
         split_part(s.wscode_ltree::text, '.', 1) AS region,
         dn.gradient AS gradient_dn
  FROM t_obs o
  JOIN LATERAL (
    SELECT s.*, count(*) OVER () AS n_cand
    FROM %1$s.streams s
    WHERE s.blue_line_key = o.blue_line_key
      AND s.watershed_group_code = o.watershed_group_code
      AND (abs(s.downstream_route_measure - o.m) < 1
           OR (s.downstream_route_measure <= o.m AND o.m < s.upstream_route_measure))
    ORDER BY (abs(s.downstream_route_measure - o.m) < 1) DESC,
             s.downstream_route_measure DESC
    LIMIT 1) s ON true
  LEFT JOIN LATERAL (
    SELECT d.gradient FROM %1$s.streams d
    WHERE d.blue_line_key = o.blue_line_key
      AND d.watershed_group_code = o.watershed_group_code
      AND abs(d.upstream_route_measure - o.m) < 1
    LIMIT 1) dn ON true", schema))

# 100 m window gradient from FWA geometry Z, independent of link's breaks.
dbExecute(conn, "DROP TABLE IF EXISTS t_obs_w100")
dbExecute(conn, "
  CREATE TEMP TABLE t_obs_w100 AS
  WITH b AS (
    SELECT o.observation_key, o.blue_line_key, o.m,
           least(o.m + 100, x.blk_max) AS m_up
    FROM t_obs o
    JOIN t_obs_seg USING (observation_key)
    JOIN LATERAL (
      SELECT max(upstream_route_measure) AS blk_max
      FROM whse_basemapping.fwa_stream_networks_sp f
      WHERE f.blue_line_key = o.blue_line_key) x ON true)
  SELECT b.observation_key,
         (st_z(u.geom) - st_z(d.geom)) / nullif(b.m_up - b.m, 0) AS gradient_w100
  FROM b
  LEFT JOIN LATERAL whse_basemapping.fwa_locatealong(b.blue_line_key, b.m) d ON true
  LEFT JOIN LATERAL whse_basemapping.fwa_locatealong(b.blue_line_key, b.m_up) u ON true")

obs <- dbGetQuery(conn, sprintf("
  SELECT o.*, s.id_segment, s.seg_wsg, s.n_cand, s.gradient, s.gradient_dn,
         w100.gradient_w100, s.channel_width, s.channel_width_source,
         s.edge_type, s.stream_order, s.length_metre, s.region,
         wb.waterbody_type,
         h.accessible, h.spawning, h.rearing
  FROM t_obs o
  LEFT JOIN t_obs_seg s USING (observation_key)
  LEFT JOIN t_obs_w100 w100 USING (observation_key)
  LEFT JOIN whse_basemapping.fwa_waterbodies wb ON wb.waterbody_key = s.waterbody_key
  LEFT JOIN (
    SELECT 'CH' AS species_code, * FROM %1$s.streams_habitat_ch
    UNION ALL
    SELECT 'BT', * FROM %1$s.streams_habitat_bt) h
    ON h.species_code = o.species_code
   AND h.id_segment = s.id_segment AND h.watershed_group_code = s.seg_wsg
  ORDER BY o.observation_key", schema))

# -- stage -------------------------------------------------------------------
# Spawning / rearing from activity; rearing also from juvenile life stages.
# Adult, holding, migrating and "observed at this point" are not a stage.
obs <- obs |>
  mutate(
    act = paste(activity_code, activity),
    is_spawn = grepl("\\bSPL\\b|\\bSPM\\b|\\bS\\b|Spawning", act),
    is_rear = grepl("\\bR\\b|\\bREA\\b|Rearing", act) |
      grepl("Fry|Parr|Juvenile", life_stage),
    wsg_in = watershed_group_code %in% wsg_persisted,
    present = case_when(
      species_code == "CH" ~ watershed_group_code %in% presence$watershed_group_code[presence$ch],
      species_code == "BT" ~ watershed_group_code %in% presence$watershed_group_code[presence$bt]),
    pred_set = case_when(
      waterbody_type %in% "R" ~ "river_poly",
      waterbody_type %in% "L" ~ "lake",
      waterbody_type %in% "W" ~ "wetland",
      !is.na(waterbody_type) ~ "other_waterbody",
      edge_type %in% c(1000, 1100, 2000, 2300) ~ "stream",
      edge_type %in% c(1050, 1150) ~ "wetland_edge",
      !is.na(edge_type) ~ "other_edge",
      TRUE ~ NA_character_))

# -- ledger ------------------------------------------------------------------
ledger_step <- function(d, step) {
  d |> count(obs_species, name = "n") |> mutate(step = step, .before = 1)
}
o0 <- obs
o1 <- filter(o0, !is_excluded)
o2 <- filter(o1, !is_release)
o3 <- filter(o2, dv_ok)
o4 <- filter(o3, wsg_in, present)
o5 <- filter(o4, !is.na(id_segment))
o6 <- filter(o5, match_class %in% c("A", "B"))
o7 <- o6 |>
  mutate(loc = paste(species_code, blue_line_key, round(m))) |>
  arrange(observation_key) |>
  group_by(obs_species, loc) |>
  mutate(is_spawn = any(is_spawn), is_rear = any(is_rear), n_records = n()) |>
  slice(1) |>
  ungroup()
ledger <- bind_rows(
  ledger_step(o0, "0 all CH/BT/DV records"),
  ledger_step(o1, "1 minus observation_exclusions (data_error | release_exclude)"),
  ledger_step(o2, "2 minus Releases Database"),
  ledger_step(o3, "3 DV kept only where WSG has BT (pooled with BT)"),
  ledger_step(o4, sprintf("4 in %s WSGs where species present", schema)),
  ledger_step(o5, "5 joined to a segment"),
  ledger_step(o6, "6 match type A/B (stream, within 100 m)"),
  ledger_step(o7, "7 deduplicated to one per species x blue_line_key x metre"))
readr::write_csv(ledger, file.path(dir_out, "obs_ledger.csv"), na = "")

# n_cand 2 is expected when a point sits just below a break: the containing
# segment and the one starting within 1 m both qualify; the upstream one wins.
message("observations with 2+ candidate segments (upstream chosen): ",
        sum(o5$n_cand > 1L))

use <- o7
readr::write_csv(
  use |> select(observation_key, obs_species, species_code, watershed_group_code,
                blue_line_key, m, match_class, is_spawn, is_rear, n_records,
                region, id_segment, n_cand, gradient, gradient_dn, gradient_w100,
                channel_width, channel_width_source, edge_type, stream_order,
                waterbody_type, pred_set, accessible, spawning, rearing),
  file.path(dir_out, "obs_segments.csv"), na = "")

# -- use sets ----------------------------------------------------------------
sets <- list(
  CH_any = filter(use, obs_species == "CH"),
  CH_spawn = filter(use, obs_species == "CH", is_spawn),
  CH_rear = filter(use, obs_species == "CH", is_rear),
  # BT_any is BT-only records (the comparison); BT_any_dv pools BT and DV
  # (primary), and BT and DV records at one location are one location there.
  BT_any = filter(use, obs_species == "BT"),
  BT_any_dv = filter(use, species_code == "BT") |> distinct(loc, .keep_all = TRUE),
  BT_spawn_dv = filter(use, obs_species == "DV", is_spawn),
  BT_rear_dv = filter(use, obs_species == "DV", is_rear))
set_species <- sub("_.*", "", names(sets))

# -- pass / fail against current cutoffs -------------------------------------
status_one <- function(d, sp, stage) {
  t <- th[th$species_code == sp, ]
  gmax <- t[[paste0(stage, "_gradient_max")]]
  wmin <- t[[paste0(stage, "_channel_width_min")]]
  d |> mutate(status = case_when(
    pred_set == "stream" & gradient > gmax ~ "fails_gradient",
    pred_set == "stream" & is.na(channel_width) ~ "width_null",
    pred_set == "stream" & channel_width < wmin ~ "fails_width",
    pred_set == "stream" ~ "passes",
    pred_set == "river_poly" & gradient > gmax ~ "fails_gradient",
    # The R rule's channel_width [0, 9999] is a BETWEEN, so NULL still fails.
    pred_set == "river_poly" & is.na(channel_width) ~ "width_null_river_poly",
    pred_set == "river_poly" ~ "passes_river_poly",
    stage == "rear" & pred_set %in% c("wetland_edge", "lake", "wetland") ~ "waterbody_rule",
    TRUE ~ paste0("not_tested_", pred_set)),
    final = if (stage == "spawn") spawning else rearing)
}
status <- bind_rows(lapply(seq_along(sets), function(i) {
  sp <- set_species[i]
  bind_rows(lapply(c("spawn", "rear"), function(stage) {
    status_one(sets[[i]], sp, stage) |>
      count(status, final) |>
      mutate(set = names(sets)[i], predicate = stage, .before = 1)
  }))
}))
readr::write_csv(status, file.path(dir_out, "obs_status.csv"), na = "")

# -- quantiles ---------------------------------------------------------------
probs <- c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99)
qtab <- function(x, set, region, metric, subset) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) return(NULL)
  q <- stats::quantile(x, probs, names = FALSE, type = 7)
  tibble(set, region, metric, subset, n = length(x),
         !!!stats::setNames(as.list(q), sprintf("p%02d", probs * 100)))
}
quant <- bind_rows(lapply(seq_along(sets), function(i) {
  d <- sets[[i]]
  regions <- c("all", sort(unique(d$region)))
  bind_rows(lapply(regions, function(r) {
    dr <- if (r == "all") d else d[d$region %in% r, ]
    # Accessible only, as in the selection ratios and the floor rule: use on
    # segments the model already blocks cannot inform a habitat cutoff.
    dr <- dr[dr$accessible %in% TRUE, ]
    g <- dr[dr$pred_set %in% c("stream", "river_poly"), ]
    w <- dr[dr$pred_set %in% "stream", ]
    bind_rows(
      qtab(g$gradient, names(sets)[i], r, "gradient", "stream+river_poly"),
      qtab(g$gradient_w100, names(sets)[i], r, "gradient_w100", "stream+river_poly"),
      qtab(w$channel_width, names(sets)[i], r, "channel_width", "stream, any source"),
      qtab(w$channel_width[w$channel_width_source %in% "FIELD_MEASURMENT"],
           names(sets)[i], r, "channel_width", "stream, field measured"),
      qtab(w$channel_width[w$channel_width_source %in% "MODELLED"],
           names(sets)[i], r, "channel_width", "stream, modelled"))
  }))
}))
readr::write_csv(quant, file.path(dir_out, "quantiles.csv"), na = "")

# -- availability: accessible length, same WSGs, binned in SQL ----------------
breaks_g <- c(-Inf, 0.0025, 0.005, 0.01, 0.02, 0.03, 0.04, 0.045, 0.05, 0.055,
              0.06, 0.07, 0.08, 0.09, 0.10, 0.105, 0.12, 0.15, 0.20, 0.25, Inf)
breaks_w <- c(0, 1.5, 2, 3, 4, 5, 6, 8, 10, 15, 20, 30, 50, Inf)
avail <- bind_rows(lapply(species, function(sp) {
  wsgs <- intersect(wsg_persisted,
                    presence$watershed_group_code[presence[[tolower(sp)]]])
  dbGetQuery(conn, sprintf("
    SELECT '%1$s' AS species_code,
           CASE WHEN wb.waterbody_type = 'R' THEN 'river_poly'
                WHEN s.waterbody_key IS NULL
                 AND s.edge_type IN (1000, 1100, 2000, 2300) THEN 'stream'
                ELSE 'other' END AS pred_set,
           s.gradient, s.channel_width,
           sum(s.length_metre) / 1000 AS km
    FROM %2$s.streams s
    JOIN %2$s.streams_habitat_%3$s h USING (id_segment, watershed_group_code)
    LEFT JOIN whse_basemapping.fwa_waterbodies wb ON wb.waterbody_key = s.waterbody_key
    WHERE h.accessible AND s.watershed_group_code = ANY($1)
    GROUP BY 1, 2, 3, 4", sp, schema, tolower(sp)),
    params = list(paste0("{", paste(wsgs, collapse = ","), "}")))
})) |> filter(pred_set != "other")

bin_label <- function(x, breaks) {
  as.character(cut(x, breaks, right = TRUE, include.lowest = TRUE))
}
sel_one <- function(d, sp, set_name, metric, breaks) {
  a <- avail |> filter(species_code == sp)
  if (metric == "channel_width") {
    d <- d |> filter(pred_set == "stream", accessible %in% TRUE)
    a <- a |> filter(pred_set == "stream")
  } else {
    d <- d |> filter(pred_set %in% c("stream", "river_poly"), accessible %in% TRUE)
  }
  u <- tibble(bin = bin_label(d[[metric]], breaks)) |>
    mutate(bin = coalesce(bin, "NULL")) |> count(bin, name = "use_n")
  v <- a |> mutate(bin = coalesce(bin_label(.data[[metric]], breaks), "NULL")) |>
    group_by(bin) |> summarise(avail_km = sum(km), .groups = "drop")
  lv <- c(levels(cut(0, breaks, right = TRUE, include.lowest = TRUE)), "NULL")
  full_join(u, v, by = "bin") |>
    mutate(use_n = coalesce(use_n, 0L), avail_km = coalesce(avail_km, 0),
           use_share = use_n / sum(use_n), avail_share = avail_km / sum(avail_km),
           ratio = use_share / avail_share,
           bin = factor(bin, levels = lv)) |>
    arrange(bin) |>
    mutate(set = set_name, metric = metric, .before = 1)
}
sel <- bind_rows(lapply(seq_along(sets), function(i) bind_rows(
  sel_one(sets[[i]], set_species[i], names(sets)[i], "gradient", breaks_g),
  sel_one(sets[[i]], set_species[i], names(sets)[i], "channel_width", breaks_w))))
readr::write_csv(sel |> mutate(bin = as.character(bin)),
                 file.path(dir_out, "selection.csv"), na = "")

# -- project dominance -------------------------------------------------------
projects <- use |>
  mutate(project = sub(";.*", "", source_ref)) |>
  count(obs_species, project, name = "n_locations", sort = TRUE) |>
  group_by(obs_species) |>
  mutate(share = n_locations / sum(n_locations)) |>
  slice_head(n = 10) |> ungroup()
readr::write_csv(projects, file.path(dir_out, "projects.csv"), na = "")

# -- G9: BT observations lost to cluster_rearing -----------------------------
bridge <- bind_rows(lapply(c("BT_any_dv", "BT_any"), function(nm) {
  status_one(sets[[nm]], "BT", "rear") |>
    mutate(passes_predicate = status %in% c("passes", "passes_river_poly")) |>
    count(passes_predicate, rearing, accessible) |>
    mutate(share = n / sum(n)) |>
    mutate(set = nm, .before = 1)
}))
readr::write_csv(bridge, file.path(dir_out, "bridge_bt.csv"), na = "")

# -- G7: CH obs inside user_habitat_classification reaches -------------------
uhc <- readr::read_csv(cfg$files$user_habitat_classification$path,
                       show_col_types = FALSE) |>
  filter(species_code == "CH")
ch_use <- sets$CH_any |>
  select(loc, blue_line_key, m, is_spawn, is_rear, gradient, channel_width) |>
  inner_join(uhc |> select(blue_line_key, drm = downstream_route_measure,
                           urm = upstream_route_measure, uhc_spawning = spawning,
                           uhc_rearing = rearing),
             by = "blue_line_key", relationship = "many-to-many") |>
  filter(m >= drm, m <= urm) |>
  distinct(loc, .keep_all = TRUE)
readr::write_csv(
  ch_use |> count(uhc_spawning, uhc_rearing, is_spawn),
  file.path(dir_out, "uhc_ch.csv"), na = "")

# -- decision rule (task_plan.md), applied mechanically -----------------------
snap49 <- function(x) floor(x * 100) / 100 + 0.0049
q_of <- function(set, metric, subset, p) {
  r <- quant |> filter(.data$set == !!set, region == "all", .data$metric == !!metric,
                       .data$subset == !!subset)
  if (nrow(r) == 0L) return(c(n = 0, q = NA_real_))
  c(n = r$n, q = r[[p]])
}
ratio_above <- function(set, cut) {
  r <- sel |> filter(.data$set == !!set, metric == "gradient", bin != "NULL") |>
    mutate(lo = as.numeric(sub("^[\\[(]([^,]+),.*", "\\1", as.character(bin))))
  r$ratio[which(r$lo >= cut - 1e-9)[1]]
}
cand_row <- function(sp, param, set, current, kind, role = "primary") {
  if (kind == "gradient_max") {
    x <- q_of(set, "gradient", "stream+river_poly", "p95")
    cand <- snap49(x[["q"]])
    ra <- ratio_above(set, current)
    # The pre-set rule also kept the value when `ra >= 1`. That clause was
    # inverted (selection >= 1 above a cutoff argues for loosening), so it is
    # no longer a keep condition; `ra` is reported for reading.
    keep <- is.na(cand) || abs(cand - current) < 0.005
  } else {
    x <- q_of(set, "channel_width", "stream, any source", "p05")
    cand <- round(x[["q"]], 1)
    ra <- NA_real_
    keep <- is.na(cand) || abs(cand - current) < 0.5
  }
  tibble(species_code = sp, parameter = param, evidence_set = set, evidence_role = role,
         current = current, n = x[["n"]], use_quantile = x[["q"]],
         rule_value = cand, ratio_first_bin_above_current = ra,
         rule_says = if (keep) "keep" else "change")
}
cands <- bind_rows(
  cand_row("CH", "spawn_gradient_max", "CH_spawn", th$spawn_gradient_max[th$species_code == "CH"], "gradient_max"),
  cand_row("CH", "rear_gradient_max", "CH_rear", th$rear_gradient_max[th$species_code == "CH"], "gradient_max"),
  cand_row("CH", "spawn_channel_width_min", "CH_spawn", th$spawn_channel_width_min[th$species_code == "CH"], "width_min"),
  cand_row("CH", "rear_channel_width_min", "CH_rear", th$rear_channel_width_min[th$species_code == "CH"], "width_min"),
  cand_row("BT", "spawn_gradient_max", "BT_spawn_dv", th$spawn_gradient_max[th$species_code == "BT"], "gradient_max"),
  cand_row("BT", "rear_gradient_max", "BT_any_dv", th$rear_gradient_max[th$species_code == "BT"], "gradient_max"),
  cand_row("BT", "rear_gradient_max", "BT_any", th$rear_gradient_max[th$species_code == "BT"], "gradient_max",
           role = "comparison: BT records only"),
  cand_row("BT", "spawn_channel_width_min", "BT_spawn_dv", th$spawn_channel_width_min[th$species_code == "BT"], "width_min"),
  cand_row("BT", "rear_channel_width_min", "BT_any_dv", th$rear_channel_width_min[th$species_code == "BT"], "width_min"),
  cand_row("BT", "rear_channel_width_min", "BT_any", th$rear_channel_width_min[th$species_code == "BT"], "width_min",
           role = "comparison: BT records only"))

# spawn_gradient_min: floor only if spawn use below it is < 5 % and the
# selection ratio there is < 0.5.
floor_row <- function(sp, set) {
  d <- sets[[set]] |> filter(pred_set %in% c("stream", "river_poly"), accessible %in% TRUE)
  a <- avail |> filter(species_code == sp)
  bind_rows(lapply(c(0.001, 0.0025, 0.005), function(f) {
    us <- mean(d$gradient < f, na.rm = TRUE)
    as <- sum(a$km[a$gradient < f], na.rm = TRUE) / sum(a$km)
    tibble(species_code = sp, parameter = "spawn_gradient_min", evidence_set = set,
           evidence_role = "primary", current = pf$spawn_gradient_min[pf$species_code == sp], n = nrow(d),
           floor_tested = f, use_share_below = us, avail_share_below = as,
           ratio_below = us / as,
           rule_says = if (isTRUE(us < 0.05 && us / as < 0.5)) "floor" else "keep")
  }))
}
floors <- bind_rows(floor_row("CH", "CH_spawn"), floor_row("BT", "BT_spawn_dv"))

# Share of all the set's observations that sit on accessible segments passing
# the rear predicate yet carry rearing = FALSE.
bridge_row <- bind_rows(lapply(c("BT_any_dv", "BT_any"), function(nm) {
  b <- bridge[bridge$set == nm, ]
  sh <- sum(b$n[b$passes_predicate & b$rearing %in% FALSE & b$accessible %in% TRUE]) / sum(b$n)
  tibble(species_code = "BT", parameter = "cluster_bridge_gradient", evidence_set = nm,
         evidence_role = if (nm == "BT_any") "comparison: BT records only" else "primary",
         current = pf$cluster_bridge_gradient[pf$species_code == "BT"],
         n = nrow(sets[[nm]]), share_lost_to_clustering = sh,
         rule_says = if (sh > 0.10) "raise" else "keep")
}))

readr::write_csv(bind_rows(cands, floors, bridge_row),
                 file.path(dir_out, "candidates.csv"), na = "")

# -- figures -----------------------------------------------------------------
plot_sel <- function(metric, cut_cols, file, xlab) {
  d <- sel |> filter(.data$metric == !!metric, bin != "NULL", use_n + avail_km > 0)
  d <- d |> mutate(species_code = sub("_.*", "", set),
                   lo = as.numeric(sub("^[\\[(]([^,]+),.*", "\\1", as.character(bin))),
                   lo = if_else(is.infinite(lo), 0, lo))
  # One set of cutoff lines per panel, the panel's own species'.
  cuts <- th |> select(species_code, all_of(cut_cols)) |>
    tidyr::pivot_longer(-species_code, names_to = "cutoff", values_to = "value") |>
    inner_join(distinct(d, set, species_code), by = "species_code",
               relationship = "many-to-many")
  p <- ggplot(d, aes(lo, ratio)) +
    geom_hline(yintercept = 1, colour = "grey50") +
    geom_step(direction = "hv") +
    geom_point(aes(size = use_n), alpha = 0.5) +
    geom_vline(data = cuts, aes(xintercept = value, linetype = cutoff), colour = "firebrick") +
    facet_wrap(~set, scales = "free_y", ncol = 2) +
    scale_x_continuous(trans = "sqrt") +
    labs(x = xlab, y = "selection ratio (use share / accessible length share)",
         size = "observations", linetype = "current cutoff") +
    theme_minimal(base_size = 10)
  ggsave(file.path(dir_out, file), p, width = 9, height = 9, dpi = 110, bg = "white")
}
plot_sel("gradient", c("spawn_gradient_max", "rear_gradient_max"),
         "fig_selection_gradient.png", "segment gradient (bin lower edge, sqrt scale)")
plot_sel("channel_width", c("spawn_channel_width_min", "rear_channel_width_min"),
         "fig_selection_width.png", "channel width m (bin lower edge, sqrt scale)")

# -- stamp -------------------------------------------------------------------
# The fresh that analyses here is the installed one; the fresh that BUILT the
# schema is in its run log, for the runs that were logged at all.
fresh_desc <- utils::packageDescription("fresh")
fresh_sha <- .lnk_pkg_git_sha("fresh")
run_log <- dbGetQuery(conn, sprintf(
  "SELECT count(*) AS n_runs, min(date_start)::date AS first, max(date_end)::date AS last,
          string_agg(DISTINCT fresh_version || '@' || coalesce(left(fresh_sha, 7), 'NA'), ', ')
            AS built_with
   FROM %s.log", schema))
link_dirty <- length(system(paste("git status --porcelain -- R inst/extdata/configs/default",
                                  "data-raw/query_habitat_thresholds_obs.R"),
                            intern = TRUE)) > 0L
stamp <- c(
  sprintf("date: %s", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
  sprintf("link: %s @ %s%s", utils::packageVersion("link"),
          system("git rev-parse --short HEAD", intern = TRUE),
          if (link_dirty) " (dirty: R/, configs/default or this script uncommitted)" else ""),
  sprintf("fresh installed: %s @ %s", fresh_desc$Version,
          if (is.na(fresh_sha)) "no recorded sha" else fresh_sha),
  "db: docker fwapg localhost:5432",
  sprintf(paste("schema: %s (%d WSGs persisted; %d run-log rows, %s to %s, built with fresh %s;",
                "the other WSGs predate the log)"),
          schema, length(wsg_persisted), as.integer(run_log$n_runs), run_log$first,
          run_log$last, run_log$built_with),
  sprintf("bcfishobs.observations rows: %s",
          dbGetQuery(conn, "SELECT count(*) FROM bcfishobs.observations")[[1]]),
  sprintf("thresholds: %s", fs::path_rel(cfg$files$parameters_habitat_thresholds$path,
                                          fs::path_abs("."))),
  sprintf("retained observations with 2+ candidate segments (upstream chosen): %d",
          sum(use$n_cand > 1L, na.rm = TRUE)))
writeLines(stamp, file.path(dir_out, "stamp.txt"))

dbDisconnect(conn)
message("wrote ", dir_out)

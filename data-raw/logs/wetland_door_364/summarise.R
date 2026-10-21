#!/usr/bin/env Rscript
# link#364 Phase 4: what the through-wetland door and the near-river pair do,
# per species and watershed group, from the scored schemas
# (habitat_variants_build.R with data-raw/habitat_score/variants_364.csv).
#
# Tables (one row per species x WSG unless noted), all km of `rearing`:
#   wetland_flow.csv  1050/1150 rearing under `default` (free), and how the
#                     stream door splits it: kept by size (rearing under
#                     ch_door_stream), kept by the river only (rearing under
#                     ch_pair_both and not ch_door_stream), dropped (rearing
#                     under default and not under ch_pair_both). CO: under
#                     co_door_stream (no pair).
#   floor.csv         1050/1150 km that are accessible but not rearing under
#                     free, split by why: no wetland polygon, a polygon under
#                     rear_wetland_ha_min (the #311 floor), or neither.
#   stream_edges.csv  rearing km on 1000/1100/2000/2300 the pair moves:
#                     ch_pair_both minus ch_pair_wetland_flow (the stream
#                     scope), and ch_pair_stream minus ch_door_stream.
#   w_polygon.csv     km the W polygon rule alone admits under default:
#                     1000/1100 inside a wetland polygon at or over the floor,
#                     rearing, failing the stream test (gradient over the
#                     rear maximum, or width below the minimum or NULL).
#   measures.csv      river-polygon (1250) and lake (1200) main-flow rows,
#                     and how many carry fwapg discharge, channel width and
#                     stream order.
#
# Usage (repo root):
#   Rscript data-raw/logs/wetland_door_364/summarise.R [--prefix=score364_]
#     [--roles=data-raw/habitat_score/wsg_roles_364.csv]
#     [--out=data-raw/logs/wetland_door_364]

pkgload::load_all(quiet = TRUE)
suppressPackageStartupMessages(library(DBI))

opt <- function(name, default) {
  a <- grep(paste0("^--", name, "="), commandArgs(trailingOnly = TRUE),
            value = TRUE)
  if (length(a) == 0L) default else sub(paste0("^--", name, "="), "", a[length(a)])
}
prefix <- opt("prefix", "score364_")
roles <- utils::read.csv(opt("roles", "data-raw/habitat_score/wsg_roles_364.csv"))
out_dir <- opt("out", file.path("data-raw", "logs", "wetland_door_364"))
stopifnot(grepl("^[a-z][a-z0-9_]*_$", prefix))
sch <- function(v) paste0(prefix, v)

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg <- lnk_config("default")
th <- utils::read.csv(cfg$files$parameters_habitat_thresholds$path)
dims <- utils::read.csv(cfg$dimensions)
km <- function(x) round(x / 1000, 1)
q <- function(sql, ...) dbGetQuery(conn, sql, params = list(...))

# A segment's rearing flag in a variant schema, NA when that schema holds no
# row for it (a variant classifies only its own species).
rear_join <- function(alias, v, sp) {
  sprintf("LEFT JOIN %s.streams_habitat_%s %s
             ON %s.id_segment = s.id_segment
            AND %s.watershed_group_code = s.watershed_group_code",
          sch(v), tolower(sp), alias, alias, alias)
}

wf <- list(); fl <- list(); se <- list(); wp <- list(); ms <- list()
for (k in seq_len(nrow(roles))) {
  w <- roles$watershed_group_code[k]
  sp <- roles$species_code[k]
  base <- sch("default")
  door <- if (sp == "CH") "ch_door_stream" else "co_door_stream"
  has <- function(v) dbExistsTable(conn, Id(schema = sch(v),
                                            table = paste0("streams_habitat_", tolower(sp))))
  if (!has(door)) next
  pair <- sp == "CH" && has("ch_pair_both")
  r <- q(sprintf(
    "SELECT sum(s.length_metre) FILTER (WHERE b.rearing) AS free_km,
            sum(s.length_metre) FILTER (WHERE d.rearing) AS kept_size_km,
            %s AS kept_river_km,
            %s AS dropped_km
       FROM %s.streams s
       %s %s %s
      WHERE s.watershed_group_code = $1 AND s.edge_type IN (1050, 1150)",
    if (pair) "sum(s.length_metre) FILTER (WHERE p.rearing AND NOT coalesce(d.rearing, false))" else "NULL::double precision",
    if (pair) "sum(s.length_metre) FILTER (WHERE b.rearing AND NOT coalesce(p.rearing, false))" else
      "sum(s.length_metre) FILTER (WHERE b.rearing AND NOT coalesce(d.rearing, false))",
    base, rear_join("b", "default", sp), rear_join("d", door, sp),
    if (pair) rear_join("p", "ch_pair_both", sp) else ""), w)
  wf[[length(wf) + 1L]] <- data.frame(watershed_group_code = w, species_code = sp,
    free_km = km(r$free_km), kept_by_size_km = km(r$kept_size_km),
    kept_by_river_only_km = km(r$kept_river_km), dropped_km = km(r$dropped_km))

  floor_ha <- suppressWarnings(as.numeric(dims$rear_wetland_ha_min[dims$species == sp]))
  # No floor (CO): every polygon is at or over it.
  if (length(floor_ha) != 1L || is.na(floor_ha)) floor_ha <- 0
  r <- q(sprintf(
    "SELECT sum(s.length_metre) FILTER (WHERE s.waterbody_key IS NULL) AS no_polygon,
            sum(s.length_metre) FILTER (WHERE w.area_ha < %s) AS under_floor,
            sum(s.length_metre) FILTER (WHERE w.area_ha >= %s) AS other
       FROM %s.streams s
       JOIN %s.streams_access a USING (id_segment, watershed_group_code)
       %s
       LEFT JOIN whse_basemapping.fwa_wetlands_poly w ON w.waterbody_key = s.waterbody_key
      WHERE s.watershed_group_code = $1 AND s.edge_type IN (1050, 1150)
        AND a.access_%s IN (1, 2) AND NOT coalesce(b.rearing, false)",
    floor_ha, floor_ha, base, base, rear_join("b", "default", sp), tolower(sp)), w)
  fl[[length(fl) + 1L]] <- data.frame(watershed_group_code = w, species_code = sp,
    floor_ha = floor_ha, accessible_not_rearing_no_polygon_km = km(r$no_polygon),
    accessible_not_rearing_under_floor_km = km(r$under_floor),
    accessible_not_rearing_over_floor_km = km(r$other))

  if (pair) {
    r <- q(sprintf(
      "SELECT sum(s.length_metre) FILTER (WHERE p.rearing AND NOT coalesce(f.rearing, false)) AS both_not_wf,
              sum(s.length_metre) FILTER (WHERE t.rearing AND NOT coalesce(d.rearing, false)) AS stream_not_door
         FROM %s.streams s %s %s %s %s
        WHERE s.watershed_group_code = $1 AND s.edge_type IN (1000, 1100, 2000, 2300)",
      base, rear_join("p", "ch_pair_both", sp), rear_join("f", "ch_pair_wetland_flow", sp),
      rear_join("t", "ch_pair_stream", sp), rear_join("d", "ch_door_stream", sp)), w)
    se[[length(se) + 1L]] <- data.frame(watershed_group_code = w, species_code = sp,
      pair_on_stream_edges_both_minus_wetland_flow_km = km(r$both_not_wf),
      pair_on_stream_edges_stream_minus_door_km = km(r$stream_not_door))
  }

  t_sp <- th[th$species_code == sp, ]
  r <- q(sprintf(
    "SELECT sum(s.length_metre) AS km
       FROM %s.streams s %s
       JOIN whse_basemapping.fwa_wetlands_poly w ON w.waterbody_key = s.waterbody_key
      WHERE s.watershed_group_code = $1 AND s.edge_type IN (1000, 1100)
        AND w.area_ha >= %s AND b.rearing
        AND (s.gradient > %s OR s.channel_width IS NULL OR s.channel_width < %s)",
    base, rear_join("b", "default", sp), floor_ha, t_sp$rear_gradient_max,
    t_sp$rear_channel_width_min), w)
  wp[[length(wp) + 1L]] <- data.frame(watershed_group_code = w, species_code = sp,
    w_polygon_rule_alone_km = km(r$km))
}
for (w in unique(roles$watershed_group_code)) {
  r <- q(sprintf(
    "SELECT s.edge_type, count(*)::int AS rows,
            count(d.mad_m3s)::int AS with_fwapg_discharge,
            count(s.channel_width)::int AS with_channel_width,
            count(s.stream_order)::int AS with_stream_order
       FROM %s.streams s
       LEFT JOIN whse_basemapping.fwa_stream_networks_discharge d
         ON d.linear_feature_id = s.linear_feature_id
      WHERE s.watershed_group_code = $1 AND s.edge_type IN (1200, 1250)
        AND s.blue_line_key = s.watershed_key
      GROUP BY 1 ORDER BY 1", sch("default")), w)
  if (nrow(r)) ms[[length(ms) + 1L]] <- cbind(watershed_group_code = w, r)
}
wr <- function(x, f) {
  x <- do.call(rbind, x)
  utils::write.csv(x, file.path(out_dir, f), row.names = FALSE, na = "")
  cat("\n", f, "\n", sep = "")
  print(x)
}
wr(wf, "wetland_flow.csv"); wr(fl, "floor.csv"); wr(se, "stream_edges.csv")
wr(wp, "w_polygon.csv"); wr(ms, "measures.csv")
dbDisconnect(conn)

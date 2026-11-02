#!/usr/bin/env Rscript
# #432 / #433: what pausing KO and RB in `default` does to segmentation and to
# what tuning reads. Compares two builds of the same groups, one commit apart
# in behaviour only: zz432_pre (KO and RB modelled, link 07203cde) and
# zz432_post (paused, link a6942b5d). Writes, beside this script:
#   summary.csv   per group: segments, break positions only one side has,
#                 barrier and override rows that differ
#   km.csv        per group x species: accessible / spawning / rearing km each
#                 side, and km whose flag differs (measure-overlap join)
#   obs.csv       per group: modelled-species fish records, how many sit on a
#                 segment that changed, and the gradient shift there
# Usage: Rscript data-raw/logs/species_paused_432/compare.R [pre] [post]
args <- commandArgs(trailingOnly = TRUE)
pre  <- if (length(args) >= 1L) args[1] else "zz432_pre"
post <- if (length(args) >= 2L) args[2] else "zz432_post"
out_dir <- "data-raw/logs/species_paused_432"
suppressPackageStartupMessages({ library(DBI); library(RPostgres) })
conn <- dbConnect(Postgres(), dbname = "fwapg", host = "localhost", port = 5432L,
                  user = "postgres", password = "postgres")
q <- function(sql, ...) dbGetQuery(conn, sprintf(sql, ...))

wsgs <- q("SELECT DISTINCT watershed_group_code w FROM %s.streams
           INTERSECT SELECT DISTINCT watershed_group_code FROM %s.streams
           ORDER BY 1", pre, post)$w
stopifnot(length(wsgs) > 0L)
modelled <- c("BT", "CH", "CM", "CO", "PK", "SK", "ST", "WCT", "GR")

# Pieces: each pre segment cut by each post segment it overlaps on its line.
# Measures overshoot by up to a few mm within a side, so pieces under 1 cm
# are dropped (research/bcfp_segmentation_parity.md).
pieces_sql <- "
  SELECT a.watershed_group_code, a.id_segment AS id_pre, b.id_segment AS id_post,
         least(a.upstream_route_measure, b.upstream_route_measure) -
           greatest(a.downstream_route_measure, b.downstream_route_measure) AS len
    FROM %1$s.streams a
    JOIN %2$s.streams b
      ON b.watershed_group_code = a.watershed_group_code
     AND b.blue_line_key = a.blue_line_key
     AND b.downstream_route_measure < a.upstream_route_measure
     AND b.upstream_route_measure > a.downstream_route_measure
   WHERE a.watershed_group_code = '%3$s'"

summary <- do.call(rbind, lapply(wsgs, function(w) {
  n <- function(s) q("SELECT count(*) n FROM %s.streams WHERE watershed_group_code = '%s'", s, w)$n
  brk <- function(a, b) q(
    "SELECT count(*) n FROM (
       SELECT blue_line_key, round(downstream_route_measure::numeric, 3)
         FROM %1$s.streams WHERE watershed_group_code = '%3$s'
       EXCEPT
       SELECT blue_line_key, round(downstream_route_measure::numeric, 3)
         FROM %2$s.streams WHERE watershed_group_code = '%3$s') d", a, b, w)$n
  rows_diff <- function(tbl, a, b) q(
    "SELECT count(*) n FROM (
       SELECT * FROM %1$s.%4$s WHERE watershed_group_code = '%3$s'
       EXCEPT SELECT * FROM %2$s.%4$s WHERE watershed_group_code = '%3$s') d",
    a, b, w, tbl)$n
  data.frame(
    wsg = w,
    segments_pre = n(pre), segments_post = n(post),
    breaks_pre_only = brk(pre, post), breaks_post_only = brk(post, pre),
    barriers_pre_only = rows_diff("barriers", pre, post),
    barriers_post_only = rows_diff("barriers", post, pre),
    overrides_pre_only = rows_diff("barrier_overrides", pre, post),
    overrides_post_only = rows_diff("barrier_overrides", post, pre),
    ko_rb_habitat_rows_post = q(
      "SELECT (SELECT count(*) FROM %1$s.streams_habitat_ko WHERE watershed_group_code = '%2$s') +
              (SELECT count(*) FROM %1$s.streams_habitat_rb WHERE watershed_group_code = '%2$s') n",
      post, w)$n)
}))

km <- do.call(rbind, lapply(wsgs, function(w) {
  sp_here <- intersect(tolower(modelled), sub("^access_", "", q(
    "SELECT column_name c FROM information_schema.columns
      WHERE table_schema = '%s' AND table_name = 'streams_access'
        AND column_name LIKE 'access\\_%%'", post)$c))
  do.call(rbind, lapply(sp_here, function(sp) {
    has <- function(s) q(
      "SELECT count(*) n FROM %s.streams_habitat_%s WHERE watershed_group_code = '%s'",
      s, sp, w)$n > 0L
    if (!has(pre) && !has(post)) return(NULL)
    side <- function(s) q(
      "SELECT coalesce(sum(st.length_metre) FILTER (WHERE a.access_%2$s IN (1, 2)), 0) / 1000 acc,
              coalesce(sum(st.length_metre) FILTER (WHERE h.spawning), 0) / 1000 spawn,
              coalesce(sum(st.length_metre) FILTER (WHERE h.rearing), 0) / 1000 rear
         FROM %1$s.streams st
         JOIN %1$s.streams_habitat_%2$s h USING (id_segment, watershed_group_code)
         JOIN %1$s.streams_access a USING (id_segment, watershed_group_code)
        WHERE st.watershed_group_code = '%3$s'", s, sp, w)
    a <- side(pre); b <- side(post)
    moved <- q(paste0(
      "WITH p AS (", sprintf(pieces_sql, pre, post, w), ")
       SELECT coalesce(sum(p.len) FILTER (WHERE ha.rearing IS DISTINCT FROM hb.rearing), 0) / 1000 rear,
              coalesce(sum(p.len) FILTER (WHERE ha.spawning IS DISTINCT FROM hb.spawning), 0) / 1000 spawn,
              coalesce(sum(p.len) FILTER (WHERE (aa.access_%3$s IN (1, 2)) IS DISTINCT FROM
                                               (ab.access_%3$s IN (1, 2))), 0) / 1000 acc
         FROM p
         JOIN %1$s.streams_habitat_%3$s ha ON ha.id_segment = p.id_pre AND ha.watershed_group_code = p.watershed_group_code
         JOIN %2$s.streams_habitat_%3$s hb ON hb.id_segment = p.id_post AND hb.watershed_group_code = p.watershed_group_code
         JOIN %1$s.streams_access aa ON aa.id_segment = p.id_pre AND aa.watershed_group_code = p.watershed_group_code
         JOIN %2$s.streams_access ab ON ab.id_segment = p.id_post AND ab.watershed_group_code = p.watershed_group_code
        WHERE p.len >= 0.01"), pre, post, sp)
    data.frame(wsg = w, species = toupper(sp),
               accessible_km_pre = a$acc, accessible_km_post = b$acc,
               accessible_km_moved = moved$acc,
               spawning_km_pre = a$spawn, spawning_km_post = b$spawn,
               spawning_km_moved = moved$spawn,
               rearing_km_pre = a$rear, rearing_km_post = b$rear,
               rearing_km_moved = moved$rear)
  }))
}))

# A record sits on the segment whose measures contain it (start inclusive).
obs <- do.call(rbind, lapply(wsgs, function(w) {
  r <- q(
    "WITH o AS (
       SELECT fish_observation_point_id, species_code, blue_line_key, downstream_route_measure m
         FROM bcfishobs.observations
        WHERE watershed_group_code = '%3$s' AND species_code IN (%4$s)),
     s AS (
       SELECT o.*, a.downstream_route_measure dn_a, a.upstream_route_measure up_a, a.gradient g_a,
              b.downstream_route_measure dn_b, b.upstream_route_measure up_b, b.gradient g_b
         FROM o
         JOIN %1$s.streams a ON a.watershed_group_code = '%3$s' AND a.blue_line_key = o.blue_line_key
          AND o.m >= a.downstream_route_measure AND o.m < a.upstream_route_measure
         JOIN %2$s.streams b ON b.watershed_group_code = '%3$s' AND b.blue_line_key = o.blue_line_key
          AND o.m >= b.downstream_route_measure AND o.m < b.upstream_route_measure)
     SELECT count(*) n_records,
            count(*) FILTER (WHERE round(dn_a::numeric, 3) <> round(dn_b::numeric, 3)
                                OR round(up_a::numeric, 3) <> round(up_b::numeric, 3)) n_moved,
            percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(g_b - g_a))
              FILTER (WHERE round(dn_a::numeric, 3) <> round(dn_b::numeric, 3)
                         OR round(up_a::numeric, 3) <> round(up_b::numeric, 3)) med_abs_dgrad,
            max(abs(g_b - g_a)) max_abs_dgrad
       FROM s", pre, post, w,
    paste0("'", c(modelled, "DV"), "'", collapse = ", "))
  cbind(wsg = w, r)
}))

write.csv(summary, file.path(out_dir, "summary.csv"), row.names = FALSE)
write.csv(km, file.path(out_dir, "km.csv"), row.names = FALSE)
write.csv(obs, file.path(out_dir, "obs.csv"), row.names = FALSE)
print(summary); print(km, digits = 4); print(obs, digits = 4)
dbDisconnect(conn)

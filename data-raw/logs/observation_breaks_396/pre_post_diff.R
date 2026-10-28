# Question 6 (#396): does the reduced break set move the outputs only where
# expected? `default` BEFORE (zz396_default_pre) against AFTER
# (zz396_default_post), per group and species, on measure-overlap pieces per
# (watershed_group_code, blue_line_key), never on id_segment (renumbered).
#
#   Rscript data-raw/logs/observation_breaks_396/pre_post_diff.R
#
# Each piece carries both sides' access_<sp>, has_barriers_<sp>_dnstr,
# mapping_code_<sp> and habitat flags. Pieces under 1 cm are dropped: a
# segment's upstream measure can overshoot the next one's start by up to
# 3.93 mm within one side (FWA). Expected: no 2 -> 1 (slivers included); 1 -> 2 only on AFTER
# segments starting within 1 m of a kept top of that species
# (zz396_cuts.obs_<wsg>, build_obs.R); and no 0 <-> {1, 2} or has_barriers
# change, except on boundary slivers. Observations are the first break source,
# and a later source cuts only more than 1 m from the current segment ends, so
# a barrier or crossing within 1 m of a removed observation cut did not cut
# before and cuts now, moving that boundary by up to 1 m (breaks are rounded to
# the metre, so by 1 m). Pieces under 1.01 m are counted apart as `sliver_*`.
# A whole segment can also change side next to a barrier: one whose raw measure
# lies 1 to 1.5 m above an observation cut breaks 1 m above it, which did not
# cut, so the segment above the observation read it as more than 1 m above its
# start (open); now its break cuts and the segment above it reads blocked
# (#349's metre-rounding class). A moved cut can also suppress or release the
# next break above it. So blocked/open and has_barriers changes on longer
# pieces are split by whether either side's segment starts within 3 m of a
# persisted barrier of that species (`*_near_barrier`); `*_elsewhere` must be 0.
# Habitat flags and mapping codes may move where merged pieces take a new
# gradient.
# Writes pre_post_diff.csv and stops if the overlap does not cover both sides.
pkgload::load_all(quiet = TRUE)
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
out <- "data-raw/logs/observation_breaks_396"
pre <- "zz396_default_pre"
post <- "zz396_default_post"
wsgs <- c("LKEL", "BULK", "UPCE", "PARS", "ELKR")
q <- function(sql) DBI::dbGetQuery(conn, sql)
has_tbl <- function(schema, tbl) nrow(q(sprintf(
  "SELECT 1 FROM information_schema.tables
    WHERE table_schema = '%s' AND table_name = '%s'", schema, tbl))) > 0L
acc_cols <- q(sprintf(
  "SELECT column_name FROM information_schema.columns
    WHERE table_schema = '%s' AND table_name = 'streams_access'
      AND column_name LIKE 'access\\_%%'", post))$column_name
species <- sub("^access_", "", acc_cols)

side <- function(schema, wsg, sp) {
  hab <- has_tbl(schema, paste0("streams_habitat_", sp))
  hcol <- function(col) if (hab) sprintf("coalesce(h.%s, false)", col) else "false"
  sprintf(
    "SELECT s.blue_line_key AS blk, s.downstream_route_measure AS dm,
            s.upstream_route_measure AS um,
            a.access_%2$s AS acc, a.has_barriers_%2$s_dnstr AS hb,
            m.mapping_code_%2$s AS mc,
            %4$s AS accessible, %5$s AS spawning, %6$s AS rearing,
            %7$s AS lake_rearing, %8$s AS wetland_rearing
       FROM %1$s.streams s
       JOIN %1$s.streams_access a
         ON a.id_segment = s.id_segment
        AND a.watershed_group_code = s.watershed_group_code
       LEFT JOIN %1$s.streams_mapping_code m
         ON m.id_segment = s.id_segment
        AND m.watershed_group_code = s.watershed_group_code
       %9$s
      WHERE s.watershed_group_code = '%3$s'",
    schema, sp, wsg, hcol("accessible"), hcol("spawning"), hcol("rearing"),
    hcol("lake_rearing"), hcol("wetland_rearing"),
    if (hab) sprintf(
      "LEFT JOIN %1$s.streams_habitat_%2$s h
         ON h.id_segment = s.id_segment
        AND h.watershed_group_code = s.watershed_group_code", schema, sp)
    else "")
}

rows <- list()
for (wsg in wsgs) {
  obs_tbl <- paste0("zz396_cuts.obs_", tolower(wsg))
  for (sp in species) {
    r <- q(sprintf(
      "WITH a AS (%1$s), b AS (%2$s),
       tops AS (
         SELECT blue_line_key AS blk,
                round(max(downstream_route_measure)) AS m
           FROM %3$s WHERE upper(species_code) = upper('%4$s')
          GROUP BY blue_line_key),
       pc AS (
         SELECT a.acc AS acc_a, b.acc AS acc_b, a.hb AS hb_a, b.hb AS hb_b,
                a.mc AS mc_a, b.mc AS mc_b,
                a.accessible AS ac_a, b.accessible AS ac_b,
                a.spawning AS sp_a, b.spawning AS sp_b,
                a.rearing AS re_a, b.rearing AS re_b,
                a.lake_rearing AS lr_a, b.lake_rearing AS lr_b,
                a.wetland_rearing AS wr_a, b.wetland_rearing AS wr_b,
                EXISTS (SELECT 1 FROM tops t
                         WHERE t.blk = b.blk AND abs(t.m - b.dm) <= 1) AS b_at_top,
                EXISTS (SELECT 1 FROM %6$s.barriers x
                         WHERE x.blue_line_key = b.blk
                           AND upper('%4$s') = ANY (x.blocks_species)
                           AND (abs(x.downstream_route_measure - b.dm) <= 3
                                OR abs(x.downstream_route_measure - a.dm) <= 3))
                  AS near_barrier,
                least(a.um, b.um) - greatest(a.dm, b.dm) AS len,
                least(a.um, b.um) - greatest(a.dm, b.dm) < 1.01 AS sliver
           FROM a JOIN b
             ON a.blk = b.blk AND a.dm < b.um AND b.dm < a.um
          WHERE least(a.um, b.um) - greatest(a.dm, b.dm) >= 0.01)
       SELECT '%5$s' AS wsg, '%4$s' AS sp,
              (SELECT sum(um - dm) FROM a) / 1000 AS km_pre,
              (SELECT sum(um - dm) FROM b) / 1000 AS km_post,
              sum(len) / 1000 AS km_pieces,
              (SELECT count(*) FROM a) AS seg_pre,
              (SELECT count(*) FROM b) AS seg_post,
              bool_or(acc_a <> -9) AS present,
              coalesce(sum(len) FILTER (WHERE acc_a = 0 AND acc_b IN (1, 2) AND NOT sliver AND near_barrier), 0) / 1000 AS km_acc_0_to_open_near_barrier,
              coalesce(sum(len) FILTER (WHERE acc_a IN (1, 2) AND acc_b = 0 AND NOT sliver AND near_barrier), 0) / 1000 AS km_acc_open_to_0_near_barrier,
              coalesce(sum(len) FILTER (WHERE acc_a = 0 AND acc_b IN (1, 2) AND NOT sliver AND NOT near_barrier), 0) / 1000 AS km_acc_0_to_open_elsewhere,
              coalesce(sum(len) FILTER (WHERE acc_a IN (1, 2) AND acc_b = 0 AND NOT sliver AND NOT near_barrier), 0) / 1000 AS km_acc_open_to_0_elsewhere,
              coalesce(sum(len) FILTER (WHERE acc_a = 2 AND acc_b = 1), 0) / 1000 AS km_acc_2_to_1,
              coalesce(sum(len) FILTER (WHERE acc_a = 1 AND acc_b = 2 AND b_at_top), 0) / 1000 AS km_acc_1_to_2_at_top,
              coalesce(sum(len) FILTER (WHERE acc_a = 1 AND acc_b = 2 AND NOT b_at_top), 0) / 1000 AS km_acc_1_to_2_elsewhere,
              coalesce(sum(len) FILTER (WHERE acc_a IS DISTINCT FROM acc_b
                AND NOT (acc_a = 1 AND acc_b = 2) AND NOT sliver), 0) / 1000 AS km_acc_other_change,
              count(*) FILTER (WHERE sliver AND (acc_a IS DISTINCT FROM acc_b
                OR hb_a IS DISTINCT FROM hb_b)) AS n_sliver_access_change,
              coalesce(sum(len) FILTER (WHERE sliver AND (acc_a IS DISTINCT FROM acc_b
                OR hb_a IS DISTINCT FROM hb_b)), 0) AS m_sliver_access_change,
              coalesce(sum(len) FILTER (WHERE hb_a IS DISTINCT FROM hb_b AND NOT sliver AND near_barrier), 0) / 1000 AS km_has_barriers_change_near_barrier,
              coalesce(sum(len) FILTER (WHERE hb_a IS DISTINCT FROM hb_b AND NOT sliver AND NOT near_barrier), 0) / 1000 AS km_has_barriers_change_elsewhere,
              coalesce(sum(len) FILTER (WHERE mc_a IS DISTINCT FROM mc_b), 0) / 1000 AS km_mapping_code_change,
              coalesce(sum(len) FILTER (WHERE ac_a <> ac_b), 0) / 1000 AS km_accessible_flag_change,
              coalesce(sum(len) FILTER (WHERE sp_a AND NOT sp_b), 0) / 1000 AS km_spawning_lost,
              coalesce(sum(len) FILTER (WHERE sp_b AND NOT sp_a), 0) / 1000 AS km_spawning_gained,
              coalesce(sum(len) FILTER (WHERE re_a AND NOT re_b), 0) / 1000 AS km_rearing_lost,
              coalesce(sum(len) FILTER (WHERE re_b AND NOT re_a), 0) / 1000 AS km_rearing_gained,
              coalesce(sum(len) FILTER (WHERE lr_a <> lr_b), 0) / 1000 AS km_lake_rearing_change,
              coalesce(sum(len) FILTER (WHERE wr_a <> wr_b), 0) / 1000 AS km_wetland_rearing_change,
              coalesce(sum(len) FILTER (WHERE sp_a), 0) / 1000 AS km_spawning_pre,
              coalesce(sum(len) FILTER (WHERE re_a), 0) / 1000 AS km_rearing_pre
         FROM pc",
      side(pre, wsg, sp), side(post, wsg, sp), obs_tbl, sp, wsg, post))
    rows[[length(rows) + 1L]] <- r
  }
}
d <- do.call(rbind, rows)
d <- d[d$present %in% TRUE, ]
# The overlap must cover both sides to within 1 m per 1,000 segments.
tol <- pmax(d$seg_post, d$seg_pre) / 1e6
bad <- abs(d$km_pieces - d$km_pre) > tol | abs(d$km_pieces - d$km_post) > tol
if (any(bad)) {
  print(d[bad, c("wsg", "sp", "km_pre", "km_post", "km_pieces")])
  stop("overlap pieces do not cover both sides", call. = FALSE)
}
num <- vapply(d, is.numeric, logical(1))
d[num] <- lapply(d[num], function(x) round(x, 3))
utils::write.csv(d, file.path(out, "pre_post_diff.csv"), row.names = FALSE)
print(d[, c("wsg", "sp", "seg_pre", "seg_post",
            "km_acc_0_to_open_near_barrier", "km_acc_open_to_0_near_barrier",
            "km_acc_0_to_open_elsewhere", "km_acc_open_to_0_elsewhere",
            "km_acc_2_to_1", "km_acc_1_to_2_at_top",
            "km_acc_1_to_2_elsewhere", "km_acc_other_change",
            "km_has_barriers_change_elsewhere", "n_sliver_access_change")])
DBI::dbDisconnect(conn)

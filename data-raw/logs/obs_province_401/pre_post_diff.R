# Does counting every group's fish records for code 2 (#401) move the outputs
# only where expected? BEFORE (zz401_<config>_pre) against AFTER
# (zz401_<config>_post), per config, group and species, on measure-overlap
# pieces per blue_line_key, never on id_segment.
#
#   Rscript data-raw/logs/obs_province_401/pre_post_diff.R
#
# Pieces under 1 cm are dropped: a segment's upstream measure can overshoot the
# next one's start by up to 3.93 mm within one side (FWA).
#
# Code 2 is recomputed here for every AFTER segment, independently of fresh,
# with the join bcfishpass writes (`SELECT DISTINCT segment, species_code`
# over FWA_Upstream(..., false, 1)), from the record sets build_obs.R rebuilds:
#   up    a record of the species, any group (zz401_obs.province_<config>)
#   own   a record of the species, the segment's group (zz401_obs.<config>_<wsg>)
#   gate  a record of any species, the segment's group (the same table)
# The rule each build should follow, on an accessible segment (code 1 or 2):
#   BEFORE  2 iff own
#   AFTER   default (province):       2 iff up
#           bcfishpass (group_gated): 2 iff up and gate
# Checks (`n_violation` must be 0 on every row):
#   - every piece's start is the same in both builds, and each group and species
#     has the same segment count;
#   - BEFORE and AFTER each equal their rule on every accessible piece
#     (n_rule_pre, n_rule_post): completeness as well as soundness;
#   - the only change is access 1 -> 2 (n_acc_unexpected), and each such piece
#     has a record from another group upstream and none of its own species'
#     (n_1_to_2_unexplained);
#   - no has_barriers, mapping code or habitat flag moves.
# Writes pre_post_diff.csv and stops on any violation.
pkgload::load_all(quiet = TRUE)
# nolint start: indentation_linter, brace_linter, line_length_linter
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
out <- "data-raw/logs/obs_province_401"
groups <- list(default = c("LKEL", "BULK", "UPCE", "PARS", "ELKR", "LNTH"),
               bcfishpass = c("BULK", "PARS", "UPCE"))
q <- function(sql) DBI::dbGetQuery(conn, sql)
ex <- function(sql) invisible(DBI::dbExecute(conn, sql))
has_tbl <- function(schema, tbl) nrow(q(sprintf(
  "SELECT 1 FROM information_schema.tables
    WHERE table_schema = '%s' AND table_name = '%s'", schema, tbl))) > 0L

side <- function(schema, wsg, sp) {
  hab <- has_tbl(schema, paste0("streams_habitat_", sp))
  hcol <- function(col) if (hab) sprintf("coalesce(h.%s, false)", col) else "false"
  sprintf(
    "SELECT s.id_segment AS id, s.blue_line_key AS blk,
            s.downstream_route_measure AS dm, s.upstream_route_measure AS um,
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

# Per AFTER segment, which species are recorded upstream, from which tables.
walk_sql <- function(post, wsg, rec) sprintf(
  "SELECT DISTINCT a.id_segment AS id, upper(b.species_code) AS sp
     FROM %1$s.streams a
     JOIN %3$s b
       ON whse_basemapping.fwa_upstream(
            a.blue_line_key, a.downstream_route_measure,
            a.wscode_ltree, a.localcode_ltree,
            b.blue_line_key, b.downstream_route_measure,
            b.wscode, b.localcode, false, 1)
    WHERE a.watershed_group_code = '%2$s'", post, wsg, rec)

rows <- list()
for (config in names(groups)) {
  pre <- paste0("zz401_", config, "_pre")
  post <- paste0("zz401_", config, "_post")
  gated <- identical(config, "bcfishpass")
  acc_cols <- q(sprintf(
    "SELECT column_name FROM information_schema.columns
      WHERE table_schema = '%s' AND table_name = 'streams_access'
        AND column_name LIKE 'access\\_%%' ORDER BY column_name", post))$column_name
  species <- sub("^access_", "", acc_cols)
  for (wsg in groups[[config]]) {
    own_tbl <- sprintf("zz401_obs.%s_%s", config, tolower(wsg))
    ex("DROP TABLE IF EXISTS pg_temp.up401, pg_temp.own401")
    ex(paste("CREATE TEMP TABLE up401 AS",
             walk_sql(post, wsg, paste0("zz401_obs.province_", config))))
    ex(paste("CREATE TEMP TABLE own401 AS", walk_sql(post, wsg, own_tbl)))
    ex("CREATE INDEX ON pg_temp.up401 (id, sp)")
    ex("CREATE INDEX ON pg_temp.own401 (id, sp)")
    ex("ANALYZE pg_temp.up401")
    ex("ANALYZE pg_temp.own401")
    for (sp in species) {
      r <- q(sprintf(
        "WITH a AS (%1$s), b AS (%2$s),
         pc AS (
           SELECT a.acc AS acc_a, b.acc AS acc_b, a.hb AS hb_a, b.hb AS hb_b,
                  a.mc AS mc_a, b.mc AS mc_b,
                  a.accessible AS ac_a, b.accessible AS ac_b,
                  a.spawning AS sp_a, b.spawning AS sp_b,
                  a.rearing AS re_a, b.rearing AS re_b,
                  a.lake_rearing AS lr_a, b.lake_rearing AS lr_b,
                  a.wetland_rearing AS wr_a, b.wetland_rearing AS wr_b,
                  EXISTS (SELECT 1 FROM pg_temp.up401 u
                           WHERE u.id = b.id AND u.sp = upper('%3$s')) AS up,
                  EXISTS (SELECT 1 FROM pg_temp.own401 u
                           WHERE u.id = b.id AND u.sp = upper('%3$s')) AS own,
                  EXISTS (SELECT 1 FROM pg_temp.own401 u
                           WHERE u.id = b.id) AS gate,
                  abs(b.dm - a.dm) >= 0.01 AS moved,
                  least(a.um, b.um) - greatest(a.dm, b.dm) AS len
             FROM a JOIN b
               ON a.blk = b.blk AND a.dm < b.um AND b.dm < a.um
            WHERE least(a.um, b.um) - greatest(a.dm, b.dm) >= 0.01),
         flag AS (
           SELECT *,
                  CASE WHEN own THEN 2 ELSE 1 END AS want_a,
                  CASE WHEN up AND (%6$s OR gate) THEN 2 ELSE 1 END AS want_b
             FROM pc)
         SELECT '%5$s' AS config, '%4$s' AS wsg, '%3$s' AS sp,
                (SELECT sum(um - dm) FROM a) / 1000 AS km_pre,
                (SELECT sum(um - dm) FROM b) / 1000 AS km_post,
                sum(len) / 1000 AS km_pieces,
                (SELECT count(*) FROM a) AS seg_pre,
                (SELECT count(*) FROM b) AS seg_post,
                bool_or(acc_a <> -9) AS present,
                coalesce(sum(len) FILTER (WHERE acc_a IN (1, 2)), 0) / 1000 AS km_accessible,
                coalesce(sum(len) FILTER (WHERE acc_a = 2), 0) / 1000 AS km_observed_pre,
                coalesce(sum(len) FILTER (WHERE acc_b = 2), 0) / 1000 AS km_observed_post,
                coalesce(sum(len) FILTER (WHERE acc_a = 1 AND acc_b = 2), 0) / 1000 AS km_acc_1_to_2,
                count(*) FILTER (WHERE acc_a = 1 AND acc_b = 2) AS n_pieces_1_to_2,
                count(*) FILTER (WHERE acc_a IN (1, 2) AND acc_a <> want_a) AS n_rule_pre,
                count(*) FILTER (WHERE acc_b IN (1, 2) AND acc_b <> want_b) AS n_rule_post,
                count(*) FILTER (WHERE moved) AS n_moved_start,
                count(*) FILTER (WHERE acc_a IS DISTINCT FROM acc_b
                                   AND NOT (acc_a = 1 AND acc_b = 2)) AS n_acc_unexpected,
                count(*) FILTER (WHERE acc_a = 1 AND acc_b = 2
                                   AND (own OR NOT up)) AS n_1_to_2_unexplained,
                count(*) FILTER (WHERE hb_a IS DISTINCT FROM hb_b) AS n_has_barriers_change,
                count(*) FILTER (WHERE mc_a IS DISTINCT FROM mc_b) AS n_mapping_code_change,
                count(*) FILTER (WHERE ac_a <> ac_b OR sp_a <> sp_b OR re_a <> re_b
                                    OR lr_a <> lr_b OR wr_a <> wr_b) AS n_habitat_change
           FROM flag",
        side(pre, wsg, sp), side(post, wsg, sp), sp, wsg, config,
        if (gated) "false" else "true"))
      rows[[length(rows) + 1L]] <- r
    }
    message(config, " ", wsg, " done")
  }
}
d <- do.call(rbind, rows)
d <- d[d$present %in% TRUE, ]
# The overlap must cover both sides to within 1 m per 1,000 segments.
tol <- pmax(d$seg_post, d$seg_pre) / 1e6
bad <- abs(d$km_pieces - d$km_pre) > tol | abs(d$km_pieces - d$km_post) > tol
if (any(bad)) {
  print(d[bad, c("config", "wsg", "sp", "km_pre", "km_post", "km_pieces")])
  stop("overlap pieces do not cover both sides", call. = FALSE)
}
num <- vapply(d, is.numeric, logical(1))
d[num] <- lapply(d[num], function(x) round(x, 3))
d$n_violation <- d$n_moved_start + (d$seg_pre != d$seg_post) +
  d$n_rule_pre + d$n_rule_post + d$n_acc_unexpected + d$n_1_to_2_unexplained +
  d$n_has_barriers_change + d$n_mapping_code_change + d$n_habitat_change
utils::write.csv(d, file.path(out, "pre_post_diff.csv"), row.names = FALSE)
print(d[, c("config", "wsg", "sp", "km_accessible", "km_observed_pre",
            "km_observed_post", "km_acc_1_to_2", "n_pieces_1_to_2",
            "n_violation")])
DBI::dbDisconnect(conn)
if (any(d$n_violation > 0)) {
  stop("DEFECT: an output moved other than as #401 expects; see ",
       "n_violation in pre_post_diff.csv", call. = FALSE)
}
# nolint end

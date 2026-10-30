# Does reading a record at a segment's start as not upstream (#399) move the
# outputs only where expected? BEFORE (zz399_<config>_pre) against AFTER
# (zz399_<config>_post), per config, group and species, on measure-overlap
# pieces per (watershed_group_code, blue_line_key), never on id_segment.
#
#   Rscript data-raw/logs/record_at_start_399/pre_post_diff.R
#
# Pieces under 1 cm are dropped: a segment's upstream measure can overshoot the
# next one's start by up to 3.93 mm within one side (FWA).
#
# Expected. #399 changes only the observation walk's same-line test, from
# `m >= start - 1` to `m >= start + 1`; the walk's other-line tests and every
# barrier walk are unchanged, and no break moves. So:
#   - invariants: every piece's start is the same in both builds (`dir = 0`),
#     and each group and species has the same segment count;
#   - the one change allowed: access_<sp> 2 -> 1 on a piece whose segment has a
#     same-line record of the species in [start - 1, start + 1) (`at_record`,
#     half-open: a record at exactly start + 1 counts in both builds). The
#     record set is the one the walk read, rebuilt by build_obs.R into
#     zz399_obs.<config>_<wsg>. "No record further upstream" is implied by
#     AFTER = 1; a tributary record above keeps 2 in both builds.
# Every other difference is a violation (`n_violation` must be 0): 1 -> 2, to or
# from 0, has_barriers, mapping codes, habitat flags, and a 2 -> 1 piece with no
# record at its start. Writes pre_post_diff.csv and stops on any violation.
pkgload::load_all(quiet = TRUE)
# nolint start: indentation_linter, brace_linter
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
out <- "data-raw/logs/record_at_start_399"
groups <- list(default = c("LKEL", "BULK", "UPCE", "PARS", "ELKR"),
               bcfishpass = c("BULK", "PARS"))
q <- function(sql) DBI::dbGetQuery(conn, sql)
has_tbl <- function(schema, tbl) nrow(q(sprintf(
  "SELECT 1 FROM information_schema.tables
    WHERE table_schema = '%s' AND table_name = '%s'", schema, tbl))) > 0L

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
for (config in names(groups)) {
  pre <- paste0("zz399_", config, "_pre")
  post <- paste0("zz399_", config, "_post")
  acc_cols <- q(sprintf(
    "SELECT column_name FROM information_schema.columns
      WHERE table_schema = '%s' AND table_name = 'streams_access'
        AND column_name LIKE 'access\\_%%' ORDER BY column_name", post))$column_name
  species <- sub("^access_", "", acc_cols)
  for (wsg in groups[[config]]) {
    obs_tbl <- sprintf("zz399_obs.%s_%s", config, tolower(wsg))
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
                  EXISTS (SELECT 1 FROM %3$s o
                           WHERE upper(o.species_code) = upper('%4$s')
                             AND o.blue_line_key = b.blk
                             AND o.downstream_route_measure >= b.dm - 1
                             AND o.downstream_route_measure < b.dm + 1) AS at_record,
                  abs(b.dm - a.dm) >= 0.01 AS moved,
                  least(a.um, b.um) - greatest(a.dm, b.dm) AS len
             FROM a JOIN b
               ON a.blk = b.blk AND a.dm < b.um AND b.dm < a.um
            WHERE least(a.um, b.um) - greatest(a.dm, b.dm) >= 0.01),
         flag AS (
           SELECT *,
                  (acc_a = 2 AND acc_b = 1 AND at_record) AS expected,
                  (acc_a IS DISTINCT FROM acc_b) AS acc_change
             FROM pc)
         SELECT '%6$s' AS config, '%5$s' AS wsg, '%4$s' AS sp,
                (SELECT sum(um - dm) FROM a) / 1000 AS km_pre,
                (SELECT sum(um - dm) FROM b) / 1000 AS km_post,
                sum(len) / 1000 AS km_pieces,
                (SELECT count(*) FROM a) AS seg_pre,
                (SELECT count(*) FROM b) AS seg_post,
                bool_or(acc_a <> -9) AS present,
                coalesce(sum(len) FILTER (WHERE acc_a IN (1, 2)), 0) / 1000 AS km_accessible,
                coalesce(sum(len) FILTER (WHERE acc_a = 2), 0) / 1000 AS km_observed_pre,
                coalesce(sum(len) FILTER (WHERE acc_b = 2), 0) / 1000 AS km_observed_post,
                coalesce(sum(len) FILTER (WHERE expected), 0) / 1000 AS km_acc_2_to_1,
                count(*) FILTER (WHERE expected) AS n_pieces_2_to_1,
                count(*) FILTER (WHERE moved) AS n_moved_start,
                count(*) FILTER (WHERE acc_change AND NOT expected) AS n_acc_unexpected,
                count(*) FILTER (WHERE acc_a = 2 AND acc_b = 1 AND NOT at_record) AS n_2_to_1_no_record,
                count(*) FILTER (WHERE acc_a = 1 AND acc_b = 2) AS n_1_to_2,
                count(*) FILTER (WHERE (acc_a = 0) <> (acc_b = 0)) AS n_open_change,
                count(*) FILTER (WHERE hb_a IS DISTINCT FROM hb_b) AS n_has_barriers_change,
                count(*) FILTER (WHERE mc_a IS DISTINCT FROM mc_b) AS n_mapping_code_change,
                count(*) FILTER (WHERE ac_a <> ac_b OR sp_a <> sp_b OR re_a <> re_b
                                    OR lr_a <> lr_b OR wr_a <> wr_b) AS n_habitat_change
           FROM flag",
        side(pre, wsg, sp), side(post, wsg, sp), obs_tbl, sp, wsg, config))
      rows[[length(rows) + 1L]] <- r
    }
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
  d$n_acc_unexpected + d$n_has_barriers_change + d$n_mapping_code_change +
  d$n_habitat_change
utils::write.csv(d, file.path(out, "pre_post_diff.csv"), row.names = FALSE)
print(d[, c("config", "wsg", "sp", "seg_pre", "seg_post", "km_accessible",
            "km_observed_pre", "km_observed_post", "km_acc_2_to_1",
            "n_pieces_2_to_1", "n_violation")])
DBI::dbDisconnect(conn)
if (any(d$n_violation > 0)) {
  stop("DEFECT: an output moved other than 2 -> 1 at a record; see ",
       "n_violation in pre_post_diff.csv", call. = FALSE)
}
# nolint end

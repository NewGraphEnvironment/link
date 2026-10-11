#!/usr/bin/env Rscript
# rearing_diff_segments.R — where link's `rearing` flag and bcfishpass's disagree,
# segment by segment, for one WSG and species (#324).
#
# link side:  <schema>.streams x streams_habitat_<sp> (full PK join), x streams_access.
# bcfp side:  fresh.streams_vw_bcfp, rearing_<sp> IN (1,2) (research/bcfp_view_column_coding.md).
#
# The two sides are segmented differently (PCEA: 106,079 link segments against
# 37,957 bcfp, same network km), so an exact (blue_line_key, downstream_route_measure)
# join is wrong. Pieces are the measure-interval overlaps per blue_line_key: each
# piece carries both sides' segment attributes and its overlap length.
#
# Asserts before writing anything:
#   - the overlap total equals each side's network km in the WSG (to 1 m)
#   - link-only minus bcfp-only equals the two sides' rearing-flag totals' difference
#
# Writes to data-raw/logs/rearing_diff_324/ (override with LNK_OUT):
#   <wsg>_<sp>_summary.csv  agreement classes (km), with and without lake connection lines
#   <wsg>_<sp>_pieces.csv   every disagreeing piece, both sides' attributes
#   <wsg>_<sp>_stamp.txt    environment stamp
#
# Usage: [LNK_LOAD=loadall] Rscript data-raw/rearing_diff_segments.R [WSG] [species] [schema]
#        defaults: PCEA bt fresh

if (identical(Sys.getenv("LNK_LOAD"), "loadall")) {
  suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
} else {
  suppressPackageStartupMessages(library(link))
}
suppressPackageStartupMessages(library(DBI))

args   <- commandArgs(trailingOnly = TRUE)
wsg    <- toupper(if (length(args) >= 1) args[1] else "PCEA")
sp     <- tolower(if (length(args) >= 2) args[2] else "bt")
schema <- if (length(args) >= 3) args[3] else "fresh"
out    <- Sys.getenv("LNK_OUT", "data-raw/logs/rearing_diff_324")
stopifnot(grepl("^[A-Z]{4}$", wsg), grepl("^[a-z]{2,3}$", sp),
          grepl("^[a-z_][a-z0-9_]*$", schema))
dir.create(out, showWarnings = FALSE, recursive = TRUE)

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")

lake_conn <- link:::.lnk_sql_lake_connection()
wb_join   <- link:::.lnk_sql_waterbody_join()
wb_class  <- link:::.lnk_sql_waterbody_class()
wsg_lit   <- DBI::dbQuoteLiteral(conn, wsg)

q <- function(sql) DBI::dbGetQuery(conn, sql)
x <- function(sql) invisible(DBI::dbExecute(conn, sql))

# ---- each side, one row per segment ------------------------------------------
x(sprintf("
  CREATE TEMP TABLE rd_link AS
  SELECT s.id_segment, s.blue_line_key AS blk,
         s.downstream_route_measure AS dm, s.upstream_route_measure AS um,
         s.length_metre AS len, s.edge_type, s.waterbody_key, %1$s AS wb,
         %2$s AS lake_conn, s.gradient, s.channel_width, s.channel_width_source,
         s.stream_order, s.stream_order_parent, h.spawning, h.rearing, a.access_%3$s AS access
  FROM %4$s.streams s
  JOIN %4$s.streams_habitat_%3$s h
    ON h.id_segment = s.id_segment AND h.watershed_group_code = s.watershed_group_code
  LEFT JOIN %4$s.streams_access a
    ON a.id_segment = s.id_segment AND a.watershed_group_code = s.watershed_group_code
  %5$s
  WHERE s.watershed_group_code = %6$s",
  wb_class, lake_conn, sp, schema, wb_join, wsg_lit))

x(sprintf("
  CREATE TEMP TABLE rd_bcfp AS
  SELECT s.segmented_stream_id, s.blue_line_key AS blk,
         s.downstream_route_measure AS dm, s.upstream_route_measure AS um,
         s.length_metre AS len, s.edge_type, s.waterbody_key, %1$s AS wb,
         %2$s AS lake_conn, s.gradient, s.channel_width, s.stream_order, s.stream_order_parent,
         s.spawning_%3$s IN (1,2) AS spawning, s.rearing_%3$s IN (1,2) AS rearing,
         s.rearing_%3$s AS rearing_code, s.access_%3$s AS access
  FROM fresh.streams_vw_bcfp s
  %4$s
  WHERE s.watershed_group_code = %5$s",
  wb_class, lake_conn, sp, wb_join, wsg_lit))
x("CREATE INDEX ON rd_link (blk, dm)")
x("CREATE INDEX ON rd_bcfp (blk, dm)")
x("ANALYZE rd_link")
x("ANALYZE rd_bcfp")

# ---- overlap pieces ------------------------------------------------------------
x("
  CREATE TEMP TABLE rd_piece AS
  SELECT l.blk,
         greatest(l.dm, b.dm) AS dm, least(l.um, b.um) AS um,
         least(l.um, b.um) - greatest(l.dm, b.dm) AS len,
         CASE WHEN l.rearing AND b.rearing THEN 'both'
              WHEN l.rearing THEN 'link_only'
              WHEN b.rearing THEN 'bcfp_only'
              ELSE 'neither' END AS class,
         l.id_segment, l.len AS l_len, l.edge_type AS l_edge, l.wb AS l_wb,
         l.lake_conn AS l_lake_conn, l.gradient AS l_gradient,
         l.channel_width AS l_cw, l.channel_width_source AS l_cw_source,
         l.stream_order AS l_order, l.stream_order_parent AS l_order_parent,
         l.spawning AS l_spawn, l.access AS l_access,
         b.segmented_stream_id, b.dm AS b_dm, b.um AS b_um, b.len AS b_len,
         b.edge_type AS b_edge, b.wb AS b_wb,
         b.lake_conn AS b_lake_conn, b.gradient AS b_gradient,
         b.channel_width AS b_cw, b.stream_order AS b_order, b.stream_order_parent AS b_order_parent,
         b.spawning AS b_spawn, b.rearing_code AS b_rearing_code, b.access AS b_access
  FROM rd_link l
  JOIN rd_bcfp b
    ON b.blk = l.blk AND l.dm < b.um AND b.dm < l.um")

# ---- reconciliation ------------------------------------------------------------
tot <- q("
  SELECT (SELECT sum(len) FROM rd_link) AS link_m,
         (SELECT sum(len) FROM rd_bcfp) AS bcfp_m,
         (SELECT sum(len) FROM rd_piece) AS piece_m,
         (SELECT coalesce(sum(len) FILTER (WHERE rearing), 0) FROM rd_link) AS link_rear_m,
         (SELECT coalesce(sum(len) FILTER (WHERE rearing), 0) FROM rd_bcfp) AS bcfp_rear_m,
         (SELECT coalesce(sum(len) FILTER (WHERE class = 'link_only'), 0) FROM rd_piece) AS link_only_m,
         (SELECT coalesce(sum(len) FILTER (WHERE class = 'bcfp_only'), 0) FROM rd_piece) AS bcfp_only_m")
# length_metre and the measure span agree to well under a metre per segment; a
# WSG-wide tolerance of 1 m per 1,000 segments allows that rounding and nothing else
tol_m <- max(1, nrow(q("SELECT 1 FROM rd_link")) / 1000)
gap_cov  <- abs(tot$piece_m - tot$link_m) + abs(tot$piece_m - tot$bcfp_m)
gap_rear <- abs((tot$link_only_m - tot$bcfp_only_m) - (tot$link_rear_m - tot$bcfp_rear_m))
cat(sprintf("%s %s: network km link %.1f | bcfp %.1f | pieces %.1f (coverage gap %.1f m, tol %.0f m)\n",
            wsg, toupper(sp), tot$link_m / 1e3, tot$bcfp_m / 1e3, tot$piece_m / 1e3, gap_cov, tol_m))
cat(sprintf("  rearing flag km link %.1f | bcfp %.1f | link-only %.1f | bcfp-only %.1f (gap %.1f m)\n",
            tot$link_rear_m / 1e3, tot$bcfp_rear_m / 1e3,
            tot$link_only_m / 1e3, tot$bcfp_only_m / 1e3, gap_rear))
if (gap_cov > tol_m) stop("pieces do not cover both networks: ", round(gap_cov, 1), " m")
if (gap_rear > tol_m) stop("piece classes do not reconcile the rearing totals: ", round(gap_rear, 1), " m")

# ---- outputs -------------------------------------------------------------------
summ <- q("
  SELECT class,
         round((sum(len) / 1000)::numeric, 2) AS km,
         round((coalesce(sum(len) FILTER (WHERE NOT l_lake_conn AND NOT b_lake_conn), 0)
                / 1000)::numeric, 2) AS km_excl_lake_conn,
         count(DISTINCT blk) AS n_blk, count(*) AS n_piece
  FROM rd_piece GROUP BY class ORDER BY class")
pieces <- q("SELECT * FROM rd_piece WHERE class IN ('link_only', 'bcfp_only')
             ORDER BY class, blk, dm")
pieces[] <- lapply(pieces, function(v) if (is.double(v)) round(v, 4) else v)

stem <- file.path(out, sprintf("%s_%s", tolower(wsg), sp))
utils::write.csv(summ, paste0(stem, "_summary.csv"), row.names = FALSE, na = "")
utils::write.csv(pieces, paste0(stem, "_pieces.csv"), row.names = FALSE, na = "")

git_sha <- tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE),
                    error = function(e) NA_character_)
logrow <- q(sprintf("SELECT run_id, date_end, link_version, link_sha, fresh_version, config_name
                     FROM %s.log WHERE watershed_group_code = %s
                     ORDER BY date_end DESC LIMIT 1", schema, wsg_lit))
view_n <- q("SELECT count(*) AS n FROM fresh.streams_vw_bcfp")$n
writeLines(c(
  sprintf("run: %s (UTC)", format(Sys.time(), "%Y-%m-%dT%H:%MZ", tz = "UTC")),
  sprintf("script: data-raw/rearing_diff_segments.R %s %s %s @ link %s (%s)",
          wsg, sp, schema, utils::packageVersion("link"), git_sha),
  sprintf("db: local docker fwapg localhost:5432; fresh.streams_vw_bcfp rows %s", view_n),
  sprintf("%s.log latest %s row: %s", schema, wsg,
          if (nrow(logrow)) paste(paste(names(logrow), unlist(lapply(logrow, as.character)), sep = "="),
                                  collapse = " ") else "none"),
  sprintf("network km link %.2f bcfp %.2f; rearing flag km link %.2f bcfp %.2f",
          tot$link_m / 1e3, tot$bcfp_m / 1e3, tot$link_rear_m / 1e3, tot$bcfp_rear_m / 1e3)),
  paste0(stem, "_stamp.txt"))
print(summ)
DBI::dbDisconnect(conn)

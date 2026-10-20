# moves.R — what moved between the 2026-10-17 parity build (fresh_parity246, pre-#349)
# and the v0.66.6 build (fresh_parity362), for link#362.
#
#   1. pair_moves.csv   every scored pair, joined to the 2026-10-17 annotated sweep
#   2. segment_diff.csv per (WSG, species): segments on one segmentation whose access,
#                       spawning or rearing differ, in km, classed by what changed
#                       (rearing here is the raw flag, lake connection lines included)
#   3. override_diff.csv barrier-override positions added or lost, across all holders
#   4. mapping_code_moves.csv the driver's 17-group mapping_code compare, before / after
#
# LNK_COMPARE_NEW names the new run's compare CSV under data-raw/logs/study_area_run/.
# Segments are matched on (watershed_group_code, blue_line_key, downstream_route_measure),
# unique within a persist schema. Segments in one build only (a moved break, #277) are
# written to resegmented.csv and left out of the segment diff.
# Run from the repo root:
#   LNK_COMPARE_NEW=<TS>_compare.csv Rscript data-raw/logs/parity_0.66.6/moves.R
suppressPackageStartupMessages({
  library(DBI)
})
dir_out <- "data-raw/logs/parity_0.66.6"
old <- read.csv("data-raw/logs/provincial_246/parity_annotated.csv")
new <- read.csv(file.path(dir_out, "parity_annotated.csv"))
key <- c("wsg", "species", "habitat_type")
m <- merge(old[, c(key, "link_value", "ref_value", "diff_pct", "class")],
           new[, c(key, "link_value", "ref_value", "diff_pct", "class")],
           by = key, suffixes = c("_20261017", "_0.66.6"), all = TRUE)
stopifnot(nrow(m) == nrow(old), nrow(m) == nrow(new))
stopifnot(all(m$ref_value_20261017 == m$ref_value_0.66.6))  # same reference
m$link_km_change <- round(m$link_value_0.66.6 - m$link_value_20261017, 1)
m$diff_pct_change <- round(m$diff_pct_0.66.6 - m$diff_pct_20261017, 2)
m <- m[order(m$wsg, m$species, m$habitat_type), ]
write.csv(m, file.path(dir_out, "pair_moves.csv"), row.names = FALSE, na = "")

conn <- dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                  port = 5432L, user = "postgres", password = "postgres")
wsgs <- unique(new$wsg)
seg_n <- function(s) dbGetQuery(conn, sprintf(
  "SELECT watershed_group_code AS wsg, count(*) AS n, round(sum(length_metre)) AS m
     FROM %s.streams WHERE watershed_group_code IN (%s) GROUP BY 1 ORDER BY 1",
  s, paste0("'", wsgs, "'", collapse = ",")))
n_old <- seg_n("fresh_parity246")
n_new <- seg_n("fresh_parity362")
print(merge(n_old, n_new, by = "wsg", suffixes = c("_246", "_362")))
# Segments present in one build only (a break that moved). The segment diff below
# joins on the segments both builds share, so these are reported here, not there.
reseg <- dbGetQuery(conn, sprintf("
  WITH o AS (SELECT watershed_group_code AS wsg, blue_line_key, downstream_route_measure, length_metre
               FROM fresh_parity246.streams WHERE watershed_group_code IN (%1$s)),
       n AS (SELECT watershed_group_code AS wsg, blue_line_key, downstream_route_measure, length_metre
               FROM fresh_parity362.streams WHERE watershed_group_code IN (%1$s))
  SELECT 'only_246' AS side, o.* FROM o
   WHERE NOT EXISTS (SELECT 1 FROM n WHERE n.wsg = o.wsg AND n.blue_line_key = o.blue_line_key
                     AND n.downstream_route_measure = o.downstream_route_measure)
  UNION ALL
  SELECT 'only_362', n.* FROM n
   WHERE NOT EXISTS (SELECT 1 FROM o WHERE o.wsg = n.wsg AND o.blue_line_key = n.blue_line_key
                     AND o.downstream_route_measure = n.downstream_route_measure)
  ORDER BY 2, 3, 4, 1", paste0("'", wsgs, "'", collapse = ",")))
write.csv(reseg, file.path(dir_out, "resegmented.csv"), row.names = FALSE)
cat(sprintf("segments in one build only: %d (%s)\n", nrow(reseg),
            paste(unique(reseg$wsg), collapse = ", ")))

sp_pairs <- unique(new[, c("wsg", "species")])
diffs <- do.call(rbind, lapply(seq_len(nrow(sp_pairs)), function(i) {
  w <- sp_pairs$wsg[i]
  sp <- tolower(sp_pairs$species[i])
  q <- sprintf("
    WITH o AS (
      SELECT s.blue_line_key, s.downstream_route_measure, s.length_metre,
             a.access_%1$s AS acc, h.spawning, h.rearing
        FROM fresh_parity246.streams s
        JOIN fresh_parity246.streams_access a USING (id_segment, watershed_group_code)
        LEFT JOIN fresh_parity246.streams_habitat_%1$s h USING (id_segment, watershed_group_code)
       WHERE s.watershed_group_code = '%2$s'),
    n AS (
      SELECT s.blue_line_key, s.downstream_route_measure,
             a.access_%1$s AS acc, h.spawning, h.rearing
        FROM fresh_parity362.streams s
        JOIN fresh_parity362.streams_access a USING (id_segment, watershed_group_code)
        LEFT JOIN fresh_parity362.streams_habitat_%1$s h USING (id_segment, watershed_group_code)
       WHERE s.watershed_group_code = '%2$s')
    SELECT
      CASE WHEN o.acc IS DISTINCT FROM n.acc THEN 'access_changed'
           WHEN n.acc = 0 THEN 'gate_settle'
           ELSE 'other' END AS cause,
      round(sum(o.length_metre) FILTER (WHERE (o.acc IN (1,2)) IS DISTINCT FROM (n.acc IN (1,2)))::numeric / 1000, 3) AS accessible_km,
      round(sum(o.length_metre) FILTER (WHERE coalesce(o.spawning, false) AND NOT coalesce(n.spawning, false))::numeric / 1000, 3) AS spawning_lost_km,
      round(sum(o.length_metre) FILTER (WHERE coalesce(n.spawning, false) AND NOT coalesce(o.spawning, false))::numeric / 1000, 3) AS spawning_gained_km,
      round(sum(o.length_metre) FILTER (WHERE coalesce(o.rearing, false) AND NOT coalesce(n.rearing, false))::numeric / 1000, 3) AS rearing_lost_km,
      round(sum(o.length_metre) FILTER (WHERE coalesce(n.rearing, false) AND NOT coalesce(o.rearing, false))::numeric / 1000, 3) AS rearing_gained_km,
      count(*) AS n_segments
      FROM o JOIN n USING (blue_line_key, downstream_route_measure)
     WHERE o.acc IS DISTINCT FROM n.acc
        OR coalesce(o.spawning, false) <> coalesce(n.spawning, false)
        OR coalesce(o.rearing, false) <> coalesce(n.rearing, false)
     GROUP BY 1 ORDER BY 1", sp, w)
  d <- dbGetQuery(conn, q)
  if (nrow(d) == 0) return(NULL)
  cbind(wsg = w, species = toupper(sp), d)
}))
# Lifts, measured directly: override positions across every holding group, both
# directions. Per position, not per group, so a group writing a row another holder
# already had is not counted as a new lift.
ov <- function(s) dbGetQuery(conn, sprintf(
  "SELECT species_code, blue_line_key, round(downstream_route_measure::numeric) AS drm,
          string_agg(DISTINCT watershed_group_code, ';' ORDER BY watershed_group_code) AS holders
     FROM %s.barrier_overrides GROUP BY 1, 2, 3", s))
ov_old <- ov("fresh_parity246")
ov_new <- ov("fresh_parity362")
pos <- c("species_code", "blue_line_key", "drm")
ov_m <- merge(ov_old, ov_new, by = pos, all = TRUE, suffixes = c("_246", "_362"))
ov_m$change <- ifelse(is.na(ov_m$holders_246), "added",
                      ifelse(is.na(ov_m$holders_362), "lost", "same"))
ov_changed <- ov_m[ov_m$change != "same", ]
write.csv(ov_changed, file.path(dir_out, "override_diff.csv"), row.names = FALSE, na = "")
cat(sprintf("override positions: %d before, %d after; %d added, %d lost\n",
            nrow(ov_old), nrow(ov_new), sum(ov_m$change == "added"), sum(ov_m$change == "lost")))
dbDisconnect(conn)

# mapping_code agreement with bcfishpass over all 17 groups (the driver's compare).
# Confounded by 91a968ab (has_barriers_<sp>_dnstr FALSE, not NA, for a present species
# with no barrier), which changes mapping codes but not km.
cmp_dir <- "data-raw/logs/study_area_run"
c_old <- read.csv(file.path(cmp_dir, "20261017_093603_compare.csv"))
c_new <- read.csv(file.path(cmp_dir, Sys.getenv("LNK_COMPARE_NEW")))
cm <- merge(c_old[, c("wsg", "species", "total_segs", "match_pct", "n_diffs")],
            c_new[, c("wsg", "species", "total_segs", "match_pct", "n_diffs")],
            by = c("wsg", "species"), all = TRUE, suffixes = c("_20261017", "_0.66.6"))
cm$match_pct_change <- round(cm$match_pct_0.66.6 - cm$match_pct_20261017, 2)
write.csv(cm, file.path(dir_out, "mapping_code_moves.csv"), row.names = FALSE, na = "")
print(cm[is.na(cm$match_pct_change) | cm$match_pct_change != 0, ], row.names = FALSE)

if (is.null(diffs)) {
  diffs <- data.frame(wsg = character(), species = character(), cause = character())
}
write.csv(diffs, file.path(dir_out, "segment_diff.csv"), row.names = FALSE, na = "0")
print(m[abs(m$link_km_change) > 0.1, c(key, "link_value_20261017", "link_value_0.66.6",
                                         "link_km_change", "diff_pct_20261017", "diff_pct_0.66.6")],
      row.names = FALSE)
print(diffs, row.names = FALSE)

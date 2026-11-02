# moves.R — what moved between the v0.68.0 parity build (fresh_parity361, 2026-10-23, #361)
# and the link 0.78.0 build (fresh_parity441), for link#440. Adapted from ../parity_0.68.0/moves.R;
# like that one it reports the reference's change per pair rather than assuming none.
#
#   1. pair_moves.csv   every scored pair, joined to the v0.68.0 annotated score
#   2. segment_diff.csv per (WSG, species): segments on one segmentation whose access,
#                       spawning or rearing differ, in km, classed by what changed
#                       (rearing here is the raw flag, lake connection lines included)
#      resegmented_habitat.csv habitat km on the lines holding those segments, per build
#   3. override_diff.csv barrier-override positions added or lost, across all holders
#   4. mapping_code_moves.csv the driver's 17-group mapping_code compare, before / after
#   5. resegmented_closure.csv segments in one build only, per group, over all 17 groups
#
# LNK_COMPARE_NEW names the new run's compare CSV under data-raw/logs/study_area_run/.
# Segments are matched on (watershed_group_code, blue_line_key, downstream_route_measure),
# unique within a persist schema, and must have the same length (within 1 mm). Segments
# in one build only (the two builds break the line in different places, #277) are written
# to resegmented.csv and left out of the segment diff.
# Run from the repo root:
#   LNK_COMPARE_NEW=<TS>_compare.csv Rscript data-raw/logs/parity_0.78.0/moves.R
suppressPackageStartupMessages({
  library(DBI)
})
dir_out <- "data-raw/logs/parity_0.78.0"
compare_new <- Sys.getenv("LNK_COMPARE_NEW")
if (!nzchar(compare_new) ||
    !file.exists(file.path("data-raw/logs/study_area_run", compare_new))) {
  stop("set LNK_COMPARE_NEW to the new run's <TS>_compare.csv under data-raw/logs/study_area_run/")
}
old <- read.csv("data-raw/logs/parity_0.68.0/parity_annotated.csv")
new <- read.csv(file.path(dir_out, "parity_annotated.csv"))
key <- c("wsg", "species", "habitat_type")
m <- merge(old[, c(key, "link_value", "ref_value", "diff_pct", "class")],
           new[, c(key, "link_value", "ref_value", "diff_pct", "class")],
           by = key, suffixes = c("_0.68.0", "_0.78.0"), all = TRUE)
stopifnot(nrow(m) == nrow(old), nrow(m) == nrow(new))
# The reference's move is reported per pair, not asserted away (both builds read m1's views of
# 2026-10-23, so it should be zero); a pair's diff_pct change is link_km_change against ref_km_change.
m$ref_km_change <- round(m$ref_value_0.78.0 - m$ref_value_0.68.0, 1)
cat(sprintf("reference moved on %d of %d pairs (values compared, not the build that produced them)\n",
            sum(m$ref_km_change != 0), nrow(m)))
m$link_km_change <- round(m$link_value_0.78.0 - m$link_value_0.68.0, 1)
m$diff_pct_change <- round(m$diff_pct_0.78.0 - m$diff_pct_0.68.0, 2)
m <- m[order(m$wsg, m$species, m$habitat_type), ]
write.csv(m, file.path(dir_out, "pair_moves.csv"), row.names = FALSE, na = "")

conn <- dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                  port = 5432L, user = "postgres", password = "postgres")
wsgs <- unique(new$wsg)
seg_n <- function(s) dbGetQuery(conn, sprintf(
  "SELECT watershed_group_code AS wsg, count(*) AS n, round(sum(length_metre)) AS m
     FROM %s.streams WHERE watershed_group_code IN (%s) GROUP BY 1 ORDER BY 1",
  s, paste0("'", wsgs, "'", collapse = ",")))
n_old <- seg_n("fresh_parity361")
n_new <- seg_n("fresh_parity441")
print(merge(n_old, n_new, by = "wsg", suffixes = c("_old", "_new")))
# Segments present in one build only (the builds break the line in different places):
# no segment in the other build with the same start and the same length (within 1 mm).
# The segment diff below joins only on segments both builds share, so these are reported
# here, not there.
reseg_in <- function(groups) dbGetQuery(conn, sprintf("
  WITH o AS (SELECT watershed_group_code AS wsg, blue_line_key, downstream_route_measure, length_metre
               FROM fresh_parity361.streams WHERE watershed_group_code IN (%1$s)),
       n AS (SELECT watershed_group_code AS wsg, blue_line_key, downstream_route_measure, length_metre
               FROM fresh_parity441.streams WHERE watershed_group_code IN (%1$s))
  SELECT 'only_old' AS side, o.* FROM o
   WHERE NOT EXISTS (SELECT 1 FROM n WHERE n.wsg = o.wsg AND n.blue_line_key = o.blue_line_key
                     AND n.downstream_route_measure = o.downstream_route_measure
                     AND abs(n.length_metre - o.length_metre) < 0.001)
  UNION ALL
  SELECT 'only_new', n.* FROM n
   WHERE NOT EXISTS (SELECT 1 FROM o WHERE o.wsg = n.wsg AND o.blue_line_key = n.blue_line_key
                     AND o.downstream_route_measure = n.downstream_route_measure
                     AND abs(o.length_metre - n.length_metre) < 0.001)
  ORDER BY 2, 3, 4, 1", paste0("'", groups, "'", collapse = ",")))
reseg <- reseg_in(wsgs)
write.csv(reseg, file.path(dir_out, "resegmented.csv"), row.names = FALSE)
# The same over every group of the closure, summarised per group.
closure <- dbGetQuery(conn,
  "SELECT DISTINCT watershed_group_code AS wsg FROM fresh_parity441.streams ORDER BY 1")$wsg
reseg_all <- reseg_in(closure)
reseg_sum <- if (nrow(reseg_all) == 0) {
  data.frame(wsg = character(), segments = integer(), lines = integer())
} else {
  data.frame(wsg = sort(unique(reseg_all$wsg)),
             segments = as.integer(table(reseg_all$wsg)[sort(unique(reseg_all$wsg))]),
             lines = as.integer(tapply(reseg_all$blue_line_key, reseg_all$wsg,
                                       function(x) length(unique(x)))[sort(unique(reseg_all$wsg))]))
}
write.csv(reseg_sum, file.path(dir_out, "resegmented_closure.csv"), row.names = FALSE)
cat(sprintf("closure: %d groups; segments in one build only: %d on %d lines in %d groups\n",
            length(closure), nrow(reseg_all), sum(reseg_sum$lines), nrow(reseg_sum)))
cat(sprintf("segments in one build only, old build: %d; new build: %d; new build's segments shared with the old: %.0f of %.0f\n",
            sum(reseg$side == "only_old"), sum(reseg$side == "only_new"),
            as.numeric(sum(as.numeric(n_new$n))) - sum(reseg$side == "only_new"), sum(as.numeric(n_new$n))))
cat(sprintf("segments in one build only: %d on %d lines (%s)\n", nrow(reseg),
            nrow(unique(reseg[, c("wsg", "blue_line_key")])),
            paste(unique(reseg$wsg), collapse = ", ")))
# Habitat km on those lines, per build: the part of a pair's move the segment diff
# cannot see. Lines, not segments, so the two builds sum over the same stretch.
reseg_lines <- unique(reseg[, c("wsg", "blue_line_key")])
sp_all <- unique(tolower(new$species))
# A temp table, not a VALUES list: at 0.78.0 #326 re-breaks most lines (17,527 here), and the
# list overflowed Postgres's stack.
if (nrow(reseg_lines)) {
  dbWriteTable(conn, "moves_reseg_lines", data.frame(wsg = reseg_lines$wsg,
               blue_line_key = as.integer(reseg_lines$blue_line_key)), temporary = TRUE, overwrite = TRUE)
}
reseg_hab <- if (nrow(reseg_lines) == 0) NULL else do.call(rbind, lapply(c("fresh_parity361", "fresh_parity441"), function(s) {
  do.call(rbind, lapply(sp_all, function(sp) {
    d <- dbGetQuery(conn, sprintf(
      "SELECT s.watershed_group_code AS wsg,
              round(sum(s.length_metre) FILTER (WHERE h.spawning)::numeric / 1000, 3) AS spawning_km,
              round(sum(s.length_metre) FILTER (WHERE h.rearing)::numeric / 1000, 3) AS rearing_km
         FROM %1$s.streams s
         JOIN %1$s.streams_habitat_%2$s h USING (id_segment, watershed_group_code)
         JOIN moves_reseg_lines r ON r.wsg = s.watershed_group_code AND r.blue_line_key = s.blue_line_key
        GROUP BY 1", s, sp))
    if (nrow(d) == 0) return(NULL)
    cbind(schema = s, species = toupper(sp), d)
  }))
}))
if (is.null(reseg_hab)) {
  reseg_hab <- data.frame(schema = character(), species = character(), wsg = character(),
                          spawning_km = numeric(), rearing_km = numeric())
}
write.csv(reseg_hab, file.path(dir_out, "resegmented_habitat.csv"), row.names = FALSE, na = "0")

sp_pairs <- unique(new[, c("wsg", "species")])
diffs <- do.call(rbind, lapply(seq_len(nrow(sp_pairs)), function(i) {
  w <- sp_pairs$wsg[i]
  sp <- tolower(sp_pairs$species[i])
  q <- sprintf("
    WITH o AS (
      SELECT s.blue_line_key, s.downstream_route_measure, s.length_metre,
             a.access_%1$s AS acc, h.spawning, h.rearing
        FROM fresh_parity361.streams s
        JOIN fresh_parity361.streams_access a USING (id_segment, watershed_group_code)
        LEFT JOIN fresh_parity361.streams_habitat_%1$s h USING (id_segment, watershed_group_code)
       WHERE s.watershed_group_code = '%2$s'),
    n AS (
      SELECT s.blue_line_key, s.downstream_route_measure, s.length_metre,
             a.access_%1$s AS acc, h.spawning, h.rearing
        FROM fresh_parity441.streams s
        JOIN fresh_parity441.streams_access a USING (id_segment, watershed_group_code)
        LEFT JOIN fresh_parity441.streams_habitat_%1$s h USING (id_segment, watershed_group_code)
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
      FROM o JOIN n ON n.blue_line_key = o.blue_line_key
                   AND n.downstream_route_measure = o.downstream_route_measure
                   AND abs(n.length_metre - o.length_metre) < 0.001
     WHERE (o.acc IS DISTINCT FROM n.acc
        OR coalesce(o.spawning, false) <> coalesce(n.spawning, false)
        OR coalesce(o.rearing, false) <> coalesce(n.rearing, false))
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
ov_old <- ov("fresh_parity361")
ov_new <- ov("fresh_parity441")
pos <- c("species_code", "blue_line_key", "drm")
ov_m <- merge(ov_old, ov_new, by = pos, all = TRUE, suffixes = c("_old", "_new"))
ov_m$change <- ifelse(is.na(ov_m$holders_old), "added",
                      ifelse(is.na(ov_m$holders_new), "lost", "same"))
ov_changed <- ov_m[ov_m$change != "same", ]
write.csv(ov_changed, file.path(dir_out, "override_diff.csv"), row.names = FALSE, na = "")
cat(sprintf("override positions: %d before, %d after; %d added, %d lost\n",
            nrow(ov_old), nrow(ov_new), sum(ov_m$change == "added"), sum(ov_m$change == "lost")))
dbDisconnect(conn)

# mapping_code agreement with bcfishpass over all 17 groups (the driver's compare).
# Moved by the gate and by lines the two builds break differently (resegmented_closure.csv),
# which also changes downstream-barrier flags on segments of other lines.
cmp_dir <- "data-raw/logs/study_area_run"
c_old <- read.csv(file.path(cmp_dir, "20261023_215312_compare.csv"))
c_new <- read.csv(file.path(cmp_dir, compare_new))
cm <- merge(c_old[, c("wsg", "species", "total_segs", "match_pct", "n_diffs")],
            c_new[, c("wsg", "species", "total_segs", "match_pct", "n_diffs")],
            by = c("wsg", "species"), all = TRUE, suffixes = c("_0.68.0", "_0.78.0"))
cm$match_pct_change <- round(cm$match_pct_0.78.0 - cm$match_pct_0.68.0, 2)
write.csv(cm, file.path(dir_out, "mapping_code_moves.csv"), row.names = FALSE, na = "")
print(cm[is.na(cm$match_pct_change) | cm$match_pct_change != 0, ], row.names = FALSE)

if (is.null(diffs)) {
  diffs <- data.frame(wsg = character(), species = character(), cause = character())
}
write.csv(diffs, file.path(dir_out, "segment_diff.csv"), row.names = FALSE, na = "0")
print(m[abs(m$link_km_change) > 0.1 | m$ref_km_change != 0,
        c(key, "link_value_0.68.0", "link_value_0.78.0", "link_km_change", "ref_km_change",
          "diff_pct_0.68.0", "diff_pct_0.78.0")],
      row.names = FALSE)
print(diffs, row.names = FALSE)

# link#478's scratch re-models, main against the branch: what moved, and
# whether every move sits at a crossing the snap moved.
#
#   Rscript data-raw/logs/snap_tie_478/compare_builds.R <config>
#
# Reads zz478_build_before_<config> and zz478_build_after_<config> (run.sh).
# Per persisted table and group: rows in each build, and rows found in only one
# (every column but run stamps). Then each moved row is tied to the snap:
#   streams, barriers, barrier_overrides: the row's blue line holds a moved
#     PSCIS pick or dam (picks_moved.csv / dams_moved.csv, old or new position);
#   per-segment tables (streams_access, streams_habitat_*, streams_mapping_code,
#     streams_near_river), compared by each segment's position, since
#     id_segment is renumbered by any added segment: on such a blue line, or
#     upstream of a moved position (mapping codes read the barriers downstream).
# Writes compare_<config>.csv (per table and group) and
# unexplained_<config>.csv (moved rows the snap does not account for).
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L, args %in% c("bcfishpass", "default"))
cfg <- args[1]
b <- paste0("zz478_build_before_", cfg)
a <- paste0("zz478_build_after_", cfg)
dir <- "data-raw/logs/snap_tie_478"
conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                       port = 5432L, user = "postgres", password = "postgres")
q <- function(sql) DBI::dbGetQuery(conn, sql)

# Moved positions: old and new of every moved PSCIS pick and dam
picks <- utils::read.csv(file.path(dir, "picks_moved.csv"))
dams_b <- q("SELECT dam_id, blue_line_key, downstream_route_measure FROM zz478_before.dams_matched")
dams_a <- q("SELECT dam_id, blue_line_key, downstream_route_measure FROM zz478_after.dams_matched")
dm <- utils::read.csv(file.path(dir, "dams_moved.csv"))
moved <- rbind(
  data.frame(blk = picks$blk_before, m = picks$drm_before),
  data.frame(blk = picks$blk_after, m = picks$drm_after),
  dams_b[dams_b$dam_id %in% dm$dam_id, c("blue_line_key", "downstream_route_measure")] |>
    stats::setNames(c("blk", "m")),
  dams_a[dams_a$dam_id %in% dm$dam_id, c("blue_line_key", "downstream_route_measure")] |>
    stats::setNames(c("blk", "m")))
moved <- unique(moved[!is.na(moved$blk), ])
DBI::dbWriteTable(conn, "moved", moved,
                  temporary = TRUE, overwrite = TRUE)
q("CREATE TEMP TABLE moved_pos AS
   SELECT m.blk, m.m, s.wscode_ltree, s.localcode_ltree
     FROM moved m JOIN whse_basemapping.fwa_stream_networks_sp s
       ON s.blue_line_key = m.blk AND m.m >= s.downstream_route_measure
      AND m.m <= s.upstream_route_measure")

stamp_cols <- c("run_id", "run_uid", "date_start", "date_end", "link_sha")
tables <- q(sprintf(
  "SELECT table_name FROM information_schema.tables
    WHERE table_schema = '%s' AND table_type = 'BASE TABLE'
      AND table_name NOT LIKE 'log%%' ORDER BY 1", a))$table_name

res <- list(); unexpl <- list()
for (tb in tables) {
  cols <- q(sprintf("SELECT column_name FROM information_schema.columns
                      WHERE table_schema = '%s' AND table_name = '%s'", a, tb))$column_name
  cols <- sort(setdiff(cols, stamp_cols), method = "radix")
  if (!"watershed_group_code" %in% cols) next
  # id_segment is a positional number: a segment added below renumbers every
  # one above it. Compare a segment by its position (blue line, measure).
  seg_tbl <- "id_segment" %in% cols && tb != "streams"
  cmp <- setdiff(cols, "id_segment")
  from <- function(sch) if (seg_tbl) sprintf(
    "%1$s.%2$s t JOIN %1$s.streams s USING (id_segment, watershed_group_code)", sch, tb) else
    sprintf("%s.%s t", sch, tb)
  row <- sprintf("row(%s)::text", paste(c(paste0("t.", setdiff(cmp, "watershed_group_code")),
    if (seg_tbl) c("s.blue_line_key", "s.downstream_route_measure")), collapse = ", "))
  key <- if (seg_tbl) {
    "s.blue_line_key::double precision AS k1, s.downstream_route_measure AS k2"
  } else if (all(c("blue_line_key", "downstream_route_measure") %in% cols)) {
    "t.blue_line_key::double precision AS k1, t.downstream_route_measure AS k2"
  } else "NULL::double precision AS k1, NULL::double precision AS k2"
  d <- q(sprintf(
    "WITH b AS (SELECT t.watershed_group_code AS wsg, %1$s AS r, %3$s FROM %2$s),
          a AS (SELECT t.watershed_group_code AS wsg, %1$s AS r, %3$s FROM %4$s)
     SELECT 'before_only' AS side, b.* FROM b WHERE NOT EXISTS (SELECT 1 FROM a WHERE a.r = b.r)
     UNION ALL
     SELECT 'after_only', a.* FROM a WHERE NOT EXISTS (SELECT 1 FROM b WHERE b.r = a.r)",
    row, from(b), key, from(a)))
  n <- q(sprintf(
    "SELECT watershed_group_code AS wsg,
            (SELECT count(*) FROM %1$s.%2$s x WHERE x.watershed_group_code = t.watershed_group_code)::int AS n_before,
            count(*)::int AS n_after
       FROM %3$s.%2$s t GROUP BY 1", b, tb, a))
  if (nrow(n) == 0L) next
  n$table <- tb
  n$before_only <- vapply(n$wsg, function(w) sum(d$side == "before_only" & d$wsg == w), 1L)
  n$after_only <- vapply(n$wsg, function(w) sum(d$side == "after_only" & d$wsg == w), 1L)
  res[[tb]] <- n
  if (nrow(d) > 0L) {
    d$table <- tb
    unexpl[[tb]] <- d[, c("table", "side", "wsg", "k1", "k2")]
  }
}
out <- do.call(rbind, res)[, c("table", "wsg", "n_before", "n_after", "before_only", "after_only")]
moved_rows <- if (length(unexpl)) do.call(rbind, unexpl) else data.frame()

# Explain each moved row
explain <- function(tb, k1, k2) {
  if (is.na(k1)) return(FALSE)
  if (k1 %in% moved$blk) return(TRUE)
  if (tb %in% c("streams", "barriers", "barrier_overrides", "barrier_override_evidence")) {
    return(FALSE)
  }
  # a segment on another line: upstream of a moved position (mapping codes
  # read the barriers downstream)
  seg <- q(sprintf(
    "SELECT wscode_ltree::text AS w, localcode_ltree::text AS l
       FROM whse_basemapping.fwa_stream_networks_sp
      WHERE blue_line_key = %d AND %.17g >= downstream_route_measure
        AND %.17g < upstream_route_measure LIMIT 1", as.integer(k1), k2, k2))
  if (nrow(seg) == 0L) return(FALSE)
  q(sprintf(
    "SELECT EXISTS (SELECT 1 FROM moved_pos p WHERE whse_basemapping.fwa_upstream(
       p.blk, p.m, p.wscode_ltree, p.localcode_ltree,
       %d, %.17g, '%s'::ltree, '%s'::ltree, true, 1)) AS e",
    as.integer(k1), k2, seg$w, seg$l))$e
}
if (nrow(moved_rows) > 0L) {
  moved_rows$explained <- mapply(explain, moved_rows$table, moved_rows$k1, moved_rows$k2)
  out$unexplained <- vapply(seq_len(nrow(out)), function(i) sum(
    moved_rows$table == out$table[i] & moved_rows$wsg == out$wsg[i] & !moved_rows$explained), 1L)
} else out$unexplained <- 0L
out <- out[order(out$table, out$wsg, method = "radix"), ]
# which code built each side: the builds' own log rows
stamps <- do.call(rbind, lapply(c(b, a), function(sch) cbind(schema = sch, q(sprintf(
  "SELECT watershed_group_code AS wsg, link_sha, link_dirty, fresh_sha
     FROM %s.log ORDER BY 1, date_start DESC", sch)))))
utils::write.csv(stamps, file.path(dir, sprintf("builds_%s.csv", cfg)), row.names = FALSE)
utils::write.csv(out, file.path(dir, sprintf("compare_%s.csv", cfg)), row.names = FALSE)
utils::write.csv(if (nrow(moved_rows)) moved_rows[!moved_rows$explained, ] else moved_rows,
                 file.path(dir, sprintf("unexplained_%s.csv", cfg)), row.names = FALSE)
DBI::dbDisconnect(conn)
print(out[out$before_only + out$after_only > 0, ])
message(sprintf("[compare] %s: %d table-group pairs, %d with moved rows, %d moved rows unexplained",
                cfg, nrow(out), sum(out$before_only + out$after_only > 0), sum(out$unexplained)))

#!/usr/bin/env Rscript
# diff.R — what moved between two proof builds of link#386 (BEFORE and
# AFTER-386), and why. Every changed row is put in a named category with a
# count; anything outside them stops the script (exit 1) after writing what it
# found.
#
# Usage: Rscript diff.R <before schema> <after schema> <bundle> <out dir>
#   bundle  config whose control file decides which positions a re-filed
#           control row touches (default or bcfishpass)
#
# Categories
#   non_owner_copy   a gradient or override row a group held at a position
#                    another group of the set owns, removed while the owner
#                    holds the same row in AFTER
#   owner_outside    a row at a position owned by a group outside the set (or
#                    a group the bundle does not model): removed, and no group
#                    of the set holds it now (open decision 8 keeps it only
#                    where the owner would never hold it)
#   control          a row within 1 m of a control row on a line several
#                    groups scan (a row filed under one group now applies in
#                    every group scanning the position)
#   disagreed        a row within 1 m of a position whose copies disagreed in
#                    BEFORE (a built scanner held no copy)
#   segment_cut      a segment present in one build and not the other (by
#                    line, start and length to the mm)
#   access / habitat a value changed on a segment identical in both, where the
#                    segment lies at or upstream of a position in one of the
#                    explained categories (control, disagreed, owner_outside)
# Keys: barriers by source, line, measure (to the cm) and subtype, plus the
# holder; overrides by line, measure, species and holder. Gradient ids and
# id_segment renumber when rows or cuts move, so neither is a key.
# Also asserts that every (position, species) lifted in BEFORE is lifted by
# some group of the set in AFTER, outside the control and owner_outside
# positions.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 4L)
sb <- args[[1]]; sa <- args[[2]]; bundle <- args[[3]]; out <- args[[4]]
stopifnot(grepl("^[a-z_][a-z0-9_]*$", sb), grepl("^[a-z_][a-z0-9_]*$", sa))
dir.create(out, recursive = TRUE, showWarnings = FALSE)
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
q <- function(sql) DBI::dbGetQuery(conn, sql)
x <- function(sql) {
  # one statement per call: RPostgres refuses several in one prepared query
  for (part in strsplit(sql, ";\\s*\n")[[1]]) {
    if (nzchar(trimws(part))) DBI::dbExecute(conn, part)
  }
  invisible(NULL)
}

set <- q(sprintf("SELECT DISTINCT watershed_group_code AS w FROM %s.log
                   WHERE date_end IS NOT NULL ORDER BY 1", sa))$w
set_b <- q(sprintf("SELECT DISTINCT watershed_group_code AS w FROM %s.log
                     WHERE date_end IS NOT NULL ORDER BY 1", sb))$w
stopifnot(identical(set, set_b))
set_sql <- paste(sprintf("'%s'", set), collapse = ", ")
cfg <- lnk_config(bundle)
loaded <- suppressWarnings(lnk_load_overrides(cfg))
modelled <- lnk_wsg_resolve(cfg, loaded)

x("CREATE OR REPLACE FUNCTION pg_temp.d386_owner(blk integer, m double precision)
   RETURNS text LANGUAGE sql STABLE AS $f$
     SELECT COALESCE(
       (SELECT s.watershed_group_code::text
          FROM whse_basemapping.fwa_stream_networks_sp s
         WHERE s.blue_line_key = blk
           AND m >= s.downstream_route_measure AND m < s.upstream_route_measure
         ORDER BY s.downstream_route_measure, s.linear_feature_id LIMIT 1),
       (SELECT n.watershed_group_code::text
          FROM whse_basemapping.fwa_stream_networks_sp n
         WHERE n.blue_line_key = blk
         ORDER BY least(abs(m - n.downstream_route_measure),
                        abs(m - n.upstream_route_measure)), n.linear_feature_id
         LIMIT 1))
   $f$")

# --- explained positions ---------------------------------------------------
ctrl <- loaded$user_barriers_definite_control
x("DROP TABLE IF EXISTS pg_temp.d386_ctrl")
x("CREATE TEMP TABLE d386_ctrl (blue_line_key integer, downstream_route_measure double precision)")
if (!is.null(ctrl) && nrow(ctrl) > 0L) {
  x(sprintf("INSERT INTO d386_ctrl VALUES %s", paste(sprintf("(%d, %s)",
    as.integer(ctrl$blue_line_key), format(ctrl$downstream_route_measure,
                                           digits = 15)), collapse = ", ")))
}
# Only those on a line several groups scan: elsewhere the filed group is the
# only scanner, so filing by position changes nothing.
x("DELETE FROM d386_ctrl c WHERE (SELECT count(DISTINCT watershed_group_code)
     FROM whse_basemapping.fwa_stream_networks_sp s
    WHERE s.blue_line_key = c.blue_line_key AND s.edge_type != 6010) < 2")

# BEFORE's disagreements: a gradient position on a multi-group line some built
# scanner of the set did not hold within 1 m.
x(sprintf("DROP TABLE IF EXISTS pg_temp.d386_dis;
  CREATE TEMP TABLE d386_dis AS
  WITH g AS (SELECT DISTINCT b.watershed_group_code::text AS holder,
                    b.blue_line_key, b.downstream_route_measure AS drm
               FROM %1$s.barriers b
              WHERE b.barrier_source = 'GRADIENT'),
       sc AS (SELECT s.blue_line_key, s.watershed_group_code::text AS w
                FROM whse_basemapping.fwa_stream_networks_sp s
               WHERE s.blue_line_key IN (SELECT blue_line_key FROM g)
                 AND s.edge_type != 6010 AND s.watershed_group_code IN (%2$s)
               GROUP BY 1, 2)
  SELECT DISTINCT g.blue_line_key, g.drm AS downstream_route_measure
    FROM g JOIN sc USING (blue_line_key)
   WHERE NOT EXISTS (SELECT 1 FROM g g2 WHERE g2.holder = sc.w
                       AND g2.blue_line_key = g.blue_line_key
                       AND abs(g2.drm - g.drm) < 1)", sb, set_sql))

# --- barriers ----------------------------------------------------------------
bkey <- function(s) sprintf(
  "SELECT DISTINCT barrier_source, blue_line_key,
          round(downstream_route_measure::numeric, 2) AS m, barrier_subtype,
          watershed_group_code::text AS holder
     FROM %s.barriers", s)
x(sprintf("DROP TABLE IF EXISTS pg_temp.d386_b;
  CREATE TEMP TABLE d386_b AS
  SELECT 'removed' AS change, * FROM ((%1$s) EXCEPT (%2$s)) r
  UNION ALL
  SELECT 'added', * FROM ((%2$s) EXCEPT (%1$s)) a", bkey(sb), bkey(sa)))
x("ALTER TABLE d386_b ADD COLUMN owner text, ADD COLUMN category text")
x("UPDATE d386_b SET owner = pg_temp.d386_owner(blue_line_key, m::double precision)")
cat_sql <- function(t, src_filter, m) sprintf(
  "UPDATE %1$s d SET category = CASE
     WHEN EXISTS (SELECT 1 FROM d386_ctrl c WHERE c.blue_line_key = d.blue_line_key
                    AND abs(c.downstream_route_measure - d.%2$s) < 1) THEN 'control'
     WHEN EXISTS (SELECT 1 FROM d386_dis c WHERE c.blue_line_key = d.blue_line_key
                    AND abs(c.downstream_route_measure - d.%2$s) < 1) THEN 'disagreed'
     WHEN d.change = 'removed' AND d.owner <> d.holder
          AND (d.owner NOT IN (%3$s) OR d.owner <> ALL (%4$s)) THEN 'owner_outside'
     ELSE NULL END
   WHERE %5$s", t, m, set_sql,
  sprintf("ARRAY[%s]::text[]", paste(sprintf("'%s'", modelled), collapse = ",")),
  src_filter)
x(cat_sql("d386_b", "barrier_source = 'GRADIENT'", "m"))
# A removed non-owner copy whose owner (in the set) holds the same row now.
x(sprintf("UPDATE d386_b d SET category = 'non_owner_copy'
   WHERE d.category IS NULL AND d.change = 'removed' AND d.owner <> d.holder
     AND d.barrier_source = 'GRADIENT'
     AND EXISTS (SELECT 1 FROM %s.barriers a
                  WHERE a.watershed_group_code = d.owner
                    AND a.barrier_source = 'GRADIENT'
                    AND a.blue_line_key = d.blue_line_key
                    AND round(a.downstream_route_measure::numeric, 2) = d.m
                    AND a.barrier_subtype = d.barrier_subtype)", sa))

# --- overrides ---------------------------------------------------------------
okey <- function(s) sprintf(
  "SELECT DISTINCT blue_line_key, round(downstream_route_measure::numeric, 2) AS m,
          species_code, watershed_group_code::text AS holder
     FROM %s.barrier_overrides", s)
x(sprintf("DROP TABLE IF EXISTS pg_temp.d386_o;
  CREATE TEMP TABLE d386_o AS
  SELECT 'removed' AS change, * FROM ((%1$s) EXCEPT (%2$s)) r
  UNION ALL
  SELECT 'added', * FROM ((%2$s) EXCEPT (%1$s)) a", okey(sb), okey(sa)))
# The owner of an override is the owner of the natural barrier it sits beside:
# the nearest BEFORE barrier row within 1 m (a rounded measure can fall on
# the neighbour's side of a boundary).
x("ALTER TABLE d386_o ADD COLUMN owner text, ADD COLUMN category text")
x(sprintf("UPDATE d386_o d SET owner = (
    SELECT pg_temp.d386_owner(b.blue_line_key, b.downstream_route_measure)
      FROM %s.barriers b
     WHERE b.blue_line_key = d.blue_line_key
       AND abs(b.downstream_route_measure - d.m::double precision) < 1
       AND b.barrier_source IN ('GRADIENT', 'FALLS', 'SUBSURFACE_FLOW')
     ORDER BY abs(b.downstream_route_measure - d.m::double precision) LIMIT 1)", sb))
x("UPDATE d386_o SET owner = pg_temp.d386_owner(blue_line_key, m::double precision)
    WHERE owner IS NULL")
x(cat_sql("d386_o", "TRUE", "m"))
x(sprintf("UPDATE d386_o d SET category = 'non_owner_copy'
   WHERE d.category IS NULL AND d.change = 'removed' AND d.owner <> d.holder
     AND EXISTS (SELECT 1 FROM %s.barrier_overrides a
                  WHERE a.watershed_group_code = d.owner
                    AND a.blue_line_key = d.blue_line_key
                    AND round(a.downstream_route_measure::numeric, 2) = d.m
                    AND a.species_code = d.species_code)", sa))

# Every (position, species) lifted in BEFORE is lifted by a group of the set
# in AFTER, outside the control and owner_outside positions.
lost <- q(sprintf(
  "SELECT DISTINCT o.blue_line_key, o.m, o.species_code FROM (%1$s) o
    WHERE NOT EXISTS (SELECT 1 FROM %2$s.barrier_overrides a
                       WHERE a.blue_line_key = o.blue_line_key
                         AND abs(a.downstream_route_measure - o.m::double precision) < 0.01
                         AND a.species_code = o.species_code)
      AND NOT EXISTS (SELECT 1 FROM d386_o d WHERE d.blue_line_key = o.blue_line_key
                        AND d.m = o.m AND d.species_code = o.species_code
                        AND d.category IN ('control', 'owner_outside'))",
  okey(sb), sa))

# --- explained positions, located ----------------------------------------------
x("DROP TABLE IF EXISTS pg_temp.d386_p;
   CREATE TEMP TABLE d386_p AS
   SELECT DISTINCT category, blue_line_key, m::double precision AS drm FROM d386_b
    WHERE category IN ('control', 'disagreed', 'owner_outside')
   UNION
   SELECT DISTINCT category, blue_line_key, m::double precision FROM d386_o
    WHERE category IN ('control', 'disagreed', 'owner_outside')
   UNION
   SELECT 'control', blue_line_key, downstream_route_measure FROM d386_ctrl
   UNION
   SELECT 'disagreed', blue_line_key, downstream_route_measure FROM d386_dis")
x("ALTER TABLE d386_p ADD COLUMN ws ltree, ADD COLUMN lc ltree")
x("UPDATE d386_p p SET ws = s.wscode_ltree, lc = s.localcode_ltree
     FROM whse_basemapping.fwa_stream_networks_sp s
    WHERE s.blue_line_key = p.blue_line_key
      AND p.drm >= s.downstream_route_measure AND p.drm < s.upstream_route_measure")

# --- segments, access, habitat ---------------------------------------------------
skey <- function(s) sprintf(
  "SELECT watershed_group_code::text AS w, blue_line_key,
          round(downstream_route_measure::numeric, 3) AS m,
          round(length_metre::numeric, 3) AS len
     FROM %s.streams WHERE watershed_group_code IN (%s)", s, set_sql)
seg <- q(sprintf(
  "SELECT 'removed' AS change, w, count(*)::int AS n FROM ((%1$s) EXCEPT (%2$s)) r GROUP BY 2
   UNION ALL
   SELECT 'added', w, count(*)::int FROM ((%2$s) EXCEPT (%1$s)) a GROUP BY 2 ORDER BY 2, 1",
  skey(sb), skey(sa)))

species <- sub("^access_", "", grep("^access_", q(sprintf(
  "SELECT column_name FROM information_schema.columns
    WHERE table_schema = '%s' AND table_name = 'streams_access'", sa))$column_name,
  value = TRUE))
val_rows <- list()
for (sp in species) {
  for (spec in list(
    list(what = "access", t = "streams_access", col = paste0("access_", sp)),
    list(what = "spawning", t = paste0("streams_habitat_", sp), col = "spawning"),
    list(what = "rearing", t = paste0("streams_habitat_", sp), col = "rearing"))) {
    if (!.lnk_table_exists(conn, paste0(sa, ".", spec$t)) ||
        !.lnk_table_exists(conn, paste0(sb, ".", spec$t))) next
    v <- q(sprintf(
      "WITH sb AS (SELECT s.watershed_group_code::text AS w, s.blue_line_key,
                          round(s.downstream_route_measure::numeric, 3) AS m,
                          round(s.length_metre::numeric, 3) AS len,
                          s.wscode_ltree, s.localcode_ltree,
                          s.downstream_route_measure AS drm,
                          v.%3$s::text AS val
                     FROM %1$s.streams s JOIN %1$s.%4$s v USING (id_segment, watershed_group_code)
                    WHERE s.watershed_group_code IN (%5$s)),
            sa AS (SELECT s.watershed_group_code::text AS w, s.blue_line_key,
                          round(s.downstream_route_measure::numeric, 3) AS m,
                          round(s.length_metre::numeric, 3) AS len,
                          v.%3$s::text AS val
                     FROM %2$s.streams s JOIN %2$s.%4$s v USING (id_segment, watershed_group_code)
                    WHERE s.watershed_group_code IN (%5$s))
       SELECT b.w, b.blue_line_key, b.m, b.len, b.val AS before, a.val AS after,
              (SELECT p.category FROM d386_p p
                WHERE p.ws IS NOT NULL
                  AND whse_basemapping.fwa_upstream(p.blue_line_key, p.drm, p.ws, p.lc,
                        b.blue_line_key, b.drm, b.wscode_ltree, b.localcode_ltree,
                        true, 1)
                ORDER BY p.category LIMIT 1) AS category
         FROM sb b JOIN sa a USING (w, blue_line_key, m, len)
        WHERE b.val IS DISTINCT FROM a.val",
      sb, sa, spec$col, spec$t, set_sql))
    if (nrow(v) > 0L) {
      v$species <- sp; v$what <- spec$what
      val_rows[[length(val_rows) + 1L]] <- v
    }
  }
}
vals <- if (length(val_rows)) do.call(rbind, val_rows) else
  data.frame(w = character(0), category = character(0), what = character(0),
             species = character(0), length = numeric(0))

# --- report ------------------------------------------------------------------
b <- q("SELECT * FROM d386_b ORDER BY barrier_source, blue_line_key, m, holder")
o <- q("SELECT * FROM d386_o ORDER BY blue_line_key, m, species_code, holder")
utils::write.csv(b, file.path(out, "barriers_changed.csv"), row.names = FALSE)
utils::write.csv(o, file.path(out, "overrides_changed.csv"), row.names = FALSE)
utils::write.csv(seg, file.path(out, "segments_changed.csv"), row.names = FALSE)
utils::write.csv(vals, file.path(out, "values_changed.csv"), row.names = FALSE)
utils::write.csv(lost, file.path(out, "lifts_lost.csv"), row.names = FALSE)
tab <- function(d, by) {
  if (nrow(d) == 0L) return(data.frame())
  d$category[is.na(d$category)] <- "UNEXPLAINED"
  stats::aggregate(list(n = rep(1L, nrow(d))), d[by], sum)
}
summary <- list(
  barriers = tab(b, c("barrier_source", "change", "category")),
  overrides = tab(o, c("change", "category")),
  segments = seg,
  values = if (nrow(vals)) tab(vals, c("what", "category")) else data.frame(),
  lifts_lost = nrow(lost))
sink(file.path(out, "summary.txt"))
cat(sprintf("diff %s -> %s (%s), %d groups: %s\n", sb, sa, bundle, length(set),
            paste(set, collapse = " ")))
cat(sprintf("explained positions: %d control, %d disagreed in BEFORE\n",
            q("SELECT count(*)::int AS n FROM d386_ctrl")$n,
            q("SELECT count(*)::int AS n FROM d386_dis")$n))
for (k in names(summary)) { cat("\n==", k, "\n"); print(summary[[k]]) }
sink()
cat(readLines(file.path(out, "summary.txt")), sep = "\n")
bad <- sum(is.na(b$category)) + sum(is.na(o$category)) +
  sum(is.na(vals$category)) + nrow(lost)
if (bad > 0L) {
  cat(sprintf("\nSTOP: %d change(s) outside the named categories\n", bad))
  quit(status = 1)
}
cat("\nOK: every change is in a named category\n")

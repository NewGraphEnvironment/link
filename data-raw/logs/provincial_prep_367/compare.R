# link#367 Phase 3 comparisons. Run after p3/run.sh finishes.
#   Rscript compare.R <out_dir>
suppressPackageStartupMessages({ library(DBI); library(RPostgres) })
out <- commandArgs(trailingOnly = TRUE)[1]
dir.create(out, showWarnings = FALSE, recursive = TRUE)
conn <- dbConnect(Postgres(), dbname = "fwapg", host = "localhost", port = 5432L,
                  user = "postgres", password = "postgres")
q <- function(sql) dbGetQuery(conn, sql)
invisible(dbExecute(conn, "SET extra_float_digits = 3"))

tables_of <- function(sch) {
  q(sprintf("SELECT table_name FROM information_schema.tables
              WHERE table_schema = '%s' AND table_type = 'BASE TABLE'
                AND (table_name IN ('streams','barriers','streams_access','streams_mapping_code')
                     OR table_name LIKE 'streams_habitat_%%')
              ORDER BY 1", sch))$table_name
}
# Digest of one group's rows of one table, every column, geometry as EWKB.
# Rows ordered by position for streams, by id for the rest; barriers also
# get a digest that leaves the id out, to tell an id change from a content one.
digest <- function(sch, tbl, wsg, drop = character()) {
  cols <- q(sprintf("SELECT column_name, udt_name FROM information_schema.columns
                      WHERE table_schema = '%s' AND table_name = '%s' ORDER BY column_name", sch, tbl))
  cols <- cols[!cols$column_name %in% drop, ]
  expr <- ifelse(cols$udt_name == "geometry", sprintf("md5(ST_AsEWKB(%s))", cols$column_name), cols$column_name)
  ord <- switch(tbl,
    streams = "blue_line_key, downstream_route_measure",
    barriers = "barrier_source, blue_line_key, downstream_route_measure, barrier_subtype, id_barrier",
    "id_segment")
  r <- q(sprintf("SELECT count(*) AS n, md5(string_agg(md5(ROW(%s)::text), '' ORDER BY %s)) AS d
                    FROM %s.%s WHERE watershed_group_code = '%s'",
                 paste(expr, collapse = ", "), ord, sch, tbl, wsg))
  r
}
compare_pair <- function(a, b, wsgs, label) {
  rows <- list()
  for (w in wsgs) for (t in intersect(tables_of(a), tables_of(b))) {
    da <- digest(a, t, w); db <- digest(b, t, w)
    row <- data.frame(comparison = label, wsg = w, table = t, n_a = da$n, n_b = db$n,
                      identical = identical(da$d, db$d))
    if (t == "barriers") {
      row$identical_without_id <- identical(digest(a, t, w, "id_barrier")$d, digest(b, t, w, "id_barrier")$d)
    } else row$identical_without_id <- NA
    rows[[length(rows) + 1]] <- row
  }
  do.call(rbind, rows)
}

# 1. Reproducibility: two branch builds.
rep <- compare_pair("fresh_367a", "fresh_367b", c("ADMS", "ELKR"), "branch A vs branch B")
write.csv(rep, file.path(out, "reproducibility.csv"), row.names = FALSE)

# 2. #244 isolated: knob on (A) vs off (C), recomputed.
k <- compare_pair("fresh_367a", "fresh_367c", c("LARL", "KETL", "SKGT"), "knob on vs off")
write.csv(k, file.path(out, "knob_tables.csv"), row.names = FALSE)

sp_cols <- function(sch) sub("^mapping_code_", "", grep("^mapping_code_", q(sprintf(
  "SELECT column_name FROM information_schema.columns WHERE table_schema='%s' AND table_name='streams_mapping_code'", sch))$column_name, value = TRUE))
tok <- list()
for (sp in sp_cols("fresh_367a")) {
  r <- q(sprintf("SELECT a.watershed_group_code AS wsg, '%1$s' AS species,
                         c.mapping_code_%1$s AS code_off, a.mapping_code_%1$s AS code_on, count(*) AS segments
                    FROM fresh_367a.streams_mapping_code a
                    JOIN fresh_367c.streams_mapping_code c USING (id_segment, watershed_group_code)
                   WHERE a.watershed_group_code IN ('LARL','KETL','SKGT')
                     AND a.mapping_code_%1$s IS DISTINCT FROM c.mapping_code_%1$s
                   GROUP BY 1,2,3,4 ORDER BY 1,2,5 DESC", sp))
  if (nrow(r)) tok[[sp]] <- r
}
tok <- if (length(tok)) do.call(rbind, tok) else data.frame()
if (nrow(tok)) {
  tok$only_token2_to_dam <- mapply(function(o, n) {
    po <- strsplit(o, ";", fixed = TRUE)[[1]]; pn <- strsplit(n, ";", fixed = TRUE)[[1]]
    length(po) >= 2 && length(po) == length(pn) && identical(po[-2], pn[-2]) && pn[2] == "DAM"
  }, tok$code_off, tok$code_on)
}
write.csv(tok, file.path(out, "knob_mapping_code_changes.csv"), row.names = FALSE)
bar <- q("SELECT 'on_only' AS side, watershed_group_code, id_barrier, barrier_source, barrier_subtype FROM fresh_367a.barriers a
           WHERE watershed_group_code IN ('LARL','KETL','SKGT') AND NOT EXISTS (SELECT 1 FROM fresh_367c.barriers c
             WHERE c.watershed_group_code = a.watershed_group_code AND c.id_barrier = a.id_barrier)
          UNION ALL
          SELECT 'off_only', watershed_group_code, id_barrier, barrier_source, barrier_subtype FROM fresh_367c.barriers c
           WHERE watershed_group_code IN ('LARL','KETL','SKGT') AND NOT EXISTS (SELECT 1 FROM fresh_367a.barriers a
             WHERE a.watershed_group_code = c.watershed_group_code AND a.id_barrier = c.id_barrier)")
write.csv(bar, file.path(out, "knob_barrier_rows.csv"), row.names = FALSE)

# 3. Effect of the branch at the habitat level: main (M) vs branch (A).
km <- list()
for (w in c("ADMS", "ELKR", "NATR")) {
  seg <- q(sprintf("SELECT (SELECT count(*) FROM fresh_367m.streams WHERE watershed_group_code='%1$s') AS seg_main,
                           (SELECT count(*) FROM fresh_367a.streams WHERE watershed_group_code='%1$s') AS seg_branch", w))
  for (sp in intersect(sp_cols("fresh_367m"), sp_cols("fresh_367a"))) {
    t <- paste0("streams_habitat_", sp)
    if (!t %in% tables_of("fresh_367m") || !t %in% tables_of("fresh_367a")) next
    f <- function(sch) q(sprintf(
      "SELECT round((sum(s.length_metre) FILTER (WHERE h.accessible)/1000)::numeric, 3) acc,
              round((sum(s.length_metre) FILTER (WHERE h.spawning)/1000)::numeric, 3) spawn,
              round((sum(s.length_metre) FILTER (WHERE h.rearing)/1000)::numeric, 3) rear
         FROM %1$s.%2$s h JOIN %1$s.streams s USING (id_segment, watershed_group_code)
        WHERE h.watershed_group_code = '%3$s'", sch, t, w))
    m <- f("fresh_367m"); b <- f("fresh_367a")
    if (all(is.na(unlist(m))) && all(is.na(unlist(b)))) next
    km[[paste(w, sp)]] <- data.frame(wsg = w, species = sp, seg_main = seg$seg_main, seg_branch = seg$seg_branch,
      accessible_main = m$acc, accessible_branch = b$acc, spawning_main = m$spawn, spawning_branch = b$spawn,
      rearing_main = m$rear, rearing_branch = b$rear)
  }
}
km <- do.call(rbind, km)
write.csv(km, file.path(out, "main_vs_branch_km.csv"), row.names = FALSE)

print(rep); print(k); print(head(tok, 30)); print(bar); print(km)

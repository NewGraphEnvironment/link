# split_compare.R — per-group, per-table digests of a split-and-recomputed
# build against the reference build of the same groups (link#361). Adapted
# from ../provincial_prep_367/compare.R.
#
#   Rscript split_compare.R <out_dir> <schema_a> <schema_ref> <schema_control> <groups csv>
#
# Every BASE TABLE both schemas hold that carries watershed_group_code and is
# not a log table is digested: every column, ordered by name; geometry as
# EWKB; rows in a key order that does not depend on insertion. `barriers`
# also gets a digest without id_barrier, to tell an id change from a content
# one.
#
# The control: <schema_control> is a build of the same groups at ANOTHER link
# version. Its digest of one group must differ from <schema_a>'s, or the
# compare cannot see a change and the identical rows mean nothing.
#
# Writes split_test.csv (one row per group x table), split_test_summary.txt,
# and for the first differing id_segment-keyed table a column-level diff of
# its first differing group, split_test_diff_<table>_<wsg>.csv.
suppressPackageStartupMessages({ library(DBI); library(RPostgres) })
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 5L) stop("usage: split_compare.R <out_dir> <schema_a> <schema_ref> <schema_control> <groups csv>")
out <- args[1]; sch_a <- args[2]; sch_ref <- args[3]; sch_ctl <- args[4]
wsgs <- strsplit(args[5], ",")[[1]]
conn <- dbConnect(Postgres(), dbname = "fwapg", host = "localhost", port = 5432L,
                  user = "postgres", password = "postgres")
q <- function(sql, ...) dbGetQuery(conn, sprintf(sql, ...))
for (s in c("SET extra_float_digits = 3", "SET DateStyle = 'ISO, MDY'", "SET TimeZone = 'UTC'",
            "SET bytea_output = 'hex'", "SET lc_numeric = 'C'")) invisible(dbExecute(conn, s))

tables_of <- function(sch) q(
  "SELECT t.table_name FROM information_schema.tables t
    WHERE t.table_schema = '%s' AND t.table_type = 'BASE TABLE'
      AND t.table_name NOT LIKE 'log%%'
      AND EXISTS (SELECT 1 FROM information_schema.columns c
                   WHERE c.table_schema = t.table_schema AND c.table_name = t.table_name
                     AND c.column_name = 'watershed_group_code')
    ORDER BY 1", sch)$table_name
schema_exists <- function(sch) nrow(q("SELECT 1 FROM information_schema.schemata WHERE schema_name = '%s'", sch)) == 1L

order_of <- function(tbl) switch(tbl,
  streams = "blue_line_key, downstream_route_measure",
  barriers = "barrier_source, blue_line_key, downstream_route_measure, barrier_subtype, id_barrier",
  barrier_overrides = "blue_line_key, downstream_route_measure, species_code",
  "id_segment")

digest <- function(sch, tbl, wsg, drop = character()) {
  cols <- q("SELECT column_name, udt_name FROM information_schema.columns
              WHERE table_schema = '%s' AND table_name = '%s' ORDER BY column_name", sch, tbl)
  cols <- cols[!cols$column_name %in% drop, ]
  expr <- ifelse(cols$udt_name == "geometry", sprintf("md5(ST_AsEWKB(%s))", cols$column_name),
                 cols$column_name)
  r <- q("SELECT count(*) AS n, md5(string_agg(md5(ROW(%s)::text), '' ORDER BY %s)) AS d
            FROM %s.%s WHERE watershed_group_code = '%s'",
         paste(expr, collapse = ", "), order_of(tbl), sch, tbl, wsg)
  r$n <- as.integer(r$n)   # count(*) arrives as integer64, which sprintf's %%d refuses
  r
}

tabs <- intersect(tables_of(sch_a), tables_of(sch_ref))
only_a <- setdiff(tables_of(sch_a), tabs); only_ref <- setdiff(tables_of(sch_ref), tabs)
rows <- list()
for (w in wsgs) for (t in tabs) {
  da <- digest(sch_a, t, w); dr <- digest(sch_ref, t, w)
  row <- data.frame(wsg = w, table = t, n_a = da$n, n_ref = dr$n,
                    identical = identical(da$d, dr$d), identical_without_id = NA)
  if (t == "barriers") {
    row$identical_without_id <- identical(digest(sch_a, t, w, "id_barrier")$d,
                                          digest(sch_ref, t, w, "id_barrier")$d)
  }
  rows[[length(rows) + 1L]] <- row
  cat(sprintf("%s %-24s %8d %8d %s\n", w, t, da$n, dr$n, if (row$identical) "identical" else "DIFFERS"))
}
res <- do.call(rbind, rows)
write.csv(res, file.path(out, "split_test.csv"), row.names = FALSE)

# The control: the compare must be able to see a change.
ctl <- NA
if (schema_exists(sch_ctl)) {
  w0 <- wsgs[1]
  ctl <- !identical(digest(sch_a, "streams_access", w0)$d, digest(sch_ctl, "streams_access", w0)$d)
}

diff_rows <- res[!res$identical, ]
summ <- c(
  sprintf("schemas: %s (split, recomputed) vs %s (reference); %d groups x %d tables = %d digests",
          sch_a, sch_ref, length(wsgs), length(tabs), nrow(res)),
  sprintf("identical: %d of %d; differing: %d", sum(res$identical), nrow(res), nrow(diff_rows)),
  sprintf("tables only in %s: %s; only in %s: %s", sch_a,
          if (length(only_a)) paste(only_a, collapse = ", ") else "none",
          sch_ref, if (length(only_ref)) paste(only_ref, collapse = ", ") else "none"),
  sprintf("control (%s, another link version, %s streams_access): %s", sch_ctl, wsgs[1],
          if (is.na(ctl)) "schema absent, NOT RUN" else if (ctl) "differs, as it must" else "IDENTICAL: the compare cannot see a change"))
if (nrow(diff_rows)) {
  summ <- c(summ, "differing (wsg table n_a n_ref):",
            sprintf("  %s %s %d %d", diff_rows$wsg, diff_rows$table, diff_rows$n_a, diff_rows$n_ref))
  # Column-level diff for the first differing id_segment-keyed table.
  keyed <- vapply(diff_rows$table, order_of, character(1)) == "id_segment"
  first <- diff_rows[keyed, ][1, ]
  if (!is.na(first$table)) {
    cols_of <- function(sch) q("SELECT column_name FROM information_schema.columns
                WHERE table_schema = '%s' AND table_name = '%s' AND column_name NOT IN ('id_segment','watershed_group_code')
                ORDER BY column_name", sch, first$table)$column_name
    cols <- intersect(cols_of(sch_a), cols_of(sch_ref))   # a column one side lacks is itself a difference, reported above
    per_col <- q("SELECT %s FROM %s.%s a JOIN %s.%s r USING (id_segment, watershed_group_code)
                   WHERE a.watershed_group_code = '%s'",
                 paste(sprintf("count(*) FILTER (WHERE a.%1$s IS DISTINCT FROM r.%1$s) AS %1$s", cols), collapse = ", "),
                 sch_a, first$table, sch_ref, first$table, first$wsg)
    per_col <- data.frame(column = names(per_col),   # one integer64 per column; coerce each on its own
                          segments_differing = vapply(per_col, function(v) as.integer(v[[1]]), integer(1)))
    per_col <- per_col[per_col$segments_differing > 0, ]
    f <- file.path(out, sprintf("split_test_diff_%s_%s.csv", first$table, first$wsg))
    write.csv(per_col, f, row.names = FALSE)
    summ <- c(summ, sprintf("column diff of %s %s: %s", first$table, first$wsg, f),
              sprintf("  %s: %d", per_col$column, per_col$segments_differing))
  }
}
writeLines(summ, file.path(out, "split_test_summary.txt"))
cat(summ, sep = "\n")
dbDisconnect(conn)

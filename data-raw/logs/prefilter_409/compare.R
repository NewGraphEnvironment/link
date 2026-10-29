# compare.R — link#409 Phase 3: digest every persisted table of each group in
# fresh_409b (fresh v0.44.0) and fresh_409a (fresh v0.46.0), built by
# model_run.sh from one worktree on one host. Digest function from
# data-raw/logs/provincial_prep_367/compare.R: every column, geometry as EWKB,
# rows in a fixed order. Writes model_digests.csv.
#   Rscript compare.R <out_dir>
suppressPackageStartupMessages({ library(DBI); library(RPostgres) })
out <- commandArgs(trailingOnly = TRUE)[1]
stopifnot(!is.na(out), dir.exists(out))
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
digest <- function(sch, tbl, wsg) {
  cols <- q(sprintf("SELECT column_name, udt_name FROM information_schema.columns
                      WHERE table_schema = '%s' AND table_name = '%s' ORDER BY column_name", sch, tbl))
  expr <- ifelse(cols$udt_name == "geometry", sprintf("md5(ST_AsEWKB(%s))", cols$column_name), cols$column_name)
  ord <- switch(tbl,
    streams = "blue_line_key, downstream_route_measure",
    barriers = "barrier_source, blue_line_key, downstream_route_measure, barrier_subtype, id_barrier",
    "id_segment")
  q(sprintf("SELECT count(*) AS n, md5(string_agg(md5(ROW(%s)::text), '' ORDER BY %s)) AS d
               FROM %s.%s WHERE watershed_group_code = '%s'",
            paste(expr, collapse = ", "), ord, sch, tbl, wsg))
}
a <- "fresh_409b"; b <- "fresh_409a"
# Each build's own log row names the fresh it ran with, read inside that
# process; refuse unless every group in each schema has the expected one.
want <- c(fresh_409b = "0.44.0", fresh_409a = "0.46.0")
prov <- do.call(rbind, lapply(names(want), function(s) cbind(schema = s, q(sprintf(
  "SELECT watershed_group_code AS wsg, fresh_version, fresh_sha, link_sha, link_dirty
     FROM %s.log l WHERE date_start = (SELECT max(date_start) FROM %s.log l2
       WHERE l2.watershed_group_code = l.watershed_group_code)", s, s)))))
write.csv(prov, file.path(out, "model_provenance.csv"), row.names = FALSE)
print(prov)
stopifnot(nrow(prov) == 6L, all(prov$fresh_version == want[prov$schema]),
          length(unique(prov$link_sha)) == 1L, !any(prov$link_dirty))
ta <- tables_of(a); tb <- tables_of(b)
if (!identical(ta, tb)) stop("table sets differ: ", paste(setdiff(union(ta, tb), intersect(ta, tb)), collapse = ", "))
rows <- list()
for (w in c("ADMS", "NATR", "ELKR")) for (t in ta) {
  da <- digest(a, t, w); db <- digest(b, t, w)
  rows[[length(rows) + 1L]] <- data.frame(wsg = w, table = t, n_044 = da$n, n_046 = db$n,
                                          identical = identical(da$d, db$d))
}
res <- do.call(rbind, rows)
# A table with no rows for a group digests NA on both sides; say so, not "identical".
res$identical[res$n_044 == 0 & res$n_046 == 0] <- NA
write.csv(res, file.path(out, "model_digests.csv"), row.names = FALSE)
print(res)
cat(sprintf("%d of %d group-tables identical, %d empty on both sides, %d differ\n",
            sum(res$identical, na.rm = TRUE), nrow(res), sum(is.na(res$identical)),
            sum(!res$identical, na.rm = TRUE)))

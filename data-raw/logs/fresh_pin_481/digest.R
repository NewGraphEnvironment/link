#!/usr/bin/env Rscript
# digest.R — digest every persisted table of a scratch schema per group, for
# #481's before/after comparison of the fresh pin (0.52.0 to 0.55.1).
#
# Every base table but the log tables, grouped by watershed_group_code. Each
# row is digested as the text of its columns in name order (so the new column's
# place in the table cannot move a digest), and each table twice: `md5_all`
# over every column, `md5_old` leaving out the columns #481 adds
# (`streams_near_river.linear_feature_id`). compare.R reads `md5_old` across the
# two steps and `md5_all` within one.
#
# Usage (from the repo root, any checkout; reads only the database):
#   Rscript data-raw/logs/fresh_pin_481/digest.R <schema> <out csv>
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L, grepl("^fresh_pin481_[a-z_]+$", args[1]))
schema <- args[1]
out <- args[2]
added <- list(streams_near_river = "linear_feature_id")

conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg",
                       host = "localhost", port = 5432L,
                       user = "postgres", password = "postgres")
on.exit(DBI::dbDisconnect(conn), add = TRUE)
q <- function(sql) DBI::dbGetQuery(conn, sql)

cols <- q(sprintf(
  "SELECT c.table_name, c.column_name
   FROM information_schema.columns c
   JOIN information_schema.tables t USING (table_schema, table_name)
   WHERE c.table_schema = '%s' AND t.table_type = 'BASE TABLE'
     AND c.table_name NOT LIKE 'log%%'", schema))
tables <- sort(unique(cols$table_name), method = "radix")
stopifnot(length(tables) > 0L)

dig <- function(tb, cn) {
  cn <- sort(cn, method = "radix")
  row <- sprintf("row(%s)::text", paste0("t.", cn, collapse = ", "))
  q(sprintf(
    "SELECT watershed_group_code AS wsg, count(*)::int AS n,
            md5(string_agg(%1$s, '|' ORDER BY %1$s COLLATE \"C\")) AS md5
     FROM %2$s.%3$s t GROUP BY 1 ORDER BY 1", row, schema, tb))
}

res <- lapply(tables, function(tb) {
  cn <- cols$column_name[cols$table_name == tb]
  if (!"watershed_group_code" %in% cn) return(NULL)
  a <- dig(tb, cn)
  if (nrow(a) == 0L) return(NULL)
  o <- dig(tb, setdiff(cn, added[[tb]]))
  stopifnot(identical(a$wsg, o$wsg), identical(a$n, o$n))
  data.frame(table = tb, wsg = a$wsg, n = a$n, md5_all = a$md5,
             md5_old = o$md5, cols = length(cn))
})
d <- do.call(rbind, res)
utils::write.csv(d, out, row.names = FALSE)
message(sprintf("[digest] %s: %d tables, %d rows -> %s", schema,
                length(unique(d$table)), nrow(d), out))

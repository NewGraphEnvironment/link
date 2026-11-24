#!/usr/bin/env Rscript
# digest.R — digest every persisted table of a scratch schema per group, for
# #507's before/after comparison of the fresh pin (0.55.1 to 0.56.0).
#
# Every base table but the log tables, grouped by watershed_group_code, each
# row digested as the text of its columns in name order. Adapted from
# data-raw/logs/fresh_pin_481/digest.R; no column is added at this pin, so
# one digest per table covers every column.
#
# Usage (from the repo root, any checkout; reads only the database):
#   Rscript data-raw/logs/fresh_pin_507/digest.R <schema> <out csv>
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L, grepl("^fresh_pin507_[a-z_]+$", args[1]))
schema <- args[1]
out <- args[2]

conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg",
                       host = "localhost", port = 5432L,
                       user = "postgres", password = "postgres")
q <- function(sql) DBI::dbGetQuery(conn, sql)

cols <- q(sprintf(
  "SELECT c.table_name, c.column_name
   FROM information_schema.columns c
   JOIN information_schema.tables t USING (table_schema, table_name)
   WHERE c.table_schema = '%s' AND t.table_type = 'BASE TABLE'
     AND c.table_name NOT LIKE 'log%%'", schema))
tables <- sort(unique(cols$table_name), method = "radix")
stopifnot(length(tables) > 0L)

res <- lapply(tables, function(tb) {
  cn <- sort(cols$column_name[cols$table_name == tb], method = "radix")
  if (!"watershed_group_code" %in% cn) return(NULL)
  row <- sprintf("row(%s)::text", paste0("t.", cn, collapse = ", "))
  d <- q(sprintf(
    "SELECT watershed_group_code AS wsg, count(*)::int AS n,
            md5(string_agg(%1$s, '|' ORDER BY %1$s COLLATE \"C\")) AS md5
     FROM %2$s.%3$s t GROUP BY 1 ORDER BY 1", row, schema, tb))
  if (nrow(d) == 0L) return(NULL)
  data.frame(table = tb, wsg = d$wsg, n = d$n, md5 = d$md5, cols = length(cn))
})
d <- do.call(rbind, res)
tok <- q(sprintf(
  "SELECT watershed_group_code AS wsg, token_cut, token_acc, token_grad, token_flow
   FROM %s.log WHERE date_end IS NOT NULL ORDER BY 1", schema))
DBI::dbDisconnect(conn)
utils::write.csv(d, out, row.names = FALSE)
utils::write.csv(tok, sub("\\.csv$", "_tokens.csv", out), row.names = FALSE)
message(sprintf("[digest] %s: %d tables, %d rows -> %s", schema,
                length(unique(d$table)), nrow(d), out))

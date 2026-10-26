#!/usr/bin/env Rscript
# ab_compare.R — link#374: the same groups built twice, once with the early
# recompute (schema a) and once with --recompute-at-end (schema b). Every
# group's streams_access, streams_mapping_code and gated habitat flags must
# match row for row. Floating columns are compared after rounding to 6
# decimals; geometry is left out.
#
# Usage: Rscript ab_compare.R <schema a> <schema b> <groups csv> [out.tsv]
args <- commandArgs(trailingOnly = TRUE)
a <- args[1]; b <- args[2]
groups <- toupper(strsplit(args[3], ",", fixed = TRUE)[[1]])
out <- if (length(args) >= 4L) args[4] else ""
conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                       port = 5432L, user = "postgres", password = "postgres")
q <- function(sql) DBI::dbGetQuery(conn, sql)
lit <- function(v) paste(DBI::dbQuoteString(conn, v), collapse = ",")
tabs <- q(sprintf("SELECT table_name FROM information_schema.tables
  WHERE table_schema = %s AND table_type = 'BASE TABLE'
    AND (table_name IN ('streams_access', 'streams_mapping_code')
         OR table_name LIKE 'streams_habitat\\_%%')
  ORDER BY 1", DBI::dbQuoteString(conn, a)))$table_name
flags <- c("accessible", "spawning", "rearing", "lake_rearing", "wetland_rearing")
res <- do.call(rbind, lapply(tabs, function(t) {
  cols <- q(sprintf("SELECT column_name, data_type FROM information_schema.columns
    WHERE table_schema = %s AND table_name = %s ORDER BY ordinal_position",
    DBI::dbQuoteString(conn, a), DBI::dbQuoteString(conn, t)))
  cols <- cols[cols$data_type != "USER-DEFINED", ]
  if (grepl("^streams_habitat_", t)) {
    cols <- cols[cols$column_name %in% c("id_segment", "watershed_group_code", flags), ]
  }
  sel <- ifelse(cols$data_type %in% c("double precision", "real", "numeric"),
                sprintf("round(%s::numeric, 6) AS %s", cols$column_name, cols$column_name),
                cols$column_name)
  sel <- paste(sel, collapse = ", ")
  w <- sprintf("watershed_group_code IN (%s)", lit(groups))
  r <- q(sprintf(
    "WITH x AS (SELECT %1$s FROM %2$s.%4$s WHERE %5$s),
          y AS (SELECT %1$s FROM %3$s.%4$s WHERE %5$s)
     SELECT (SELECT count(*) FROM x) n_a, (SELECT count(*) FROM y) n_b,
            (SELECT count(*) FROM (SELECT * FROM x EXCEPT ALL SELECT * FROM y) d) only_a,
            (SELECT count(*) FROM (SELECT * FROM y EXCEPT ALL SELECT * FROM x) d) only_b",
    sel, a, b, t, w))
  data.frame(table = t, r)
}))
DBI::dbDisconnect(conn)
print(res, row.names = FALSE)
if (nzchar(out)) utils::write.table(res, out, sep = "\t", quote = FALSE, row.names = FALSE)
acc <- if (is.null(res)) NULL else res[res$table == "streams_access", ]
if (is.null(acc) || nrow(acc) != 1L || acc$n_a == 0L) {
  stop("nothing compared: no streams_access rows for these groups in ", a, call. = FALSE)
}
same <- all(res$n_a == res$n_b & res$only_a == 0 & res$only_b == 0)
cat(sprintf("%s vs %s over %d groups: %s\n", a, b, length(groups),
            if (same) "identical" else "DIFFERENT"))
quit(status = if (same) 0 else 1)

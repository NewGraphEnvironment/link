#!/usr/bin/env Rscript
# final_equal.R — FINAL (the branch head) against AFTER-386, for link#479's
# #236 and #341 halves: with no further lift rule declared and the barrier
# rules reproducing the status, every persisted model table digests equal per
# group. The evidence table is compared on AFTER-386's columns, holding FINAL's
# rows with lift_rule own or habitat; the log tables are left out. Also asserts
# that FINAL's crossings carry barrier_rule_id on exactly the crossings the
# status predicate selects, in every group's kept working schema, so the rules
# helper ran and agreed (a helper that never ran would leave the column off).
#
# Usage: Rscript final_equal.R <after schema> <final schema> <final working prefix> <out csv>
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 4L)
sa <- args[[1]]; sf <- args[[2]]; pf <- args[[3]]; out <- args[[4]]
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
q <- function(sql) DBI::dbGetQuery(conn, sql)
groups <- q(sprintf("SELECT DISTINCT watershed_group_code AS w FROM %s.log
                      WHERE date_end IS NOT NULL ORDER BY 1", sf))$w
tables <- q(sprintf(
  "SELECT table_name FROM information_schema.tables
    WHERE table_schema = '%s' AND table_type = 'BASE TABLE'
      AND table_name NOT LIKE 'log%%' ORDER BY 1", sa))$table_name
cols_of <- function(s, t) q(sprintf(
  "SELECT column_name FROM information_schema.columns
    WHERE table_schema = '%s' AND table_name = '%s' ORDER BY ordinal_position",
  s, t))$column_name
dig <- function(s, t, w, cols, where = "TRUE") {
  q(sprintf(
    "SELECT md5(coalesce(string_agg(r, E'\\n' ORDER BY r), '')) AS d, count(*)::int AS n
       FROM (SELECT ROW(%s)::text AS r FROM %s.%s
              WHERE watershed_group_code = '%s' AND %s) t",
    paste(cols, collapse = ", "), s, t, w, where))
}
rows <- list()
for (t in tables) {
  cols <- cols_of(sa, t)
  if (!"watershed_group_code" %in% cols) next
  where_f <- if (t == "barrier_override_evidence") {
    "lift_rule IN ('own', 'habitat')"
  } else "TRUE"
  for (w in groups) {
    a <- dig(sa, t, w, cols); f <- dig(sf, t, w, cols, where_f)
    rows[[length(rows) + 1L]] <- data.frame(
      table = t, wsg = w, n_after = a$n, n_final = f$n, equal = a$d == f$d)
  }
}
res <- do.call(rbind, rows)
marker <- do.call(rbind, lapply(groups, function(w) {
  s <- paste0(pf, tolower(w))
  m <- q(sprintf(
    "SELECT count(*)::int AS crossings,
            count(*) FILTER (WHERE barrier_rule_id IS NOT NULL)::int AS marked,
            count(*) FILTER (WHERE (barrier_rule_id IS NOT NULL) IS DISTINCT FROM
                                   (barrier_status IN ('BARRIER', 'POTENTIAL')))::int AS disagree
       FROM %s.crossings", s))
  cbind(wsg = w, m)
}))
write.csv(res, out, row.names = FALSE)
write.csv(marker, sub("\\.csv$", "_marker.csv", out), row.names = FALSE)
print(aggregate(equal ~ table, res, function(x) sprintf("%d/%d", sum(x), length(x))))
print(marker)
bad <- sum(!res$equal) + sum(marker$disagree) + sum(marker$crossings == 0L)
if (bad > 0L) {
  print(res[!res$equal, ])
  cat("STOP: FINAL differs from AFTER-386, or the marker disagrees\n")
  quit(status = 1)
}
cat("OK: FINAL equals AFTER-386 in every persisted model table, and the marker sits on the status set\n")

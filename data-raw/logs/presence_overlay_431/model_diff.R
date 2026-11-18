suppressMessages(library(DBI))
conn <- dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost", port = 5432L, user = "postgres", password = "postgres")
tabs <- function(s) dbGetQuery(conn, sprintf("SELECT table_name FROM information_schema.tables WHERE table_schema = '%s' AND table_type = 'BASE TABLE' AND table_name NOT LIKE 'log%%' ORDER BY 1", s))$table_name
tm <- tabs("zz472_main"); th <- tabs("zz472_head")
cat("tables only main:", setdiff(tm, th), " only head:", setdiff(th, tm), "\n")
out <- list()
for (t in intersect(tm, th)) {
  has_w <- "watershed_group_code" %in% dbGetQuery(conn, sprintf("SELECT column_name FROM information_schema.columns WHERE table_schema='zz472_main' AND table_name='%s'", t))$column_name
  for (w in if (has_w) c("ADMS", "BULK", "GUIC") else "ALL") {
    q <- function(s) dbGetQuery(conn, sprintf("SELECT count(*)::int n, md5(coalesce(string_agg(x, '|' ORDER BY x), '')) h FROM (SELECT t::text x FROM %s.%s t %s) z", s, t, if (has_w) sprintf("WHERE watershed_group_code = '%s'", w) else ""))
    a <- q("zz472_main"); b <- q("zz472_head")
    out[[length(out) + 1]] <- data.frame(table = t, wsg = w, n_main = a$n, n_head = b$n, same = a$h == b$h)
  }
}
r <- do.call(rbind, out); print(r[!r$same, ]); cat("compared", nrow(r), "table x group pairs;", sum(r$same), "identical\n")
write.csv(r, file.path(commandArgs(TRUE)[1], "diff472.csv"), row.names = FALSE)

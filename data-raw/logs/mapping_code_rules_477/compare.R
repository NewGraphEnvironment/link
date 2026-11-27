# data-raw/logs/mapping_code_rules_477/compare.R
#
# Compares digests_before.csv and digests_after.csv (parity.R) per schema,
# group and mapping-code column, and counts persisted access_<sp> = -9 in
# each schema (the #351 merge change persisted nothing if every count is 0).
# Writes compare.csv and minus9.csv beside them.
#
#   Rscript data-raw/logs/mapping_code_rules_477/compare.R

d <- "data-raw/logs/mapping_code_rules_477"
a <- utils::read.csv(file.path(d, "digests_before.csv"), stringsAsFactors = FALSE)
b <- utils::read.csv(file.path(d, "digests_after.csv"), stringsAsFactors = FALSE)
m <- merge(a, b, by = c("config", "schema", "wsg", "column"), all = TRUE,
           suffixes = c("_before", "_after"))
m$same <- !is.na(m$md5_before) & !is.na(m$md5_after) &
  m$md5_before == m$md5_after & m$n_before == m$n_after
utils::write.csv(m[, c("config", "schema", "wsg", "column", "n_before",
                       "n_after", "same")],
                 file.path(d, "compare.csv"), row.names = FALSE)
cat(sprintf("[compare] %d of %d digests identical (before %s, after %s)\n",
            sum(m$same), nrow(m), a$link_sha[1], b$link_sha[1]))

conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg",
                       host = "localhost", port = 5432L,
                       user = "postgres", password = "postgres")
on.exit(DBI::dbDisconnect(conn), add = TRUE)
rows <- list()
for (s in c("fresh_default", "fresh")) {
  cols <- DBI::dbGetQuery(conn, sprintf(
    "SELECT column_name FROM information_schema.columns
      WHERE table_schema = %s AND table_name = 'streams_access'
        AND column_name ~ '^access_[a-z]+$' ORDER BY column_name",
    DBI::dbQuoteString(conn, s)))$column_name
  for (col in cols) {
    n <- DBI::dbGetQuery(conn, sprintf(
      "SELECT count(*)::int AS n FROM %s.streams_access WHERE %s = -9",
      s, col))$n
    rows[[length(rows) + 1L]] <- data.frame(schema = s, column = col, n_minus9 = n)
  }
}
m9 <- do.call(rbind, rows)
utils::write.csv(m9, file.path(d, "minus9.csv"), row.names = FALSE)
cat(sprintf("[compare] access_<sp> = -9: %d rows over %d columns in %s\n",
            sum(m9$n_minus9), nrow(m9), paste(unique(m9$schema), collapse = ", ")))

#!/usr/bin/env Rscript
# headroom_setup.R — link#374: a scratch schema the headroom benchmark can
# recompute in without touching fresh_default. Holds the recompute groups'
# persisted rows and EVERY group's barriers and barrier_overrides, so their
# downstream walks see the whole province, as on a real run.
#
# Usage (repo root): Rscript data-raw/logs/recompute_early_374/headroom_setup.R \
#                      <scratch schema> <groups csv> [source schema] [config]
args <- commandArgs(trailingOnly = TRUE)
dest   <- args[1]
groups <- toupper(strsplit(args[2], ",", fixed = TRUE)[[1]])
src    <- if (length(args) >= 3L) args[3] else "fresh_default"
config <- if (length(args) >= 4L) args[4] else "default"
stopifnot(grepl("^fresh_374", dest), dest != src)

suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                       port = 5432L, user = "postgres", password = "postgres")
cfg <- lnk_config(config)
cfg$pipeline$schema <- dest
DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", dest))
lnk_persist_init(conn, cfg, species = cfg$species)

tabs <- DBI::dbGetQuery(conn, sprintf(
  "SELECT c.table_name FROM information_schema.columns c
   JOIN information_schema.tables t USING (table_schema, table_name)
   WHERE c.table_schema = %s AND c.column_name = 'watershed_group_code'
     AND t.table_type = 'BASE TABLE' AND c.table_name NOT LIKE 'log%%'
   ORDER BY 1", DBI::dbQuoteString(conn, dest)))$table_name
in_list <- paste(DBI::dbQuoteString(conn, groups), collapse = ",")
for (t in tabs) {
  have <- DBI::dbGetQuery(conn, sprintf(
    "SELECT 1 FROM information_schema.tables WHERE table_schema = %s AND table_name = %s",
    DBI::dbQuoteString(conn, src), DBI::dbQuoteString(conn, t)))
  if (nrow(have) == 0L) next
  cols <- intersect(
    DBI::dbGetQuery(conn, sprintf("SELECT column_name FROM information_schema.columns
      WHERE table_schema = %s AND table_name = %s ORDER BY ordinal_position",
      DBI::dbQuoteString(conn, dest), DBI::dbQuoteString(conn, t)))$column_name,
    DBI::dbGetQuery(conn, sprintf("SELECT column_name FROM information_schema.columns
      WHERE table_schema = %s AND table_name = %s",
      DBI::dbQuoteString(conn, src), DBI::dbQuoteString(conn, t)))$column_name)
  where <- if (t %in% c("barriers", "barrier_overrides")) "" else
    sprintf(" WHERE watershed_group_code IN (%s)", in_list)
  n <- DBI::dbExecute(conn, sprintf("INSERT INTO %s.%s (%s) SELECT %s FROM %s.%s%s",
    dest, t, paste(cols, collapse = ", "), paste(cols, collapse = ", "), src, t, where))
  cat(sprintf("%-32s %9d rows\n", t, n))
}
DBI::dbExecute(conn, sprintf("ANALYZE %s.barriers", dest))
DBI::dbExecute(conn, sprintf("ANALYZE %s.barrier_overrides", dest))
DBI::dbDisconnect(conn)
cat("=== headroom setup done\n")

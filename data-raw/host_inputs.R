#!/usr/bin/env Rscript
# host_inputs.R — print what this host loaded for each snapshot primitive, for
# study_area_run.sh's pre-flight to compare across hosts before any write
# (link#276).
#
# Byte-identical invocation on the dispatcher and on every remote host. Plain
# SQL over DBI, no link: the rows are read the same way whatever link a host
# runs. Connects to the LOCAL docker fwapg explicitly (#222, as host_vintage.R).
#
# Prints a header and one tab-separated row per table: the newest `loader` row
# in provenance.source_artifact (table_name, version_id, content_md5, n_rows,
# loaded_at, notes); empty fields where a value is absent. A table never loaded
# prints no row, which the comparison reads as missing. Exit 1 when the table
# cannot be read.
#
# Usage: Rscript data-raw/host_inputs.R

suppressPackageStartupMessages({
  library(DBI)
  library(RPostgres)
})
tables <- c("bcfishobs.observations", "cabd.dams", "fresh.modelled_stream_crossings",
            "whse_fish.pscis_assessment_svw")
conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                       port = 5432L, user = "postgres", password = "postgres")
present <- !is.na(DBI::dbGetQuery(conn,
  "SELECT to_regclass('provenance.source_artifact')::text AS t")$t)
rows <- if (present) {
  # content_md5 through to_jsonb: a table from before link#465 has no such column.
  DBI::dbGetQuery(conn, sprintf(
    "SELECT DISTINCT ON (table_name) table_name,
            coalesce(version_id, '') AS version_id,
            coalesce(to_jsonb(a) ->> 'content_md5', '') AS content_md5,
            coalesce(n_rows::text, '') AS n_rows,
            coalesce(to_char(loaded_at AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"'), '') AS loaded_at,
            coalesce(replace(replace(notes, E'\\t', ' '), E'\\n', ' '), '') AS notes
       FROM provenance.source_artifact a
      WHERE recorded_by = 'loader' AND table_name IN (%s)
      ORDER BY table_name, loaded_at DESC NULLS LAST",
    paste0("'", tables, "'", collapse = ", ")))
} else {
  data.frame(table_name = character(), version_id = character(), content_md5 = character(),
             n_rows = character(), loaded_at = character(), notes = character())
}
DBI::dbDisconnect(conn)
utils::write.table(rows, stdout(), sep = "\t", quote = FALSE, row.names = FALSE, na = "")

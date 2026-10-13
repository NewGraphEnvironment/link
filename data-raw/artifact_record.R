#!/usr/bin/env Rscript
# artifact_record.R — snapshot_bcfp.sh's writer for fresh.log_source_artifact
# (link#265). Two modes:
#
#   Rscript data-raw/artifact_record.R --clear
#       Before any load: delete this host's `loader` rows for the snapshot
#       primitives. A snapshot that dies half way then leaves those tables
#       UNSTAMPED, which the vintage gate fails on, instead of leaving a row
#       that names a version the database no longer holds.
#
#   Rscript data-raw/artifact_record.R --probe
#       After the loads: HEAD the FWA primitives' artifacts and record what is
#       current now (recorded_by = 'probe' -- weaker, and labelled weaker;
#       fwapg's load.sh records nothing itself, link#270). snapshot_bcfp.sh
#       treats a failure here as a warning: the FWA tables were not loaded by
#       the snapshot, so a probe failure says nothing about what it loaded.
#
#   Rscript data-raw/artifact_record.R <manifest.tsv>
#       After the loads: record each manifest row with recorded_by = 'loader'.
#       Manifest columns (tab-separated, unquoted, header row):
#       table_name url version_id etag last_modified loaded_at notes
#       last_modified is an HTTP date; loaded_at is ISO-8601 UTC (...Z).
#
# Exits non-zero on any failure: provenance is the point of the call, so a
# snapshot that cannot record what it loaded has failed.
#
# Connection comes from DATABASE_URL in the ENVIRONMENT (never argv, which
# `ps` shows), as postgres[ql]://user:pass@host[:port]/dbname. RPostgres does
# not expand a URI given as dbname, so it is parsed here.
#
# Loads the source tree with pkgload when run from a link checkout, so the
# writer matches the checkout snapshot_bcfp.sh came from; otherwise the
# installed package.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
  stop("usage: artifact_record.R --clear | --probe | <manifest.tsv>",
       call. = FALSE)
}

desc <- "DESCRIPTION"
from_source <- file.exists(desc) &&
  identical(unname(read.dcf(desc, fields = "Package")[1, 1]), "link") &&
  requireNamespace("pkgload", quietly = TRUE)
if (from_source) {
  suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
} else {
  suppressPackageStartupMessages(library(link))
}
cat(sprintf("artifact_record: link %s (%s)\n",
            utils::packageVersion("link"),
            if (from_source) "source tree" else "installed"))

url <- Sys.getenv("DATABASE_URL", "")
m <- regmatches(url, regexec(
  "^postgres(ql)?://([^:@/]+)(:([^@]*))?@([^:/]+)(:([0-9]+))?/([^?]+)", url))[[1]]
if (length(m) == 0L) {
  stop("DATABASE_URL is unset or not postgres[ql]://user:pass@host[:port]/db",
       call. = FALSE)
}
conn <- DBI::dbConnect(
  RPostgres::Postgres(),
  user = utils::URLdecode(m[3]),
  password = utils::URLdecode(m[5]),
  host = m[6],
  port = if (nzchar(m[8])) as.integer(m[8]) else 5432L,
  dbname = utils::URLdecode(m[9]))

# The same set the vintage gate judges, from the same dictionary: a second
# copy here would let a new primitive be gated but never cleared or checked.
snapshot_tables <- link:::.lnk_vintage_primitives()

if (identical(args[1], "--clear")) {
  link:::.lnk_artifact_create(conn)
  n <- DBI::dbExecute(conn, sprintf(
    "DELETE FROM %s WHERE host = %s AND recorded_by = 'loader'
        AND table_name IN (%s)",
    link:::.lnk_artifact_table(),
    DBI::dbQuoteLiteral(conn, link:::.lnk_host()),
    paste(vapply(snapshot_tables, function(t)
      as.character(DBI::dbQuoteLiteral(conn, t)), character(1)),
      collapse = ", ")))
  cat(sprintf("artifact_record: cleared %d loader rows for host %s\n",
              n, link:::.lnk_host()))
  DBI::dbDisconnect(conn)
  quit(status = 0L)
}

if (identical(args[1], "--probe")) {
  lnk_artifact_probe(conn)
  DBI::dbDisconnect(conn)
  quit(status = 0L)
}

man <- utils::read.delim(args[1], quote = "", na.strings = "",
                         comment.char = "", colClasses = "character")
need <- c("table_name", "url", "version_id", "etag", "last_modified",
          "loaded_at", "notes")
if (!all(need %in% names(man))) {
  stop("manifest lacks columns: ",
       paste(setdiff(need, names(man)), collapse = ", "), call. = FALSE)
}
if (!setequal(man$table_name, snapshot_tables)) {
  stop("manifest does not cover exactly the snapshot primitives; has: ",
       paste(man$table_name, collapse = ", "), call. = FALSE)
}
# last_modified stays the raw HTTP date; lnk_artifact_record() parses it.
man$loaded_at <- as.POSIXct(man$loaded_at, format = "%Y-%m-%dT%H:%M:%SZ",
                            tz = "UTC")
if (anyNA(man$loaded_at)) stop("manifest has an unparseable loaded_at",
                               call. = FALSE)

lnk_artifact_record(conn, man, recorded_by = "loader")
# Read back rather than trusting the INSERT: the snapshot is only recorded if
# every one of its primitives has a loader row for this host now.
out <- DBI::dbGetQuery(conn, sprintf(
  "SELECT table_name, version_id, etag, last_modified, n_rows, loaded_at
     FROM %s WHERE host = %s AND recorded_by = 'loader'
    ORDER BY table_name",
  link:::.lnk_artifact_table(), DBI::dbQuoteLiteral(conn, link:::.lnk_host())))
out <- out[out$table_name %in% snapshot_tables, , drop = FALSE]
print(out, row.names = FALSE)
DBI::dbDisconnect(conn)
missing <- setdiff(snapshot_tables, out$table_name)
if (length(missing)) {
  stop("snapshot primitives left unrecorded: ",
       paste(missing, collapse = ", "), call. = FALSE)
}
# A version id with no Last-Modified means a header was lost between the
# HEAD and the record -- the defect the first live run had.
lost <- out$table_name[!is.na(out$version_id) & is.na(out$last_modified)]
if (length(lost)) {
  stop("recorded a version id without its Last-Modified: ",
       paste(lost, collapse = ", "), call. = FALSE)
}
cat("artifact_record: recorded", nrow(man), "loader rows\n")

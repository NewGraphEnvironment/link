#!/usr/bin/env Rscript
# build_minutes_append.R — append one run's build minutes to the committed record
# (data-raw/logs/build_minutes.csv) the pre-run gate bounds its picks on (link#450).
#
#   Rscript data-raw/build_minutes_append.R --schema=<persist schema> --run-uid=<uid>
#
# One row per group the run finished: its newest finished `log` row under the run_uid
# (a group re-modelled inside the run keeps its last build), with the config, host and
# its speed class, the link and fresh SHAs, date_start in UTC and minutes rounded to two
# decimals. Rows already in the record (same config, group and run_uid) are left as they
# are, so running it twice adds nothing. The file is kept sorted by config, group and
# date_start, so a diff shows only what a run added.
#
# Why committed: minutes belong to a group on a host class, not to one schema on one
# host. A record in the repo reaches every host and a brand-new database, which a
# table in one database cannot (RUNBOOK section 8d, "The pre-run gate").

args <- commandArgs(trailingOnly = TRUE)
arg_val <- function(flag, default = "") {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (length(hit)) sub(paste0("^", flag, "="), "", hit[length(hit)]) else default
}
script_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))))
source(file.path(script_dir, "pretest.R"))
source(file.path(script_dir, "study_area_packing.R"))

schema <- arg_val("--schema")
run_uid <- arg_val("--run-uid")
path <- arg_val("--out", file.path(script_dir, "logs", "build_minutes.csv"))
if (!grepl("^[a-z_][a-z0-9_]*$", schema)) stop("--schema must be a bare schema name", call. = FALSE)
if (!grepl("^[A-Za-z0-9_.-]+$", run_uid)) stop("--run-uid is required (letters, digits, _ . -)", call. = FALSE)

suppressPackageStartupMessages({
  library(DBI)
  library(RPostgres)
})
conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                       port = 5432L, user = "postgres", password = "postgres")
rows <- DBI::dbGetQuery(conn, sprintf(
  "SELECT DISTINCT ON (watershed_group_code)
          watershed_group_code AS wsg, config_name AS config, run_uid, host,
          link_sha, fresh_sha, date_start,
          extract(epoch FROM (date_end - date_start)) / 60 AS minutes
     FROM %s.log
    WHERE run_uid = $1 AND date_end IS NOT NULL AND date_start IS NOT NULL
    ORDER BY watershed_group_code, date_start DESC", schema), params = list(run_uid))
DBI::dbDisconnect(conn)
if (!nrow(rows)) stop(schema, ".log has no finished rows for run ", run_uid, call. = FALSE)
if (length(unique(rows$config)) != 1L) {
  stop("run ", run_uid, " holds more than one config: ", paste(unique(rows$config), collapse = ", "),
       call. = FALSE)
}
host_names_check(unique(rows$host))

new <- data.frame(
  wsg = rows$wsg, config = rows$config, run_uid = rows$run_uid, host = rows$host,
  host_class = host_class(rows$host),
  link_sha = ifelse(is.na(rows$link_sha), "", rows$link_sha),
  fresh_sha = ifelse(is.na(rows$fresh_sha), "", rows$fresh_sha),
  date_start = format(rows$date_start, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  minutes = sprintf("%.2f", rows$minutes), stringsAsFactors = FALSE)

old <- if (file.exists(path)) {
  utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character", na.strings = character())
} else {
  new[0, , drop = FALSE]
}
if (!identical(names(old), PRETEST_BUILD_MINUTES_COLS)) {
  stop(path, ": columns must be ", paste(PRETEST_BUILD_MINUTES_COLS, collapse = ","), call. = FALSE)
}
key <- function(d) paste(d$config, d$wsg, d$run_uid)
add <- new[!key(new) %in% key(old), , drop = FALSE]
all <- rbind(old, add)
all <- all[order(all$config, all$wsg, all$date_start, method = "radix"), , drop = FALSE]
utils::write.csv(all, path, row.names = FALSE, quote = FALSE)
# Read back through the gate's own reader, so a row it would refuse fails here.
invisible(pretest_build_minutes_read(path))
message(sprintf("%s: %d row(s) added from %s.log run %s (%s), %d already held; %d rows",
                path, nrow(add), schema, run_uid, new$config[1], nrow(new) - nrow(add), nrow(all)))

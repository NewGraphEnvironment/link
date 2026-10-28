#!/usr/bin/env Rscript
# pretest_check.R — does a pre-run gate record clear this run? (link#372)
# Called by study_area_run.sh's preflight_local().
#
#   Rscript data-raw/pretest_check.R --config=<bundle> --schema=<persist schema> \
#     --head=<sha> --fresh-sha=<installed fresh sha>
#
# Prints one line. Exit 0 when <schema>.log_pretest's newest record for the
# config clears HEAD (pretest_record_check() in pretest.R), 1 when it does not
# or there is none, 2 when the check itself could not run.

args <- commandArgs(trailingOnly = TRUE)
arg_val <- function(flag, default = "") {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (length(hit)) sub(paste0("^", flag, "="), "", hit[length(hit)]) else default
}
script_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))))
repo <- normalizePath(file.path(script_dir, ".."))
config <- arg_val("--config")
schema <- arg_val("--schema")
head_sha <- arg_val("--head")
fresh_sha <- arg_val("--fresh-sha")

out <- tryCatch({
  source(file.path(script_dir, "pretest.R"))
  if (!grepl("^[a-z_][a-z0-9_]*$", schema) || !nzchar(config) || !nzchar(head_sha)) {
    stop("needs --config, --schema and --head")
  }
  suppressPackageStartupMessages({
    library(DBI)
    library(RPostgres)
  })
  conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                         port = 5432L, user = "postgres", password = "postgres")
  on.exit(DBI::dbDisconnect(conn))
  reg <- function(t) !is.na(DBI::dbGetQuery(conn, sprintf("SELECT to_regclass('%s.%s')::text AS t",
                                                          schema, t))$t)
  if (!reg("log_pretest")) {
    list(ok = FALSE, why = sprintf("no gate record (%s.log_pretest does not exist)", schema))
  } else {
    records <- DBI::dbGetQuery(conn, sprintf("SELECT * FROM %s.log_pretest", schema))
    if (!reg("log")) stop(schema, ".log does not exist: no history to hold a gate to")
    hist <- DBI::dbGetQuery(conn, pretest_history_sql(schema, config))
    chain <- pretest_config_chain(file.path(repo, "inst/extdata/configs"), config)
    map <- pretest_map_read(file.path(script_dir, "pretest_inputs.csv"))
    r <- pretest_record_check(records, config, head_sha, fresh_sha, hist$link_sha,
                              hist$link_dirty, repo, map, chain,
                              reached = pretest_reach_repo(repo))
    if (r$ok) {
      r$why <- sprintf("gate passed at %s (%s UTC), range from %s: %s", substr(r$record$link_sha, 1, 12),
                       format(r$record$run_at, "%Y-%m-%d %H:%M", tz = "UTC"),
                       substr(r$record$since_sha, 1, 12), r$record$groups)
    }
    r
  }
}, error = function(e) list(ok = NA, why = conditionMessage(e)))

cat(out$why, "\n", sep = "")
quit(status = if (isTRUE(out$ok)) 0L else if (is.na(out$ok)) 2L else 1L)

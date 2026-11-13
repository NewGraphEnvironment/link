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
  # The record speaks for commits; a dispatcher leg models the working tree
  # (load_all), so uncommitted code is code no gate ran.
  dirty <- pretest_git(repo, c("status", "--porcelain", "--", ":(top,exclude)data-raw/logs"))
  suppressPackageStartupMessages({
    library(DBI)
    library(RPostgres)
  })
  conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                         port = 5432L, user = "postgres", password = "postgres")
  on.exit(DBI::dbDisconnect(conn))
  reg <- function(t) !is.na(DBI::dbGetQuery(conn, sprintf("SELECT to_regclass('%s.%s')::text AS t",
                                                          schema, t))$t)
  if (length(dirty)) {
    list(ok = FALSE, why = sprintf("the checkout has uncommitted changes (%s), which no gate ran",
                                   paste(utils::head(sub("^...", "", dirty), 3), collapse = ", ")))
  } else if (!reg("log_pretest")) {
    list(ok = FALSE, why = sprintf("no gate record (%s.log_pretest does not exist)", schema))
  } else {
    records <- DBI::dbGetQuery(conn, sprintf("SELECT * FROM %s.log_pretest", schema))
    chain <- pretest_config_chain(file.path(repo, "inst/extdata/configs"), config)
    own <- if (reg("log")) DBI::dbGetQuery(conn, pretest_history_sql(schema, config)) else NULL
    modelable <- pretest_modelable_groups(repo, config)
    # A bundle whose own builds do not yet cover it is held to the history its gate
    # borrowed, or, with no build of its own here, to none (an every-input gate, link#450).
    src <- pretest_record_history(records, schema, config, pretest_history_complete(own$wsg, modelable),
                                  chain, own_n = length(unique(own$wsg)))
    every_input <- isTRUE(src$every_input)
    hist <- if (!is.null(src) && !every_input) {
      DBI::dbGetQuery(conn, pretest_history_sql(src$schema, src$config))
    } else {
      data.frame(link_sha = character(), link_dirty = logical())
    }
    borrowed <- !is.null(src) && !identical(src$config, config)
    short <- if (borrowed) pretest_history_short(hist$wsg, modelable, paste0(src$schema, ".log")) else ""
    if (is.null(src)) {
      list(ok = FALSE, why = sprintf("%s does not cover the groups %s models, and its gate borrowed no history to hold it to",
                                     schema, config))
    } else if (nzchar(short)) {
      list(ok = FALSE, why = paste0("the gate borrowed a short history: ", short))
    } else {
      map <- pretest_map_read(file.path(script_dir, "pretest_inputs.csv"))
      r <- pretest_record_check(records, config, head_sha, fresh_sha, hist$link_sha,
                                hist$link_dirty, repo, map, chain,
                                reached = pretest_reach_repo(repo), every_input = every_input)
      # Beside a borrowed history, the bundle's own builds so far must be in the range too.
      own_why <- if (r$ok && borrowed) {
        pretest_own_builds_why(repo, r$record$since_sha, r$record$link_sha, own, schema)
      } else ""
      if (nzchar(own_why)) {
        r <- list(ok = FALSE, why = paste0("the gate's range: ", own_why), record = r$record)
      } else if (r$ok) {
        r$why <- sprintf("gate passed at %s (%s UTC), %s: %s", substr(r$record$link_sha, 1, 12),
                         format(r$record$run_at, "%Y-%m-%d %H:%M", tz = "UTC"),
                         if (every_input) "on every input (no history)" else
                           paste("range from", substr(r$record$since_sha, 1, 12)),
                         r$record$groups)
      }
      r
    }
  }
}, error = function(e) list(ok = NA, why = conditionMessage(e)))

cat(out$why, "\n", sep = "")
quit(status = if (isTRUE(out$ok)) 0L else if (is.na(out$ok)) 2L else 1L)

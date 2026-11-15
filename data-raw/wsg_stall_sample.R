#!/usr/bin/env Rscript
# wsg_stall_sample.R — watch one group's backend and record what it waits on
# while a statement runs past a threshold (link#487).
#
# Started by wsg_run_one.R beside each group (system2(wait = FALSE)), with the
# group's stdout, so its lines land in the same host log over every leg. While
# the group's backend has been on one statement longer than <after_s>, each
# check writes one `[wsg_stall] <WSG>\t...` line per backend (the statement,
# its parallel workers, the sessions blocking any of them); the driver splits
# them into <TS>_stall_<WSG>.tsv (study_area_finish.sh, run_stalls). It ends
# when the group's R process does, and it never fails the group: every error
# is one `[wsg_stall_error] <WSG>` line and exit 0.
#
# Usage: [LNK_LOAD=loadall] Rscript wsg_stall_sample.R <WSG> <backend pid> \
#          <parent R pid> <after_s> <every_s>

wsg <- "????"
tryCatch({
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) != 5L) stop("usage: wsg_stall_sample.R <WSG> <pid> <parent pid> <after_s> <every_s>")
  wsg <- args[1]
  num <- suppressWarnings(as.numeric(args[2:5]))
  if (anyNA(num)) stop("non-numeric argument: ", paste(args[2:5], collapse = " "))
  if (identical(Sys.getenv("LNK_LOAD"), "loadall")) {
    suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
  } else {
    suppressPackageStartupMessages(library(link))
  }
  conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                         port = 5432L, user = "postgres", password = "postgres",
                         application_name = "lnk_stall_sample", connect_timeout = 10)
  # PGOPTIONS carries the group's statement bound; the watch's own queries
  # are catalogue reads, so a tight bound of their own.
  DBI::dbExecute(conn, "SET statement_timeout = '10s'")
  DBI::dbExecute(conn, "SET lock_timeout = '5s'")
  link:::.lnk_stall_watch(conn, pid = as.integer(num[1]), parent_pid = as.integer(num[2]),
                          wsg = wsg, after_s = num[3], every_s = num[4])
  try(DBI::dbDisconnect(conn), silent = TRUE)
}, error = function(e) {
  cat(sprintf("[wsg_stall_error] %s %s\n",
              wsg, gsub("[[:space:]]+", " ", conditionMessage(e))))
})
quit(status = 0)

#!/usr/bin/env Rscript
# host_vintage.R — assert this host's snapshot primitives are recent enough.
#
# Byte-identical invocation on the dispatcher and on every cypher, the same
# host-agnostic contract as wsg_run_one.R. Exits 0 when every primitive is
# inside the window, 1 otherwise — including when a primitive has never been
# loaded, which is a failure and not a neutral (link#246).
#
# Connects to the LOCAL docker fwapg explicitly rather than through
# lnk_db_conn()'s env-var defaults, which resolve to the :63333 bcfp tunnel
# on some hosts — a different database with a different load state (#222).
#
# Usage: [LNK_LOAD=loadall] Rscript data-raw/host_vintage.R [max_age_days]
#   LNK_LOAD=loadall -> pkgload::load_all() (dispatcher dev checkout)
#   default          -> library(link)       (pak-installed, e.g. cyphers)

args <- commandArgs(trailingOnly = TRUE)
max_days <- if (length(args) >= 1L && nzchar(args[1])) {
  suppressWarnings(as.numeric(args[1]))
} else {
  7
}
if (is.na(max_days) || max_days <= 0) {
  stop("max_age_days must be a positive number (got '",
       if (length(args) >= 1L) args[1] else "", "')", call. = FALSE)
}

if (identical(Sys.getenv("LNK_LOAD"), "loadall")) {
  suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
} else {
  suppressPackageStartupMessages(library(link))
}
suppressPackageStartupMessages({
  library(DBI); library(RPostgres)
})

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

res <- lnk_preflight_vintage(conn, max_age_days = max_days)
quit(status = if (isTRUE(res$ok)) 0L else 1L)

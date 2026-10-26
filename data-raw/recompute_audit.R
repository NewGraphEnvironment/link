#!/usr/bin/env Rscript
# recompute_audit.R — did any group's recompute start before a group it reads
# had landed? (link#374). A post-condition on an early recompute: the
# scheduler decides from what it polls, and this checks the outcome from the
# records, so a readiness bug shows up as a failed run, not as a group whose
# access was settled on a half-present path (the habitat gate cannot undo it).
#
# For every group with a closed log_recompute row for the run, and every
# dependency of it (recompute_deps.R, line rule) that the run built:
#   the dependency's landing   a dispatcher group: its log row's date_end for
#                              the run; a remote group: its host's consolidate
#                              state_utc when `ok` (written after the copy)
#   the group's recompute      log_recompute.date_start (after the job's
#                              prologue, so later than its launch)
# A dependency that never landed (a failed group) is not checked: the final
# set starts its dependants anyway, as the end-of-run pool always has. It is
# counted in the report.
#
# Usage: Rscript data-raw/recompute_audit.R <schema> <run_uid> <deps.tsv>
#          <run_wsgs.tsv> <consolidate_state.tsv> [out.tsv]
# Exit 0 when nothing started early, 1 on any violation, 2 when it cannot
# read what it needs (a missing state file means no remote host landed).

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 5L) {
  stop("usage: recompute_audit.R <schema> <run_uid> <deps.tsv> <run_wsgs.tsv> <consolidate_state.tsv> [out.tsv]",
       call. = FALSE)
}
schema <- args[1]; run_uid <- args[2]; deps_p <- args[3]; wsgs_p <- args[4]
state_p <- args[5]; out_p <- if (length(args) >= 6L) args[6] else ""

fail_read <- function(msg) {
  message("[recompute_audit] cannot audit: ", msg)
  quit(status = 2)
}
rd <- function(p) utils::read.delim(p, colClasses = "character", quote = "",
                                    na.strings = character(), comment.char = "")
deps <- tryCatch(rd(deps_p), error = function(e) fail_read(conditionMessage(e)))
wsgs <- tryCatch(rd(wsgs_p), error = function(e) fail_read(conditionMessage(e)))
state <- if (file.exists(state_p)) {
  tryCatch(rd(state_p), error = function(e) fail_read(conditionMessage(e)))
} else {
  data.frame(wsg = character(), workspace = character(), state = character(),
             run_uid = character(), state_utc = character())
}
if (!all(c("wsg", "rule", "dep") %in% names(deps))) fail_read("deps header")
if (!all(c("wsg", "host", "skip") %in% names(wsgs))) fail_read("run_wsgs header")
deps <- deps[deps$rule == "line", ]

conn <- tryCatch(DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                                port = 5432L, user = "postgres", password = "postgres"),
                 error = function(e) fail_read(conditionMessage(e)))
uid <- DBI::dbQuoteLiteral(conn, run_uid)
q <- function(sql) tryCatch(DBI::dbGetQuery(conn, sql), error = function(e) fail_read(conditionMessage(e)))
model <- q(sprintf(
  "SELECT DISTINCT ON (watershed_group_code) watershed_group_code AS wsg, date_end
   FROM %s.log WHERE run_uid = %s AND date_end IS NOT NULL
   ORDER BY watershed_group_code, date_start DESC", schema, uid))
rc <- q(sprintf(
  "SELECT DISTINCT ON (watershed_group_code) watershed_group_code AS wsg, date_start
   FROM %s.log_recompute WHERE run_uid = %s AND date_end IS NOT NULL
   ORDER BY watershed_group_code, date_start", schema, uid))
DBI::dbDisconnect(conn)

# Landing of each (group, host) the run gave out; a group lands at the latest.
run <- wsgs[wsgs$skip != "yes", c("wsg", "host")]
land_one <- function(w, h) {
  if (h == "dispatcher") {
    t <- model$date_end[model$wsg == w]
  } else {
    s <- state$state_utc[state$wsg == w & state$workspace == h & state$state == "ok" &
                           state$run_uid == run_uid]
    t <- as.POSIXct(s, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  }
  if (length(t) == 0L || is.na(t[1])) NA else as.numeric(t[1])
}
run$landed <- mapply(land_one, run$wsg, run$host)
landed <- tapply(run$landed, run$wsg, function(x) if (anyNA(x)) NA else max(x))

rows <- list()
for (i in seq_len(nrow(rc))) {
  g <- rc$wsg[i]
  start <- as.numeric(rc$date_start[i])
  for (d in deps$dep[deps$wsg == g]) {
    if (!d %in% names(landed)) next   # outside the run: landed already
    rows[[length(rows) + 1L]] <- data.frame(
      wsg = g, dep = d, recompute_start = start, dep_landed = unname(landed[d]))
  }
}
tab <- if (length(rows)) do.call(rbind, rows) else
  data.frame(wsg = character(), dep = character(), recompute_start = numeric(), dep_landed = numeric())
tab$verdict <- ifelse(is.na(tab$dep_landed), "dep_never_landed",
                      ifelse(tab$recompute_start >= tab$dep_landed, "ok", "EARLY"))
if (nzchar(out_p)) {
  o <- tab
  o$recompute_start <- format(as.POSIXct(o$recompute_start, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")
  o$dep_landed <- ifelse(is.na(tab$dep_landed), "",
    format(as.POSIXct(tab$dep_landed, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ"))
  utils::write.table(o, out_p, sep = "\t", quote = FALSE, row.names = FALSE)
}
n_early <- sum(tab$verdict == "EARLY")
cat(sprintf("[recompute_audit] %d recomputed groups, %d dependency pairs in the run: %d ok, %d whose dependency never landed, %d EARLY\n",
            nrow(rc), nrow(tab), sum(tab$verdict == "ok"), sum(tab$verdict == "dep_never_landed"), n_early))
if (n_early > 0L) {
  e <- tab[tab$verdict == "EARLY", ]
  cat(sprintf("  EARLY: %s started before %s landed\n", e$wsg, e$dep), sep = "")
  quit(status = 1)
}
quit(status = 0)

#!/usr/bin/env Rscript
# recompute_audit.R — did any group's recompute start before a group it reads
# had landed? (link#374). A post-condition on an early recompute: the
# scheduler decides from what it polls, and this checks the outcome from the
# records, so a readiness bug shows up as a failed run, not as a group whose
# access was settled on a half-present path (the habitat gate cannot undo it).
#
# For every group the run recomputed and every dependency of it
# (recompute_deps.R, line rule) that the run built, each comparison is made on
# ONE clock:
#   a dispatcher dependency  its log row's date_end against the group's
#                            earliest log_recompute.date_start, open rows
#                            included (a recompute that failed after its gate
#                            committed has still cleared flags): both the
#                            database's clock
#   a remote dependency      its host's consolidate state_utc (`ok`, written
#                            after the copy) against the group's launch time in
#                            the scheduler's launched.tsv: both the driver's
#                            clock. The database runs in a VM whose clock can
#                            drift from the host's, so a cross-clock check would
#                            report right starts EARLY or miss wrong ones.
# A dependency built on the dispatcher AND a remote host (a closure-mode
# overlap) is checked on its remote arm only: the dispatcher's log also holds
# the remote host's copied rows (#354), on that host's clock, and an
# overlapping host is consolidated only after the dispatcher leg ends
# (study_area_legs.sh, rule 3), so the remote landing is the later one.
# A dependency that never landed (a failed group) is not checked: the final
# set starts its dependants anyway, as the end-of-run pool always has. A group
# with no start recorded is safe only when nothing ran (no log_recompute row:
# its gate never committed) or the fallback pool started it (fallback.txt,
# after every landing); any other missing start is "could not audit", never a
# pass. All are counted.
#
# Usage: Rscript data-raw/recompute_audit.R <schema> <run_uid> <deps.tsv>
#          <run_wsgs.tsv> <consolidate_state.tsv> <launched.tsv> [out.tsv]
#          [fallback.txt]
# Exit 0 when nothing started early, 1 on any violation, 2 when it cannot
# audit (any error, a missing input; a missing state file means no remote host
# landed, a missing launched file means the scheduler started nothing).

# Any error is "could not audit", never "a group started early": the driver
# reads 1 as the verdict and prints a re-model remedy.
options(error = function() {
  message("[recompute_audit] cannot audit: ", geterrmessage())
  quit(status = 2, save = "no")
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 6L) {
  stop("usage: recompute_audit.R <schema> <run_uid> <deps.tsv> <run_wsgs.tsv> <consolidate_state.tsv> <launched.tsv> [out.tsv]",
       call. = FALSE)
}
schema <- args[1]; run_uid <- args[2]; deps_p <- args[3]; wsgs_p <- args[4]
state_p <- args[5]; launched_p <- args[6]
out_p <- if (length(args) >= 7L) args[7] else ""
fallback_p <- if (length(args) >= 8L) args[8] else ""
fallback <- if (nzchar(fallback_p) && file.exists(fallback_p)) readLines(fallback_p) else character(0)

rd <- function(p, header = TRUE) utils::read.delim(p, header = header, colClasses = "character",
                                                   quote = "", na.strings = character(),
                                                   comment.char = "")
deps <- rd(deps_p)
wsgs <- rd(wsgs_p)
state <- if (file.exists(state_p)) rd(state_p) else
  data.frame(wsg = character(), workspace = character(), state = character(),
             run_uid = character(), state_utc = character())
launched <- if (file.exists(launched_p) && file.size(launched_p) > 0) rd(launched_p, header = FALSE) else
  data.frame(V1 = character(), V2 = character())
if (!all(c("wsg", "rule", "dep") %in% names(deps))) stop("deps.tsv has no wsg / rule / dep header")
if (!all(c("wsg", "host", "skip") %in% names(wsgs))) stop("run_wsgs.tsv has no wsg / host / skip header")
deps <- deps[deps$rule == "line", ]
# "<wsg>\t<iso> <epoch>\t<mode>\t<pid>": the first launch of each group.
launch_ep <- tapply(as.numeric(sub("^.* ", "", launched$V2)), launched$V1, min)

conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                       port = 5432L, user = "postgres", password = "postgres")
uid <- DBI::dbQuoteLiteral(conn, run_uid)
model <- DBI::dbGetQuery(conn, sprintf(
  "SELECT DISTINCT ON (watershed_group_code) watershed_group_code AS wsg, date_end
   FROM %s.log WHERE run_uid = %s AND date_end IS NOT NULL
   ORDER BY watershed_group_code, date_start DESC", schema, uid))
rc <- DBI::dbGetQuery(conn, sprintf(
  "SELECT watershed_group_code AS wsg, min(date_start) AS date_start
   FROM %s.log_recompute WHERE run_uid = %s GROUP BY 1", schema, uid))
DBI::dbDisconnect(conn)

run <- wsgs[wsgs$skip != "yes", c("wsg", "host")]
land_disp <- stats::setNames(as.numeric(model$date_end), model$wsg)
ok_state <- state[state$state == "ok" & state$run_uid == run_uid, ]
land_remote <- function(w, h) {
  s <- ok_state$state_utc[ok_state$wsg == w & ok_state$workspace == h]
  if (length(s) == 0L) return(NA_real_)
  as.numeric(as.POSIXct(s[1], format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
}
rc_start <- stats::setNames(as.numeric(rc$date_start), rc$wsg)
groups <- union(rc$wsg, names(launch_ep))

rows <- list()
for (g in groups) {
  for (d in deps$dep[deps$wsg == g]) {
    hs <- run$host[run$wsg == d]
    if (length(hs) == 0L) next   # outside the run, or a SKIP: landed already
    for (h in hs) {
      if (h == "dispatcher" && length(hs) > 1L) next
      if (h == "dispatcher") {
        landed <- unname(land_disp[d]); start <- unname(rc_start[g]); clock <- "database"
      } else {
        landed <- land_remote(d, h); start <- unname(launch_ep[g]); clock <- "driver"
      }
      verdict <- if (is.na(landed)) "dep_never_landed" else
        if (!is.na(start)) { if (start >= landed) "ok" else "EARLY" } else
        if (!g %in% rc$wsg) "no_recompute_row" else
        if (g %in% fallback) "after_final" else "start_unrecorded"
      rows[[length(rows) + 1L]] <- data.frame(
        wsg = g, dep = d, dep_host = h, clock = clock,
        recompute_start = start, dep_landed = landed, verdict = verdict)
    }
  }
}
tab <- if (length(rows)) do.call(rbind, rows) else
  data.frame(wsg = character(), dep = character(), dep_host = character(), clock = character(),
             recompute_start = numeric(), dep_landed = numeric(), verdict = character())
if (nzchar(out_p)) {
  iso <- function(x) ifelse(is.na(x), "",
    format(as.POSIXct(x, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ"))
  o <- tab
  o$recompute_start <- iso(tab$recompute_start)
  o$dep_landed <- iso(tab$dep_landed)
  utils::write.table(o, out_p, sep = "\t", quote = FALSE, row.names = FALSE)
}
n_early <- sum(tab$verdict == "EARLY")
cat(sprintf(paste0("[recompute_audit] %d recomputed groups, %d dependency pairs in the run: ",
                   "%d ok, %d whose dependency never landed, %d started by the fallback pool, ",
                   "%d with no recompute row, %d with no recorded start, %d EARLY\n"),
            length(groups), nrow(tab), sum(tab$verdict == "ok"),
            sum(tab$verdict == "dep_never_landed"), sum(tab$verdict == "after_final"),
            sum(tab$verdict == "no_recompute_row"), sum(tab$verdict == "start_unrecorded"), n_early))
if (n_early > 0L) {
  e <- tab[tab$verdict == "EARLY", ]
  cat(sprintf("  EARLY: %s started before %s (%s) landed\n", e$wsg, e$dep, e$dep_host), sep = "")
  quit(status = 1)
}
# A start that should have been recorded and was not is not a pass.
if (any(tab$verdict == "start_unrecorded")) {
  u <- tab[tab$verdict == "start_unrecorded", ]
  cat(sprintf("  cannot audit %s against %s (%s): no launch time recorded\n", u$wsg, u$dep, u$dep_host), sep = "")
  quit(status = 2)
}
quit(status = 0)

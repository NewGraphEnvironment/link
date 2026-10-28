#!/usr/bin/env Rscript
# host_speeds_calibrate.R — learn host speeds from a run's model legs
# (link#259, folding in #163). The operator runs it after a run; the driver's
# summary prints the command and runs nothing, so a run with a stall can be
# left out by judgment (--skip) rather than by a rule.
#
# Usage:
#   Rscript data-raw/host_speeds_calibrate.R --plan=<plan.tsv> \
#     --phases=<log dir>/<TS>_phases.tsv [--skip=<name>:<reason> ...] [--dry-run] \
#     [--state=data-raw/logs/host_speeds.tsv] [--history=data-raw/logs/host_speeds_history.tsv]
#
#   --plan     study_area_buckets.R --plan-out=: one row per group, with its
#              host, the host's name and speed, and its weight in minutes
#   --phases   the run's <TS>_phases.tsv; <TS>_run_wsgs.tsv and
#              <TS>_coverage.tsv are read beside it
#   --skip     leave a name's legs out, with the reason the history records
#              (a stall, a host shared with another job). Repeatable
#   --dry-run  print what would change and write nothing
#
# What it does (the arithmetic is speeds_calibrate() in study_area_packing.R):
#   - Each leg's actual time is its `model` row: the whole leg, as #163 asks,
#     never a mean over its groups. A killed driver can leave two rows for one
#     leg; the later end is the leg's.
#   - Each leg's projected time is the sum of its groups' plan weights over the
#     speed it was packed at, less groups the host SKIPped (run_wsgs `skip`
#     yes) and groups with no rows from this run (coverage class other than
#     `recompute`).
#   - A host whose `account` row is not `ok` did not finish its bucket, so its
#     leg is left out.
#   - It refuses a plan whose groups for a host differ from what the run gave
#     that host, a plan weighted in segments (no minutes to compare), a
#     phases file with no model rows (a --recompute-only pass), and a run the
#     history already holds.

args <- commandArgs(trailingOnly = TRUE)
arg_val <- function(flag, default) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (!length(hit)) return(default)
  sub(paste0("^", flag, "="), "", hit[1])
}
script_dir <- dirname(normalizePath(sub("^--file=", "",
  grep("^--file=", commandArgs(FALSE), value = TRUE)[1]), mustWork = FALSE))
source(file.path(script_dir, "study_area_packing.R"))

plan_path <- arg_val("--plan", "")
phases_path <- arg_val("--phases", "")
state_path <- arg_val("--state", file.path(script_dir, "logs", "host_speeds.tsv"))
history_path <- arg_val("--history", file.path(script_dir, "logs", "host_speeds_history.tsv"))
dry_run <- "--dry-run" %in% args
skips <- sub("^--skip=", "", grep("^--skip=", args, value = TRUE))
if (!nzchar(plan_path) || !nzchar(phases_path)) {
  stop("--plan= and --phases= are both required", call. = FALSE)
}
if (length(skips) && !all(grepl("^[^:]+:.+$", skips))) {
  stop("--skip takes <name>:<reason>, got: ", paste(skips, collapse = ", "), call. = FALSE)
}
skip_reason <- stats::setNames(sub("^[^:]+:", "", skips), sub(":.*$", "", skips))

read_tsv <- function(path, what) {
  if (!file.exists(path)) stop(what, " not found: ", path, call. = FALSE)
  utils::read.delim(path, colClasses = "character", na.strings = character(),
                    quote = "", comment.char = "")
}
need_cols <- function(d, cols, what) {
  miss <- setdiff(cols, names(d))
  if (length(miss)) stop(what, " lacks columns: ", paste(miss, collapse = ", "), call. = FALSE)
}

# --- the plan ---------------------------------------------------------------
plan <- read_tsv(plan_path, "plan")
need_cols(plan, c("wsg", "host_key", "name", "speed", "weight_unit", "weight"), "plan")
if (!nrow(plan)) stop("plan has no rows", call. = FALSE)
if (any(plan$weight_unit != "min")) {
  stop("the plan is weighted in ", paste(unique(plan$weight_unit), collapse = ", "),
       ": only a plan in minutes (study_area_buckets.R --minutes-schema=) can be compared ",
       "with a leg's minutes", call. = FALSE)
}
host_names_check(unique(plan$name))
plan$speed <- as.numeric(plan$speed)
plan$weight <- as.numeric(plan$weight)
if (anyNA(plan$speed) || anyNA(plan$weight) || anyDuplicated(plan$wsg)) {
  stop("plan: every row needs a numeric speed and weight, one row per group", call. = FALSE)
}

# --- the run ------------------------------------------------------------------
ph <- read_tsv(phases_path, "phases")
need_cols(ph, c("run_uid", "phase", "host", "start_utc", "end_utc", "status"), "phases")
ts <- sub("_phases\\.tsv$", "", basename(phases_path))
run_dir <- dirname(phases_path)
model <- ph[ph$phase == "model" & nzchar(ph$end_utc) & nzchar(ph$host), ]
if (!nrow(model)) {
  stop(phases_path, " has no finished model rows (a --recompute-only pass models nothing)",
       call. = FALSE)
}
run_uid <- unique(ph$run_uid)
if (length(run_uid) != 1L) stop(phases_path, ": more than one run_uid", call. = FALSE)
iso <- function(x) as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
model$start <- iso(model$start_utc)
model$end <- iso(model$end_utc)
if (anyNA(model$start) || anyNA(model$end)) stop(phases_path, ": unreadable model times", call. = FALSE)
model <- model[order(model$host, model$end, decreasing = TRUE), ]
model <- model[!duplicated(model$host), ]          # the later end is the leg's
account <- ph[ph$phase == "account" & nzchar(ph$host), ]
account <- account[order(account$host, account$end_utc, decreasing = TRUE), ]
account <- account[!duplicated(account$host), ]

rw <- read_tsv(file.path(run_dir, paste0(ts, "_run_wsgs.tsv")), "run_wsgs")
need_cols(rw, c("wsg", "host", "skip", "run_uid"), "run_wsgs")
if (!all(rw$run_uid == run_uid)) stop("run_wsgs names another run_uid", call. = FALSE)
cov <- read_tsv(file.path(run_dir, paste0(ts, "_coverage.tsv")), "coverage")
need_cols(cov, c("wsg", "class"), "coverage")
if (file.exists(history_path)) {
  h0 <- read_tsv(history_path, "history")
  if (run_uid %in% h0$run_uid) {
    stop("the history already holds run ", run_uid, ": a run is calibrated once", call. = FALSE)
  }
}

# The groups the packer gave each host must be the groups the run gave it.
for (k in union(unique(plan$host_key), unique(rw$host))) {
  a <- sort(plan$wsg[plan$host_key == k]); b <- sort(rw$wsg[rw$host == k])
  if (!identical(a, b)) {
    stop(sprintf("host %s: the plan gives it %d groups and the run %d (%s): calibrate against the plan the run used",
                 k, length(a), length(b),
                 paste(utils::head(c(setdiff(a, b), setdiff(b, a)), 5), collapse = ", ")),
         call. = FALSE)
  }
}

# --- legs -------------------------------------------------------------------
modelled <- rw$wsg[rw$skip == "no"]
finished <- cov$wsg[cov$class == "recompute"]
legs <- do.call(rbind, lapply(unique(plan$host_key), function(k) {
  p <- plan[plan$host_key == k, ]
  keep <- p$wsg %in% modelled & p$wsg %in% finished
  m <- model[model$host == k, ]
  a <- account$status[account$host == k]
  why <- c(
    if (!nrow(m)) "no model row",
    if (length(a) && a != "ok") paste("account", a),
    if (!length(a)) "no account row",
    if (!any(keep)) "no group finished",
    if (p$name[1] %in% names(skip_reason)) skip_reason[[p$name[1]]])
  data.frame(host_key = k, name = p$name[1], speed = p$speed[1],
             projected = sum(p$weight[keep] / p$speed[keep]),
             actual = if (nrow(m)) as.numeric(difftime(m$end, m$start, units = "mins")) else NA,
             groups = sum(keep),
             skip = if (length(why)) paste(why, collapse = "; ") else NA)
}))
# A skipped leg needs no times; give it placeholders the arithmetic never reads.
legs$projected[!is.na(legs$skip) & !(legs$projected > 0)] <- 1
legs$actual[!is.na(legs$skip) & is.na(legs$actual)] <- 1
unknown_skip <- setdiff(names(skip_reason), legs$name)
if (length(unknown_skip)) {
  stop("--skip names no host in the plan: ", paste(unknown_skip, collapse = ", "), call. = FALSE)
}

state <- speeds_state_read(state_path)
date_utc <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
out <- speeds_calibrate(legs, state, run_uid = run_uid, date_utc = date_utc)

cat(sprintf("run %s: %d legs, run-wide ratio (actual / projected) %.3f\n\n",
            run_uid, nrow(legs), out$run_ratio))
cat("| host | name | speed | groups | projected min | actual min | skipped |\n|---|---|---|---|---|---|---|\n")
for (i in seq_len(nrow(legs))) {
  l <- legs[i, ]
  cat(sprintf("| %s | %s | %.3f | %d | %s | %s | %s |\n", l$host_key, l$name, l$speed, l$groups,
              if (is.na(l$skip)) sprintf("%.1f", l$projected) else "",
              if (is.na(l$skip)) sprintf("%.1f", l$actual) else "",
              if (is.na(l$skip)) "" else l$skip))
}
cat("\n| name | old | correction | observed | new | clamped | action |\n|---|---|---|---|---|---|---|\n")
h <- out$history
for (i in seq_len(nrow(h))) {
  f <- function(x) if (is.na(x)) "" else sprintf("%.3f", x)
  cat(sprintf("| %s | %s | %s | %s | %s | %s | %s |\n", h$name[i], f(h$old[i]), f(h$correction[i]),
              f(h$observed[i]), f(h$new[i]), if (is.na(h$clamped[i])) "" else h$clamped[i],
              h$action[i]))
}

if (dry_run) {
  cat("\n--dry-run: nothing written\n")
} else {
  st_out <- out$state
  st_out$factor <- sprintf("%.4f", st_out$factor)
  utils::write.table(st_out, state_path, sep = "\t", quote = FALSE, row.names = FALSE)
  hist_out <- h
  num <- c("old", "correction", "observed", "damped", "new", "run_ratio")
  hist_out[num] <- lapply(hist_out[num], function(x) ifelse(is.na(x), "", sprintf("%.4f", x)))
  utils::write.table(hist_out, history_path, sep = "\t", quote = FALSE, row.names = FALSE,
                     na = "", append = file.exists(history_path),
                     col.names = !file.exists(history_path))
  cat(sprintf("\nwrote %s and appended %d rows to %s\n", state_path, nrow(h), history_path))
}

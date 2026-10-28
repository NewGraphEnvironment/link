#!/usr/bin/env Rscript
# pretest_pick.R — which groups the pre-run gate models (link#372). Called by
# pretest_run.sh; runs alone for a pick with nothing modelled.
#
#   Rscript data-raw/pretest_pick.R --config=<bundle> --schema=<persist schema> \
#     --out=<dir> [--since=<sha>] [--until=HEAD] [--per-input=2] [--k=3] \
#     [--floor-min=5] [--statement-timeout=30] [--fresh-repo=<fresh checkout>] \
#     [--minutes-schema=<schema>] [--minutes-exclude=KTSU,...]
#
# --since defaults to the link SHA of the earliest of the groups' newest
# finished builds in <schema>.log (the last provincial run, even where a group
# was re-modelled after it). A group is picked only if <schema>.log has a
# finished build of it, so the config can model it. Its bound is its newest
# finished minutes in --minutes-schema (default --schema); a group in
# --minutes-exclude, whose newest minutes are a known stall, or with no row
# there, is bounded on the median. Writes <out>/picks.tsv (one row per group) and
# <out>/pretest.md (what changed, which input each file named, each query and
# its top groups, the picks). Exit 0 with picks, 2 refused (an unmapped file,
# a bad argument, no history).

args <- commandArgs(trailingOnly = TRUE)
arg_val <- function(flag, default = "") {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (length(hit)) sub(paste0("^", flag, "="), "", hit[length(hit)]) else default
}
refuse <- function(...) {
  message("REFUSED: ", ...)
  quit(status = 2)
}
script_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))))
repo <- normalizePath(file.path(script_dir, ".."))
source(file.path(script_dir, "pretest.R"))

config <- arg_val("--config")
schema <- arg_val("--schema")
out <- arg_val("--out")
since <- arg_val("--since")
until <- arg_val("--until", "HEAD")
per_input <- suppressWarnings(as.integer(arg_val("--per-input", "2")))
k <- suppressWarnings(as.numeric(arg_val("--k", "3")))
floor_min <- suppressWarnings(as.numeric(arg_val("--floor-min", "5")))
stmt_cap <- suppressWarnings(as.integer(arg_val("--statement-timeout", "30")))
fresh_repo <- arg_val("--fresh-repo", file.path(dirname(repo), "fresh"))
minutes_schema <- arg_val("--minutes-schema", schema)
minutes_exclude <- toupper(trimws(strsplit(arg_val("--minutes-exclude"), ",")[[1]]))
minutes_exclude <- minutes_exclude[nzchar(minutes_exclude)]

if (!nzchar(config) || !nzchar(schema) || !nzchar(out)) refuse("--config, --schema and --out are required")
for (s in c(schema, minutes_schema)) {
  if (!grepl("^[a-z_][a-z0-9_]*$", s)) refuse("a schema must be a bare schema name, got '", s, "'")
}
if (!all(grepl("^[A-Z]{4}$", minutes_exclude))) refuse("--minutes-exclude takes four-letter group codes")
if (is.na(per_input) || per_input < 1L) refuse("--per-input must be a whole number >= 1")
if (is.na(k) || k <= 0) refuse("--k must be > 0")
if (is.na(floor_min) || floor_min < 0) refuse("--floor-min must be >= 0")
if (is.na(stmt_cap) || stmt_cap < 1L || stmt_cap > 1440L) refuse("--statement-timeout must be 1..1440")
if (!dir.exists(fresh_repo)) refuse("no fresh checkout at ", fresh_repo, " (pass --fresh-repo=)")

suppressPackageStartupMessages({
  library(DBI)
  library(RPostgres)
})
conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                       port = 5432L, user = "postgres", password = "postgres")

for (s in unique(c(schema, minutes_schema))) {
  if (is.na(DBI::dbGetQuery(conn, sprintf("SELECT to_regclass('%s.log')::text AS t", s))$t)) {
    refuse(s, ".log does not exist: no history")
  }
}
built <- DBI::dbGetQuery(conn, pretest_history_sql(schema))
if (!nrow(built)) refuse(schema, ".log has no finished rows")
if (!nzchar(since)) {
  since <- tryCatch(pretest_since_default(built), error = function(e) refuse(conditionMessage(e)))
  message(sprintf("--since from %s.log: the earliest of the groups' newest builds, link %s",
                  schema, substr(since, 1, 12)))
}
since_sha <- tryCatch(pretest_git(repo, c("rev-parse", "--verify", paste0(since, "^{commit}"))),
                      error = function(e) refuse(conditionMessage(e)))
until_sha <- tryCatch(pretest_git(repo, c("rev-parse", "--verify", paste0(until, "^{commit}"))),
                      error = function(e) refuse(conditionMessage(e)))
# The record check holds a gate to covering every build the history holds;
# say so now rather than after an hour of modelling.
cover <- tryCatch(pretest_since_covers(repo, since_sha, built$link_sha),
                  error = function(e) refuse(conditionMessage(e)))
if (nzchar(cover)) refuse(cover, "; a gate on this range cannot clear a run")

chain <- tryCatch(pretest_config_chain(file.path(repo, "inst/extdata/configs"), config),
                  error = function(e) refuse(conditionMessage(e)))
desc_at <- function(ref) pretest_git(repo, c("show", paste0(ref, ":DESCRIPTION")))
fresh_from <- pretest_fresh_pin(desc_at(since_sha))
fresh_to <- pretest_fresh_pin(desc_at(until_sha))

changed <- tryCatch(rbind(pretest_changed_link(repo, since_sha, until_sha, chain),
                          pretest_changed_fresh(fresh_repo, fresh_from, fresh_to)),
                    error = function(e) refuse(conditionMessage(e)))
map <- pretest_map_read(file.path(script_dir, "pretest_inputs.csv"))
m <- pretest_match(changed, map, chain)

dir.create(out, recursive = TRUE, showWarnings = FALSE)
md <- file.path(out, "pretest.md")
w <- function(...) cat(..., "\n", sep = "", file = md, append = TRUE)
cat("", file = md)
w("# Pre-run gate (link#372)")
w("")
w(sprintf("- config `%s` (chain: %s), history in `%s.log`", config,
          paste(chain, collapse = " < "), schema))
w(sprintf("- link `%s..%s`; fresh `%s..%s`", substr(since_sha, 1, 12), substr(until_sha, 1, 12),
          fresh_from, fresh_to))
w(sprintf("- per input %d groups; bound %g x last minutes in `%s.log`, floor %g min; statement bound <= %d min",
          per_input, k, minutes_schema, floor_min, stmt_cap))
if (length(minutes_exclude)) w(sprintf("- minutes excluded (bounded on the median): %s",
                                       paste(minutes_exclude, collapse = ", ")))
w("")
w(sprintf("## Changed files (%d)", nrow(changed)))
w("")
if (nrow(m$unmapped)) {
  w("**Unmapped (the gate refuses):**")
  w("")
  for (i in seq_len(nrow(m$unmapped))) w(sprintf("- %s `%s`", m$unmapped$repo[i], m$unmapped$path[i]))
  message("Changed files the map (data-raw/pretest_inputs.csv) does not name:")
  message(paste0("  ", m$unmapped$repo, " ", m$unmapped$path, collapse = "\n"))
  refuse(nrow(m$unmapped), " unmapped file(s); add a row for each, naming the input that drives its cost")
}
w("| repo | file | inputs |")
w("|---|---|---|")
by_file <- split(m$hits$input, paste(m$hits$repo, m$hits$path))
for (f in names(by_file)) {
  parts <- strsplit(f, " ", fixed = TRUE)[[1]]
  w(sprintf("| %s | `%s` | %s |", parts[1], parts[2], paste(sort(unique(by_file[[f]])), collapse = ", ")))
}
w("")
unex <- sort(unique(paste(m$hits$repo, m$hits$path)[m$hits$input == "unexercised"]))
writeLines(unex, file.path(out, "unexercised.txt"))
if (length(unex)) {
  w("**Changed and unexercised by the gate** (on the run's path, not on the modelled one):")
  w("")
  for (u in unex) w(sprintf("- `%s`", u))
  w("")
  message("Changed and NOT exercised by the gate: ", paste(unex, collapse = ", "))
}

mins <- if (identical(minutes_schema, schema)) built else
  DBI::dbGetQuery(conn, pretest_history_sql(minutes_schema))
history <- data.frame(wsg = built$wsg, stringsAsFactors = FALSE)
i <- match(history$wsg, mins$wsg)
history$minutes <- mins$minutes[i]
history$host <- mins$host[i]
history$minutes[history$wsg %in% minutes_exclude] <- NA
med <- stats::median(history$minutes, na.rm = TRUE)
fill <- is.na(history$minutes)
history$host[fill] <- "median"
history$minutes[fill] <- med
if (any(fill)) {
  message(sprintf("%d group(s) bounded on the median %.1f min (excluded or no row in %s.log)",
                  sum(fill), med, minutes_schema))
}

inputs <- pretest_inputs(m$hits)
values <- list()
for (inp in inputs) {
  f <- file.path(script_dir, "pretest", paste0(inp, ".sql"))
  if (!file.exists(f)) refuse("input ", inp, " has no query (", f, ")")
  sql <- paste(readLines(f), collapse = "\n")
  v <- DBI::dbGetQuery(conn, sql)
  names(v) <- c("wsg", "value")
  values[[inp]] <- v
}
picks <- tryCatch(pretest_pick(values, history, per_input, any = "any" %in% m$hits$input),
                  error = function(e) refuse(conditionMessage(e)))

w("## Inputs")
w("")
for (inp in inputs) {
  f <- file.path("data-raw", "pretest", paste0(inp, ".sql"))
  v <- values[[inp]]
  v <- v[v$wsg %in% history$wsg, , drop = FALSE]
  v <- utils::head(v[order(-v$value, v$wsg), , drop = FALSE], 5)
  w(sprintf("### %s (`%s`)", inp, f))
  w("")
  w(sprintf("Top five among groups with history: %s.",
            paste(sprintf("%s %s", v$wsg, format(round(v$value), big.mark = ",", trim = TRUE)),
                  collapse = "; ")))
  w("")
}
if (!nrow(picks)) {
  w("No changed file is on the modelling path: nothing to model.")
  message("No changed file is on the modelling path: nothing to model.")
}

groups <- pretest_groups(picks, history, k, floor_min)
groups$statement_min <- pretest_statement_min(groups$bound, stmt_cap)
# No empty field: bash's `IFS=$'\t' read` collapses consecutive tabs.
groups$host[is.na(groups$host) | !nzchar(groups$host)] <- "unknown"
utils::write.table(groups, file.path(out, "picks.tsv"), sep = "\t", quote = FALSE,
                   row.names = FALSE, na = "NA")
w("## Picks")
w("")
w("| group | inputs | last minutes | measured on | bound (min) | statement bound (min) |")
w("|---|---|---|---|---|---|")
for (i in seq_len(nrow(groups))) {
  w(sprintf("| %s | %s | %.1f | %s | %.1f | %d |", groups$wsg[i], groups$inputs[i],
            groups$minutes[i], groups$host[i], groups$bound[i], groups$statement_min[i]))
}
w("")
w(sprintf("Estimated modelling: %.1f min (sum of last minutes).", sum(groups$minutes)))
w("")
writeLines(c(since_sha, until_sha), file.path(out, "range.txt"))

message(sprintf("%d changed file(s), inputs: %s", nrow(changed),
                if (length(inputs)) paste(inputs, collapse = ", ") else "(none)"))
for (i in seq_len(nrow(groups))) {
  message(sprintf("  pick %s  [%s]  last %.1f min on %s, bound %.1f min", groups$wsg[i],
                  groups$inputs[i], groups$minutes[i], groups$host[i], groups$bound[i]))
}
DBI::dbDisconnect(conn)

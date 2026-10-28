#!/usr/bin/env Rscript
# pretest_pick.R — which groups the pre-run gate models (link#372). Called by
# pretest_run.sh; runs alone for a pick with nothing modelled.
#
#   Rscript data-raw/pretest_pick.R --config=<bundle> --schema=<persist schema> \
#     --out=<dir> [--since=<sha>] [--until=HEAD] [--per-input=2] [--k=3] \
#     [--floor-min=5] [--statement-timeout=30] [--fresh-repo=<fresh checkout>]
#
# --since defaults to the link SHA of the newest run_uid in <schema>.log, the
# last provincial run. History is each group's newest finished row in the same
# log, so a group is picked only if it has minutes to be bounded against and
# the config can model it. Writes <out>/picks.tsv (one row per group) and
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

if (!nzchar(config) || !nzchar(schema) || !nzchar(out)) refuse("--config, --schema and --out are required")
if (!grepl("^[a-z_][a-z0-9_]*$", schema)) refuse("--schema must be a bare schema name, got '", schema, "'")
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

has_log <- DBI::dbGetQuery(conn, sprintf(
  "SELECT 1 FROM information_schema.tables WHERE table_schema = '%s' AND table_name = 'log'", schema))
if (!nrow(has_log)) refuse(schema, ".log does not exist: no history to bound against")

if (!nzchar(since)) {
  last <- DBI::dbGetQuery(conn, sprintf(
    "SELECT run_uid, link_sha FROM %s.log
      WHERE run_uid IS NOT NULL AND link_sha IS NOT NULL
      ORDER BY date_start DESC LIMIT 1", schema))
  if (!nrow(last)) refuse(schema, ".log has no run_uid row with a link_sha; pass --since=")
  since <- last$link_sha
  message(sprintf("--since from %s.log: run_uid %s at link %s", schema, last$run_uid,
                  substr(since, 1, 12)))
}
since_sha <- tryCatch(pretest_git(repo, c("rev-parse", "--verify", paste0(since, "^{commit}"))),
                      error = function(e) refuse(conditionMessage(e)))
until_sha <- tryCatch(pretest_git(repo, c("rev-parse", "--verify", paste0(until, "^{commit}"))),
                      error = function(e) refuse(conditionMessage(e)))

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
w(sprintf("- per input %d groups; bound %g x last minutes, floor %g min; statement bound <= %d min",
          per_input, k, floor_min, stmt_cap))
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

history <- DBI::dbGetQuery(conn, sprintf(
  "SELECT DISTINCT ON (watershed_group_code)
          watershed_group_code AS wsg, host,
          extract(epoch FROM (date_end - date_start)) / 60 AS minutes
     FROM %s.log
    WHERE date_end IS NOT NULL AND date_start IS NOT NULL
    ORDER BY watershed_group_code, date_start DESC", schema))
if (!nrow(history)) refuse(schema, ".log has no finished rows")

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
utils::write.table(groups, file.path(out, "picks.tsv"), sep = "\t", quote = FALSE,
                   row.names = FALSE, na = "")
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

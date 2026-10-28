#!/usr/bin/env Rscript
# pretest_verdict.R — the pre-run gate's verdict (link#372). Called by
# pretest_run.sh after it has modelled the picks into the scratch schema.
#
#   Rscript data-raw/pretest_verdict.R --out=<dir> --schema=<persist schema> \
#     --scratch=<scratch schema> --config=<bundle> [--k=3] [--floor-min=5] \
#     [--per-input=2] [--notes=<text>]
#
# Reads <out>/picks.tsv, <out>/exits.tsv (wsg, exit status) and
# <out>/range.txt; each group's minutes and provenance come from its row in
# <scratch>.log, the same measure as its history. Appends the verdict table to
# <out>/pretest.md and writes one row to <schema>.log_pretest, which
# study_area_run.sh's pre-flight reads. Exit 0 when the gate passes, 1 when it
# does not.
#
# A pass needs every picked group to have finished, with a log row, within its
# bound, on one clean link SHA equal to the end of the picked range and one
# fresh SHA. Anything else is recorded as a fail with the reason in notes.

args <- commandArgs(trailingOnly = TRUE)
arg_val <- function(flag, default = "") {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (length(hit)) sub(paste0("^", flag, "="), "", hit[length(hit)]) else default
}
script_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))))
source(file.path(script_dir, "pretest.R"))

out <- arg_val("--out")
schema <- arg_val("--schema")
scratch <- arg_val("--scratch")
config <- arg_val("--config")
k <- as.numeric(arg_val("--k", "3"))
floor_min <- as.numeric(arg_val("--floor-min", "5"))
per_input <- as.integer(arg_val("--per-input", "2"))
notes_in <- arg_val("--notes")
subset <- "--subset" %in% args
for (s in c(schema, scratch)) {
  if (!grepl("^[a-z_][a-z0-9_]*$", s)) stop("bad schema name '", s, "'", call. = FALSE)
}

picks <- utils::read.delim(file.path(out, "picks.tsv"), stringsAsFactors = FALSE,
                           colClasses = c(wsg = "character"))
exits <- if (nrow(picks)) {
  utils::read.delim(file.path(out, "exits.tsv"), header = FALSE, col.names = c("wsg", "exit"),
                    stringsAsFactors = FALSE, colClasses = c("character", "integer"))
} else {
  data.frame(wsg = character(), exit = integer())
}
range <- readLines(file.path(out, "range.txt"))

suppressPackageStartupMessages({
  library(DBI)
  library(RPostgres)
})
conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                       port = 5432L, user = "postgres", password = "postgres")

rows <- if (nrow(picks)) {
  DBI::dbGetQuery(conn, sprintf(
    "SELECT watershed_group_code AS wsg, link_sha, link_dirty, fresh_sha,
            extract(epoch FROM (date_end - date_start)) / 60 AS minutes
       FROM %s.log", scratch))
} else {
  data.frame(wsg = character(), link_sha = character(), link_dirty = logical(),
             fresh_sha = character(), minutes = numeric())
}
fin <- rows[!is.na(rows$minutes), , drop = FALSE]
picks$exit <- exits$exit[match(picks$wsg, exits$wsg)]
picks$run_minutes <- fin$minutes[match(picks$wsg, fin$wsg)]
picks$verdict <- pretest_verdict(picks$exit, picks$run_minutes, picks$bound)

why <- character()
if (!nrow(picks)) why <- c(why, "no changed file is on the modelling path")
bad <- picks$wsg[picks$verdict != "pass"]
if (length(bad)) why <- c(why, sprintf("%s %s", bad, picks$verdict[picks$verdict != "pass"]))
link_sha <- unique(stats::na.omit(rows$link_sha))
fresh_sha <- unique(stats::na.omit(rows$fresh_sha))
dirty <- any(is.na(rows$link_dirty) | rows$link_dirty)
if (nrow(picks)) {
  if (length(link_sha) != 1L) why <- c(why, sprintf("%d link SHAs in the scratch log", length(link_sha)))
  if (length(fresh_sha) != 1L) why <- c(why, sprintf("%d fresh SHAs in the scratch log", length(fresh_sha)))
  if (dirty) why <- c(why, "a scratch log row is link_dirty (or unknown)")
  if (length(link_sha) == 1L && !identical(link_sha, range[2])) {
    why <- c(why, sprintf("modelled link %s is not the picked range's end %s",
                          substr(link_sha, 1, 12), substr(range[2], 1, 12)))
  }
} else {
  # Nothing modelled, so nothing logged it: the record carries what the pick
  # read, and the driver's own pre-flight still checks the tree and fresh.
  link_sha <- range[2]
  dirty <- FALSE
  fresh_sha <- NA_character_
}
overall <- if (!nrow(picks)) "pass" else pretest_overall(picks$verdict)
groups_pass <- overall
if (overall == "pass" && nrow(picks) && (length(link_sha) != 1L || length(fresh_sha) != 1L ||
                                          dirty || !identical(link_sha, range[2]))) {
  overall <- "fail"
}

md <- file.path(out, "pretest.md")
w <- function(...) cat(..., "\n", sep = "", file = md, append = TRUE)
w("## Verdict")
w("")
if (nrow(picks)) {
  w("| group | inputs | last minutes | bound | this run | exit | verdict |")
  w("|---|---|---|---|---|---|---|")
  for (i in seq_len(nrow(picks))) {
    w(sprintf("| %s | %s | %.1f | %.1f | %s | %s | %s |", picks$wsg[i], picks$inputs[i],
              picks$minutes[i], picks$bound[i],
              if (is.na(picks$run_minutes[i])) "" else sprintf("%.1f", picks$run_minutes[i]),
              if (is.na(picks$exit[i])) "" else picks$exit[i], picks$verdict[i]))
  }
  w("")
}
if (subset) {
  overall <- "fail"
  why <- c(why, "a subset of the picks (--only), never a pass")
}
w(sprintf("**Gate: %s.**%s", toupper(overall),
          if (length(why)) paste0(" ", paste(why, collapse = "; "), ".") else ""))
w("")

# The record. Its table is created only when the catalog says it is absent:
# a CREATE TABLE IF NOT EXISTS on an existing table still takes a lock.
exists <- nrow(DBI::dbGetQuery(conn, sprintf(
  "SELECT 1 FROM information_schema.tables WHERE table_schema = '%s' AND table_name = 'log_pretest'",
  schema))) > 0
if (!exists) {
  invisible(DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s.log_pretest (
       run_at      timestamptz NOT NULL DEFAULT now(),
       config_name text NOT NULL,
       link_sha    text,
       link_dirty  boolean,
       fresh_sha   text,
       since_sha   text NOT NULL,
       until_sha   text NOT NULL,
       scratch     text NOT NULL,
       k           double precision NOT NULL,
       floor_min   double precision NOT NULL,
       per_input   integer NOT NULL,
       groups      text,
       verdict     text NOT NULL CHECK (verdict IN ('pass', 'fail', 'override')),
       notes       text)", schema)))
}
notes <- paste(c(why, if (nzchar(notes_in)) notes_in), collapse = "; ")
invisible(DBI::dbExecute(conn, sprintf(
  "INSERT INTO %s.log_pretest (config_name, link_sha, link_dirty, fresh_sha, since_sha,
     until_sha, scratch, k, floor_min, per_input, groups, verdict, notes)
   VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)", schema),
  params = list(config, if (length(link_sha) == 1L) link_sha else NA_character_, dirty,
                if (length(fresh_sha) == 1L) fresh_sha else NA_character_,
                range[1], range[2], scratch, k, floor_min, per_input,
                paste(sprintf("%s:%s", picks$wsg, picks$verdict), collapse = ","),
                overall, if (nzchar(notes)) notes else NA_character_)))
DBI::dbDisconnect(conn)

for (i in seq_len(nrow(picks))) {
  message(sprintf("  %-4s %-7s last %5.1f  bound %5.1f  this run %s", picks$wsg[i], picks$verdict[i],
                  picks$minutes[i], picks$bound[i],
                  if (is.na(picks$run_minutes[i])) "-" else sprintf("%.1f", picks$run_minutes[i])))
}
message(sprintf("GATE %s%s (recorded in %s.log_pretest)", toupper(overall),
                if (length(why)) paste0(": ", paste(why, collapse = "; ")) else "", schema))
# A subset run's record is a fail by construction; its exit says whether the
# groups it modelled passed.
quit(status = if ((if (subset) groups_pass else overall) == "pass") 0L else 1L)

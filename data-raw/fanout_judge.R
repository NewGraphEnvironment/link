#!/usr/bin/env Rscript
# fanout_judge.R — shell-callable wrapper around lnk_fanout_judge() (link#250).
#
# Exists because there is no shell test harness in this repo. The predicate
# ("did the fan-out actually complete?") lives in R where testthat can prove
# it; this file only marshals arguments and turns the verdict into an exit
# status. Same shape as host_vintage.R / host_stamp.R.
#
# Usage:
#   [LNK_LOAD=loadall] Rscript data-raw/fanout_judge.R <rc.tsv> <expected-csv> [label]
#
#   rc.tsv        two columns, no header: <job>\t<exit status>. One line per
#                 job that actually reported. MAY BE EMPTY OR ABSENT -- that
#                 is the "nothing ran" case, and it is a real answer rather
#                 than an error.
#   expected-csv  comma-separated job ids that were supposed to run.
#
# Exit 0 iff every expected job reported and every status was zero.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L) {
  stop("usage: fanout_judge.R <rc.tsv> <expected-csv> [label]", call. = FALSE)
}
tsv      <- args[1]
expected <- args[2]
label    <- if (length(args) >= 3L && nzchar(args[3])) args[3] else "fanout"

if (identical(Sys.getenv("LNK_LOAD"), "loadall")) {
  suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
} else {
  suppressPackageStartupMessages(library(link))
}

# Split on comma AND whitespace, then drop empties: a trailing comma in the
# WSG list must not become a phantom job id that can never report.
expected_ids <- trimws(strsplit(expected, "[,[:space:]]+")[[1]])
expected_ids <- expected_ids[nzchar(expected_ids)]

# An absent or zero-byte file is the "nothing ran" case, not a parse error.
# read.delim() on an empty file stops with "no lines available in input",
# which under `set -e` would be indistinguishable from a real verdict of
# failure -- and would hide WHY. Handle it here so the R function always sees
# a well-formed frame and the branch is judged, not thrown.
#
# Emptiness is decided by READING, not by file.size(): size does not stat
# reliably for a fifo, so a caller passing a process substitution would have
# a perfectly good pass judged "nothing ran".
rc_lines <- if (file.exists(tsv)) {
  readLines(tsv, warn = FALSE)
} else {
  character(0)
}
rc_lines <- rc_lines[nzchar(trimws(rc_lines))]

rc <- if (length(rc_lines) == 0L) {
  data.frame(job = character(0), rc = character(0), stringsAsFactors = FALSE)
} else {
  # na.strings = character(0): a literal "NA" in the status column must reach
  # the judge as the string so it can be reported as unreadable, not silently
  # become R's NA. Same reasoning as judge_stamps() in study_area_run.sh.
  utils::read.delim(text = rc_lines, header = FALSE, sep = "\t", quote = "",
                    colClasses = "character", na.strings = character(0),
                    col.names = c("job", "rc"), strip.white = TRUE)
}

res <- lnk_fanout_judge(rc, expected = expected_ids, label = label)
quit(status = if (isTRUE(res$ok)) 0L else 1L)

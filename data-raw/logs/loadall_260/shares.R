#!/usr/bin/env Rscript
# shares.R — link#260: the recompute job prologue as a share of the work it
# precedes. Reads timings.tsv (measure.sh), span.tsv (span.sql) and the
# 2026-10-23 run's per-group minutes; writes shares.txt beside itself.
# Rscript data-raw/logs/loadall_260/shares.R   (from the repo root)
here <- "data-raw/logs/loadall_260"
x <- read.delim(file.path(here, "timings.tsv"))
x$all  <- x$r_start + x$total
x$cond <- sub("[0-9]+$", "", sub("_w.*", "", x$label))
x$cond[x$label == "seq1"] <- "cold"
x$cond[x$cond == "seq"] <- "seq"
med <- tapply(x$all, list(x$cond, x$mode), median)
med_load <- tapply(x$load, list(x$cond, x$mode), median)

log <- readLines("data-raw/logs/study_area_run/20261023_074321_recompute.log")
m <- regmatches(log, regexpr("\\] [A-Z]{4} recomputed in [0-9.]+ min", log))
mins <- setNames(as.numeric(sub(".* in ([0-9.]+) min", "\\1", m)),
                 sub("^\\] ([A-Z]{4}) .*", "\\1", m))
stopifnot(length(mins) == 240L, !anyDuplicated(names(mins)))

sp <- read.delim(file.path(here, "span.tsv"), header = FALSE,
                 col.names = c("jobs", "first_start", "last_end", "span_min",
                               "job_min_sum", "longest_min"))
stopifnot(sp$jobs == 240L)

width <- 8
p_busy <- med["busy", "loadall"]           # one slot starting while seven compute
p_lib  <- med["busy", "library"]
gap_slot_s <- (sp$span_min * width - sp$job_min_sum) * 60 / sp$jobs

out <- c(
  "## Prologue, seconds (median; all = R startup + every stage before t0)",
  capture.output(print(round(med, 2))),
  "",
  "## load stage alone (load_all or library(link)), seconds",
  capture.output(print(round(med_load, 2))),
  "",
  "## The 2026-10-23 pool (log_recompute, -j8)",
  sprintf("jobs %d, span %.1f min, summed work %.1f min, longest %.2f min",
          sp$jobs, sp$span_min, sp$job_min_sum, sp$longest_min),
  sprintf("summed work / %d = %.1f min; span - that = %.1f min",
          width, sp$job_min_sum / width, sp$span_min - sp$job_min_sum / width),
  sprintf("untimed slot time per job, upper bound (prologue, R exit, poll, tail): %.1f s",
          gap_slot_s),
  "",
  "## Prologue share (busy-condition load_all prologue = %.2f s)" |> sprintf(p_busy),
  sprintf("%-28s %8s %8s", "denominator", "work_s", "share"),
  sprintf("%-28s %8.0f %7.1f%%", c("SALR in run", "median group in run", "CHWK in run",
                                   "SALR #260 (11 s)", "CHWK #260 (226 s)"),
          w <- c(mins[["SALR"]] * 60, median(mins) * 60, mins[["CHWK"]] * 60, 11, 226),
          100 * p_busy / (w + p_busy)),
  sprintf("whole pool: %d x %.2f s / %d = %.2f min of %.1f min span (%.2f%%)",
          sp$jobs, p_busy, width, sp$jobs * p_busy / width / 60, sp$span_min,
          100 * sp$jobs * p_busy / width / 60 / sp$span_min),
  sprintf("saving from library(link): %.2f s/job -> %.2f min of span (%.2f%%)",
          p_busy - p_lib, sp$jobs * (p_busy - p_lib) / width / 60,
          100 * sp$jobs * (p_busy - p_lib) / width / 60 / sp$span_min)
)
writeLines(out, file.path(here, "shares.txt"))
cat(out, sep = "\n")

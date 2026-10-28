#!/usr/bin/env Rscript
# analyze.R — where a threshold variant's pass spends its time (link#404).
#
# Reads variant_timing.csv (written by data-raw/habitat_variants_build.R) and
# writes, beside it:
#   steps.csv              minutes per step per variant x group, and each
#                          step's share of its pass
#   split.csv              the model / verification / write split per pass,
#                          and pooled over the groups
#   steps_vs_segments.png  minutes against the group's segment count, one
#                          panel per step, in_total steps only
# and prints the parallel bound the issue asks for: the nine groups' pass
# minutes summed over four jobs against the longest group.
#
# It stops if the seven in_total steps of any pass do not sum to that pass's
# "done in" minutes in the build log within 2 %: the split is only a split
# of the total if they do.
#
#   Rscript data-raw/logs/variant_cost_404/analyze.R [<dir>]

args <- commandArgs(trailingOnly = TRUE)
dir <- if (length(args) >= 1L) args[1] else
  file.path("data-raw", "logs", "variant_cost_404")
tm <- utils::read.csv(file.path(dir, "variant_timing.csv"),
                      stringsAsFactors = FALSE)
tm$in_total <- as.logical(tm$in_total)
tm$minutes <- tm$seconds / 60

kind <- c(classify = "model", connect = "model", digest_working = "verification",
          persist = "write", copy_access_analyze = "write", gate = "model",
          digest_persist = "verification")
steps <- tm[tm$in_total, ]
stopifnot(all(steps$step %in% names(kind)))
steps$kind <- unname(kind[steps$step])
key <- paste(steps$variant, steps$watershed_group_code)
steps$pass_minutes <- ave(steps$minutes, key, FUN = sum)
steps$share <- steps$minutes / steps$pass_minutes

# -- the sum of the steps is the total the build printed ------------------------------
logs <- list.files(dir, pattern = "^build_.*\\.log$", full.names = TRUE)
logs <- logs[order(file.info(logs)$mtime)]   # oldest first, whatever the names sort to
done <- unlist(lapply(logs, function(f) {
  l <- grep("variant [^ ]+ [A-Z]{4} done in [0-9.]+ min", readLines(f, warn = FALSE),
            value = TRUE)
  m <- regmatches(l, regexec("variant ([^ ]+) ([A-Z]{4}) done in ([0-9.]+) min", l))
  stats::setNames(vapply(m, function(x) as.numeric(x[4]), 1),
                  vapply(m, function(x) paste(x[2], x[3]), ""))
}))
passes <- unique(data.frame(key = key, variant = steps$variant,
                            wsg = steps$watershed_group_code,
                            minutes = steps$pass_minutes))
# The last line for a pass wins (REVL is re-run by the full pass after the pre-flight,
# and its timing rows are replaced): logs are read oldest first, so drop earlier
# duplicates by name.
done <- done[!duplicated(names(done), fromLast = TRUE)]
passes$logged <- done[passes$key]
passes$residual <- passes$minutes - passes$logged
bad <- passes[is.na(passes$logged) |
                abs(passes$residual) > pmax(0.02 * passes$logged, 0.05), ]  # 0.05: half the log's 0.1 min
if (nrow(bad) > 0L) {
  print(bad)
  stop("steps do not sum to the logged total (2 %, or the log's 0.1 min rounding)")
}

# -- steps.csv ------------------------------------------------------------------------
out <- steps[order(steps$variant, steps$watershed_group_code,
                   match(steps$step, names(kind))),
             c("variant", "watershed_group_code", "species", "step", "kind",
               "minutes", "share", "pass_minutes", "n_segments", "load_1min")]
out$minutes <- round(out$minutes, 3)
out$share <- round(out$share, 3)
out$pass_minutes <- round(out$pass_minutes, 3)
utils::write.csv(out, file.path(dir, "steps.csv"), row.names = FALSE)

# -- split.csv: model / verification / write, per pass and pooled ---------------------
split_of <- function(d, label) {
  s <- vapply(c("model", "verification", "write"),
              function(k) sum(d$minutes[d$kind == k]), numeric(1))
  data.frame(pass = label, model_min = round(s[["model"]], 3),
             verification_min = round(s[["verification"]], 3),
             write_min = round(s[["write"]], 3),
             model_share = round(s[["model"]] / sum(s), 3),
             verification_share = round(s[["verification"]] / sum(s), 3),
             write_share = round(s[["write"]] / sum(s), 3))
}
split <- do.call(rbind, c(
  lapply(split(steps, key), function(d)
    split_of(d, paste(d$variant[1], d$watershed_group_code[1]))),
  lapply(split(steps, steps$variant), function(d)
    split_of(d, paste(d$variant[1], "pooled")))))
rownames(split) <- NULL
utils::write.csv(split, file.path(dir, "split.csv"), row.names = FALSE)
print(split[grepl("pooled$", split$pass), ])

# -- the step shares, pooled per variant, and the base pass beside them --------------
for (v in unique(steps$variant)) {
  d <- steps[steps$variant == v, ]
  s <- tapply(d$minutes, d$step, sum)[names(kind)]
  s <- s[!is.na(s)]
  cat(sprintf("\n%s: %d groups, %.1f min summed\n", v, length(unique(d$watershed_group_code)),
              sum(d$minutes)))
  print(round(rbind(minutes = s, share = s / sum(s)), 3))
}
base <- tm[tm$step %in% c("base_model", "base_recompute"), ]
if (nrow(base) > 0L) {
  cat("\nbase run (reference, outside any pass):\n")
  print(round(tapply(base$minutes, base$step, sum), 1))
}
outside <- tm[!tm$in_total & !tm$step %in% c("base_model", "base_recompute"), ]
if (nrow(outside) > 0L) {
  cat("\noutside the total (per variant, summed over groups):\n")
  print(round(tapply(outside$minutes, list(outside$variant, outside$step), sum), 2))
}

# -- the parallel bound, from the serial numbers ---------------------------------------
cat("\nparallel bound over groups (four jobs, longest-first greedy), per variant:\n")
for (v in unique(passes$variant)) {
  p <- sort(passes$minutes[passes$variant == v], decreasing = TRUE)
  jobs <- numeric(4)
  for (x in p) jobs[which.min(jobs)] <- jobs[which.min(jobs)] + x
  cat(sprintf("  %s: serial %.1f min; four jobs %.1f min (longest group %.1f)\n",
              v, sum(p), max(jobs), p[1]))
}

# -- steps_vs_segments.png -------------------------------------------------------------
st <- names(kind)[names(kind) %in% unique(steps$step)]
grDevices::png(file.path(dir, "steps_vs_segments.png"), width = 1600, height = 1000,
               res = 150)
graphics::par(mfrow = c(2, 4), mar = c(4, 4, 2.5, 1))
vars <- unique(steps$variant)
pch <- stats::setNames(seq_along(vars) + 14L, vars)
for (s in st) {
  d <- steps[steps$step == s, ]
  graphics::plot(d$n_segments / 1000, d$minutes, pch = pch[d$variant],
                 xlab = "segments (thousands)", ylab = "minutes",
                 main = sprintf("%s (%s)", s, kind[[s]]),
                 ylim = c(0, max(d$minutes) * 1.05))
  for (v in vars) {
    dv <- d[d$variant == v, ]
    if (length(unique(dv$n_segments)) > 2L) {
      graphics::abline(stats::lm(minutes ~ I(n_segments / 1000), dv), col = "grey50",
                       lty = match(v, vars))
    }
  }
}
graphics::plot.new()
graphics::legend("center", legend = vars, pch = pch, lty = seq_along(vars),
                 col = "grey50", bty = "n")
invisible(grDevices::dev.off())
cat("\nwrote steps.csv, split.csv, steps_vs_segments.png in", dir, "\n")

#!/usr/bin/env Rscript
# correlations.R — which predictor tracks a group's recompute minutes, and how
# much of the pool the walk's province-wide probe costs (link#261). No database.
#
# Reads predictors.tsv, walks.tsv, walk_prefilter.tsv and the two provincial
# runs' recompute logs (minutes per group as logged by wsg_recompute_one.R).
# Primary: 2026-10-23 (-j8); 2026-10-17 (-j4) beside it.
#
# Usage (from the repo root):
#   Rscript data-raw/logs/recompute_cost_261/correlations.R
# Output: correlations.tsv, pool.tsv, misses.tsv, minutes_vs_predictors.png

suppressPackageStartupMessages(library(ggplot2))
d <- "data-raw/logs/recompute_cost_261"
logs <- c(m1023 = "data-raw/logs/study_area_run/20261023_074321_recompute.log",
          m1017 = "data-raw/logs/study_area_run/20261017_004619_recompute.log")
minutes <- function(f) {
  x <- grep("recomputed in [0-9.]+ min", readLines(f), value = TRUE)
  data.frame(wsg = sub(".*\\] ([A-Z]+) recomputed.*", "\\1", x),
             min = as.numeric(sub(".*recomputed in ([0-9.]+) min.*", "\\1", x)))
}
m <- Reduce(function(a, b) merge(a, b, all = TRUE), lapply(names(logs), function(k) {
  x <- minutes(logs[[k]]); names(x)[2] <- k; x
}))
stopifnot(!anyDuplicated(m$wsg))

p <- read.delim(file.path(d, "predictors.tsv"))
# Natural walks dominate (walks.tsv: the three sources take at most 11.5 s a group);
# predicted from the sample walk, slope 1.00 against walks.tsv's nine groups.
p$walk_s_pred <- p$outer_rows_natural * p$probe_us / 1e6
# The sample's own prefilter estimate: it overstates the prefiltered walk (scanning the
# unindexed sample), except where the walk is output-bound (SETN: 539 s, measured 560).
p$walk_pre_s_upper <- p$outer_rows_natural * p$probe_pre_us / 1e6
x <- merge(p, m, by = "wsg")

# Calibrate the prefiltered walk on the nine measured groups: each shape's
# measured prefilter time given to every walk of that shape.
shape <- c(ch = 1, cm = 1, co = 1, gr = 1, ko = 1, pk = 1, sk = 1,
           bt = 2, dv = 2, rb = 2, st = 3, wct = 3)
w <- read.delim(file.path(d, "walks.tsv"))
w <- w[grepl("_access$", w$table), ]
w$shape <- shape[sub("barriers_(.*)_access", "\\1", w$table)]
f <- read.delim(file.path(d, "walk_prefilter.tsv"))
f <- f[f$form == "prefilter" & grepl("_access$", f$table), ]
f$shape <- shape[sub("barriers_(.*)_access", "\\1", f$table)]
f <- f[!duplicated(paste(f$wsg, f$shape), fromLast = TRUE), ]
w$pre_s <- f$seconds[match(paste(w$wsg, w$shape), paste(f$wsg, f$shape))]
# aggregate()'s formula form drops NA rows: a walk with no prefilter row would vanish.
stopifnot(!anyNA(w$pre_s))
meas <- aggregate(cbind(walk_s = exec_s, pre_s) ~ wsg, w, sum)
cal <- merge(meas, x[, c("wsg", "outer_rows_natural", "walk_pre_s_upper", "walk_s_pred")])
fit_pre <- lm(pre_s ~ outer_rows_natural + walk_pre_s_upper, cal)
# Floored at 5 % of the sent walk: the fit goes below zero for small groups
# (34 of 240); floors of 0 to 20 % move the pool total by -95 to +1,264 s.
x$walk_pre_s_cal <- pmin(pmax(predict(fit_pre, x), 0.05 * x$walk_s_pred), x$walk_s_pred)

preds <- c("segments", "walks", "species_walked", "features_inside", "natural_inside",
           "crossings_inside", "features_below_outlet", "natural_below_outlet",
           "in_range", "probe_us", "walk_s_pred")
cor_row <- function(v, run) {
  ok <- !is.na(x[[v]]) & !is.na(x[[run]])
  lx <- log1p(x[[v]][ok]); ly <- log(x[[run]][ok])
  fit <- stats::lm(ly ~ lx)
  data.frame(predictor = v, run = run, n = sum(ok),
             spearman = round(stats::cor(x[[v]][ok], x[[run]][ok], method = "spearman"), 3),
             loglog_slope = round(unname(stats::coef(fit)[2]), 3),
             loglog_r2 = round(summary(fit)$r.squared, 3))
}
cors <- do.call(rbind, c(
  lapply(preds, cor_row, run = "m1023"), lapply(preds, cor_row, run = "m1017"),
  list(data.frame(predictor = "m1017 (other run)", run = "m1023",
    n = sum(!is.na(x$m1017) & !is.na(x$m1023)),
    spearman = round(stats::cor(x$m1017, x$m1023, method = "spearman",
                                use = "complete.obs"), 3),
    loglog_slope = NA, loglog_r2 = round(stats::cor(log(x$m1017), log(x$m1023),
                                                   use = "complete.obs")^2, 3)))))
utils::write.table(cors, file.path(d, "correlations.tsv"), sep = "\t",
                   row.names = FALSE, quote = FALSE)

# Groups the best predictor misses: residual of log minutes on log predicted walk.
y <- x[!is.na(x$m1023), ]
fit <- stats::lm(log(m1023) ~ log(walk_s_pred), y)
y$resid <- stats::residuals(fit)
y$walk_share <- y$walk_s_pred / (60 * y$m1023)
miss <- y[order(-abs(y$resid)), c("wsg", "segments", "walks", "m1023", "m1017",
                                   "walk_s_pred", "walk_share", "resid")][1:15, ]
miss[, -1] <- lapply(miss[, -1], function(v) signif(v, 3))
utils::write.table(miss, file.path(d, "misses.tsv"), sep = "\t",
                   row.names = FALSE, quote = FALSE)

# The pool: summed job seconds against summed predicted walk seconds, and what
# the prefilter would leave (a range: the sample's estimate, above, and the
# calibrated one, fitted on nine groups).
pool <- data.frame(
  run = "m1023", groups = nrow(y),
  job_s = round(sum(60 * y$m1023)),
  walk_s_pred = round(sum(y$walk_s_pred)),
  walk_pre_s_upper = round(sum(pmin(y$walk_pre_s_upper, y$walk_s_pred))),
  walk_pre_s_cal = round(sum(y$walk_pre_s_cal)),
  chwk_job_s = round(60 * y$m1023[y$wsg == "CHWK"]),
  top10_walk_share = round(sum(sort(y$walk_s_pred, decreasing = TRUE)[1:10]) /
                             sum(y$walk_s_pred), 3))
pool$saving_s_low <- pool$walk_s_pred - pool$walk_pre_s_upper
pool$saving_s_high <- pool$walk_s_pred - pool$walk_pre_s_cal
utils::write.table(pool, file.path(d, "pool.tsv"), sep = "\t",
                   row.names = FALSE, quote = FALSE)

lab <- c("CHWK", "SALR", "LFRA", "SETN", "LSKE", "FRCN", "LILL", "LKEL", "CHES")
long <- rbind(
  data.frame(panel = "segments in the group", v = y$segments, min = y$m1023, wsg = y$wsg),
  data.frame(panel = "predicted walk seconds (sample walk)", v = y$walk_s_pred,
             min = y$m1023, wsg = y$wsg))
long$panel <- factor(long$panel, levels = unique(long$panel))
g <- ggplot(long, aes(v, min)) +
  geom_point(alpha = 0.5, size = 1.2) +
  ggrepel::geom_text_repel(data = long[long$wsg %in% lab, ], aes(label = wsg),
                           size = 2.6, min.segment.length = 0, seed = 261) +
  scale_x_log10() + scale_y_log10() +
  facet_wrap(~panel, scales = "free_x") +
  labs(x = NULL, y = "recompute minutes, 2026-10-23 run (-j8)") +
  theme_bw(base_size = 9)
ggsave(file.path(d, "minutes_vs_predictors.png"), g, width = 7, height = 3.4, dpi = 150)
print(cors[cors$run == "m1023", ], row.names = FALSE)
print(pool, row.names = FALSE)
print(miss, row.names = FALSE)

#!/usr/bin/env Rscript
# analyze.R — read measure.tsv and walks.tsv (link#394) and write:
#   steps.tsv    per group and variant: runs, mean walk and access seconds,
#                ratio to base044, and whether every run's output digest equals
#                base044's (the run fails if one does not)
#   ceiling.tsv  per group, at `exists`: seconds of per-species walks whose
#                segment set repeats an earlier walk in the same run (what one
#                walk per distinct set could save at most), over all walk seconds
# and prints both, with the lever-2 gate: repeats summed over the groups, over
# all walk seconds summed over the groups, at least 10 %.
#
# Usage (from the repo root): Rscript data-raw/logs/recompute_access_394/analyze.R

d <- "data-raw/logs/recompute_access_394"
m <- utils::read.delim(file.path(d, "measure.tsv"), quote = "",
                       na.strings = character(), comment.char = "")
w <- utils::read.delim(file.path(d, "walks.tsv"), quote = "",
                       na.strings = character(), comment.char = "")
stopifnot(!any(m$link_dirty))

base_md5 <- tapply(m$output_md5[m$variant == "base044"],
                   m$wsg[m$variant == "base044"], unique)
if (any(lengths(base_md5) != 1L)) stop("base044 digests differ between runs")

steps <- do.call(rbind, lapply(split(m, list(m$wsg, m$variant), drop = TRUE),
                               function(x) {
  data.frame(wsg = x$wsg[1], variant = x$variant[1], runs = nrow(x),
             walk_s = round(mean(x$walk_seconds), 2),
             access_s = round(mean(x$access_seconds), 2),
             walks = x$n_walks[1],
             md5_equal_base = all(x$output_md5 == base_md5[[x$wsg[1]]]),
             other_backends_max = max(x$other_backends_max),
             inputs_moved = any(x$inputs_start != x$inputs_end))
}))
base_walk <- steps$walk_s[steps$variant == "base044"]
names(base_walk) <- steps$wsg[steps$variant == "base044"]
steps$x_base <- round(base_walk[steps$wsg] / steps$walk_s, 2)
steps <- steps[order(steps$wsg, match(steps$variant,
                                      c("base044", "prefilter", "exists", "dedup"))), ]
utils::write.table(steps, file.path(d, "steps.tsv"), sep = "\t", quote = FALSE,
                   row.names = FALSE)
print(steps, row.names = FALSE)
if (!all(steps$md5_equal_base)) stop("an output digest differs from base044")

ex <- w[w$variant == "exists", ]
ex$run <- paste(ex$wsg, ex$date_utc)
ceil <- do.call(rbind, lapply(split(ex, ex$run), function(x) {
  sp <- grepl("_access$", x$features)
  rep_ <- sp & duplicated(ifelse(sp, x$segments_md5, paste0("src:", seq_len(nrow(x)))))
  data.frame(wsg = x$wsg[1], date_utc = x$date_utc[1], walks = nrow(x),
             species_walks = sum(sp), repeated_walks = sum(rep_),
             walk_s = sum(x$seconds), repeated_s = sum(x$seconds[rep_]))
}))
ceil <- do.call(rbind, lapply(split(ceil, ceil$wsg), function(x) {
  data.frame(wsg = x$wsg[1], runs = nrow(x), walks = x$walks[1],
             species_walks = x$species_walks[1],
             repeated_walks = x$repeated_walks[1],
             walk_s = round(mean(x$walk_s), 2),
             repeated_s = round(mean(x$repeated_s), 2),
             share = round(mean(x$repeated_s) / mean(x$walk_s), 3))
}))
utils::write.table(ceil, file.path(d, "ceiling.tsv"), sep = "\t", quote = FALSE,
                   row.names = FALSE)
print(ceil, row.names = FALSE)
gate <- sum(ceil$repeated_s) / sum(ceil$walk_s)
cat(sprintf("\nlever-2 ceiling over %d groups: %.1f %% of walk seconds (gate 10 %%): %s\n",
            nrow(ceil), 100 * gate, if (gate >= 0.10) "BUILD" else "STOP"))

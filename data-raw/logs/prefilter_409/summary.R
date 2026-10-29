# summary.R — link#409 Phase 2: the recompute's steps per group, fresh v0.44.0
# against v0.46.0, from rerun.R's steps_<WSG>_<label>.tsv and walks_*.tsv.
# A label is "b" (before, v0.44.0) or "a" (after, v0.46.0) with a run number:
# each group runs b1, a1, a2, b2, so cache warmth favours neither side. Each
# side's minimum is taken (the run least disturbed by cache or load).
# Writes summary_steps.csv, summary_walks.csv.
#   Rscript summary.R <dir>
dir <- commandArgs(trailingOnly = TRUE)[1]
stopifnot(!is.na(dir), dir.exists(dir))
rd <- function(pat) {
  f <- list.files(dir, pattern = pat, full.names = TRUE)
  stopifnot(length(f) > 0L)
  do.call(rbind, lapply(f, utils::read.delim, stringsAsFactors = FALSE))
}
steps <- rd("^steps_[A-Z]+_[ab][0-9]*\\.tsv$")
walks <- rd("^walks_[A-Z]+_[ab][0-9]*\\.tsv$")
steps$side <- substr(steps$label, 1, 1)
walks$side <- substr(walks$label, 1, 1)
# Each side carries one fresh version, and the two differ.
v <- unique(steps[, c("side", "fresh")])
stopifnot(!anyDuplicated(v$side), setequal(v$side, c("a", "b")),
          v$fresh[v$side == "b"] == "0.44.0", v$fresh[v$side == "a"] == "0.46.0")

keep <- c("total", "lnk_access", "lnk_access:walks", "lnk_access:pipeline_access_other",
          "lnk_access:setup_and_update", "habitat_gate", "mapping_code",
          "downstream_guard", "prior_copy")
s <- steps[steps$step %in% keep, ]
best <- aggregate(s ~ wsg + step + side, data = s, FUN = min)
w <- reshape(best, idvar = c("wsg", "step"), timevar = "side", direction = "wide")
names(w) <- sub("^s\\.", "s_", names(w))
w$ratio <- round(w$s_b / w$s_a, 2)
w$saved_s <- round(w$s_b - w$s_a, 1)
w <- w[order(w$wsg, match(w$step, keep)), ]
runs <- aggregate(label ~ wsg + side, data = unique(steps[, c("wsg", "side", "label")]),
                  FUN = function(x) paste(sort(x), collapse = ","))
w$runs_b <- runs$label[match(paste(w$wsg, "b"), paste(runs$wsg, runs$side))]
w$runs_a <- runs$label[match(paste(w$wsg, "a"), paste(runs$wsg, runs$side))]
others <- aggregate(cbind(others_start, others_end) ~ wsg, data = steps, FUN = max)
w$others_max <- pmax(others$others_start, others$others_end)[match(w$wsg, others$wsg)]
utils::write.csv(w, file.path(dir, "summary_steps.csv"), row.names = FALSE)

# Walks per table: the fastest run per side.
wb <- aggregate(s ~ wsg + table + side, data = walks, FUN = min)
ww <- reshape(wb, idvar = c("wsg", "table"), timevar = "side", direction = "wide")
names(ww) <- sub("^s\\.", "s_", names(ww))
ww$ratio <- round(ww$s_b / ww$s_a, 2)
# Every run of a walk, on either side, must return the same arrays: the
# sorted digest is the features per segment, the ordered one adds their order.
one <- function(x) length(unique(x)) == 1L
key <- paste(ww$wsg, ww$table)
sa <- aggregate(cbind(digest_sorted, digest_order) ~ wsg + table, data = walks, FUN = one)
ww$same_features <- sa$digest_sorted[match(key, paste(sa$wsg, sa$table))]
ww$same_order <- sa$digest_order[match(key, paste(sa$wsg, sa$table))]
ww <- ww[order(ww$wsg, -ww$s_b), ]
utils::write.csv(ww, file.path(dir, "summary_walks.csv"), row.names = FALSE)

tot <- w[w$step == "total", ]
print(w[, c("wsg", "step", "s_b", "s_a", "ratio", "saved_s")], row.names = FALSE)
cat(sprintf("\nsummed total over %d groups: %.1f min before, %.1f after, %.1f %% less\n",
            nrow(tot), sum(tot$s_b) / 60, sum(tot$s_a) / 60,
            100 * (1 - sum(tot$s_a) / sum(tot$s_b))))
cat(sprintf("arrays identical across every run: features %d of %d walks, order %d of %d\n",
            sum(ww$same_features), nrow(ww), sum(ww$same_order), nrow(ww)))

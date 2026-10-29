#!/usr/bin/env Rscript
# compare.R — every digest identical across the widths a build ran at (link#406).
#
#   Rscript data-raw/logs/variants_parallel_406/compare.R
#
# Reads digests_j<N>.csv (digest.R after the build at --jobs=N) beside this
# script and writes compare.csv: one row per schema x table x group, with each
# width's md5 and whether they all agree. Stops if any differ.
#
# The negative control proves the comparison can fail: the same function,
# given the base schema's habitat against the variant's for each group, must
# report a difference in at least one group, since the variant moved BT
# rearing. A comparison that cannot fail there would pass anything.
here <- "data-raw/logs/variants_parallel_406"
files <- list.files(here, "^digests_j[0-9]+\\.csv$", full.names = TRUE)
if (length(files) < 2L) stop("need digests from at least two widths, found ", length(files))
jobs <- as.integer(sub("^digests_j([0-9]+)\\.csv$", "\\1", basename(files)))
files <- files[order(jobs)]
jobs <- sort(jobs)
d <- lapply(files, utils::read.csv, colClasses = "character")
key <- c("schema", "table", "watershed_group_code")
keys <- lapply(d, function(x) do.call(paste, c(x[key], sep = "|")))
if (!all(vapply(keys, function(k) setequal(k, keys[[1]]) && !anyDuplicated(k),
                logical(1)))) {
  stop("the widths' digest files do not cover the same tables and groups")
}
# One column per width, aligned on the key.
m <- vapply(seq_along(d), function(i) d[[i]]$md5[match(keys[[1]], keys[[i]])],
            character(length(keys[[1]])))
agree <- function(m) apply(m, 1, function(r) length(unique(r)) == 1L)
out <- cbind(d[[1]][key], stats::setNames(as.data.frame(m), paste0("md5_j", jobs)),
             n = d[[1]]$n, identical = agree(m))
utils::write.csv(out, file.path(here, "compare.csv"), row.names = FALSE)

# The comparator must fail on one changed digest: perturb a copy and check.
m_bad <- m
m_bad[1, ncol(m_bad)] <- paste0(m_bad[1, ncol(m_bad)], "x")
if (all(agree(m_bad))) stop("agree() missed a perturbed digest: the comparison cannot fail")

# Negative control, through the same agree().
base_hab <- out[startsWith(out$schema, "score404_default"), ]
var_hab <- out[out$table == base_hab$table[1] & !startsWith(out$schema, "score404_default") &
                 !startsWith(out$schema, "working_"), ]
ctl <- cbind(base_hab[[paste0("md5_j", jobs[1])]],
             var_hab[[paste0("md5_j", jobs[1])]][match(base_hab$watershed_group_code,
                                                         var_hab$watershed_group_code)])
n_ctl_differ <- sum(!agree(ctl))
cat(sprintf("negative control: base vs variant %s differ in %d of %d groups\n",
            base_hab$table[1], n_ctl_differ, nrow(ctl)))
if (n_ctl_differ == 0L) stop("the negative control found no difference: the comparison cannot fail")

cat(sprintf("widths %s: %d of %d digests identical\n", paste(jobs, collapse = ", "),
            sum(out$identical), nrow(out)))
if (!all(out$identical)) {
  print(out[!out$identical, ])
  stop("digests differ between widths")
}

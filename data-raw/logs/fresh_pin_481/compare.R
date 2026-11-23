#!/usr/bin/env Rscript
# compare.R — #481's verdict: the fresh pin (0.52.0 to 0.55.1) moves no
# persisted output but the new column.
#
# Reads the digests digest.R wrote for the four scratch schemas and stops on
# anything but: the same tables, groups and row counts before and after, every
# table's `md5_old` (every column but #481's new one) identical, and the new
# column present after and absent before. Writes compare.csv beside it, and
# builds.csv from the two status files (each group's minutes).
#
# Usage (from the repo root):
#   Rscript data-raw/logs/fresh_pin_481/compare.R
dir <- "data-raw/logs/fresh_pin_481"
read <- function(f) utils::read.csv(file.path(dir, f), stringsAsFactors = FALSE)
pairs <- list(default = c("digest_before.csv", "digest_after.csv"),
              bcfishpass = c("digest_bcfp_before.csv", "digest_bcfp_after.csv"))

out <- do.call(rbind, lapply(names(pairs), function(cfg) {
  b <- read(pairs[[cfg]][1])
  a <- read(pairs[[cfg]][2])
  key <- function(d) paste(d$table, d$wsg)
  if (!setequal(key(b), key(a))) {
    stop(cfg, ": tables or groups differ: before only ",
         paste(setdiff(key(b), key(a)), collapse = "; "), " / after only ",
         paste(setdiff(key(a), key(b)), collapse = "; "), call. = FALSE)
  }
  m <- merge(b, a, by = c("table", "wsg"), suffixes = c("_before", "_after"))
  m$config <- cfg
  m$same_rows <- m$n_before == m$n_after
  m$same_old <- m$md5_old_before == m$md5_old_after
  # Only streams_near_river gains a column; every other table's whole row is
  # unchanged too.
  nr <- m$table == "streams_near_river"
  m$added_cols <- m$cols_after - m$cols_before
  m$same_all <- m$md5_all_before == m$md5_all_after
  bad <- !m$same_rows | !m$same_old | (!nr & (!m$same_all | m$added_cols != 0L)) |
    (nr & m$added_cols != 1L)
  if (any(bad)) {
    print(m[bad, c("config", "table", "wsg", "n_before", "n_after",
                   "same_old", "same_all", "added_cols")])
    stop(cfg, ": ", sum(bad), " table-group digests moved", call. = FALSE)
  }
  m[, c("config", "table", "wsg", "n_before", "n_after", "cols_before",
        "cols_after", "md5_old_before", "md5_old_after", "same_old")]
}))
utils::write.csv(out, file.path(dir, "compare.csv"), row.names = FALSE)

st <- do.call(rbind, lapply(c("status_before.tsv", "status_after.tsv"), function(f) {
  utils::read.delim(file.path(dir, f), stringsAsFactors = FALSE)
}))
st <- st[st$exit == 0L, ]
st$minutes <- round(as.numeric(difftime(as.POSIXct(st$end_utc, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                                        as.POSIXct(st$start_utc, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                                        units = "mins")), 2)
utils::write.csv(st[, c("step", "config", "wsg", "start_utc", "end_utc",
                        "minutes", "load_start", "load_end")],
                 file.path(dir, "builds.csv"), row.names = FALSE)

nr <- out[out$table == "streams_near_river", ]
message(sprintf(
  "[compare] %d table-group digests identical over the old columns (%d near-river: %s rows); minutes before/after: %s",
  nrow(out), nrow(nr), paste(nr$n_after, collapse = "/"),
  paste(sprintf("%s %s %s", st$step, st$config, st$wsg), st$minutes, collapse = "; ")))

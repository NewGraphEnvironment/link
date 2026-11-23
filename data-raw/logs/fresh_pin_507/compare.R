#!/usr/bin/env Rscript
# compare.R — #507's verdict: the fresh pin (0.55.1 to 0.56.0) moves no
# persisted output.
#
# Reads the digests digest.R wrote for the four scratch schemas and stops on
# anything but the same tables, groups, row counts, column counts, digests
# and output tokens before and after. Writes compare.csv beside it, and
# builds.csv from the two status files (each group's minutes).
#
# Usage (from the repo root):
#   Rscript data-raw/logs/fresh_pin_507/compare.R
dir <- "data-raw/logs/fresh_pin_507"
read <- function(f) utils::read.csv(file.path(dir, f), stringsAsFactors = FALSE)
pairs <- list(default = c("digest_before.csv", "digest_after.csv"),
              bcfishpass = c("digest_bcfp_before.csv", "digest_bcfp_after.csv"))

# Every build ended with an exit-0 row, and each digest holds exactly the
# groups built: identical digests over a group that failed in both steps
# would otherwise read as a pass.
builds <- list(default = c("ADMS", "BULK"), bcfishpass = "ADMS")
st0 <- do.call(rbind, lapply(c("status_before.tsv", "status_after.tsv"), function(f) {
  utils::read.delim(file.path(dir, f), stringsAsFactors = FALSE)
}))
for (step in c("before", "after")) for (cfg in names(builds)) for (w in builds[[cfg]]) {
  r <- st0[st0$step == step & st0$config == cfg & st0$wsg == w, ]
  if (!nrow(r) || r$exit[nrow(r)] != 0L) {
    stop(step, " ", cfg, " ", w, ": no successful build", call. = FALSE)
  }
}

out <- do.call(rbind, lapply(names(pairs), function(cfg) {
  b <- read(pairs[[cfg]][1])
  a <- read(pairs[[cfg]][2])
  for (d in list(b, a)) {
    if (!setequal(unique(d$wsg), builds[[cfg]])) {
      stop(cfg, ": digest groups are ", paste(sort(unique(d$wsg)), collapse = ", "),
           ", not ", paste(builds[[cfg]], collapse = ", "), call. = FALSE)
    }
  }
  key <- function(d) paste(d$table, d$wsg)
  if (!setequal(key(b), key(a))) {
    stop(cfg, ": tables or groups differ: before only ",
         paste(setdiff(key(b), key(a)), collapse = "; "), " / after only ",
         paste(setdiff(key(a), key(b)), collapse = "; "), call. = FALSE)
  }
  m <- merge(b, a, by = c("table", "wsg"), suffixes = c("_before", "_after"))
  m$config <- cfg
  m$same <- m$n_before == m$n_after & m$cols_before == m$cols_after &
    m$md5_before == m$md5_after
  if (!all(m$same)) {
    print(m[!m$same, c("config", "table", "wsg", "n_before", "n_after",
                       "cols_before", "cols_after")])
    stop(cfg, ": ", sum(!m$same), " table-group digests moved", call. = FALSE)
  }
  tb <- read(sub("\\.csv$", "_tokens.csv", pairs[[cfg]][1]))
  ta <- read(sub("\\.csv$", "_tokens.csv", pairs[[cfg]][2]))
  if (!identical(tb, ta)) stop(cfg, ": output tokens differ", call. = FALSE)
  m[, c("config", "table", "wsg", "n_before", "n_after", "cols_before",
        "cols_after", "md5_before", "md5_after", "same")]
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
message(sprintf(
  "[compare] %d table-group digests identical; minutes: %s",
  nrow(out), paste(sprintf("%s %s %s", st$step, st$config, st$wsg), st$minutes,
                   collapse = "; ")))

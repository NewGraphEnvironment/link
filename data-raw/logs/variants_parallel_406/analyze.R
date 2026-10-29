#!/usr/bin/env Rscript
# analyze.R — what width buys a variants build (link#406).
#
#   Rscript data-raw/logs/variants_parallel_406/analyze.R
#
# Reads j<N>/variant_timing.csv (the build at --jobs=N, each into its own
# --out) and #404's serial record, and writes:
#   wall.csv   per variant x width: the pass's wall minutes (pass_wall: first
#              dispatch to last return), its summed step minutes, the speed-up
#              against this build's own --jobs=1 and #404's greedy bound
#   steps.csv  per variant x width x step: summed minutes over the groups, so
#              contention shows as a step whose summed minutes grow with width
# It stops if any pass's seven in_total steps do not sum, per group, to within
# the log's 0.1 min rounding of the "done in" line it printed.
here <- "data-raw/logs/variants_parallel_406"
dirs <- list.files(here, "^j[0-9]+$", full.names = TRUE)
if (length(dirs) == 0L) stop("no j<N> build directories under ", here)
tm <- do.call(rbind, lapply(dirs, function(d) {
  x <- utils::read.csv(file.path(d, "variant_timing.csv"), colClasses = "character")
  x$width <- as.integer(sub("^j", "", basename(d)))
  x
}))
tm$seconds <- as.numeric(tm$seconds)
tm$in_total <- as.logical(tm$in_total)
# A j<N> directory holds only the variants step built at --jobs=N.
stopifnot(all(as.integer(tm$jobs) == tm$width))

# Each pass's steps against its "done in" line.
for (d in dirs) {
  log <- readLines(file.path(d, "build.log"))
  done <- regmatches(log, regexec("variant (\\S+) ([A-Z]{4}) done in ([0-9.]+) min", log))
  done <- do.call(rbind, lapply(done[lengths(done) == 4L], function(z) {
    data.frame(variant = z[2], watershed_group_code = z[3], printed = as.numeric(z[4]))
  }))
  w <- as.integer(sub("^j", "", basename(d)))
  s <- stats::aggregate(seconds ~ variant + watershed_group_code,
                        tm[tm$width == w & tm$in_total, ], sum)
  chk <- merge(done, s)
  # Every pass with timing rows has a printed line, and every line its rows.
  if (nrow(chk) != nrow(done) || nrow(chk) != nrow(s) ||
      any(abs(chk$seconds / 60 - chk$printed) > 0.051)) {
    stop("steps do not sum to the printed minutes in ", d)
  }
}

steps <- stats::aggregate(seconds ~ variant + width + step,
                          tm[tm$in_total, ], function(x) sum(x) / 60)
names(steps)[names(steps) == "seconds"] <- "minutes"
steps$minutes <- round(steps$minutes, 3)
utils::write.csv(steps[order(steps$variant, steps$step, steps$width), ],
                 file.path(here, "steps.csv"), row.names = FALSE)

wall <- tm[tm$step == "pass_wall", c("variant", "width", "seconds", "load_1min")]
wall$wall_min <- round(wall$seconds / 60, 2)
summed <- stats::aggregate(seconds ~ variant + width, tm[tm$in_total, ], sum)
wall <- merge(wall, transform(summed, steps_min = round(seconds / 60, 2))[
  c("variant", "width", "steps_min")])
serial <- wall[wall$width == 1L, c("variant", "wall_min")]
names(serial)[2] <- "wall_min_j1"
wall <- merge(wall, serial)
wall$speedup <- round(wall$wall_min_j1 / wall$wall_min, 2)
# #404's greedy bound at four jobs from its serial numbers (its README).
wall$bound_404_j4 <- ifelse(wall$width == 4L,
                            ifelse(wall$variant == "default", 1.8, 1.6), NA)
wall <- wall[order(wall$variant, wall$width),
             c("variant", "width", "wall_min", "steps_min", "speedup",
               "bound_404_j4", "load_1min")]
utils::write.csv(wall, file.path(here, "wall.csv"), row.names = FALSE)
print(wall, row.names = FALSE)
